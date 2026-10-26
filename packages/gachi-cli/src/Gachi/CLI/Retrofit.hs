{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Module: Gachi.CLI.Retrofit
-- Description: Command execution engine for 'gachi retrofit'
--
-- This module coordinates the diagnostic inspection and non-destructive overlay
-- workflows for the @gachi retrofit@ subcommand (Phase 4).
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
--    In subsequent phases, applies pushout-amalgamated configurations, scaffolds missing
--    verification runners, and provisions agent operational layers without mutating
--    domain source files.
--
-- == Formatting Modes
--
-- * __Standard Terminal Mode (Default):__ Emits an 80-column aligned ASCII terminal
--   dashboard featuring boxed sections, Unicode score progress bars, and aligned checklists.
-- * __Markdown Mode (@--markdown@ / @-m@):__ Emits clean GitHub-Flavored Markdown tables
--   suitable for piping into @RETROFIT_PLAN.md@ or CI workflow artifacts.
-- * __Simulation Mode (@--dry-run@):__ Explicitly flags execution as purely observational,
--   reassuring developers that no filesystem changes are planned or applied.
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
  , runInspection
  ) where

import Control.Exception (SomeException, catch)
import Data.Maybe (fromMaybe)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import System.Directory (doesDirectoryExist)
import System.Exit (ExitCode(..))
import System.IO (stderr)

import Gachi.CLI.Options (RetrofitOptions(..))
import Gachi.Retrofit
  ( formatDiagnosticMarkdown
  , formatDiagnosticReport
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
-- 3. Dispatches to 'runInspection' to execute read-only static analysis and render
--    the diagnostic dashboard.
--
-- === Exit Codes
--
-- * 'ExitSuccess': Inspection completed and reported cleanly.
-- * 'ExitFailure 1': Target directory does not exist or was inaccessible.
runRetrofit :: RetrofitOptions -> IO ExitCode
runRetrofit opts = do
  let targetDir = fromMaybe "." (retrofitTargetDir opts)
  isDir <- doesDirectoryExist targetDir `catch` (\(_ :: SomeException) -> pure False)
  if not isDir
    then do
      TIO.hPutStrLn stderr ("gachi retrofit error: Target directory '" <> T.pack targetDir <> "' does not exist.")
      pure (ExitFailure 1)
    else runInspection targetDir (retrofitDryRun opts) (retrofitMarkdown opts)

--------------------------------------------------------------------------------
-- 2. Operational Routines
--------------------------------------------------------------------------------

-- | Performs the static diagnostic analysis of the target directory and prints
-- the formatted report to standard output.
--
-- Evaluates the target directory using 'scanRepository', renders the report using
-- 'formatDiagnosticMarkdown' or 'formatDiagnosticReport' according to the @--markdown@
-- flag, and outputs operational status indicators.
runInspection :: FilePath -> Bool -> Bool -> IO ExitCode
runInspection targetDir isDryRun isMarkdown = do
  report <- scanRepository targetDir
  if isMarkdown
    then TIO.putStr (formatDiagnosticMarkdown report)
    else TIO.putStr (formatDiagnosticReport report)

  if isDryRun
    then TIO.putStrLn "  [*] Simulation mode (--dry-run): No filesystem changes planned or applied."
    else TIO.putStrLn "  [*] Milestone 4.1 Diagnostic Scan complete. (Non-destructive overlay synthesis: Milestone 4.2)."
  pure ExitSuccess
