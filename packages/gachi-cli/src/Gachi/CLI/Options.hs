{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Module: Gachi.CLI.Options
-- Description: Command-line option parsing and data structures for gachi
--
-- This module defines the complete command hierarchy, flags, execution modes,
-- and applicative parsers for the unified @gachi@ command-line interface.
--
-- = Architectural Context & Invariants
--
-- Per Note [CLI Ergonomics and Non-Destructive Initialization]
-- [ref:note-cli-init-ergonomics], the command-line interface balances declarative
-- precision (loading typed Dhall schemas) with rapid-prototyping convenience
-- (CLI flags and interactive prompts).
--
-- == Command Hierarchy and Strategic Roadmap
--
-- The Gachi CLI establishes five primary operational subcommands designed to
-- govern the entire repository lifecycle across the ecosystem:
--
-- 1. __Workspace Initialization ('init'):__
--    Bootstraps a complete, standardized multi-package repository skeleton adhering to
--    all five verification gates immediately upon creation (Milestone 2.3).
--    Supports declarative Dhall files (@--config FILE@), CLI flag overrides, and
--    an interactive step-by-step terminal wizard (@--interactive@ / @-i@).
--
-- 2. __Harmonic Configuration Propagation ('sync'):__
--    Propagates unified toolchain pins, linters, pre-commit hooks, and verification
--    harnesses across heterogeneous repositories (Phase 3). Evaluates differential
--    changes using a bidirectional merge strategy without manual editing.
--
-- 3. __Non-Destructive Codebase Retrofitting ('retrofit'):__
--    Migrates legacy or non-standard Haskell repositories into the canonical Gachi
--    multi-package workspace layout (Phase 4). Preserves existing business logic while
--    inserting the universal verification infrastructure.
--
-- 4. __Roadmap & Snapshot Governance ('plan'):__
--    Interacts with detached Git storage and immutable ledger checkpoints (Phase 5).
--    Maintains atomic session states, branch histories, and multi-step rollbacks.
--
-- 5. __Version & Toolchain Diagnostics ('version'):__
--    Emits detailed build metadata, including active GHC compiler pinning (GHC 9.14.1),
--    Cabal specification target (Cabal 3.18), and licensing status (EUPL-1.2).
--
-- == Safety & Verification Invariants
--
-- * __Fail-Safe Defaults:__ All filesystem mutations default to 'FailOnExisting'
--   mode, preventing accidental clobbering of uncommitted user files or directories.
-- * __Dry-Run Capability:__ Every mutating subcommand provides a @--dry-run@ flag
--   enabling developers to inspect planned actions and file trees prior to execution.
-- * __Total Failure Modes:__ Option parsers fail cleanly with informative usage
--   diagnostics on invalid inputs rather than terminating with runtime exceptions.
--
-- = Worked Example
--
-- >>> import Options.Applicative
-- >>> let parseArgs = execParserPure defaultPrefs (info (commandParser "0.1.0.0") idm)
-- >>> case parseArgs ["init", "my-project", "--no-git"] of { Success (CmdInit opts) -> initNoGit opts; _ -> False }
-- True
module Gachi.CLI.Options
  ( -- * High-Level CLI Command Types
    Command(..)
  , InitOptions(..)
  , SyncOptions(..)
  , RetrofitOptions(..)
  , PlanOptions(..)

    -- * Mode and List Parsers
  , parseMode
  , parsePackageList

    -- * Optparse-Applicative Parsers
  , commandParser
  , initOptionsParser
  , syncOptionsParser
  , retrofitOptionsParser
  , planOptionsParser
  ) where

import Data.Char (toLower)
import Data.Text (Text)
import qualified Data.Text as T
import Options.Applicative
  ( Parser
  , ParserInfo
  , command
  , eitherReader
  , fullDesc
  , header
  , help
  , helper
  , hsubparser
  , info
  , long
  , many
  , metavar
  , option
  , optional
  , progDesc
  , short
  , strArgument
  , strOption
  , switch
  , value
  )

import Gachi.Scaffold (ScaffoldMode(..))

--------------------------------------------------------------------------------
-- 1. Command-Line AST & Option Types
--------------------------------------------------------------------------------

-- | Top-level command dispatcher covering all ecosystem operational subcommands.
data Command
  = CmdInit !InitOptions
    -- ^ Initialize a new standardized multi-package workspace ('gachi init').
  | CmdSync !SyncOptions
    -- ^ Harmonically synchronize configuration across repositories ('gachi sync').
  | CmdRetrofit !RetrofitOptions
    -- ^ Non-destructively retrofit an existing codebase ('gachi retrofit').
  | CmdPlan !PlanOptions
    -- ^ Manage ecosystem strategic roadmaps and rollback ('gachi plan').
  | CmdVersion
    -- ^ Print toolchain version, GHC pinning, and licensing stanzas.
  deriving stock (Eq, Show)

-- | Configuration parameters controlling the 'gachi init' scaffolding engine.
--
-- Governs pure specification resolution, terminal interaction, target destination paths,
-- filesystem write modes, and automated Git governance bootstrapping.
data InitOptions = InitOptions
  { initProjectName :: !(Maybe Text)
    -- ^ Positional project name (e.g., @"gongju"@). When supplied, defines the canonical
    -- project identifier, directory basename, Cabal workspace name, and verification harness slug.
  , initConfigFile  :: !(Maybe FilePath)
    -- ^ Optional path to declarative Dhall configuration file (@--config FILE@ / @-c FILE@).
    -- When specified, the schema is hermetically evaluated from disk, superseding positional defaults.
  , initTargetDir   :: !(Maybe FilePath)
    -- ^ Destination directory path (@--target-dir DIR@ / @-d DIR@).
    -- Defaults to @./<project-name>@ when omitted. Created recursively if non-existent.
  , initMode        :: !ScaffoldMode
    -- ^ Filesystem write mode: 'FailOnExisting' (abort on collision), 'SkipExisting' (preserve
    -- pre-existing files untouched), or 'OverwriteExisting' (clobber existing destination files).
  , initAuthorName  :: !(Maybe Text)
    -- ^ Override for author full personal or organizational name (@--author-name NAME@).
    -- Overrides values detected from ambient Git configuration (@user.name@).
  , initAuthorEmail :: !(Maybe Text)
    -- ^ Override for author contact email address (@--author-email EMAIL@).
    -- Overrides values detected from ambient Git configuration (@user.email@).
  , initDescription :: !(Maybe Text)
    -- ^ Override for high-level project synopsis or mission description (@--desc TEXT@).
    -- Embedded directly in generated README.md, cabal files, and package documentation.
  , initPackages    :: ![Text]
    -- ^ Optional comma-separated list of satellite packages to instantiate in the workspace.
    -- Each package receives a dedicated cabal manifest, test suite, and module hierarchy.
  , initNoGit       :: !Bool
    -- ^ Skip hermetic Git repository initialization and .githooks configuration (@--no-git@).
    -- Intended for generating sub-trees inside existing Git working copies or container sandboxes.
  , initDryRun      :: !Bool
    -- ^ Preview file tree generation and permissions without writing to disk (@--dry-run@).
    -- Prints an audit table containing relative paths, character counts, and executable marks.
  , initInteractive :: !Bool
    -- ^ Interactively prompt for missing project parameters (@--interactive@ / @-i@).
    -- Launches terminal wizard offering intelligent defaults drawn from ambient Git configuration.
  } deriving stock (Eq, Show)

-- | Configuration parameters controlling Phase 3 'gachi sync'.
--
-- Used to synchronize standardized ecosystem configuration across disparate repositories.
data SyncOptions = SyncOptions
  { syncTargetDir :: !(Maybe FilePath)
    -- ^ Target repository checkout directory to synchronize (@--target DIR@ / @-t DIR@).
    -- Defaults to current working directory when omitted.
  , syncDryRun    :: !Bool
    -- ^ Preview differential synchronization changes without mutating filesystem (@--dry-run@).
    -- Displays unified diffs and file permission updates planned by the synchronization engine.
  , syncAll       :: !Bool
    -- ^ Discover and synchronize all sibling repositories across the ecosystem parent directory (@--all@ / @-a@).
  } deriving stock (Eq, Show)

-- | Configuration parameters controlling Phase 4 'gachi retrofit'.
--
-- Used to migrate legacy or ad-hoc Haskell codebases into the standardized ecosystem hierarchy.
data RetrofitOptions = RetrofitOptions
  { retrofitTargetDir :: !(Maybe FilePath)
    -- ^ Legacy repository checkout directory to inspect and overlay (@--target DIR@ / @-t DIR@).
    -- Defaults to current working directory when omitted.
  , retrofitDryRun    :: !Bool
    -- ^ Preview retrofitting actions without modifying existing source files (@--dry-run@).
    -- Reports missing verification harnesses, hooks, and documentation skeletons.
  } deriving stock (Eq, Show)

-- | Configuration parameters controlling Phase 5 'gachi plan'.
--
-- Interacts with immutable ledger checkpoints and atomic rollback via detached git storage.
data PlanOptions = PlanOptions
  { planSubcommand :: !Text
    -- ^ Plan governance subcommand (e.g. @"checkpoint"@, @"diff"@, @"log"@, @"rollback"@).
    -- Dictates state store transitions and audit trail queries.
  , planArgs       :: ![Text]
    -- ^ Additional positional or keyword arguments supplied to the plan action.
    -- Passed verbatim to the underlying detached Git storage engine.
  } deriving stock (Eq, Show)

--------------------------------------------------------------------------------
-- 2. Parsing Helpers
--------------------------------------------------------------------------------

-- | Parses a textual write mode into a canonical 'ScaffoldMode'.
--
-- Accepts case-insensitive strings: @"fail"@, @"skip"@, or @"overwrite"@.
parseMode :: String -> Either String ScaffoldMode
parseMode raw = case map toLower raw of
  "fail"      -> Right FailOnExisting
  "skip"      -> Right SkipExisting
  "overwrite" -> Right OverwriteExisting
  other       -> Left ("Invalid write mode '" ++ other ++ "'. Expected 'fail', 'skip', or 'overwrite'.")

-- | Parses a comma-delimited string of package names into a cleaned list.
parsePackageList :: String -> Either String [Text]
parsePackageList raw =
  let pieces = map T.strip (T.splitOn "," (T.pack raw))
      filtered = filter (not . T.null) pieces
  in Right filtered

--------------------------------------------------------------------------------
-- 3. Top-Level Optparse Parser
--------------------------------------------------------------------------------

-- | Constructs the top-level 'ParserInfo' for the @gachi@ executable.
commandParser :: Text -> ParserInfo Command
commandParser ver =
  info (helper <*> mainParser)
    ( fullDesc
   <> header ("gachi v" ++ T.unpack ver ++ " — Ecosystem Skeleton Generator & Chattering Synchronizer")
   <> progDesc "Declarative Haskell project scaffolding, configuration propagation, and plan governance."
    )

-- | Dispatches across CLI subcommands.
mainParser :: Parser Command
mainParser = hsubparser
  ( command "init"
      (info (CmdInit <$> initOptionsParser)
        (progDesc "Initialize a new standardized multi-package Haskell workspace or satellite package"))
 <> command "sync"
      (info (CmdSync <$> syncOptionsParser)
        (progDesc "Harmonically synchronize configuration and governance stanzas across repositories (Phase 3)"))
 <> command "retrofit"
      (info (CmdRetrofit <$> retrofitOptionsParser)
        (progDesc "Non-destructively retrofit an existing codebase into the canonical ecosystem skeleton (Phase 4)"))
 <> command "plan"
      (info (CmdPlan <$> planOptionsParser)
        (progDesc "Manage ecosystem strategic roadmaps and atomic rollback via detached git storage (Phase 5)"))
 <> command "version"
      (info (pure CmdVersion)
        (progDesc "Display gachi version, compiler pinning, and licensing stanzas"))
  )

--------------------------------------------------------------------------------
-- 4. Subcommand Parsers
--------------------------------------------------------------------------------

-- | Applicative parser for 'InitOptions'.
--
-- Assembles options governing the 'gachi init' subcommand:
-- * Positional argument: Optional project identifier slug (e.g. @"gongju"@).
-- * Configuration flag (@--config@ / @-c@): Path to declarative Dhall schema file.
-- * Target directory (@--target-dir@ / @-d@): Output path (defaults to @./<project-name>@).
-- * Write mode (@--mode@ / @-m@): Safety policy ('FailOnExisting', 'SkipExisting', 'OverwriteExisting').
-- * Metadata overrides: @--author-name@, @--author-email@, and @--desc@.
-- * Satellite packages (@--packages@): Comma-delimited list of packages to instantiate.
-- * Operational switches: @--no-git@ (skip VCS setup), @--dry-run@ (simulation), @-i@ (interactive wizard).
initOptionsParser :: Parser InitOptions
initOptionsParser = InitOptions
  <$> optional
        ( strArgument
            ( metavar "PROJECT_NAME"
           <> help "Name of the project to initialize (e.g., 'gongju')"
            )
        )
  <*> optional
        ( strOption
            ( long "config"
           <> short 'c'
           <> metavar "FILE"
           <> help "Path to declarative Dhall project specification file (.dhall)"
            )
        )
  <*> optional
        ( strOption
            ( long "target-dir"
           <> short 'd'
           <> metavar "DIR"
           <> help "Destination directory for generated workspace (defaults to ./<project-name>)"
            )
        )
  <*> option (eitherReader parseMode)
        ( long "mode"
       <> short 'm'
       <> metavar "MODE"
       <> value FailOnExisting
       <> help "Filesystem write mode: 'fail', 'skip', or 'overwrite' (default: 'fail')"
        )
  <*> optional
        ( strOption
            ( long "author-name"
           <> metavar "NAME"
           <> help "Author full name override"
            )
        )
  <*> optional
        ( strOption
            ( long "author-email"
           <> metavar "EMAIL"
           <> help "Author email address override"
            )
        )
  <*> optional
        ( strOption
            ( long "desc"
           <> metavar "TEXT"
           <> help "High-level project synopsis or description override"
            )
        )
  <*> option (eitherReader parsePackageList)
        ( long "packages"
       <> metavar "PKG1,PKG2,..."
       <> value []
       <> help "Comma-separated list of satellite packages to instantiate"
        )
  <*> switch
        ( long "no-git"
       <> help "Skip Git repository initialization and .githooks configuration"
        )
  <*> switch
        ( long "dry-run"
       <> help "Simulate scaffolding generation and print summary without writing to disk"
        )
  <*> switch
        ( long "interactive"
       <> short 'i'
       <> help "Interactively prompt for missing configuration values"
        )

-- | Applicative parser for 'SyncOptions'.
--
-- Parses flags for cross-repository configuration synchronization (Phase 3):
-- * Target repository directory (@--target@ / @-t@).
-- * Dry-run simulation switch (@--dry-run@).
-- * All repositories discovery switch (@--all@ / @-a@).
syncOptionsParser :: Parser SyncOptions
syncOptionsParser = SyncOptions
  <$> optional
        ( strOption
            ( long "target"
           <> short 't'
           <> metavar "DIR"
           <> help "Target repository directory to synchronize"
            )
        )
  <*> switch
        ( long "dry-run"
       <> help "Preview synchronization diffs without mutating filesystem"
        )
  <*> switch
        ( long "all"
       <> short 'a'
       <> help "Discover and synchronize all repositories across the ecosystem parent directory"
        )

-- | Applicative parser for 'RetrofitOptions'.
--
-- Parses flags for non-destructive legacy codebase migration (Phase 4):
-- * Target codebase directory (@--target@ / @-t@).
-- * Dry-run simulation switch (@--dry-run@).
retrofitOptionsParser :: Parser RetrofitOptions
retrofitOptionsParser = RetrofitOptions
  <$> optional
        ( strOption
            ( long "target"
           <> short 't'
           <> metavar "DIR"
           <> help "Legacy repository directory to inspect and overlay"
            )
        )
  <*> switch
        ( long "dry-run"
       <> help "Preview retrofitting actions without modifying existing files"
        )

-- | Applicative parser for 'PlanOptions'.
--
-- Parses commands and arguments for detached Git state store management (Phase 5):
-- * Action subcommand (@checkpoint@, @diff@, @log@, @rollback@).
-- * Trailing positional arguments supplied directly to the plan engine.
planOptionsParser :: Parser PlanOptions
planOptionsParser = PlanOptions
  <$> strArgument
        ( metavar "SUBCOMMAND"
       <> help "Plan action: checkpoint, diff, log, or rollback"
        )
  <*> many
        ( strArgument
            ( metavar "ARGS..."
           <> help "Arguments supplied to the plan action"
            )
        )
