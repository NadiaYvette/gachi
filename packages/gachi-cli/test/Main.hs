{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Module: Main
-- Description: Comprehensive specification and verification suite for gachi-cli
--
-- Validates:
-- 1. CLI option and flag parsing across subcommands and modes.
-- 2. Pure resolution of project specifications from Dhall files and CLI options.
-- 3. Headless workspace instantiation and filesystem materialization.
-- 4. Hermetic Git repository initialization and trailer governance (.githooks / .gitmessage).
-- 5. Execution modes ('FailOnExisting', 'SkipExisting', 'OverwriteExisting', '--dry-run').
module Main (main) where

import Control.Exception (SomeException, bracket, catch)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Data.Time.Clock.POSIX (getPOSIXTime)
import Options.Applicative
  ( ParserResult(..)
  , defaultPrefs
  , execParserPure
  )
import System.Directory
  ( createDirectoryIfMissing
  , doesDirectoryExist
  , doesFileExist
  , executable
  , getPermissions
  , getTemporaryDirectory
  , removeDirectoryRecursive
  )
import System.Exit (ExitCode(..))
import System.FilePath ((</>), takeFileName)
import System.Process (readProcessWithExitCode)
import Test.Hspec

import Gachi.CLI
import Gachi.Schema.Dhall (exampleProjectDhall)
import Gachi.Schema.Project
  ( authorEmail
  , authorName
  , projectAuthor
  , projectName
  )
import Gachi.Scaffold (ScaffoldMode(..))

-- | Helper executing an action within an isolated temporary directory.
withTempDir :: String -> (FilePath -> IO a) -> IO a
withTempDir prefix action = do
  base <- getTemporaryDirectory
  t <- getPOSIXTime
  let dirPath = base </> (prefix ++ "-" ++ show (round (t * 1000) :: Integer))
  bracket
    (createDirectoryIfMissing True dirPath >> pure dirPath)
    (\p -> catch (removeDirectoryRecursive p) (\(_ :: SomeException) -> pure ()))
    action

main :: IO ()
main = hspec $ do
  describe "Gachi.CLI.Options (Option Parsing)" $ do
    it "parses default 'init' with project name positional" $ do
      let res = execParserPure defaultPrefs (commandParser "0.1.0.0") ["init", "my-project"]
      case res of
        Success (CmdInit opts) -> do
          initProjectName opts `shouldBe` Just "my-project"
          initConfigFile opts `shouldBe` Nothing
          initMode opts `shouldBe` FailOnExisting
          initNoGit opts `shouldBe` False
          initDryRun opts `shouldBe` False
        _ -> expectationFailure "Expected Success (CmdInit opts)"

    it "parses 'init' with Dhall config file and target directory" $ do
      let res = execParserPure defaultPrefs (commandParser "0.1.0.0")
                  ["init", "-c", "custom.dhall", "-d", "/tmp/target", "-m", "overwrite", "--no-git"]
      case res of
        Success (CmdInit opts) -> do
          initConfigFile opts `shouldBe` Just "custom.dhall"
          initTargetDir opts `shouldBe` Just "/tmp/target"
          initMode opts `shouldBe` OverwriteExisting
          initNoGit opts `shouldBe` True
        _ -> expectationFailure "Expected Success (CmdInit opts)"

    it "parses 'init' with satellite package list and description" $ do
      let res = execParserPure defaultPrefs (commandParser "0.1.0.0")
                  ["init", "multi-pkg", "--packages", "pkg-core,pkg-api,pkg-cli", "--desc", "My API"]
      case res of
        Success (CmdInit opts) -> do
          initProjectName opts `shouldBe` Just "multi-pkg"
          initPackages opts `shouldBe` ["pkg-core", "pkg-api", "pkg-cli"]
          initDescription opts `shouldBe` Just "My API"
        _ -> expectationFailure "Expected Success (CmdInit opts)"

    it "correctly parses mode strings" $ do
      parseMode "fail" `shouldBe` Right FailOnExisting
      parseMode "SKIP" `shouldBe` Right SkipExisting
      parseMode "Overwrite" `shouldBe` Right OverwriteExisting
      parseMode "invalid" `shouldSatisfy` (\case Left _ -> True; _ -> False)

    it "parses version command" $ do
      let res = execParserPure defaultPrefs (commandParser "0.1.0.0") ["version"]
      case res of
        Success CmdVersion -> pure ()
        _ -> expectationFailure "Expected Success CmdVersion"

    it "parses 'sync' subcommand with target, dry-run, and all flags" $ do
      let res = execParserPure defaultPrefs (commandParser "0.1.0.0")
                  ["sync", "-t", "/path/to/repo", "--dry-run", "-a"]
      case res of
        Success (CmdSync opts) -> do
          syncTargetDir opts `shouldBe` Just "/path/to/repo"
          syncDryRun opts `shouldBe` True
          syncAll opts `shouldBe` True
          syncRemotes opts `shouldBe` False
        _ -> expectationFailure "Expected Success (CmdSync opts)"

    it "parses 'sync' subcommand with --remotes / -r flag" $ do
      let res = execParserPure defaultPrefs (commandParser "0.1.0.0")
                  ["sync", "-t", "/path/to/repo", "-r"]
      case res of
        Success (CmdSync opts) -> do
          syncTargetDir opts `shouldBe` Just "/path/to/repo"
          syncRemotes opts `shouldBe` True
        _ -> expectationFailure "Expected Success (CmdSync opts)"

    it "parses 'doctor' subcommand with target, sheaf, and all flags" $ do
      let res1 = execParserPure defaultPrefs (commandParser "0.1.0.0") ["doctor"]
      case res1 of
        Success (CmdDoctor opts) -> do
          doctorTargetDir opts `shouldBe` Nothing
          doctorSheaf opts `shouldBe` False
          doctorAll opts `shouldBe` False
        _ -> expectationFailure "Expected Success (CmdDoctor opts) for default doctor"

      let res2 = execParserPure defaultPrefs (commandParser "0.1.0.0") ["doctor", "-t", "/path/to/repo", "-s", "-a"]
      case res2 of
        Success (CmdDoctor opts) -> do
          doctorTargetDir opts `shouldBe` Just "/path/to/repo"
          doctorSheaf opts `shouldBe` True
          doctorAll opts `shouldBe` True
        _ -> expectationFailure "Expected Success (CmdDoctor opts) with flags"

    it "parses 'retrofit' subcommand with target, dry-run, and markdown flags" $ do
      let res1 = execParserPure defaultPrefs (commandParser "0.1.0.0") ["retrofit"]
      case res1 of
        Success (CmdRetrofit opts) -> do
          retrofitTargetDir opts `shouldBe` Nothing
          retrofitDryRun opts `shouldBe` False
          retrofitMarkdown opts `shouldBe` False
        _ -> expectationFailure "Expected Success (CmdRetrofit opts) for default retrofit"

      let res2 = execParserPure defaultPrefs (commandParser "0.1.0.0")
                   ["retrofit", "-t", "/path/to/legacy", "--dry-run", "-m"]
      case res2 of
        Success (CmdRetrofit opts) -> do
          retrofitTargetDir opts `shouldBe` Just "/path/to/legacy"
          retrofitDryRun opts `shouldBe` True
          retrofitMarkdown opts `shouldBe` True
        _ -> expectationFailure "Expected Success (CmdRetrofit opts) with flags"

  describe "Gachi.CLI.Init (Project Resolution)" $ do
    it "resolves default project when no config is provided" $ do
      let opts = InitOptions
            { initProjectName = Just "test-slug"
            , initConfigFile = Nothing
            , initTargetDir = Nothing
            , initMode = FailOnExisting
            , initAuthorName = Just "Alice Smith"
            , initAuthorEmail = Just "alice@example.com"
            , initDescription = Just "Test project"
            , initPackages = ["test-slug-core"]
            , initNoGit = True
            , initDryRun = False
            , initInteractive = False
            }
      res <- resolveProject opts
      case res of
        Right (proj, targetDir) -> do
          projectName proj `shouldBe` "test-slug"
          authorName (projectAuthor proj) `shouldBe` "Alice Smith"
          authorEmail (projectAuthor proj) `shouldBe` "alice@example.com"
          targetDir `shouldBe` "test-slug"
        Left err -> expectationFailure (T.unpack err)

    it "resolves project from Dhall configuration file" $ do
      withTempDir "gachi-dhall-resolve" $ \tmpDir -> do
        let dhallPath = tmpDir </> "project.dhall"
        TIO.writeFile dhallPath exampleProjectDhall
        let opts = InitOptions
              { initProjectName = Nothing
              , initConfigFile = Just dhallPath
              , initTargetDir = Just (tmpDir </> "target")
              , initMode = FailOnExisting
              , initAuthorName = Nothing
              , initAuthorEmail = Nothing
              , initDescription = Nothing
              , initPackages = []
              , initNoGit = True
              , initDryRun = False
              , initInteractive = False
              }
        res <- resolveProject opts
        case res of
          Right (proj, targetDir) -> do
            projectName proj `shouldBe` "gongju"
            targetDir `shouldBe` (tmpDir </> "target")
          Left err -> expectationFailure (T.unpack err)

  describe "Gachi.CLI.Init (Filesystem Materialization & Git Setup)" $ do
    it "performs dry-run without writing any files to target directory" $ do
      withTempDir "gachi-dry-run" $ \tmpDir -> do
        let targetDir = tmpDir </> "uncreated-dir"
            opts = InitOptions
              { initProjectName = Just "dry-project"
              , initConfigFile = Nothing
              , initTargetDir = Just targetDir
              , initMode = FailOnExisting
              , initAuthorName = Nothing
              , initAuthorEmail = Nothing
              , initDescription = Nothing
              , initPackages = []
              , initNoGit = True
              , initDryRun = True
              , initInteractive = False
              }
        exitCode <- runInit opts
        exitCode `shouldBe` ExitSuccess
        exists <- doesDirectoryExist targetDir
        exists `shouldBe` False

    it "initializes full standardized workspace with Git governance" $ do
      withTempDir "gachi-init-full" $ \tmpDir -> do
        let targetDir = tmpDir </> "demo-project"
            opts = InitOptions
              { initProjectName = Just "demo-project"
              , initConfigFile = Nothing
              , initTargetDir = Just targetDir
              , initMode = FailOnExisting
              , initAuthorName = Just "Nadia Yvette Chambers"
              , initAuthorEmail = Just "nadia.yvette.chambers@ik.me"
              , initDescription = Just "Full demonstration workspace"
              , initPackages = ["demo-project-core"]
              , initNoGit = False
              , initDryRun = False
              , initInteractive = False
              }
        exitCode <- runInit opts
        exitCode `shouldBe` ExitSuccess

        -- Verify files created
        readmeExists <- doesFileExist (targetDir </> "README.md")
        readmeExists `shouldBe` True

        verifyScriptExists <- doesFileExist (targetDir </> "bin/demo-project-verify")
        verifyScriptExists `shouldBe` True

        cabalExists <- doesFileExist (targetDir </> "cabal.project")
        cabalExists `shouldBe` True

        -- Verify Git repository and governance configuration
        gitDirExists <- doesDirectoryExist (targetDir </> ".git")
        gitDirExists `shouldBe` True

        (c1, hooksOut, _) <- readProcessWithExitCode "git" ["-C", targetDir, "config", "--get", "core.hooksPath"] ""
        c1 `shouldBe` ExitSuccess
        T.strip (T.pack hooksOut) `shouldBe` ".githooks"

        (c2, tmplOut, _) <- readProcessWithExitCode "git" ["-C", targetDir, "config", "--get", "commit.template"] ""
        c2 `shouldBe` ExitSuccess
        T.strip (T.pack tmplOut) `shouldBe` ".gitmessage"

    it "respects FailOnExisting mode on pre-existing files" $ do
      withTempDir "gachi-fail-mode" $ \tmpDir -> do
        let targetDir = tmpDir </> "existing-proj"
            opts = InitOptions
              { initProjectName = Just "existing-proj"
              , initConfigFile = Nothing
              , initTargetDir = Just targetDir
              , initMode = FailOnExisting
              , initAuthorName = Nothing
              , initAuthorEmail = Nothing
              , initDescription = Nothing
              , initPackages = []
              , initNoGit = True
              , initDryRun = False
              , initInteractive = False
              }
        exit1 <- runInit opts
        exit1 `shouldBe` ExitSuccess
        -- Second run with FailOnExisting should fail gracefully
        exit2 <- runInit opts
        exit2 `shouldBe` ExitFailure 1

  describe "Gachi.CLI.Sync (Harmonic Synchronization Command)" $ do
    it "executes dry-run synchronization without modifying files" $ do
      withTempDir "gachi-cli-sync-dry" $ \tmpDir -> do
        let targetDir = tmpDir </> "sync-proj"
            initOpts = InitOptions
              { initProjectName = Just "sync-proj"
              , initConfigFile = Nothing
              , initTargetDir = Just targetDir
              , initMode = FailOnExisting
              , initAuthorName = Nothing
              , initAuthorEmail = Nothing
              , initDescription = Nothing
              , initPackages = []
              , initNoGit = True
              , initDryRun = False
              , initInteractive = False
              }
        initCode <- runInit initOpts
        initCode `shouldBe` ExitSuccess

        let syncOpts = SyncOptions
              { syncTargetDir = Just targetDir
              , syncDryRun = True
              , syncAll = False
              , syncRemotes = False
              }
        syncCode <- runSync syncOpts
        syncCode `shouldBe` ExitSuccess

    it "synchronizes and repairs configuration in an initialized workspace" $ do
      withTempDir "gachi-cli-sync-apply" $ \tmpDir -> do
        let targetDir = tmpDir </> "repair-proj"
            initOpts = InitOptions
              { initProjectName = Just "repair-proj"
              , initConfigFile = Nothing
              , initTargetDir = Just targetDir
              , initMode = FailOnExisting
              , initAuthorName = Nothing
              , initAuthorEmail = Nothing
              , initDescription = Nothing
              , initPackages = []
              , initNoGit = True
              , initDryRun = False
              , initInteractive = False
              }
        initCode <- runInit initOpts
        initCode `shouldBe` ExitSuccess

        -- Mutate .hlint.yaml to cause drift
        let hlintPath = targetDir </> ".hlint.yaml"
        TIO.writeFile hlintPath "# Drifted HLint configuration\n"

        -- Apply synchronization to repair drift
        let syncOpts = SyncOptions
              { syncTargetDir = Just targetDir
              , syncDryRun = False
              , syncAll = False
              , syncRemotes = False
              }
        syncCode1 <- runSync syncOpts
        syncCode1 `shouldBe` ExitSuccess

        -- Verify file content was repaired
        repairedContent <- TIO.readFile hlintPath
        repairedContent `shouldSatisfy` (\t -> "Ecosystem HLint Configuration" `T.isInfixOf` t)

        -- Re-run sync to verify CLI idempotency
        syncCode2 <- runSync syncOpts
        syncCode2 `shouldBe` ExitSuccess

    it "executes ecosystem-wide synchronization with --all" $ do
      withTempDir "gachi-cli-sync-all" $ \tmpDir -> do
        let repoA = tmpDir </> "repo-one"
            repoB = tmpDir </> "repo-two"
            makeOpts dir = InitOptions
              { initProjectName = Just (T.pack (takeFileName dir))
              , initConfigFile = Nothing
              , initTargetDir = Just dir
              , initMode = FailOnExisting
              , initAuthorName = Nothing
              , initAuthorEmail = Nothing
              , initDescription = Nothing
              , initPackages = []
              , initNoGit = True
              , initDryRun = False
              , initInteractive = False
              }
        _ <- runInit (makeOpts repoA)
        _ <- runInit (makeOpts repoB)

        let allOpts = SyncOptions
              { syncTargetDir = Just tmpDir
              , syncDryRun = True
              , syncAll = True
              , syncRemotes = False
              }
        allCode <- runSync allOpts
        allCode `shouldBe` ExitSuccess

    it "executes remote topology audit and synchronization with --remotes" $ do
      withTempDir "gachi-cli-sync-remotes" $ \tmpDir -> do
        let targetDir = tmpDir </> "remote-proj"
            initOpts = InitOptions
              { initProjectName = Just "remote-proj"
              , initConfigFile = Nothing
              , initTargetDir = Just targetDir
              , initMode = FailOnExisting
              , initAuthorName = Nothing
              , initAuthorEmail = Nothing
              , initDescription = Nothing
              , initPackages = []
              , initNoGit = False
              , initDryRun = False
              , initInteractive = False
              }
        initCode <- runInit initOpts
        initCode `shouldBe` ExitSuccess

        -- Audit & sync remotes via CLI
        let syncOpts = SyncOptions
              { syncTargetDir = Just targetDir
              , syncDryRun = False
              , syncAll = False
              , syncRemotes = True
              }
        syncCode <- runSync syncOpts
        syncCode `shouldBe` ExitSuccess

        -- Verify git remote output contains canonical remotes
        (cGit, remotesOut, _) <- readProcessWithExitCode "git" ["-C", targetDir, "remote"] ""
        cGit `shouldBe` ExitSuccess
        let rList = words remotesOut
        rList `shouldContain` ["github"]
        rList `shouldContain` ["framagit"]
        rList `shouldContain` ["disroot"]

  describe "Gachi.CLI.Doctor (Diagnostics & Sheaf Auditing)" $ do
    it "audits ambient toolchain binaries successfully" $ do
      toolchainOk <- checkToolchainHealth
      toolchainOk `shouldBe` True

    it "runs sheaf coherence audit via doctor --sheaf" $ do
      let docOpts = DoctorOptions
            { doctorTargetDir = Nothing
            , doctorSheaf     = True
            , doctorAll       = False
            }
      exitCode <- runDoctor docOpts
      exitCode `shouldBe` ExitSuccess

    it "runs general doctor on an initialized workspace successfully" $ do
      withTempDir "gachi-cli-doctor" $ \tmpDir -> do
        let targetDir = tmpDir </> "doctor-proj"
            initOpts = InitOptions
              { initProjectName = Just "doctor-proj"
              , initConfigFile  = Nothing
              , initTargetDir   = Just targetDir
              , initMode        = FailOnExisting
              , initAuthorName  = Just "Doctor Tester"
              , initAuthorEmail = Just "doctor@example.com"
              , initDescription = Just "Test workspace for doctor"
              , initPackages    = []
              , initNoGit       = False
              , initDryRun      = False
              , initInteractive = False
              }
        initCode <- runInit initOpts
        initCode `shouldBe` ExitSuccess

        let docOpts = DoctorOptions
              { doctorTargetDir = Just targetDir
              , doctorSheaf     = False
              , doctorAll       = False
              }

        -- Pre-sync doctor detects missing CI workflow obstruction
        preSyncExit <- runDoctor docOpts
        preSyncExit `shouldBe` ExitFailure 1

        -- Sync repository to install standardized CI workflows
        let syncOpts = SyncOptions
              { syncTargetDir = Just targetDir
              , syncDryRun    = False
              , syncAll       = False
              , syncRemotes   = False
              }
        syncCode <- runSync syncOpts
        syncCode `shouldBe` ExitSuccess

        -- Post-sync doctor confirms harmonic equilibrium (10/10 contracts coherent)
        postSyncExit <- runDoctor docOpts
        postSyncExit `shouldBe` ExitSuccess

  describe "Gachi.CLI.Retrofit (Diagnostic Inspection Execution)" $ do
    it "fails gracefully with ExitFailure 1 when target directory does not exist" $ do
      let opts = RetrofitOptions
            { retrofitTargetDir = Just "/nonexistent/directory/path/xyz"
            , retrofitDryRun    = True
            , retrofitMarkdown  = False
            }
      exitCode <- runRetrofit opts
      exitCode `shouldBe` ExitFailure 1

    it "runs diagnostic inspection on an initialized workspace successfully" $ withTempDir "gachi-cli-retrofit" $ \baseDir -> do
      let targetDir = baseDir </> "retrofit-proj"
          initOpts = InitOptions
            { initProjectName = Just "retrofit-proj"
            , initConfigFile  = Nothing
            , initTargetDir   = Just targetDir
            , initMode        = FailOnExisting
            , initAuthorName  = Just "Nadia Yvette Chambers"
            , initAuthorEmail = Just "nadia.yvette.chambers@ik.me"
            , initDescription = Just "Retrofit Target Testing"
            , initPackages    = ["core"]
            , initNoGit       = False
            , initDryRun      = False
            , initInteractive = False
            }
      initCode <- runInit initOpts
      initCode `shouldBe` ExitSuccess

      let retroOpts = RetrofitOptions
            { retrofitTargetDir = Just targetDir
            , retrofitDryRun    = True
            , retrofitMarkdown  = False
            }
      retroCode <- runRetrofit retroOpts
      retroCode `shouldBe` ExitSuccess

      let mdOpts = RetrofitOptions
            { retrofitTargetDir = Just targetDir
            , retrofitDryRun    = False
            , retrofitMarkdown  = True
            }
      mdCode <- runRetrofit mdOpts
      mdCode `shouldBe` ExitSuccess

    it "applies non-destructive skeleton overlay to an uninitialized legacy checkout" $ withTempDir "gachi-cli-retrofit-live" $ \baseDir -> do
      let targetDir = baseDir </> "legacy-app"
      createDirectoryIfMissing True (targetDir </> "src")
      let origCode = "module Lib (greet) where\ngreet :: String -> String\ngreet name = \"Hello, \" ++ name\n"
      TIO.writeFile (targetDir </> "src" </> "Lib.hs") origCode
      TIO.writeFile (targetDir </> "legacy-app.cabal") "cabal-version: 3.0\nname: legacy-app\nversion: 0.1.0.0\n"

      let retroOpts = RetrofitOptions
            { retrofitTargetDir = Just targetDir
            , retrofitDryRun    = False
            , retrofitMarkdown  = False
            }
      retroCode <- runRetrofit retroOpts
      retroCode `shouldBe` ExitSuccess

      -- Invariant 1: Verification runner materialized with executable permissions
      let verifyScript = targetDir </> "bin" </> "legacy-app-verify"
      doesFileExist verifyScript `shouldReturn` True
      p <- getPermissions verifyScript
      executable p `shouldBe` True

      -- Invariant 2: Standard documentation hierarchy and agent advisories installed
      doesFileExist (targetDir </> "docs" </> "INDEX.md") `shouldReturn` True
      doesFileExist (targetDir </> "AGENTS.md") `shouldReturn` True
      doesFileExist (targetDir </> ".githooks" </> "commit-msg") `shouldReturn` True

      -- Invariant 3: Git repository initialized
      doesDirectoryExist (targetDir </> ".git") `shouldReturn` True

      -- Invariant 4: Domain source files preserved completely untouched
      codeAfter <- TIO.readFile (targetDir </> "src" </> "Lib.hs")
      codeAfter `shouldBe` origCode

    it "evaluates progressive quality gates during retrofit execution" $ withTempDir "gachi-cli-retrofit-gates" $ \baseDir -> do
      let targetDir = baseDir </> "quality-app"
      createDirectoryIfMissing True (targetDir </> "src")
      TIO.writeFile (targetDir </> "src" </> "Main.hs") "module Main where\nmain = pure ()\n"
      TIO.writeFile (targetDir </> "quality-app.cabal") "cabal-version: 3.0\nname: quality-app\nversion: 0.1.0.0\n"

      let retroOpts = RetrofitOptions
            { retrofitTargetDir = Just targetDir
            , retrofitDryRun    = False
            , retrofitMarkdown  = False
            }
      retroCode <- runRetrofit retroOpts
      retroCode `shouldBe` ExitSuccess

      -- Verify that overlay was applied and quality gates evaluated cleanly
      doesFileExist (targetDir </> "bin" </> "quality-app-verify") `shouldReturn` True
      doesFileExist (targetDir </> "PLAN.md") `shouldReturn` True
      doesFileExist (targetDir </> "tagref.yml") `shouldReturn` True
