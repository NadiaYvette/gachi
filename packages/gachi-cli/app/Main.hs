-- | Module: Main
-- Description: Executable entry point for the gachi CLI tool
--
-- This module serves as the physical binary entry point for the @gachi@ command-line
-- utility. It handles top-level process execution, argument consumption, and exit code
-- normalization by delegating immediately to 'Gachi.CLI.defaultMain'.
--
-- = Architectural Context & Invariants
--
-- In Gachi's infrastructure model (per Note [Ecosystem Standardization Invariants]
-- [ref:note-ecosystem-standardization]), the CLI executable provides turnkey
-- operations for repository scaffolding, configuration synchronization, codebase
-- retrofitting, and strategic planning.
--
-- == Process Execution Model
--
-- 1. __Environment Agnostic:__
--    The binary does not rely on ambient bash or Python scripts for execution logic;
--    all schema evaluation, filesystem synthesis, and Git configuration occur within
--    compiled Haskell runtime space.
--
-- 2. __Hermetic Process Termination:__
--    Process termination strictly reflects the outcome of the invoked subcommand.
--    Successful operations exit cleanly with 'System.Exit.ExitSuccess' (code 0).
--    Any syntax failure, schema mismatch, or filesystem collision terminates
--    immediately with 'System.Exit.ExitFailure' (code 1), preventing partial or
--    unstable workspaces from misleading downstream CI runners.
--
-- = Usage Summary
--
-- Invoked directly from the terminal or launcher scripts:
--
-- @
-- $ gachi init my-project
-- $ gachi init --config project.dhall --target-dir ./target
-- $ gachi version
-- @
module Main (main) where

import Gachi.CLI (defaultMain)

-- | Primary operating system process entry point.
--
-- Evaluates command-line flags and dispatches across operational subcommands via
-- 'Gachi.CLI.defaultMain'. Terminates the calling process with the appropriate
-- exit code upon completion.
main :: IO ()
main = defaultMain
