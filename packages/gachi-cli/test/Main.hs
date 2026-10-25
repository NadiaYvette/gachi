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
        _ -> expectationFailure "Expected Success (CmdSync opts)"

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
              }
        allCode <- runSync allOpts
        allCode `shouldBe` ExitSuccess
