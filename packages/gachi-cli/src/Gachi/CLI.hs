{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Module: Gachi.CLI
-- Description: Unified front-door dispatcher and entry point for gachi
--
-- This is the root library module for @gachi-cli@. It provides top-level command
-- line argument parsing, dispatching, version reporting, and error handling.
--
-- = Architectural Context & Invariants
--
-- Gachi serves as the foundational project skeleton generator and configuration
-- propagation engine across the ecosystem (per Note [Ecosystem Standardization Invariants]
-- [ref:note-ecosystem-standardization]).
--
-- == Operational Architecture
--
-- This module acts as the primary orchestrator and dispatcher across all CLI subcommands:
--
-- 1. __Argument Processing:__
--    Uses @optparse-applicative@ configured with 'showHelpOnEmpty' to display context-aware
--    usage hints whenever an empty invocation or ambiguous argument sequence is detected.
--
-- 2. __Execution Lifecycle:__
--    Dispatches parsed 'Command' representations to their specialized execution modules.
--    'CmdInit' delegates to 'runInit' in "Gachi.CLI.Init", while placeholder routines
--    for Phase 3 ('CmdSync'), Phase 4 ('CmdRetrofit'), and Phase 5 ('CmdPlan') provide
--    informative scheduling notices without failing abruptly.
--
-- 3. __Exit Code Normalization:__
--    Every subcommand produces a deterministic 'ExitCode' ('ExitSuccess' or 'ExitFailure'),
--    ensuring predictable interaction with shell scripts, CI runners, and pre-commit hooks.
--
-- = Command Matrix
--
-- * 'gachi init': Full turnkey multi-package repository materialization (Milestone 2.3).
-- * 'gachi sync': Bidirectional configuration synchronization (Phase 3).
-- * 'gachi retrofit': Non-destructive legacy codebase upgrade (Phase 4).
-- * 'gachi plan': Detached git snapshotting and rollback (Phase 5).
-- * 'gachi version': Compiler and tooling pinning diagnostics.
--
-- = Worked Example
--
-- >>> import Gachi.CLI
-- >>> -- Invoked from executable Main:
-- >>> -- defaultMain
module Gachi.CLI
  ( -- * Main CLI Dispatcher
    defaultMain
  , runCommand

    -- * Package Metadata
  , gachiVersion

    -- * Re-exports
  , module Gachi.CLI.Init
  , module Gachi.CLI.Options
  , module Gachi.CLI.Sync
  ) where

import Data.Text (Text)
import qualified Data.Text.IO as TIO
import Options.Applicative (customExecParser, prefs, showHelpOnEmpty)
import System.Exit (ExitCode(..), exitWith)

import Gachi.CLI.Init
  ( detectGitAuthor
  , executeScaffolding
  , initializeGitRepository
  , promptUser
  , resolveProject
  , runInit
  )
import Gachi.CLI.Options
  ( Command(..)
  , InitOptions(..)
  , PlanOptions(..)
  , RetrofitOptions(..)
  , SyncOptions(..)
  , commandParser
  , initOptionsParser
  , parseMode
  , parsePackageList
  , planOptionsParser
  , retrofitOptionsParser
  , syncOptionsParser
  )
import Gachi.CLI.Sync (runSync)

--------------------------------------------------------------------------------
-- 1. Metadata
--------------------------------------------------------------------------------

-- | Canonical version identifier for the gachi toolchain.
gachiVersion :: Text
gachiVersion = "0.1.0.0"

--------------------------------------------------------------------------------
-- 2. Top-Level Entry Points
--------------------------------------------------------------------------------

-- | High-level executable entry point.
--
-- Parses ambient command-line arguments using 'commandParser' and delegates
-- to 'runCommand', terminating the process with the resulting 'ExitCode'.
defaultMain :: IO ()
defaultMain = do
  let parserPrefs = prefs showHelpOnEmpty
  cmd <- customExecParser parserPrefs (commandParser gachiVersion)
  code <- runCommand cmd
  exitWith code

-- | Pure/IO command dispatcher executing a parsed 'Command'.
--
-- Maps high-level AST commands to operational routines:
--
-- * 'CmdInit': Dispatches directly to 'runInit', executing the complete project
--   synthesis, filesystem materialization, and Git governance lifecycle.
-- * 'CmdSync': Dispatches directly to 'runSync', harmonizing configuration and
--   governance stanzas across single repositories or the entire ecosystem.
-- * 'CmdRetrofit': Emits roadmap schedule notice for Phase 4 codebase retrofitting.
-- * 'CmdPlan': Emits roadmap schedule notice for Phase 5 detached Git ledger governance.
-- * 'CmdVersion': Outputs compiler pinning, Cabal target, and EUPL-1.2 licensing stanzas.
--
-- Guarantees total evaluation with deterministic exit code propagation.
runCommand :: Command -> IO ExitCode
runCommand (CmdInit opts) = runInit opts
runCommand (CmdSync opts) = runSync opts
runCommand (CmdRetrofit _opts) = do
  TIO.putStrLn "gachi retrofit: Non-destructive codebase retrofitting (Phase 4 - Scheduled)"
  pure ExitSuccess
runCommand (CmdPlan _opts) = do
  TIO.putStrLn "gachi plan: Detached Git store & snapshot rollback engine (Phase 5 - Scheduled)"
  pure ExitSuccess
runCommand CmdVersion = do
  TIO.putStrLn ("gachi v" <> gachiVersion <> " (GHC 9.14.1 / Cabal 3.18 / EUPL-1.2)")
  pure ExitSuccess
