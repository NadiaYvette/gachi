{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Module: Gachi.CLI.Sync
-- Description: Command execution engine for 'gachi sync'
--
-- This module implements the operational workflow for the @gachi sync@ subcommand.
-- It coordinates differential scanning, plan calculation, and atomic propagation
-- across single repositories or the entire multi-repository ecosystem.
--
-- = Architectural Context & Invariants
--
-- In accordance with Note [Harmonic Chattering Synchronization and Differential Propagation]
-- [ref:note-harmonic-sync] and Note [Ecosystem Standardization Invariants]
-- [ref:note-ecosystem-standardization], @gachi sync@ provides the automated mechanism
-- that brings disparate repositories into structural resonance with the canonical
-- Standardization Matrix.
--
-- == Operational Workflow
--
-- The synchronization command executes through the following phased sequence:
--
-- 1. __Target Resolution:__
--    Resolves whether the user intends to synchronize a single target repository
--    (the default, pointing to current working directory or explicit @--target@)
--    or perform ecosystem-wide orchestration via @--all@.
--
-- 2. __Differential Scan & Plan Construction:__
--    Evaluates each target checkout against the 9-dimensional canonical matrix
--    ('canonicalMatrix'), computing a pure 'SyncPlan' that categorizes every asset
--    into 'ActionCreate', 'ActionUpdate', 'ActionChmod', or 'ActionNoOp'.
--
-- 3. __Execution Mode Enforcement:__
--    * __'DryRun' (@--dry-run@):__ Emits ASCII audit tables detailing proposed
--      creations, diffs, and permission adjustments without mutating disk.
--    * __'ApplySync' (Default):__ Materializes missing files, writes updated
--      canonical contents, and sets owner executable bits where required.
--
-- 4. __Idempotency Verification:__
--    All updates are deterministic and mathematically idempotent. A secondary
--    invocation over a synchronized workspace results in zero modifications.
--
-- = Worked Example
--
-- >>> import Gachi.CLI.Options (SyncOptions(..))
-- >>> let opts = SyncOptions (Just "/home/nyc/src/gachi") True False
-- >>> code <- runSync opts
-- >>> code == ExitSuccess
-- True
module Gachi.CLI.Sync
  ( -- * High-Level Subcommand Runner
    runSync

    -- * Operational Execution Routines
  , runSingleSync
  , runEcosystemSync

    -- * Summary Formatting
  , formatEcosystemSummary
  ) where

import Control.Monad (forM_)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import System.Directory (doesDirectoryExist)
import System.Exit (ExitCode(..))
import System.FilePath (takeFileName)
import System.IO (stderr)

import Gachi.CLI.Options (SyncOptions(..))
import Gachi.Sync
  ( StandardizationMatrix
  , SyncMode(..)
  , SyncResult(..)
  , canonicalMatrix
  , discoverEcosystemRepositories
  , formatSyncResult
  , syncEcosystem
  , syncRepositoryQuick
  )

--------------------------------------------------------------------------------
-- 1. High-Level Subcommand Runner
--------------------------------------------------------------------------------

-- | Executes the @gachi sync@ subcommand from parsed 'SyncOptions'.
--
-- === Dispatch Strategy & Flags
--
-- 1. __Execution Mode Selection:__
--    Evaluates 'syncDryRun':
--    * When @--dry-run@ is specified, selects 'DryRun' mode, performing read-only
--      cryptographic differential auditing without disk mutation.
--    * Otherwise, selects 'ApplySync' mode to write canonical contents and enforce
--      executable bit permissions.
--
-- 2. __Scope Resolution:__
--    * __Ecosystem Scope (@--all@ / @-a@):__
--      Delegates to 'runEcosystemSync', discovering all sibling repositories in the
--      target directory (or current working directory if @--target@ is omitted) and
--      harmonizing each discovered checkout in sequence.
--    * __Targeted Repository Scope (Default):__
--      Delegates to 'runSingleSync', synchronizing only the specified directory.
--
-- 3. __Exit Code Normalization:__
--    * Returns 'ExitSuccess' when all planned synchronization tasks conclude without
--      disk writing exceptions or unparseable schema files.
--    * Returns 'ExitFailure 1' if unrecoverable filesystem errors or schema errors occur.
runSync :: SyncOptions -> IO ExitCode
runSync opts = do
  let mode = if syncDryRun opts then DryRun else ApplySync
      target = fromMaybe "." (syncTargetDir opts)
  if syncAll opts
    then runEcosystemSync mode target canonicalMatrix
    else runSingleSync mode target

--------------------------------------------------------------------------------
-- 2. Single Repository Synchronization
--------------------------------------------------------------------------------

-- | Synchronizes a single repository checkout against 'canonicalMatrix'.
--
-- Automatically locates and decodes @project.dhall@ if present, or infers
-- default project identity from directory naming. Emits detailed diagnostic
-- ASCII summary tables describing all executed or simulated actions.
--
-- === Operational Safety
--
-- * Checks for target directory existence prior to performing any operations.
-- * Delegates to 'syncRepositoryQuick', which runs under pure SHA-256 differential
--   scanning.
-- * Emits the formatted plan/result table via 'formatSyncResult'.
-- * Returns 'ExitSuccess' if all actions succeeded, or 'ExitFailure 1' on errors.
runSingleSync :: SyncMode -> FilePath -> IO ExitCode
runSingleSync mode targetDir = do
  exists <- doesDirectoryExist targetDir
  if not exists
    then do
      TIO.hPutStrLn stderr ("Target directory does not exist: " <> T.pack targetDir)
      pure (ExitFailure 1)
    else do
      res <- syncRepositoryQuick mode targetDir
      case res of
        Left err -> do
          TIO.hPutStrLn stderr ("Synchronization failed for " <> T.pack targetDir <> ": " <> err)
          pure (ExitFailure 1)
        Right result -> do
          TIO.putStrLn (formatSyncResult result)
          if resultSuccess result
            then pure ExitSuccess
            else pure (ExitFailure 1)

--------------------------------------------------------------------------------
-- 3. Ecosystem-Wide Multi-Repository Orchestration
--------------------------------------------------------------------------------

-- | Discovers and harmonically synchronizes all repositories in a parent directory.
--
-- Scans the specified parent directory for sibling repository checkouts, evaluates
-- differential synchronization plans for each repository, and renders a consolidated
-- audit matrix detailing the health and synchronization status across the ecosystem.
--
-- === Discovery and Batch Processing
--
-- 1. Verifies existence of the parent directory.
-- 2. Discovers child repositories via 'discoverEcosystemRepositories', identifying
--    folders containing @.git@, @cabal.project@, or @project.dhall@.
-- 3. Displays discovered repository paths and begins sequential synchronization.
-- 4. Emits a consolidated ecosystem table via 'formatEcosystemSummary'.
-- 5. Returns 'ExitSuccess' if every repository synchronized without error, or
--    'ExitFailure 1' if any repository encountered failures.
runEcosystemSync :: SyncMode -> FilePath -> StandardizationMatrix -> IO ExitCode
runEcosystemSync mode parentDir matrix = do
  exists <- doesDirectoryExist parentDir
  if not exists
    then do
      TIO.hPutStrLn stderr ("Ecosystem directory does not exist: " <> T.pack parentDir)
      pure (ExitFailure 1)
    else do
      repos <- discoverEcosystemRepositories parentDir
      if null repos
        then do
          TIO.putStrLn ("No repositories discovered under: " <> T.pack parentDir)
          pure ExitSuccess
        else do
          TIO.putStrLn ("Discovered " <> T.pack (show (length repos)) <> " repositories under " <> T.pack parentDir <> ":")
          forM_ repos $ \repo ->
            TIO.putStrLn ("  • " <> T.pack (takeFileName repo) <> " (" <> T.pack repo <> ")")
          TIO.putStrLn ""

          results <- syncEcosystem mode parentDir matrix
          let summary = formatEcosystemSummary mode results
          TIO.putStrLn summary

          let allSuccessful = all isResultSuccess results
          if allSuccessful
            then pure ExitSuccess
            else pure (ExitFailure 1)
  where
    isResultSuccess :: (FilePath, Either Text SyncResult) -> Bool
    isResultSuccess (_, Right res) = resultSuccess res
    isResultSuccess (_, Left _)    = False

--------------------------------------------------------------------------------
-- 4. Ecosystem Summary Reporting
--------------------------------------------------------------------------------

-- | Formats a tabular ASCII overview of ecosystem synchronization outcomes.
--
-- Renders a multi-column report displaying the structural alignment across all
-- discovered repositories in the target ecosystem directory.
--
-- === Table Architecture & Columns
--
-- The generated matrix contains eight informative columns:
--
-- 1. __Repository (20 chars):__ The folder basename of the discovered checkout.
-- 2. __Mode (10 chars):__ @DRY-RUN@ preview simulation vs @APPLIED@ live mutation.
-- 3. __Created (7 chars):__ Number of previously missing files synthesized.
-- 4. __Updated (7 chars):__ Number of drifted files restored to canonical form.
-- 5. __Chmod (7 chars):__ Number of scripts whose executable bits were corrected.
-- 6. __Unchanged (9 chars):__ Number of assets already in clean compliance.
-- 7. __Errors (6 chars):__ Count of I/O failures or Dhall decoding exceptions.
-- 8. __Disposition (11 chars):__
--    * @RESONANT@: Repository is in full compliance with zero errors.
--    * @DRIFTED@: Discrepancies exist (only possible under DryRun mode).
--    * @FAILED@: One or more I/O or evaluation exceptions occurred.
--
-- === Summary Footer
--
-- Emits aggregate counters indicating the total number of evaluated repositories,
-- how many achieved full resonance, and how many encountered errors.
formatEcosystemSummary :: SyncMode -> [(FilePath, Either Text SyncResult)] -> Text
formatEcosystemSummary mode results =
  let sep = "+----------------------+------------+---------+---------+---------+-----------+--------+-------------+"
      hdr = "| Repository           | Mode       | Created | Updated | Chmod   | Unchanged | Errors | Disposition |"
      rows = map formatRow results
      totalRepos = length results
      successfulRepos = length (filter (\(_, r) -> case r of Right res -> resultSuccess res; Left _ -> False) results)
      footer = "Total Repositories: " <> T.pack (show totalRepos)
            <> " | Resonant: " <> T.pack (show successfulRepos)
            <> " | Failed: " <> T.pack (show (totalRepos - successfulRepos))
  in T.unlines ([sep, hdr, sep] ++ rows ++ [sep, footer])
  where
    -- | Formats an individual repository's synchronization outcome into a padded table row.
    -- Handles both failed evaluations (schema errors, missing paths) and successful runs.
    formatRow (path, outcome) =
      let repoSlug = T.pack (takeFileName path)
          -- Helper to right-pad text values to fixed column width
          pad n t = if T.length t >= n then T.take n t else t <> T.replicate (n - T.length t) " "
          modeStr = case mode of DryRun -> "DRY-RUN"; ApplySync -> "APPLIED"
      in case outcome of
        -- Branch A: Unhandled failure during Dhall evaluation or repository access
        Left _err ->
          "| " <> pad 20 repoSlug
          <> " | " <> pad 10 modeStr
          <> " | " <> pad 7 "-"
          <> " | " <> pad 7 "-"
          <> " | " <> pad 7 "-"
          <> " | " <> pad 9 "-"
          <> " | " <> pad 6 "1"
          <> " | " <> pad 11 "FAILED" <> " |"
        -- Branch B: Structured synchronization outcome with per-category counters
        Right res ->
          let cStr = T.pack (show (length (resultCreated res)))
              uStr = T.pack (show (length (resultUpdated res)))
              mStr = T.pack (show (length (resultChmodded res)))
              kStr = T.pack (show (length (resultUnchanged res)))
              eStr = T.pack (show (length (resultErrors res)))
              disp = if resultSuccess res then "RESONANT" else "DRIFTED"
          in "| " <> pad 20 repoSlug
             <> " | " <> pad 10 modeStr
             <> " | " <> pad 7 cStr
             <> " | " <> pad 7 uStr
             <> " | " <> pad 7 mStr
             <> " | " <> pad 9 kStr
             <> " | " <> pad 6 eStr
             <> " | " <> pad 11 disp <> " |"
