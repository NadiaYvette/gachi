{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Module: Main (gachi-plan test suite)
-- Description: Unit and integration tests for detached Git plan store architecture
--
-- Validates Milestone 5.1 of Phase 5 (Ecosystem Plan Governance & Rollback per ~/src/PLAN.md §1.A).
-- Tests detached bare Git repository lifecycle, non-interference invariants,
-- governed document tracking, dirty status detection, and commit metadata.
module Main (main) where

import Control.Exception (SomeException, bracket, catch)
import Control.Monad (forM_)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Data.Time.Clock.POSIX (getPOSIXTime)
import System.Directory
  ( createDirectoryIfMissing
  , doesDirectoryExist
  , getTemporaryDirectory
  , removeDirectoryRecursive
  )
import System.FilePath ((</>))
import Test.Hspec

import Gachi.Plan
  ( PlanStore(..)
  , PlanStoreStatus(..)
  , commitStore
  , defaultGovernedFiles
  , getPlanStoreDiff
  , governedFilesExist
  , initPlanStore
  , isPlanStoreClean
  , isStoreInitialized
  , listTrackedFiles
  , queryPlanStore
  , resolvePlanStorePath
  , stageFiles
  , trackGovernedFiles
  )

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
  describe "Gachi.Plan.Store (Detached Git Store Lifecycle)" $ do
    it "initializes a fresh bare Git store in a temporary directory" $ do
      withTempDir "gachi-plan-init" $ \tmpDir -> do
        let storePath = tmpDir </> "store.git"
            workPath  = tmpDir </> "work"
        res <- initPlanStore storePath workPath
        case res of
          Left err -> expectationFailure ("initPlanStore failed: " ++ show err)
          Right store -> do
            planGitDir store `shouldBe` storePath
            planWorkTree store `shouldBe` workPath
            planGovernedFiles store `shouldBe` defaultGovernedFiles
            isInit <- isStoreInitialized storePath
            isInit `shouldBe` True

    it "idempotently re-initializes an already existing bare store" $ do
      withTempDir "gachi-plan-reinit" $ \tmpDir -> do
        let storePath = tmpDir </> "store.git"
            workPath  = tmpDir </> "work"
        res1 <- initPlanStore storePath workPath
        case res1 of
          Left err -> expectationFailure ("First init failed: " ++ show err)
          Right _ -> do
            res2 <- initPlanStore storePath workPath
            case res2 of
              Left err -> expectationFailure ("Second init failed: " ++ show err)
              Right store2 -> do
                isInit <- isStoreInitialized (planGitDir store2)
                isInit `shouldBe` True

    it "resolves explicit store path to an absolute path" $ do
      withTempDir "gachi-plan-resolve" $ \tmpDir -> do
        let explicitPath = tmpDir </> "custom.git"
        resolved <- resolvePlanStorePath (Just explicitPath)
        resolved `shouldBe` explicitPath

    it "reports false for non-existent store directory" $ do
      withTempDir "gachi-plan-missing" $ \tmpDir -> do
        let bogusPath = tmpDir </> "does-not-exist.git"
        isInit <- isStoreInitialized bogusPath
        isInit `shouldBe` False

  describe "Gachi.Plan.Store (Non-Interference & Worktree Isolation Invariants)" $ do
    it "strictly avoids creating .git in worktree root" $ do
      withTempDir "gachi-plan-isolation" $ \tmpDir -> do
        let storePath = tmpDir </> "store.git"
            workPath  = tmpDir </> "work"
        createDirectoryIfMissing True workPath
        _ <- initPlanStore storePath workPath
        -- Verify no .git directory or file was created in workPath
        hasDotGit <- doesDirectoryExist (workPath </> ".git")
        hasDotGit `shouldBe` False

    it "preserves child repository .git checkouts without interference" $ do
      withTempDir "gachi-plan-children" $ \tmpDir -> do
        let storePath = tmpDir </> "store.git"
            workPath  = tmpDir </> "work"
            childA    = workPath </> "gachi"
            childB    = workPath </> "polytropos"
        -- Simulate pre-existing child repository workspaces
        createDirectoryIfMissing True (childA </> ".git")
        createDirectoryIfMissing True (childB </> ".git")
        TIO.writeFile (childA </> "Main.hs") "module Main where"
        TIO.writeFile (childB </> "Lib.hs") "module Lib where"

        -- Initialize detached plan store at worktree root
        res <- initPlanStore storePath workPath
        case res of
          Left err -> expectationFailure ("init failed: " ++ show err)
          Right store -> do
            -- Create top-level ecosystem plan files
            TIO.writeFile (workPath </> "PLAN.md") "# Ecosystem Plan"
            TIO.writeFile (workPath </> "STATE.md") "# Ecosystem State"

            -- Stage and commit governed files
            stageRes <- trackGovernedFiles store
            case stageRes of
              Left err -> expectationFailure ("trackGovernedFiles failed: " ++ show err)
              Right staged -> length staged `shouldBe` 2

            commitRes <- commitStore store "Initial plan commit"
            case commitRes of
              Left err -> expectationFailure ("commitStore failed: " ++ show err)
              Right commitSha -> T.length commitSha `shouldBe` 40

            -- Child repo .git directories MUST remain intact
            childAExists <- doesDirectoryExist (childA </> ".git")
            childBExists <- doesDirectoryExist (childB </> ".git")
            childAExists `shouldBe` True
            childBExists `shouldBe` True

            -- Worktree root MUST NOT have a .git directory
            rootDotGit <- doesDirectoryExist (workPath </> ".git")
            rootDotGit `shouldBe` False

  describe "Gachi.Plan.Store (Governed File Tracking & Dirty Detection)" $ do
    it "reports empty tracked files and clean state on fresh store" $ do
      withTempDir "gachi-plan-empty" $ \tmpDir -> do
        let storePath = tmpDir </> "store.git"
            workPath  = tmpDir </> "work"
        Right store <- initPlanStore storePath workPath
        status <- queryPlanStore store
        statusHeadCommit status `shouldBe` Nothing
        statusLastCommitTime status `shouldBe` Nothing
        statusTrackedFiles status `shouldBe` []
        statusDirtyFiles status `shouldBe` []
        statusIsDirty status `shouldBe` False
        isPlanStoreClean status `shouldBe` True

    it "detects untracked governed planning files as dirty" $ do
      withTempDir "gachi-plan-dirty" $ \tmpDir -> do
        let storePath = tmpDir </> "store.git"
            workPath  = tmpDir </> "work"
        Right store <- initPlanStore storePath workPath

        -- Create mock governed planning files
        TIO.writeFile (workPath </> "PLAN.md") "# Master Plan\n"
        TIO.writeFile (workPath </> "STATE.md") "# Operational Frontier\n"

        status <- queryPlanStore store
        statusIsDirty status `shouldBe` True
        isPlanStoreClean status `shouldBe` False
        statusDirtyFiles status `shouldContain` ["PLAN.md"]
        statusDirtyFiles status `shouldContain` ["STATE.md"]

    it "ignores untracked files in child directories during dirty queries" $ do
      withTempDir "gachi-plan-ignore-child" $ \tmpDir -> do
        let storePath = tmpDir </> "store.git"
            workPath  = tmpDir </> "work"
            childDir  = workPath </> "some-child-package"
        createDirectoryIfMissing True childDir
        Right store <- initPlanStore storePath workPath

        -- Write untracked file in child package
        TIO.writeFile (childDir </> "SomeCode.hs") "module SomeCode where"

        -- Status should remain clean because governed files do not exist and child files are ignored
        status <- queryPlanStore store
        statusIsDirty status `shouldBe` False
        statusDirtyFiles status `shouldBe` []

    it "transitions from dirty to clean upon staging and committing" $ do
      withTempDir "gachi-plan-commit" $ \tmpDir -> do
        let storePath = tmpDir </> "store.git"
            workPath  = tmpDir </> "work"
        Right store <- initPlanStore storePath workPath

        -- Create all four canonical governed files
        createDirectoryIfMissing True (workPath </> "docs")
        TIO.writeFile (workPath </> "PLAN.md") "# Plan\n"
        TIO.writeFile (workPath </> "STATE.md") "# State\n"
        TIO.writeFile (workPath </> "INDEX.md") "# Index\n"
        TIO.writeFile (workPath </> "docs" </> "INDEX.md") "# Docs Index\n"

        -- Check physical file presence
        existList <- governedFilesExist store
        length existList `shouldBe` 4
        forM_ existList $ \(_, exists) -> exists `shouldBe` True

        -- Stage governed files
        stageRes <- stageFiles store ["PLAN.md", "STATE.md", "INDEX.md", "docs/INDEX.md"]
        case stageRes of
          Left err -> expectationFailure ("stageFiles failed: " ++ show err)
          Right () -> pure ()

        -- Files should now be tracked
        tracked <- listTrackedFiles store
        tracked `shouldContain` ["PLAN.md"]
        tracked `shouldContain` ["STATE.md"]
        tracked `shouldContain` ["INDEX.md"]
        tracked `shouldContain` ["docs/INDEX.md"]

        -- Commit changes
        commitRes <- commitStore store "Initial ecosystem governance checkpoint"
        case commitRes of
          Left err -> expectationFailure ("commitStore failed: " ++ show err)
          Right commitSha -> do
            T.length commitSha `shouldBe` 40

            -- Query updated status: should be clean with HEAD commit and timestamp
            status <- queryPlanStore store
            statusHeadCommit status `shouldBe` Just commitSha
            statusIsDirty status `shouldBe` False
            isPlanStoreClean status `shouldBe` True
            statusDirtyFiles status `shouldBe` []
            statusLastCommitTime status `shouldSatisfy` (/= Nothing)

    it "detects modifications to tracked planning documents and provides diff" $ do
      withTempDir "gachi-plan-diff" $ \tmpDir -> do
        let storePath = tmpDir </> "store.git"
            workPath  = tmpDir </> "work"
        Right store <- initPlanStore storePath workPath

        -- Initialize and commit a plan
        TIO.writeFile (workPath </> "PLAN.md") "# Version 1.0\n"
        _ <- stageFiles store ["PLAN.md"]
        _ <- commitStore store "Baseline commit"

        -- Verify clean
        status1 <- queryPlanStore store
        statusIsDirty status1 `shouldBe` False

        -- Modify PLAN.md
        TIO.appendFile (workPath </> "PLAN.md") "Added Phase 5 milestone details.\n"

        -- Verify dirty
        status2 <- queryPlanStore store
        statusIsDirty status2 `shouldBe` True
        statusDirtyFiles status2 `shouldContain` ["PLAN.md"]

        -- Inspect diff
        diffRes <- getPlanStoreDiff store Nothing
        case diffRes of
          Left err -> expectationFailure ("diff failed: " ++ show err)
          Right diffText -> do
            T.isInfixOf "Added Phase 5 milestone details." diffText `shouldBe` True
