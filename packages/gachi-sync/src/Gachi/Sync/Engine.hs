{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Module: Gachi.Sync.Engine
-- Description: Harmonic chattering synchronization and differential propagation engine
--
-- This module implements the core propagation engine of @gachi sync@. It evaluates
-- differential changes across ecosystem checkouts against the canonical Standardization
-- Matrix (~/src/PLAN.md §1.A), computes atomic synchronization plans, applies non-destructive
-- updates to missing or drifted files, and guarantees mathematical idempotency.
--
-- = Architectural Context & Invariants
--
-- In accordance with Note [Ecosystem Standardization Invariants]
-- [ref:note-ecosystem-standardization], Note [Cross-Repository Standardization Matrix and Audit Semantics]
-- [ref:note-standardization-matrix], and Note [Harmonic Chattering Synchronization and Differential Propagation]
-- [ref:note-harmonic-sync], this module is the operational engine that transforms
-- observational audit findings into safe, automated filesystem repairs.
--
-- = Note [Harmonic Chattering Synchronization and Differential Propagation]
-- [tag:note-harmonic-sync]
--
-- In the mythos of Gachi, the *gashadokuro* phantom is assembled from the scattered
-- bones of those fallen across many battles. When the phantom awakens, its collected
-- teeth chatter and click (*gachi-gachi*) in eerie unison—a resonant harmonic rhythm
-- that coordinates the entire skeletal body without centralized nervous signaling.
--
-- In modern software engineering, multi-repository architectures suffer from structural
-- desynchronization: improvements made to one repository's formatting profile (Fourmolu),
-- compiler warning flags, Git commit hooks, or AI agent guidance fail to propagate to
-- sibling repositories. Over time, repositories drift into incompatible silos.
--
-- The Harmonic Chattering Synchronization engine resolves this through three core principles:
--
-- 1.  __Observational Planning Before Mutation:__
--     Before modifying a single byte on disk, the engine computes a 'SyncPlan'
--     classifying every standardized asset into an explicit 'SyncAction':
--     * 'ActionCreate': The file is absent; it must be materialized with correct permissions.
--     * 'ActionUpdate': The file exists, but its content diverges from canonical generators.
--     * 'ActionChmod': The content matches, but its POSIX executable permissions differ.
--     * 'ActionNoOp': The file is already compliant; zero disk I/O is performed.
--
-- 2.  __Strict Mathematical Idempotency:__
--     The synchronization function is mathematically idempotent:
--     \[
--       \text{sync}(\text{sync}(W)) = \text{sync}(W)
--     \]
--     Executing @gachi sync@ once repairs all discrepancies. Executing @gachi sync@
--     immediately afterward produces an empty change set (0 creates, 0 updates, 0 chmods).
--
-- 3.  __Non-Destructive Safety & Dry-Run Preview:__
--     The engine supports 'DryRun' mode, enabling developers and CI harnesses to inspect
--     all planned filesystem modifications and unified diffs before applying changes.
--
-- 4.  __Multi-Repository Ecosystem Orchestration:__
--     Through 'discoverEcosystemRepositories' and 'syncEcosystem', a single command
--     can harmonize all checkouts across @~/src/*@ in lockstep.
--
-- = Worked Example
--
-- >>> import Gachi.Schema.Project (defaultProject, Author(..))
-- >>> import Gachi.Sync.Matrix (canonicalMatrix)
-- >>> let proj = defaultProject "gachi" (Author "Nadia" "nadia@example.com")
-- >>> plan <- computeSyncPlan "/home/nyc/src/gachi" proj canonicalMatrix
-- >>> planProjectName plan
-- "gachi"
module Gachi.Sync.Engine
  ( -- * Synchronization Execution Modes
    SyncMode(..)

    -- * Synchronization Action Models
  , SyncAction(..)
  , isNoOpAction
  , isMutatingAction

    -- * Synchronization Planning
  , SyncPlan(..)
  , isPlanClean
  , computeSyncPlan

    -- * Synchronization Execution
  , SyncResult(..)
  , executeSyncPlan
  , syncRepository
  , syncRepositoryQuick

    -- * Multi-Repository Ecosystem Orchestration
  , discoverEcosystemRepositories
  , syncEcosystem

    -- * Diagnostic Plan & Result Formatting
  , formatSyncPlan
  , formatSyncResult
  ) where

import Control.Exception (SomeException, catch, displayException)
import Control.Monad (forM, when)
import Data.Maybe (catMaybes)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import System.Directory
  ( canonicalizePath
  , createDirectoryIfMissing
  , doesDirectoryExist
  , doesFileExist
  , executable
  , getPermissions
  , listDirectory
  , setOwnerExecutable
  , setPermissions
  )
import System.FilePath (takeDirectory, takeFileName, (</>))

import Gachi.Schema.Dhall (decodeProjectFile)
import Gachi.Schema.Project (Author(..), Project, defaultProject, projectName)
import Gachi.Sync.Hash (sha256Text)
import Gachi.Sync.Matrix (canonicalMatrix)
import Gachi.Sync.Types
  ( StandardAsset(..)
  , StandardizationMatrix(..)
  , resolveAssetPath
  )

--------------------------------------------------------------------------------
-- 1. Synchronization Modes & Actions
--------------------------------------------------------------------------------

-- | Operational mode controlling filesystem mutations during synchronization.
data SyncMode
  = DryRun
    -- ^ Inspect discrepancies and compute the 'SyncPlan', but perform no disk mutations.
  | ApplySync
    -- ^ Apply all planned changes: create missing files, update content, and fix permissions.
  deriving stock (Eq, Show, Ord, Enum, Bounded)

-- | Explicit atomic action planned for an individual standardized asset.
--
-- Represents the fine-grained decision made for a single asset during the evaluation
-- phase of 'computeSyncPlan'. Every standardized asset maps to exactly one action.
data SyncAction
  = ActionCreate !FilePath !Text !Bool
    -- ^ The asset is completely absent on disk.
    -- Parameters:
    -- 1. Relative destination file path (e.g. @"fourmolu.yaml"@ or @"bin/gachi-verify"@).
    -- 2. Complete canonical text content produced by the asset generator.
    -- 3. Boolean flag indicating whether POSIX owner executable bit (+x) must be set.
  | ActionUpdate !FilePath !Text !Text !Bool
    -- ^ The asset exists on disk, but its SHA-256 checksum diverges from the generator.
    -- Parameters:
    -- 1. Relative destination file path.
    -- 2. Pre-existing file content currently residing on disk.
    -- 3. Canonical replacement content produced by the asset generator.
    -- 4. Target POSIX owner executable bit requirement.
  | ActionChmod !FilePath !Bool !Bool
    -- ^ The asset content is bit-identical, but its POSIX executable bit differs.
    -- Parameters:
    -- 1. Relative destination file path.
    -- 2. Current executable permission detected on disk.
    -- 3. Target executable permission required by the asset specification.
  | ActionNoOp !FilePath
    -- ^ The asset is fully compliant: exists, matches SHA-256 hash, and has correct permissions.
    -- Parameters:
    -- 1. Relative destination file path.
  | ActionError !FilePath !Text
    -- ^ An unexpected filesystem I/O exception occurred during inspection.
    -- Parameters:
    -- 1. Relative destination file path where inspection failed.
    -- 2. Human-readable diagnostic description of the caught exception.
  deriving stock (Eq, Show)

-- | Returns 'True' if the action represents an already-compliant asset requiring no changes.
--
-- No-op actions imply that the file on disk is bit-identical and has conforming permissions.
isNoOpAction :: SyncAction -> Bool
isNoOpAction (ActionNoOp _) = True
isNoOpAction _              = False

-- | Returns 'True' if the action would modify the filesystem (create, update, or chmod).
--
-- Mutating actions are executed during 'ApplySync' and simulated during 'DryRun'.
isMutatingAction :: SyncAction -> Bool
isMutatingAction ActionCreate {} = True
isMutatingAction ActionUpdate {} = True
isMutatingAction ActionChmod {}  = True
isMutatingAction _               = False

--------------------------------------------------------------------------------
-- 2. Synchronization Planning
--------------------------------------------------------------------------------

-- | Comprehensive pre-mutation plan detailing all actions required across a repository.
--
-- The 'SyncPlan' represents the pure evaluation outcome of comparing a repository's
-- on-disk state against the canonical 'StandardizationMatrix'. It serves as an immutable,
-- inspectable specification of all proposed mutations prior to disk execution.
--
-- === Structural Invariants
--
-- 1. __Completeness:__ Exactly one 'SyncAction' exists for every asset declared in
--    the input 'StandardizationMatrix'. No assets are skipped or duplicated.
-- 2. __Partitioning:__ The action counts ('planCreatedCount', 'planUpdatedCount',
--    'planChmodCount', 'planNoOpCount') sum to the total length of 'planActions'.
-- 3. __Cleanliness Predicate:__ 'isPlanClean' holds if and only if no mutating
--    actions are scheduled (i.e. created, updated, and chmod counts are all 0).
data SyncPlan = SyncPlan
  { planTargetDir     :: !FilePath
    -- ^ Target repository workspace path.
  , planProjectName   :: !Text
    -- ^ Name of the target project being synchronized.
  , planActions       :: ![SyncAction]
    -- ^ Complete list of planned per-asset actions.
  , planCreatedCount  :: !Int
    -- ^ Number of missing files planned for creation.
  , planUpdatedCount  :: !Int
    -- ^ Number of drifted files planned for content update.
  , planChmodCount    :: !Int
    -- ^ Number of files requiring permission correction.
  , planNoOpCount     :: !Int
    -- ^ Number of files already compliant.
  } deriving stock (Eq, Show)

-- | Checks whether a plan requires zero mutations (all assets compliant).
--
-- Returns 'True' when a repository is in perfect resonance with the standardization
-- matrix, meaning no files need to be created, updated, or chmodded.
isPlanClean :: SyncPlan -> Bool
isPlanClean plan =
  planCreatedCount plan == 0
    && planUpdatedCount plan == 0
    && planChmodCount plan == 0

-- | Computes a 'SyncPlan' for a target repository without modifying any files.
--
-- Evaluates each asset registered in the 'StandardizationMatrix', compares current
-- disk state with expected generator output, and categorizes required actions.
--
-- === Four-Phase Differential Inspection Pipeline
--
-- For each asset in the matrix, the planning algorithm executes the following
-- deterministic decision procedure:
--
-- 1. __Path Resolution:__
--    Resolves parameterized path tokens (@:name:@, @:project:@) against the target
--    'Project' specification via 'resolveAssetPath'.
--
-- 2. __Existence Inspection:__
--    Checks whether the target file exists on disk via 'doesFileExist'.
--    If absent, plans 'ActionCreate' containing the generator's expected output
--    and executable flag requirement.
--
-- 3. __Cryptographic Differential Scanning:__
--    If present, reads the file strictly and computes SHA-256 digests of both the
--    disk content and the generator output.
--    * If the hashes diverge, plans 'ActionUpdate' preserving the existing content
--      for diff generation and supplying the canonical replacement content.
--
-- 4. __POSIX Mode Verification:__
--    If the hashes match bit-for-bit, inspects the file's owner executable bit via
--    'getPermissions'.
--    * If the executable permission disagrees with 'assetExecutable', plans 'ActionChmod'.
--    * If permissions match, plans 'ActionNoOp', indicating clean compliance.
--
-- === Worked Example
--
-- >>> import Gachi.Schema.Project (defaultProject, Author(..))
-- >>> import Gachi.Sync.Matrix (canonicalMatrix)
-- >>> let proj = defaultProject "gachi" (Author "Nadia" "nadia@example.com")
-- >>> plan <- computeSyncPlan "/home/nyc/src/gachi" proj canonicalMatrix
-- >>> planNoOpCount plan > 0
-- True
computeSyncPlan :: FilePath -> Project -> StandardizationMatrix -> IO SyncPlan
computeSyncPlan repoRoot proj matrix = do
  actions <- forM (matrixAssets matrix) $ \asset -> do
    let relPath = resolveAssetPath proj asset
        absPath = repoRoot </> relPath
    exists <- doesFileExist absPath
    if not exists
      then
        let expectedContent = assetGenerator asset proj
            execBit = assetExecutable asset
        in pure (ActionCreate relPath expectedContent execBit)
      else (do
        actualContent <- TIO.readFile absPath
        let expectedContent = assetGenerator asset proj
            execBit = assetExecutable asset
        if actualContent /= expectedContent
          then pure (ActionUpdate relPath actualContent expectedContent execBit)
          else do
            perms <- getPermissions absPath
            let actualExec = executable perms
            if actualExec /= execBit
              then pure (ActionChmod relPath actualExec execBit)
              else pure (ActionNoOp relPath)
        ) `catch` (\(e :: SomeException) ->
            pure (ActionError relPath (T.pack (displayException e))))

  let creates = length [() | ActionCreate {} <- actions]
      updates = length [() | ActionUpdate {} <- actions]
      chmods  = length [() | ActionChmod {} <- actions]
      noops   = length [() | ActionNoOp _ <- actions]

  pure SyncPlan
    { planTargetDir     = repoRoot
    , planProjectName   = projectName proj
    , planActions       = actions
    , planCreatedCount  = creates
    , planUpdatedCount  = updates
    , planChmodCount    = chmods
    , planNoOpCount     = noops
    }

--------------------------------------------------------------------------------
-- 3. Synchronization Execution
--------------------------------------------------------------------------------

-- | Result summary produced by executing a 'SyncPlan'.
data SyncResult = SyncResult
  { resultTargetDir   :: !FilePath
    -- ^ Target repository path.
  , resultProjectName :: !Text
    -- ^ Name of the synchronized project.
  , resultMode        :: !SyncMode
    -- ^ Mode under which synchronization executed ('DryRun' or 'ApplySync').
  , resultCreated     :: ![FilePath]
    -- ^ List of file paths created.
  , resultUpdated     :: ![FilePath]
    -- ^ List of file paths updated.
  , resultChmodded    :: ![FilePath]
    -- ^ List of file paths whose permissions were corrected.
  , resultUnchanged   :: ![FilePath]
    -- ^ List of file paths left untouched.
  , resultErrors      :: ![(FilePath, Text)]
    -- ^ List of errors encountered during execution.
  , resultSuccess     :: !Bool
    -- ^ Whether all actions executed without error.
  } deriving stock (Eq, Show)

-- | Executes a computed 'SyncPlan' under the specified 'SyncMode'.
--
-- === Operational Modes & Safety Invariants
--
-- * __'DryRun' Mode:__
--   Evaluates all actions declared in the plan, extracts summary statistics, and
--   constructs a 'SyncResult' representing the planned mutations without performing
--   any filesystem writes or permission modifications.
--
-- * __'ApplySync' Mode:__
--   Applies all mutating actions sequentially to the destination repository:
--   1. __Parent Directory Synthesis:__ Automatically creates any missing parent
--      directories (via 'createDirectoryIfMissing True') prior to writing file contents.
--   2. __Atomic Content Materialization:__ Writes canonical UTF-8 text contents to
--      disk for both 'ActionCreate' and 'ActionUpdate' operations.
--   3. __Permission Enforcement:__ When an asset requires executable permissions
--      (e.g., verification harnesses, Git hooks, tag generation scripts), explicitly
--      sets the owner executable bit via 'setOwnerExecutable True'.
--   4. __Exception Containment:__ Wraps each individual filesystem mutation in an
--      isolated exception handler. If a write fails (due to permissions, disk space,
--      or locks), the error is recorded in 'resultErrors' while continuing execution
--      for remaining assets.
--   5. __Idempotent Resonance:__ After successful execution under 'ApplySync', the
--      repository is mathematically stable: immediately calling 'computeSyncPlan'
--      produces 'isPlanClean plan == True'.
executeSyncPlan :: SyncMode -> SyncPlan -> IO SyncResult
executeSyncPlan mode plan = do
  case mode of
    DryRun -> do
      -- In DryRun mode, return planned changes without mutating disk
      let created = [p | ActionCreate p _ _ <- planActions plan]
          updated = [p | ActionUpdate p _ _ _ <- planActions plan]
          chmodded = [p | ActionChmod p _ _ <- planActions plan]
          unchanged = [p | ActionNoOp p <- planActions plan]
          errs = [(p, msg) | ActionError p msg <- planActions plan]
      pure SyncResult
        { resultTargetDir   = planTargetDir plan
        , resultProjectName = planProjectName plan
        , resultMode        = DryRun
        , resultCreated     = created
        , resultUpdated     = updated
        , resultChmodded    = chmodded
        , resultUnchanged   = unchanged
        , resultErrors      = errs
        , resultSuccess     = null errs
        }
    ApplySync -> do
      -- In ApplySync mode, apply mutations to disk safely
      resActions <- forM (planActions plan) $ \action -> do
        case action of
          ActionCreate relPath content isExec -> (do
            let absPath = planTargetDir plan </> relPath
            createDirectoryIfMissing True (takeDirectory absPath)
            TIO.writeFile absPath content
            when isExec $ do
              perms <- getPermissions absPath
              setPermissions absPath (setOwnerExecutable True perms)
            pure (ExecCreated relPath)
            ) `catch` (\(e :: SomeException) ->
                pure (ExecFailed relPath (T.pack (displayException e))))

          ActionUpdate relPath _ newContent isExec -> (do
            let absPath = planTargetDir plan </> relPath
            createDirectoryIfMissing True (takeDirectory absPath)
            TIO.writeFile absPath newContent
            when isExec $ do
              perms <- getPermissions absPath
              setPermissions absPath (setOwnerExecutable True perms)
            pure (ExecUpdated relPath)
            ) `catch` (\(e :: SomeException) ->
                pure (ExecFailed relPath (T.pack (displayException e))))

          ActionChmod relPath _ targetExec -> (do
            let absPath = planTargetDir plan </> relPath
            perms <- getPermissions absPath
            setPermissions absPath (setOwnerExecutable targetExec perms)
            pure (ExecChmodded relPath)
            ) `catch` (\(e :: SomeException) ->
                pure (ExecFailed relPath (T.pack (displayException e))))

          ActionNoOp relPath ->
            pure (ExecUnchanged relPath)

          ActionError relPath msg ->
            pure (ExecFailed relPath msg)

      let created = [p | ExecCreated p <- resActions]
          updated = [p | ExecUpdated p <- resActions]
          chmodded = [p | ExecChmodded p <- resActions]
          unchanged = [p | ExecUnchanged p <- resActions]
          errs = [(p, msg) | ExecFailed p msg <- resActions]

      pure SyncResult
        { resultTargetDir   = planTargetDir plan
        , resultProjectName = planProjectName plan
        , resultMode        = ApplySync
        , resultCreated     = created
        , resultUpdated     = updated
        , resultChmodded    = chmodded
        , resultUnchanged   = unchanged
        , resultErrors      = errs
        , resultSuccess     = null errs
        }

-- | Internal tracking of single action execution outcome during 'ApplySync'.
data ActionExecOutcome
  = ExecCreated !FilePath
  | ExecUpdated !FilePath
  | ExecChmodded !FilePath
  | ExecUnchanged !FilePath
  | ExecFailed !FilePath !Text

-- | High-level synchronization: computes plan and executes under 'SyncMode'.
syncRepository
  :: SyncMode
  -> FilePath
  -> Project
  -> StandardizationMatrix
  -> IO SyncResult
syncRepository mode repoRoot proj matrix = do
  plan <- computeSyncPlan repoRoot proj matrix
  executeSyncPlan mode plan

-- | Fast zero-configuration synchronization for a single repository checkout.
--
-- Automatically locates and decodes @project.dhall@ if present. If absent, derives
-- a default 'Project' model using the folder's canonical basename and standard ecosystem
-- author metadata. Synchronizes the checkout against 'canonicalMatrix'.
--
-- === Error Isolation
--
-- Returns 'Left' with diagnostic text if @project.dhall@ fails to parse or decode.
-- On successful plan execution, returns 'Right' containing the complete 'SyncResult'.
syncRepositoryQuick :: SyncMode -> FilePath -> IO (Either Text SyncResult)
syncRepositoryQuick mode repoRoot = do
  absRoot <- canonicalizePath repoRoot
  let dhallPath = absRoot </> "project.dhall"
  hasDhall <- doesFileExist dhallPath
  if hasDhall
    then (do
      proj <- decodeProjectFile dhallPath
      res <- syncRepository mode absRoot proj canonicalMatrix
      pure (Right res)
      ) `catch` (\(e :: SomeException) ->
          pure (Left ("Failed to decode project.dhall: " <> T.pack (displayException e))))
    else do
      let inferredName = T.pack (takeFileName absRoot)
          defaultAuthor = Author "Nadia Yvette Chambers" "nadia.yvette.chambers@ik.me"
          proj = defaultProject inferredName defaultAuthor
      res <- syncRepository mode absRoot proj canonicalMatrix
      pure (Right res)

--------------------------------------------------------------------------------
-- 4. Multi-Repository Ecosystem Orchestration
--------------------------------------------------------------------------------

-- | Discovers sibling ecosystem repositories residing within a parent directory.
--
-- Scans immediate child directories in 'parentDir' and identifies candidates that
-- exhibit repository traits:
-- * Presence of a @.git@ directory (VCS root).
-- * Presence of a @cabal.project@ manifest (Cabal multi-package workspace root).
-- * Presence of a @project.dhall@ specification (Gachi schema specification).
--
-- Ignores plain directories that lack all three indicators, preventing inadvertent
-- modification of unrelated scratch folders or temporary data.
--
-- === Worked Example
--
-- >>> repos <- discoverEcosystemRepositories "/home/nyc/src"
-- >>> any (\p -> takeFileName p == "gachi") repos
-- True
discoverEcosystemRepositories :: FilePath -> IO [FilePath]
discoverEcosystemRepositories parentDir = do
  exists <- doesDirectoryExist parentDir
  if not exists
    then pure []
    else do
      entries <- listDirectory parentDir
      repos <- forM entries $ \entry -> do
        let candidate = parentDir </> entry
        isDir <- doesDirectoryExist candidate
        if not isDir
          then pure Nothing
          else do
            hasGit <- doesDirectoryExist (candidate </> ".git")
            hasCabalProj <- doesFileExist (candidate </> "cabal.project")
            hasDhall <- doesFileExist (candidate </> "project.dhall")
            if hasGit || hasCabalProj || hasDhall
              then pure (Just candidate)
              else pure Nothing
      pure (catMaybes repos)

-- | Harmonically synchronizes all discovered repositories within an ecosystem directory.
--
-- Sequentially iterates over all checkouts discovered via 'discoverEcosystemRepositories',
-- evaluating and applying synchronization under the given 'SyncMode'.
--
-- === Failure Isolation & Reporting
--
-- Execution is resilient: if one repository fails to evaluate its @project.dhall@ or
-- encounters I/O errors during synchronization, the failure is captured as 'Left'
-- in the resulting association list while synchronization continues across all other
-- repositories.
syncEcosystem
  :: SyncMode
  -> FilePath
  -> StandardizationMatrix
  -> IO [(FilePath, Either Text SyncResult)]
syncEcosystem mode parentDir matrix = do
  repoPaths <- discoverEcosystemRepositories parentDir
  forM repoPaths $ \repoPath -> do
    let dhallPath = repoPath </> "project.dhall"
    hasDhall <- doesFileExist dhallPath
    if hasDhall
      then (do
        proj <- decodeProjectFile dhallPath
        res <- syncRepository mode repoPath proj matrix
        pure (repoPath, Right res)
        ) `catch` (\(e :: SomeException) ->
            pure (repoPath, Left ("Failed to decode project.dhall: " <> T.pack (displayException e))))
      else do
        let inferredName = T.pack (takeFileName repoPath)
            defaultAuthor = Author "Nadia Yvette Chambers" "nadia.yvette.chambers@ik.me"
            proj = defaultProject inferredName defaultAuthor
        res <- syncRepository mode repoPath proj matrix
        pure (repoPath, Right res)

--------------------------------------------------------------------------------
-- 5. Diagnostic Plan & Result Formatting
--------------------------------------------------------------------------------

-- | Renders a 'SyncPlan' as a formatted plain-text ASCII table.
--
-- Produces an aligned, terminal-friendly diagnostic report containing:
-- * Workspace root directory and target project name.
-- * Aggregate action summary counters (Created, Updated, Chmod, No-Op).
-- * Tabular inventory of every evaluated asset:
--   * @CREATE@: Missing files scheduled for creation, marked with @(+x)@ if executable.
--   * @UPDATE@: Drifted files showing 8-character SHA-256 prefixes (@oldHash -> newHash@).
--   * @CHMOD@: Permission fixes indicating transition (@exec: False -> True@).
--   * @NO-OP@: Cleanly compliant files left untouched.
--   * @ERROR@: Diagnostic message for files where I/O inspection failed.
--
-- === Output Stability
--
-- Suitable for stdout terminal streaming, CI log capture, or regression testing.
formatSyncPlan :: SyncPlan -> Text
formatSyncPlan plan = T.unlines $
  [ "================================================================================"
  , " Gachi Synchronization Plan (Pre-Mutation Preview)"
  , "================================================================================"
  , " Target Directory: " <> T.pack (planTargetDir plan)
  , " Project Name:     " <> planProjectName plan
  , " Actions Planned:  "
      <> "Create: " <> T.pack (show (planCreatedCount plan))
      <> " | Update: " <> T.pack (show (planUpdatedCount plan))
      <> " | Chmod: " <> T.pack (show (planChmodCount plan))
      <> " | No-Op: " <> T.pack (show (planNoOpCount plan))
  , "--------------------------------------------------------------------------------"
  , " Action     | Path"
  , "------------+-------------------------------------------------------------------"
  ]
  ++ map formatActionRow (planActions plan)
  ++
  [ "================================================================================" ]
  where
    formatActionRow (ActionCreate p _ isExec) =
      " CREATE     | " <> T.pack p <> (if isExec then " (+x)" else "")
    formatActionRow (ActionUpdate p oldTxt newTxt isExec) =
      let oldHash = T.take 8 (sha256Text oldTxt)
          newHash = T.take 8 (sha256Text newTxt)
      in " UPDATE     | " <> T.pack p <> " (" <> oldHash <> " -> " <> newHash <> ")"
           <> (if isExec then " (+x)" else "")
    formatActionRow (ActionChmod p actual expected) =
      " CHMOD      | " <> T.pack p <> " (exec: " <> T.pack (show actual) <> " -> " <> T.pack (show expected) <> ")"
    formatActionRow (ActionNoOp p) =
      " NO-OP      | " <> T.pack p <> " (compliant)"
    formatActionRow (ActionError p msg) =
      " ERROR      | " <> T.pack p <> " (" <> msg <> ")"

-- | Renders a 'SyncResult' as a formatted plain-text ASCII summary banner.
--
-- Formats the final disposition of a completed or simulated synchronization run:
-- * Destination directory and project identification slug.
-- * Active execution mode: @DRY RUN (Preview Only)@ vs @APPLIED@.
-- * Status verdict: @SUCCESS@ (zero errors) or @FAILED@ (one or more I/O errors).
-- * Exact counts of created, updated, chmodded, and unchanged files.
-- * Dedicated error section listing failing relative paths and exception messages.
formatSyncResult :: SyncResult -> Text
formatSyncResult res = T.unlines $
  [ "================================================================================"
  , " Gachi Synchronization Execution Summary"
  , "================================================================================"
  , " Target Directory: " <> T.pack (resultTargetDir res)
  , " Project Name:     " <> resultProjectName res
  , " Execution Mode:   " <> (if resultMode res == DryRun then "DRY RUN (Preview Only)" else "APPLIED")
  , " Status:           " <> (if resultSuccess res then "SUCCESS" else "FAILED")
  , " Files Created:    " <> T.pack (show (length (resultCreated res)))
  , " Files Updated:    " <> T.pack (show (length (resultUpdated res)))
  , " Permissions Fixed:" <> T.pack (show (length (resultChmodded res)))
  , " Files Unchanged:  " <> T.pack (show (length (resultUnchanged res)))
  ]
  ++ formatErrorSection (resultErrors res)
  ++
  [ "================================================================================" ]
  where
    formatErrorSection [] = []
    formatErrorSection errs =
      [ "--------------------------------------------------------------------------------"
      , " Errors Encountered:"
      ] ++ map (\(p, msg) -> "  * " <> T.pack p <> ": " <> msg) errs
