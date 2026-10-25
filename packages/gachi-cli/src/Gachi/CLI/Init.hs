{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Module: Gachi.CLI.Init
-- Description: Core execution engine and interactive wizard for 'gachi init'
--
-- This module implements the operational workflow for 'gachi init', providing
-- turnkey generation of standardized Haskell repositories from Dhall schemas,
-- command-line options, or interactive terminal prompts.
--
-- = Architectural Context & Invariants
--
-- {-
-- Note [CLI Ergonomics and Non-Destructive Initialization]
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- [tag:note-cli-init-ergonomics]
--
-- The `gachi init` command serves as the turnkey front door for the entire ecosystem.
-- To satisfy the ecosystem standardization matrix (Note [Ecosystem Standardization Invariants]
-- [ref:note-ecosystem-standardization]), the CLI must uphold four foundational ergonomic invariants:
--
-- 1. Dual-Path Specification:
--    The generator must support both declarative, machine-readable specifications via
--    Dhall configuration files (`--config project.dhall`), and zero-overhead CLI flags /
--    interactive wizardry for rapid prototyping.
--
-- 2. Non-Destructive Safety:
--    File materialization is governed by explicit execution modes ('FailOnExisting',
--    'SkipExisting', 'OverwriteExisting'). The default mode is 'FailOnExisting' to prevent
--    accidental data loss. Dry-run mode (`--dry-run`) previews all file paths, sizes,
--    and permissions without touching the filesystem.
--
-- 3. Turnkey Git Governance:
--    Immediately upon materializing files, `gachi init` executes hermetic Git initialization
--    unless explicitly disabled via `--no-git`. It pins `core.hooksPath` to `.githooks` and
--    `commit.template` to `.gitmessage`, enforcing Sarutahiko RFC 2822 commit trailer
--    discipline from commit zero.
--
-- 4. Five-Gate Verification Readiness:
--    Any workspace instantiated by `gachi init` must immediately pass all five physical
--    verification gates (`./bin/<project>-verify`) without requiring manual fixes or edits.
-- -}
--
-- = Worked Example
--
-- >>> import Gachi.CLI.Options
-- >>> import Gachi.Scaffold
-- >>> let opts = InitOptions (Just "sample") Nothing (Just "/tmp/sample") FailOnExisting Nothing Nothing Nothing [] True True False
-- >>> exitCode <- runInit opts
-- >>> exitCode == ExitSuccess
-- True
module Gachi.CLI.Init
  ( -- * High-Level Execution Entry Point
    runInit

    -- * Project Resolution Operations
  , resolveProject
  , detectGitAuthor
  , promptUser

    -- * Filesystem Materialization & Git Setup
  , executeScaffolding
  , initializeGitRepository
  ) where

import Control.Exception (SomeException, catch, try)
import Control.Monad (forM_, unless, when)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import System.Directory
  ( createDirectoryIfMissing
  , doesDirectoryExist
  , doesFileExist
  )
import System.Exit (ExitCode(..))
import System.FilePath ((</>))
import System.IO (hFlush, stderr, stdout)
import System.Process (readProcessWithExitCode)

import Gachi.CLI.Options (InitOptions(..))
import Gachi.Schema.Dhall (decodeProjectFile)
import Gachi.Schema.Project
  ( Author(..)
  , PackageSpec(..)
  , Project(..)
  , authorEmail
  , authorName
  , defaultProject
  , projectAuthor
  , projectDescription
  , projectName
  , projectPackages
  )
import Gachi.Scaffold
  ( FileEntry(..)
  , ScaffoldError(..)
  , ScaffoldResult(..)
  , generateAndWriteScaffold
  , generateProjectScaffold
  )

--------------------------------------------------------------------------------
-- 1. Main Subcommand Dispatcher
--------------------------------------------------------------------------------

-- | Executes the complete 'gachi init' lifecycle.
--
-- Dispatches across Dhall configuration decoding, interactive terminal wizardry,
-- filesystem materialization, and hermetic Git repository setup.
--
-- Returns 'ExitSuccess' upon successful completion, or 'ExitFailure 1' on error.
runInit :: InitOptions -> IO ExitCode
runInit opts = do
  res <- resolveProject opts
  case res of
    Left err -> do
      TIO.hPutStrLn stderr ("[-] Error: " <> err)
      pure (ExitFailure 1)
    Right (proj, targetDir) -> do
      handleScaffold proj targetDir opts

-- | Encapsulates scaffolding execution and exception handling.
--
-- Catches known 'ScaffoldError' exceptions ('DestinationExists' and 'FileWriteFailure')
-- and renders user-friendly diagnostic messages to stderr rather than crashing with an
-- unhandled runtime exception stack trace.
--
-- Returns 'ExitFailure 1' on error, or 'ExitSuccess' upon complete materialization.
handleScaffold :: Project -> FilePath -> InitOptions -> IO ExitCode
handleScaffold proj targetDir opts =
  executeScaffolding proj targetDir opts `catch` handler
  where
    handler :: ScaffoldError -> IO ExitCode
    handler (DestinationExists path) = do
      TIO.hPutStrLn stderr
        ( "[-] Error: Target file or directory already exists: "
       <> T.pack path
       <> "\n    Use '--mode overwrite' or '--mode skip' to permit writing to existing trees."
        )
      pure (ExitFailure 1)
    handler (FileWriteFailure path msg) = do
      TIO.hPutStrLn stderr
        ( "[-] Filesystem I/O Error at "
       <> T.pack path
       <> ": "
       <> T.pack msg
        )
      pure (ExitFailure 1)

--------------------------------------------------------------------------------
-- 2. Project Specification Resolution
--------------------------------------------------------------------------------

-- | Resolves a strongly-typed 'Project' specification and target destination directory.
--
-- Evaluates initialization configuration across three strictly prioritized channels:
--
-- 1. __Declarative Dhall File (@--config FILE@):__
--    Evaluates a user-supplied Dhall specification file on disk via 'decodeProjectFile'.
--    Relative schema imports are resolved hermetically relative to the file.
--    Any command-line flags provided simultaneously (@--author-name@, @--desc@, etc.)
--    are overlaid as overrides onto the resulting 'Project'.
--
-- 2. __Interactive Wizard (@--interactive@ / @-i@):__
--    Launches a friendly interactive terminal dialogue prompting for missing or
--    customized parameters, using ambient Git defaults as baseline suggestions.
--
-- 3. __CLI Flags & Ambient Defaults:__
--    When neither a configuration file nor interactive mode is specified, synthesizes
--    a canonical 'Project' using 'defaultProject', reading ambient Git author metadata
--    and applying CLI overrides.
--
-- Returns 'Left error' on missing configuration files or decoding failure, or
-- 'Right (project, targetDirectory)' ready for filesystem materialization.
resolveProject :: InitOptions -> IO (Either Text (Project, FilePath))
resolveProject opts = case initConfigFile opts of
  Just cfgPath -> do
    exists <- doesFileExist cfgPath
    if not exists
      then pure (Left ("Dhall configuration file not found: " <> T.pack cfgPath))
      else do
        dhallRes <- try (decodeProjectFile cfgPath) :: IO (Either SomeException Project)
        case dhallRes of
          Left err -> pure (Left ("Failed to decode Dhall specification: " <> T.pack (show err)))
          Right baseProj -> do
            let proj = applyCliOverrides opts baseProj
                targetDir = case initTargetDir opts of
                  Just d  -> d
                  Nothing -> T.unpack (projectName proj)
            pure (Right (proj, targetDir))
  Nothing
    | initInteractive opts -> do
        (proj, targetDir) <- runInteractiveWizard opts
        pure (Right (proj, targetDir))
    | otherwise -> do
        gitAuthor <- detectGitAuthor
        let pName = fromMaybe "my-project" (initProjectName opts)
            baseProj = defaultProject pName gitAuthor
            proj = applyCliOverrides opts baseProj
            targetDir = case initTargetDir opts of
              Just d  -> d
              Nothing -> T.unpack pName
        pure (Right (proj, targetDir))

-- | Overlays optional CLI command-line flags onto an existing 'Project' record.
--
-- Merges CLI flag inputs into the baseline specification according to precedence:
-- * 'initProjectName': Updates canonical project slug 'name' if provided.
-- * 'initDescription': Overrides 'description' if specified.
-- * 'initAuthorName' / 'initAuthorEmail': Overlays contact fields onto 'author'.
-- * 'initPackages': Replaces package list with new 'PackageSpec' records when non-empty.
--
-- Preserves all non-overridden fields (such as pinned toolchain versions, licenses,
-- and git remote mirrors).
applyCliOverrides :: InitOptions -> Project -> Project
applyCliOverrides opts proj =
  let pName = fromMaybe (projectName proj) (initProjectName opts)
      pDesc = fromMaybe (projectDescription proj) (initDescription opts)
      curAuth = projectAuthor proj
      aName = fromMaybe (authorName curAuth) (initAuthorName opts)
      aEmail = fromMaybe (authorEmail curAuth) (initAuthorEmail opts)
      auth = Author { name = aName, email = aEmail }
      pkgs = case initPackages opts of
        [] -> projectPackages proj
        ps -> [ PackageSpec p ("Domain package for " <> p) [] | p <- ps ]
  in proj
       { name = pName
       , description = pDesc
       , author = auth
       , packages = pkgs
       }

-- | Inspects ambient Git user configuration to auto-populate author metadata.
--
-- Queries @git config --get user.name@ and @git config --get user.email@ via
-- 'readProcessWithExitCode'. If either call fails (for example, when Git is not
-- installed or no global Git config exists), falls back to canonical ecosystem
-- defaults:
--
-- * Name: @"Nadia Yvette Chambers"@
-- * Email: @"nadia.yvette.chambers@ik.me"@
--
-- This ensures that automated CI environments and container builds always succeed
-- with reproducible author metadata.
detectGitAuthor :: IO Author
detectGitAuthor = do
  (cName, oName, _) <- readProcessWithExitCode "git" ["config", "--get", "user.name"] ""
    `catch` (\(_ :: SomeException) -> pure (ExitFailure 1, "", ""))
  (cEmail, oEmail, _) <- readProcessWithExitCode "git" ["config", "--get", "user.email"] ""
    `catch` (\(_ :: SomeException) -> pure (ExitFailure 1, "", ""))
  let nameTrimmed = T.strip (T.pack oName)
      emailTrimmed = T.strip (T.pack oEmail)
      authName = if cName == ExitSuccess && not (T.null nameTrimmed)
                   then nameTrimmed
                   else "Nadia Yvette Chambers"
      authEmail = if cEmail == ExitSuccess && not (T.null emailTrimmed)
                    then emailTrimmed
                    else "nadia.yvette.chambers@ik.me"
  pure Author { name = authName, email = authEmail }

--------------------------------------------------------------------------------
-- 3. Interactive Wizard
--------------------------------------------------------------------------------

-- | Interactive terminal prompt wizard gathering project initialization parameters.
runInteractiveWizard :: InitOptions -> IO (Project, FilePath)
runInteractiveWizard opts = do
  TIO.putStrLn "================================================================================"
  TIO.putStrLn "  gachi init — Interactive Workspace Scaffolding Wizard"
  TIO.putStrLn "================================================================================"
  defaultAuth <- detectGitAuthor

  let defaultName = fromMaybe "my-project" (initProjectName opts)
  pName <- promptUser "Project identifier slug" defaultName

  let defaultDesc = fromMaybe "Standardized multi-package Haskell workspace" (initDescription opts)
  pDesc <- promptUser "Project synopsis" defaultDesc

  let defaultAName = fromMaybe (authorName defaultAuth) (initAuthorName opts)
  aName <- promptUser "Author full name" defaultAName

  let defaultAEmail = fromMaybe (authorEmail defaultAuth) (initAuthorEmail opts)
  aEmail <- promptUser "Author email address" defaultAEmail

  let defaultPkgs = case initPackages opts of
        [] -> pName <> "-core"
        ps -> T.intercalate "," ps
  pkgsRaw <- promptUser "Packages to scaffold (comma-separated)" defaultPkgs
  let pkgNames = filter (not . T.null) (map T.strip (T.splitOn "," pkgsRaw))
      pkgSpecs = [ PackageSpec p ("Domain implementation for " <> p) [] | p <- pkgNames ]

  let defaultTarget = maybe pName T.pack (initTargetDir opts)
  targetRaw <- promptUser "Destination directory" defaultTarget

  let proj = Project
        { name = pName
        , description = pDesc
        , license = "EUPL-1.2"
        , author = Author { name = aName, email = aEmail }
        , ghcVersion = "9.14.1"
        , cabalVersion = "3.18"
        , packages = pkgSpecs
        , remotes = []
        }
  pure (proj, T.unpack targetRaw)

-- | Prompts the user on stdout with a default value fallback.
promptUser :: Text -> Text -> IO Text
promptUser label defVal = do
  TIO.putStr (label <> " [" <> defVal <> "]: ")
  hFlush stdout
  line <- TIO.getLine
  let trimmed = T.strip line
  pure (if T.null trimmed then defVal else trimmed)

--------------------------------------------------------------------------------
-- 4. Scaffolding & Filesystem Materialization
--------------------------------------------------------------------------------

-- | Materializes project assets or prints dry-run execution preview.
--
-- Evaluates execution branching:
-- * __Dry-Run Mode ('initDryRun' is True):__
--   Presents an in-memory preview of all planned files, their sizes in characters,
--   and executable permission flags without performing any disk mutations.
-- * __Materialization Mode ('initDryRun' is False):__
--   Creates the destination directory tree, writes files according to 'initMode'
--   ('FailOnExisting', 'SkipExisting', or 'OverwriteExisting'), initializes Git
--   governance unless disabled via 'initNoGit', and outputs the quick-start guide.
--
-- Returns 'ExitSuccess' upon successful execution, or raises 'ScaffoldError'.
executeScaffolding :: Project -> FilePath -> InitOptions -> IO ExitCode
executeScaffolding proj targetDir opts
  | initDryRun opts = do
      let entries = generateProjectScaffold proj
      TIO.putStrLn "--------------------------------------------------------------------------------"
      TIO.putStrLn ("DRY RUN: Simulating workspace generation for '" <> projectName proj <> "'")
      TIO.putStrLn ("Target directory: " <> T.pack targetDir)
      TIO.putStrLn "Planned file materialization:"
      forM_ entries $ \e -> do
        let execMark = if entryExecutable e then " [executable]" else ""
            size = T.pack (show (T.length (entryContent e)))
        TIO.putStrLn ("  - " <> T.pack (entryPath e) <> " (" <> size <> " chars)" <> execMark)
      TIO.putStrLn ("Total: " <> T.pack (show (length entries)) <> " files planned.")
      TIO.putStrLn "--------------------------------------------------------------------------------"
      pure ExitSuccess
  | otherwise = do
      createDirectoryIfMissing True targetDir
      res <- generateAndWriteScaffold targetDir (initMode opts) proj
      TIO.putStrLn ("[+] Successfully materialized " <> T.pack (show (length (writtenFiles res))) <> " files in " <> T.pack targetDir)
      unless (null (skippedFiles res)) $ do
        TIO.putStrLn ("[!] Skipped " <> T.pack (show (length (skippedFiles res))) <> " pre-existing files (mode: SkipExisting)")

      unlessNoGit (initNoGit opts) $ do
        initializeGitRepository targetDir

      printNextSteps proj targetDir
      pure ExitSuccess
  where
    unlessNoGit True _    = pure ()
    unlessNoGit False act = act

-- | Configures canonical Git governance (.githooks and .gitmessage) within target directory.
--
-- Executes hermetic Git setup steps:
-- 1. Checks if a @.git@ directory exists; if not, invokes @git init <targetDir>@.
-- 2. Sets local repository configuration @core.hooksPath = .githooks@ to activate
--    the Sarutahiko RFC 2822 commit message hook and pre-commit validation hook.
-- 3. Sets @commit.template = .gitmessage@ to standardize commit metadata prompts.
--
-- Silently handles failures if the @git@ executable is absent, allowing offline
-- workspace bootstrapping to proceed gracefully.
initializeGitRepository :: FilePath -> IO ()
initializeGitRepository targetDir = do
  let dotGit = targetDir </> ".git"
  gitExists <- doesDirectoryExist dotGit
  unless gitExists $ do
    (cInit, _, _) <- readProcessWithExitCode "git" ["init", targetDir] ""
      `catch` (\(_ :: SomeException) -> pure (ExitFailure 1, "", ""))
    when (cInit == ExitSuccess) $ do
      TIO.putStrLn "  [+] Initialized new Git repository."

  -- Configure Git hooks and commit template
  (cHooks, _, _) <- readProcessWithExitCode "git" ["-C", targetDir, "config", "core.hooksPath", ".githooks"] ""
    `catch` (\(_ :: SomeException) -> pure (ExitFailure 1, "", ""))
  (cTmpl, _, _) <- readProcessWithExitCode "git" ["-C", targetDir, "config", "commit.template", ".gitmessage"] ""
    `catch` (\(_ :: SomeException) -> pure (ExitFailure 1, "", ""))

  when (cHooks == ExitSuccess && cTmpl == ExitSuccess) $ do
    TIO.putStrLn "  [+] Configured Git governance (.githooks and .gitmessage commit trailer template)."

-- | Outputs standard quick-start instructions for the newly scaffolded project.
--
-- Displays terminal navigation commands and the canonical verification script
-- invocation (@./bin/<project>-verify@) to guide the developer immediately to
-- successful compilation and test execution.
printNextSteps :: Project -> FilePath -> IO ()
printNextSteps proj targetDir = do
  let pName = projectName proj
  TIO.putStrLn "================================================================================"
  TIO.putStrLn ("  Workspace '" <> pName <> "' is ready!")
  TIO.putStrLn ""
  TIO.putStrLn "  Quick Start:"
  TIO.putStrLn ("    cd " <> T.pack targetDir)
  TIO.putStrLn "    cabal build all"
  TIO.putStrLn "    cabal test all"
  TIO.putStrLn ("    ./bin/" <> pName <> "-verify")
  TIO.putStrLn "================================================================================"
