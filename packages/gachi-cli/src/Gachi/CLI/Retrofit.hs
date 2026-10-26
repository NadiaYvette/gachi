{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Module: Gachi.CLI.Retrofit
-- Description: Command execution engine for 'gachi retrofit'
--
-- This module coordinates the diagnostic inspection and non-destructive overlay
-- workflows for the @gachi retrofit@ subcommand (Milestones 4.1 & 4.2, Phase 4).
--
-- = Architectural Context & Invariants
--
-- Per Note [Non-Destructive Skeleton Overlay] [ref:note-nondestructive-retrofit],
-- retrofitting operations adopt legacy, single-package, or external repositories
-- into the canonical ecosystem skeleton without altering domain code.
--
-- == Operational Workflow
--
-- The retrofitting execution lifecycle unfolds in two stages:
--
-- 1. __Diagnostic Inspection (Milestone 4.1):__
--    Executes the comprehensive 'DiagnosticReport' scanner, evaluating:
--    - Programming language distribution and file percentages.
--    - Build tool manifests and workspace topography.
--    - Test infrastructure and declared test suites.
--    - Documentation gaps relative to @DOC_STRATEGY.md@.
--    - Git governance, hook executability, and RFC 2822 @Assisted-by:@ trailer validation.
--    - Physical verification harnesses and quality gates.
--
-- 2. __Non-Destructive Overlay (Milestone 4.2):__
--    Computes the 'OverlayPlan', categorizing missing standardized assets as 'ActionCreate'
--    and pre-existing files as 'ActionPreserve'. In live execution mode, writes missing
--    documentation, agent rules, Git hooks, and verification runners with executable permissions
--    and configures Git governance without touching domain source files.
--
-- == Formatting & Execution Modes
--
-- * __Standard Terminal Mode (Default):__ Emits an 80-column aligned ASCII terminal
--   dashboard featuring boxed sections, Unicode score progress bars, and aligned checklists.
-- * __Markdown Mode (@--markdown@ / @-m@):__ Emits clean GitHub-Flavored Markdown tables
--   suitable for piping into @RETROFIT_PLAN.md@ or CI workflow artifacts.
-- * __Simulation Mode (@--dry-run@):__ Previews the diagnostic inspection report and
--   the proposed non-destructive overlay plan without modifying any filesystem files.
-- * __Materialization Mode (Live):__ Materializes the overlay plan and activates Git
--   governance hooks in the target repository.
--
-- = Worked Example
--
-- >>> import Gachi.CLI.Options (RetrofitOptions(..))
-- >>> let opts = RetrofitOptions (Just ".") True False
-- >>> code <- runRetrofit opts
-- >>> code == ExitSuccess
-- True
module Gachi.CLI.Retrofit
  ( -- * High-Level Subcommand Runner
    runRetrofit

    -- * Operational Execution Routines
  , runInspectionAndOverlay
  ) where

import Control.Exception (SomeException, catch)
import Control.Monad (unless)
import Data.Maybe (fromMaybe)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import System.Directory (doesDirectoryExist)
import System.Exit (ExitCode(..))
import System.IO (stderr)

import Gachi.CLI.Options (RetrofitOptions(..))
import Gachi.Retrofit
  ( OverlayResult(..)
  , computeOverlayPlan
  , executeOverlayPlan
  , formatDiagnosticMarkdown
  , formatDiagnosticReport
  , formatOverlayPlan
  , formatOverlayPlanMarkdown
  , formatOverlayResult
  , scanRepository
  )

--------------------------------------------------------------------------------
-- 1. High-Level Subcommand Runner
--------------------------------------------------------------------------------

-- | Executes the @gachi retrofit@ subcommand from parsed 'RetrofitOptions'.
--
-- === Execution Steps
--
-- 1. Resolves target directory from 'retrofitTargetDir', defaulting to current working
--    directory (@.@) when omitted.
-- 2. Verifies physical existence of the target directory on disk, failing cleanly
--    with 'ExitFailure 1' if missing.
-- 3. Dispatches to 'runInspectionAndOverlay' to execute diagnostic analysis, compute
--    the non-destructive overlay plan, and optionally apply disk materializations.
--
-- === Exit Codes
--
-- * 'ExitSuccess': Inspection and overlay completed successfully.
-- * 'ExitFailure 1': Target directory does not exist or was inaccessible.
runRetrofit :: RetrofitOptions -> IO ExitCode
runRetrofit opts = do
  let targetDir = fromMaybe "." (retrofitTargetDir opts)
  isDir <- doesDirectoryExist targetDir `catch` (\(_ :: SomeException) -> pure False)
  if not isDir
    then do
      TIO.hPutStrLn stderr ("gachi retrofit error: Target directory '" <> T.pack targetDir <> "' does not exist.")
      pure (ExitFailure 1)
    else runInspectionAndOverlay targetDir (retrofitDryRun opts) (retrofitMarkdown opts)

--------------------------------------------------------------------------------
-- 2. Operational Routines
--------------------------------------------------------------------------------

-- | Performs the static diagnostic analysis of the target directory, computes
-- the non-destructive overlay plan, and conditionally executes the materialization.
--
-- Observes Note [Non-Destructive Skeleton Overlay] [ref:note-nondestructive-retrofit]:
-- in simulation mode (@--dry-run@), displays the proposed overlay actions without disk mutations;
-- in materialization mode, writes missing standardized assets and pins Git governance.
runInspectionAndOverlay :: FilePath -> Bool -> Bool -> IO ExitCode
runInspectionAndOverlay targetDir isDryRun isMarkdown = do
  -- 1. Milestone 4.1 Diagnostic Inspection
  report <- scanRepository targetDir
  if isMarkdown
    then TIO.putStr (formatDiagnosticMarkdown report)
    else TIO.putStr (formatDiagnosticReport report)

  -- 2. Milestone 4.2 Non-Destructive Overlay Plan Computation
  plan <- computeOverlayPlan targetDir report

  -- 3. Execution or Simulation Branching
  if isDryRun
    then do
      if isMarkdown
        then TIO.putStr (formatOverlayPlanMarkdown plan)
        else TIO.putStr (formatOverlayPlan plan)
      TIO.putStrLn "  [*] Simulation mode (--dry-run): No filesystem changes planned or applied."
    else do
      unlessMarkdown $ TIO.putStr (formatOverlayPlan plan)
      result <- executeOverlayPlan plan
      if isMarkdown
        then do
          TIO.putStrLn ""
          TIO.putStrLn "## Overlay Materialization Result"
          TIO.putStrLn ""
          TIO.putStrLn ("- **Files Created:** " <> T.pack (show (length (resultCreatedFiles result))))
          TIO.putStrLn ("- **Files Preserved:** " <> T.pack (show (length (resultPreservedFiles result))))
          TIO.putStrLn ("- **Git Actions:** " <> T.pack (show (length (resultGitActions result))))
        else TIO.putStr (formatOverlayResult result)
      TIO.putStrLn "  [+] Milestone 4.2 Non-Destructive Skeleton Overlay applied successfully."

  pure ExitSuccess
  where
    unlessMarkdown = unless isMarkdown
