{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Module: Gachi.Sync.Audit
-- Description: Non-destructive repository audit engine and diagnostic reporter
--
-- This module implements the read-only audit engine for inspecting local
-- checkouts against the canonical Standardization Matrix (~/src/PLAN.md §1.A).
--
-- = Architectural Context & Invariants
--
-- In accordance with Note [Ecosystem Standardization Invariants]
-- [ref:note-ecosystem-standardization] and Note [Cross-Repository Standardization Matrix and Audit Semantics]
-- [ref:note-standardization-matrix], audits are strictly read-only and non-destructive.
-- They evaluate physical file existence, exact textual content matching against
-- canonical generators, and POSIX executable permissions (@+x@) without mutating
-- any filesystem state.
--
-- == Audit Classification Rules
--
-- For each asset registered in the 'StandardizationMatrix', the audit engine produces
-- exactly one 'AssetAuditResult' containing an 'AssetAuditStatus':
--
-- * 'StatusCompliant':
--   The file exists at the expected path, its textual content matches the canonical
--   generator byte-for-byte, and its executable bits conform to the specification.
--
-- * 'StatusMissing':
--   The file does not exist on disk. For required assets, this is flagged as an
--   audit violation; for optional assets (e.g. polyglot formatting rules), it is
--   recorded without failing the verification gate.
--
-- * 'StatusContentDrift':
--   The file exists on disk, but its content differs from the output produced by
--   the canonical generator. The lengths of actual and expected contents are recorded.
--
-- * 'StatusPermissionDrift':
--   The file exists and its content matches, but its executable bit differs from
--   'assetExecutable' (e.g. a script in @bin/@ lacking executable permissions).
--
-- * 'StatusIOError':
--   An unexpected filesystem exception occurred while attempting to read the file.
--
-- == Read-Only & Non-Destructive Invariant
--
-- The audit engine strictly adheres to the principle of observational purity:
-- 1. __Zero Mutations:__ No files, symlinks, or directories are created, modified,
--    or deleted during audit execution.
-- 2. __Exception Containment:__ I/O exceptions (e.g., permission denied, broken symlinks,
--    dangling filesystem nodes) are captured and reported as 'StatusIOError' rather
--    than aborting the audit process abruptly.
-- 3. __Differential Hashing:__ Content comparisons are performed in memory against
--    pure generator outputs, ensuring that audits require no network access or external
--    database queries.
--
-- = Worked Example
--
-- >>> import Gachi.Schema.Project (defaultProject, Author(..))
-- >>> import Gachi.Sync.Matrix (canonicalMatrix)
-- >>> let auth = Author "Nadia Yvette Chambers" "nadia.yvette.chambers@ik.me"
-- >>> let proj = defaultProject "gachi" auth
-- >>> report <- auditRepository "/home/nyc/src/gachi" proj canonicalMatrix
-- >>> reportTotalAssets report >= 20
-- True
-- >>> reportCompliancePct report >= 50.0
-- True
module Gachi.Sync.Audit
  ( -- * Repository Audit Operations
    auditRepository
  , auditAsset
  , auditRepositoryQuick

    -- * Diagnostic Report Formatting
  , formatAuditReport
  , formatAuditReportString

    -- * Result Filter Helpers
  , filterCompliantResults
  , filterDriftResults
  , filterMissingResults
  ) where

import Control.Exception (SomeException, catch, displayException)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import System.Directory (doesFileExist, getPermissions, executable)
import System.FilePath ((</>), takeFileName)

import Gachi.Schema.Dhall (decodeProjectFile)
import Gachi.Schema.Project (Author(..), Project, projectName, defaultProject)
import Gachi.Sync.Matrix (canonicalMatrix)
import Gachi.Sync.Types
  ( AssetAuditResult(..)
  , AssetAuditStatus(..)
  , AuditReport(..)
  , StandardAsset(..)
  , StandardizationMatrix(..)
  , categoryName
  , isCompliant
  , isDrift
  , isMissing
  , resolveAssetPath
  )

--------------------------------------------------------------------------------
-- 1. Single Asset Audit
--------------------------------------------------------------------------------

-- | Inspects an individual standardized asset against a target workspace.
--
-- Resolves the asset's concrete path using 'resolveAssetPath', checks for file
-- existence, reads the file's textual contents, checks executable permissions,
-- and compares the actual state against the expected generator output.
--
-- This operation is strictly read-only and catches all filesystem exceptions,
-- returning 'StatusIOError' upon failure rather than throwing unhandled exceptions.
--
-- === Evaluation Steps
--
-- 1. Resolves concrete relative path via 'resolveAssetPath' (substituting @:name:@ tokens).
-- 2. Checks existence using 'System.Directory.doesFileExist'.
-- 3. If file does not exist, returns 'StatusMissing'.
-- 4. If file exists, reads text content using 'TIO.readFile'.
-- 5. Evaluates the pure generator 'assetGenerator' against 'proj'.
-- 6. If textual contents diverge, returns 'StatusContentDrift'.
-- 7. If contents match, inspects POSIX executable permissions.
-- 8. If executable requirements differ, returns 'StatusPermissionDrift'.
-- 9. If everything matches, returns 'StatusCompliant'.
--
-- === Worked Example
--
-- >>> import Gachi.Schema.Project (defaultProject, Author(..))
-- >>> let proj = defaultProject "gachi" (Author "Nadia" "nadia@example.com")
-- >>> let asset = StandardAsset ".hlint.yaml" Gachi.Sync.Types.CategoryLinter True False "HLint" (const "")
-- >>> result <- auditAsset "/home/nyc/src/gachi" proj asset
-- >>> resultAsset result == asset
-- True
auditAsset :: FilePath -> Project -> StandardAsset -> IO AssetAuditResult
auditAsset repoRoot proj asset = do
  let relPath = resolveAssetPath proj asset
      absPath = repoRoot </> relPath
  exists <- doesFileExist absPath
  if not exists
    then pure (AssetAuditResult asset StatusMissing)
    else checkContentAndPerms absPath
  where
    checkContentAndPerms absPath = (do
      actualContent <- TIO.readFile absPath
      let expectedContent = assetGenerator asset proj
      if actualContent /= expectedContent
        then
          let actualLen = T.length actualContent
              expectedLen = T.length expectedContent
          in pure (AssetAuditResult asset (StatusContentDrift actualLen expectedLen))
        else do
          perms <- getPermissions absPath
          let actualExec = executable perms
              expectedExec = assetExecutable asset
          if expectedExec && not actualExec
            then pure (AssetAuditResult asset (StatusPermissionDrift actualExec expectedExec))
            else pure (AssetAuditResult asset StatusCompliant)
      ) `catch` (\(e :: SomeException) ->
          pure (AssetAuditResult asset (StatusIOError (T.pack (displayException e)))))

--------------------------------------------------------------------------------
-- 2. Complete Repository Audit
--------------------------------------------------------------------------------

-- | Audits an entire repository workspace against a 'StandardizationMatrix'.
--
-- Evaluates each asset registered in 'matrixAssets', tabulates compliance and
-- discrepancy metrics, and constructs a comprehensive 'AuditReport' summarizing
-- findings across all standardization dimensions.
--
-- === Metrics Computed
--
-- * 'reportTotalAssets': Total count of assets evaluated.
-- * 'reportCompliantCount': Assets matching content and permissions exactly.
-- * 'reportDriftCount': Assets present on disk with differing text or permissions.
-- * 'reportMissingCount': Required assets absent from the filesystem.
-- * 'reportCompliancePct': Ratio of compliant assets to total assets (0.0% to 100.0%).
--
-- === Worked Example
--
-- >>> import Gachi.Schema.Project (defaultProject, Author(..))
-- >>> import Gachi.Sync.Matrix (canonicalMatrix)
-- >>> let proj = defaultProject "gachi" (Author "Nadia" "nadia@example.com")
-- >>> report <- auditRepository "/home/nyc/src/gachi" proj canonicalMatrix
-- >>> reportTotalAssets report >= 20
-- True
auditRepository :: FilePath -> Project -> StandardizationMatrix -> IO AuditReport
auditRepository repoRoot proj matrix = do
  results <- traverse (auditAsset repoRoot proj) (matrixAssets matrix)
  let total = length results
      compliant = length (filter (isCompliant . resultStatus) results)
      drift = length (filter (isDrift . resultStatus) results)
      missing = length (filter (\r -> isMissing (resultStatus r) && assetRequired (resultAsset r)) results)
      pct = if total == 0
              then 100.0
              else (fromIntegral compliant / fromIntegral total) * 100.0
  pure AuditReport
    { reportTargetDir      = repoRoot
    , reportProjectName    = projectName proj
    , reportResults        = results
    , reportTotalAssets    = total
    , reportCompliantCount = compliant
    , reportDriftCount     = drift
    , reportMissingCount   = missing
    , reportCompliancePct  = pct
    }

-- | Fast, zero-configuration repository audit.
--
-- Attempts to locate and evaluate @project.dhall@ within 'repoRoot'. If present,
-- decodes the declarative specification via 'decodeProjectFile' and executes
-- 'auditRepository'. If absent, infers project metadata from the directory name
-- and standard author information, auditing against 'canonicalMatrix'.
--
-- Guarantees total evaluation: catches Dhall decoding exceptions and returns
-- a descriptive 'Left' error text rather than crashing.
--
-- === Worked Example
--
-- >>> res <- auditRepositoryQuick "/home/nyc/src/gachi"
-- >>> case res of { Right rep -> reportCompliancePct rep >= 50.0; Left _ -> False }
-- True
auditRepositoryQuick :: FilePath -> IO (Either Text AuditReport)
auditRepositoryQuick repoRoot = do
  let dhallPath = repoRoot </> "project.dhall"
  hasDhall <- doesFileExist dhallPath
  if hasDhall
    then (do
      proj <- decodeProjectFile dhallPath
      report <- auditRepository repoRoot proj canonicalMatrix
      pure (Right report)
      ) `catch` (\(e :: SomeException) ->
          pure (Left ("Failed to decode project.dhall: " <> T.pack (displayException e))))
    else do
      let inferredName = T.pack (takeFileName repoRoot)
          defaultAuthor = Author "Nadia Yvette Chambers" "nadia.yvette.chambers@ik.me"
          proj = defaultProject inferredName defaultAuthor
      report <- auditRepository repoRoot proj canonicalMatrix
      pure (Right report)

--------------------------------------------------------------------------------
-- 3. Result Filters
--------------------------------------------------------------------------------

-- | Filters an 'AuditReport' to only include compliant assets.
--
-- Useful for generating green status checklists and compliance confirmations.
filterCompliantResults :: AuditReport -> [AssetAuditResult]
filterCompliantResults = filter (isCompliant . resultStatus) . reportResults

-- | Filters an 'AuditReport' to only include assets exhibiting content or permission drift.
--
-- Used by synchronization engines ('gachi sync') to identify files requiring differential updates.
filterDriftResults :: AuditReport -> [AssetAuditResult]
filterDriftResults = filter (isDrift . resultStatus) . reportResults

-- | Filters an 'AuditReport' to only include missing required assets.
--
-- Identifies critical ecosystem gaps that must be populated during repository retrofitting.
filterMissingResults :: AuditReport -> [AssetAuditResult]
filterMissingResults =
  filter (\r -> isMissing (resultStatus r) && assetRequired (resultAsset r)) . reportResults

--------------------------------------------------------------------------------
-- 4. Diagnostic Report Formatting
--------------------------------------------------------------------------------

-- | Formats an 'AuditReport' as human-readable plain text with ASCII diagnostic tables.
--
-- Displays:
-- 1. Header banner with repository target path and compliance percentage.
-- 2. Summary statistics (compliant, drift, missing counts).
-- 3. Per-asset tabular evaluation detailing status, category, and relative path.
-- 4. Granular drift or missing asset diagnostics.
--
-- === Output Format Example
--
-- @
-- ================================================================================
--  Gachi Standardization Matrix Audit Report
-- ================================================================================
--  Target Directory: /home/nyc/src/gachi
--  Project Name:     gachi
--  Total Assets:     25
--  Compliant:        22
--  Drift Detected:   1
--  Missing Required: 2
--  Compliance Rate:  88.0%
-- --------------------------------------------------------------------------------
--  Status     | Dimension              | Path
-- ------------+------------------------+------------------------------------------
--  OK         | Code Formatters        | fourmolu.yaml
--  DRIFT      | Linters & Guardrails   | .hlint.yaml
--  MISSING    | Git Governance         | .githooks/commit-msg
-- ================================================================================
-- @
formatAuditReport :: AuditReport -> Text
formatAuditReport report = T.unlines $
  [ "================================================================================"
  , " Gachi Standardization Matrix Audit Report"
  , "================================================================================"
  , " Target Directory: " <> T.pack (reportTargetDir report)
  , " Project Name:     " <> reportProjectName report
  , " Total Assets:     " <> T.show (reportTotalAssets report)
  , " Compliant:        " <> T.show (reportCompliantCount report)
  , " Drift Detected:   " <> T.show (reportDriftCount report)
  , " Missing Required: " <> T.show (reportMissingCount report)
  , " Compliance Rate:  " <> formatPct (reportCompliancePct report)
  , "--------------------------------------------------------------------------------"
  , " Status     | Dimension              | Path"
  , "------------+------------------------+------------------------------------------"
  ]
  ++ map formatRow (reportResults report)
  ++ formatDriftSection (filterDriftResults report)
  ++ formatMissingSection (filterMissingResults report)
  ++
  [ "================================================================================" ]
  where
    formatPct :: Double -> Text
    formatPct val =
      let whole = floor val :: Int
          dec = floor (val * 10) `mod` 10 :: Int
      in T.show whole <> "." <> T.show dec <> "%"

    formatRow :: AssetAuditResult -> Text
    formatRow res =
      let stat = formatStatus (resultStatus res)
          cat = padRight 22 (categoryName (assetCategory (resultAsset res)))
          path = T.pack (assetPath (resultAsset res))
      in " " <> padRight 10 stat <> " | " <> cat <> " | " <> path

    formatStatus :: AssetAuditStatus -> Text
    formatStatus StatusCompliant          = "OK"
    formatStatus StatusMissing            = "MISSING"
    formatStatus (StatusContentDrift _ _) = "DRIFT"
    formatStatus (StatusPermissionDrift _ _) = "PERM-DRIFT"
    formatStatus (StatusIOError _)        = "ERROR"

    padRight :: Int -> Text -> Text
    padRight n txt =
      let len = T.length txt
      in if len >= n
           then txt
           else txt <> T.replicate (n - len) " "

    formatDriftSection :: [AssetAuditResult] -> [Text]
    formatDriftSection [] = []
    formatDriftSection drifts =
      [ "--------------------------------------------------------------------------------"
      , " Content & Permission Drift Details:"
      ] ++ map explainDrift drifts

    explainDrift :: AssetAuditResult -> Text
    explainDrift res =
      let p = T.pack (assetPath (resultAsset res))
      in case resultStatus res of
        StatusContentDrift actual expected ->
          "  * " <> p <> ": content divergence (actual len: " <> T.show actual
          <> " chars, expected: " <> T.show expected <> " chars)"
        StatusPermissionDrift actual expected ->
          "  * " <> p <> ": permission mismatch (actual exec: " <> T.show actual
          <> ", expected: " <> T.show expected <> ")"
        StatusIOError err ->
          "  * " <> p <> ": I/O error (" <> err <> ")"
        _ -> "  * " <> p

    formatMissingSection :: [AssetAuditResult] -> [Text]
    formatMissingSection [] = []
    formatMissingSection missings =
      [ "--------------------------------------------------------------------------------"
      , " Missing Required Assets:"
      ] ++ map explainMissing missings

    explainMissing :: AssetAuditResult -> Text
    explainMissing res =
      let p = T.pack (assetPath (resultAsset res))
          desc = assetDescription (resultAsset res)
      in "  * " <> p <> " — " <> desc

-- | Convenience helper rendering 'formatAuditReport' to a 'String'.
--
-- Facilitates output to standard terminal streams via 'putStrLn'.
formatAuditReportString :: AuditReport -> String
formatAuditReportString = T.unpack . formatAuditReport
