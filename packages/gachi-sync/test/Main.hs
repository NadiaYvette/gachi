{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Module: Main
-- Description: Comprehensive test suite for gachi-sync
--
-- Validates:
-- 1. Canonical Standardization Matrix completeness and category queries.
-- 2. Pure catalog template generators and multi-language formatting stanzas.
-- 3. Path token substitution (:name:, :project:).
-- 4. Audit engine accuracy: clean compliance, content drift detection, missing file reporting,
--    and permission drift detection on physical workspaces.
-- 5. Diagnostic ASCII report formatting.
module Main (main) where

import Control.Exception (bracket)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import System.Directory
  ( createDirectoryIfMissing
  , getPermissions
  , removeDirectoryRecursive
  , setPermissions
  , setOwnerExecutable
  )
import System.FilePath ((</>))
import Test.Hspec

import Gachi.Schema.Project
  ( Author(..)
  , Project
  , defaultProject
  )
import Gachi.Scaffold
  ( ScaffoldMode(..)
  , ScaffoldResult(..)
  , generateAndWriteScaffold
  )
import Gachi.Sync

-- | Test project specification for synthesis and auditing.
testProject :: Project
testProject = defaultProject "audit-test" (Author "Test Runner" "test@example.com")

-- | Helper to create a temporary test directory and clean it up after testing.
withTempDir :: (FilePath -> IO a) -> IO a
withTempDir = bracket createTemp cleanupTemp
  where
    createTemp = do
      let dir = "dist-newstyle" </> "test-audit-workspace"
      createDirectoryIfMissing True dir
      pure dir
    cleanupTemp dir = removeDirectoryRecursive dir

main :: IO ()
main = hspec $ do
  describe "Gachi.Sync.Matrix (Standardization Matrix)" $ do
    it "registers all 10 canonical dimensions" $ do
      length canonicalDimensions `shouldBe` 10
      matrixDimensions canonicalMatrix `shouldBe` canonicalDimensions

    it "registers at least 20 canonical assets" $ do
      length canonicalAssets `shouldSatisfy` (>= 20)
      length (matrixAssets canonicalMatrix) `shouldSatisfy` (>= 20)

    it "assigns non-empty paths and descriptions to all canonical assets" $ do
      mapM_ (\a -> do
        assetPath a `shouldNotBe` ""
        assetDescription a `shouldNotBe` ""
        ) canonicalAssets

    it "filters assets correctly by category" $ do
      let formatters = assetsForCategory CategoryFormatter canonicalMatrix
      map assetPath formatters `shouldContain` ["fourmolu.yaml"]
      map assetPath formatters `shouldContain` ["rustfmt.toml"]
      map assetPath formatters `shouldContain` [".clang-format"]

      let linters = assetsForCategory CategoryLinter canonicalMatrix
      map assetPath linters `shouldBe` [".hlint.yaml"]

      let builds = assetsForCategory CategoryBuild canonicalMatrix
      map assetPath builds `shouldContain` ["cabal.project"]

      let gitGov = assetsForCategory CategoryGitGovernance canonicalMatrix
      map assetPath gitGov `shouldContain` [".gitmessage"]
      map assetPath gitGov `shouldContain` [".githooks/commit-msg"]

      let agents = assetsForCategory CategoryAgentAdvisory canonicalMatrix
      map assetPath agents `shouldContain` ["AGENTS.md"]
      map assetPath agents `shouldContain` [".agents/rules/commit-attribution.md"]

    it "identifies executable verification scripts and git hooks" $ do
      let execs = executableAssets canonicalMatrix
      map assetPath execs `shouldContain` [".githooks/commit-msg"]
      map assetPath execs `shouldContain` [".githooks/pre-commit"]
      map assetPath execs `shouldContain` ["bin/:name:-verify"]
      map assetPath execs `shouldContain` ["bin/:name:-tagref"]

    it "counts assets per category accurately" $ do
      let counts = countByCategory canonicalMatrix
      length counts `shouldBe` 10
      all (\(_, c) -> c > 0) counts `shouldBe` True

    it "finds assets by relative path" $ do
      let maybeHlint = findAssetByPath ".hlint.yaml" canonicalMatrix
      fmap assetCategory maybeHlint `shouldBe` Just CategoryLinter

      let missing = findAssetByPath "nonexistent.file" canonicalMatrix
      missing `shouldBe` Nothing

  describe "Gachi.Sync.Types (Path Resolution)" $ do
    it "leaves static asset paths unchanged" $ do
      let asset = StandardAsset ".hlint.yaml" CategoryLinter True False "HLint" (const "")
      resolveAssetPath testProject asset `shouldBe` ".hlint.yaml"

    it "substitutes :name: tokens with project name" $ do
      let asset = StandardAsset "bin/:name:-verify" CategoryVerification True True "Verify" (const "")
      resolveAssetPath testProject asset `shouldBe` "bin/audit-test-verify"

    it "substitutes :project: tokens with project name" $ do
      let asset = StandardAsset "docs/:project:-notes.md" CategoryLayout True False "Notes" (const "")
      resolveAssetPath testProject asset `shouldBe` "docs/audit-test-notes.md"

  describe "Gachi.Sync.Catalog (Asset Generators)" $ do
    it "synthesizes valid Fourmolu configuration" $ do
      fourmoluTemplate `shouldSatisfy` (\t -> "indentation: 2" `T.isInfixOf` t)
      fourmoluTemplate `shouldSatisfy` (\t -> "fixities:" `T.isInfixOf` t)

    it "synthesizes valid rustfmt configuration" $ do
      rustfmtTemplate `shouldSatisfy` (\t -> "edition = \"2021\"" `T.isInfixOf` t)

    it "synthesizes valid .clang-format configuration" $ do
      clangFormatTemplate `shouldSatisfy` (\t -> "BasedOnStyle: LLVM" `T.isInfixOf` t)

    it "synthesizes high-resource GitHub Actions workflow" $ do
      let ci = githubCiTemplate testProject
      ci `shouldSatisfy` (\t -> "./bin/audit-test-verify" `T.isInfixOf` t)
      ci `shouldSatisfy` (\t -> "ubuntu-latest" `T.isInfixOf` t)

    it "synthesizes lightweight community GitLab CI workflow" $ do
      let ci = gitlabCiTemplate testProject
      ci `shouldSatisfy` (\t -> "./bin/audit-test-tagref" `T.isInfixOf` t)

    it "synthesizes modular agent advisory rules" $ do
      commitAttributionRuleTemplate `shouldSatisfy` (\t -> "Assisted-by:" `T.isInfixOf` t)
      codeNavigationRuleTemplate `shouldSatisfy` (\t -> "`./tags` symbol jump" `T.isInfixOf` t)
      compilerVerificationRuleTemplate `shouldSatisfy` (\t -> "Zero warnings tolerated" `T.isInfixOf` t)
      documentationPrecedenceRuleTemplate `shouldSatisfy` (\t -> "Precedence rule" `T.isInfixOf` t)

  describe "Gachi.Sync.Audit (Repository Audit Engine)" $ do
    it "evaluates clean synthesized workspace with high compliance" $ withTempDir $ \tmpDir -> do
      -- Materialize clean workspace
      res <- generateAndWriteScaffold tmpDir OverwriteExisting testProject
      writtenFiles res `shouldSatisfy` (not . null)
      skippedFiles res `shouldBe` []

      -- Also ensure Fourmolu config is created if needed by matrix
      TIO.writeFile (tmpDir </> "fourmolu.yaml") fourmoluTemplate

      -- Run audit
      report <- auditRepository tmpDir testProject canonicalMatrix
      reportProjectName report `shouldBe` "audit-test"
      reportTotalAssets report `shouldSatisfy` (>= 20)
      reportCompliantCount report `shouldSatisfy` (>= 14)
      reportCompliancePct report `shouldSatisfy` (>= 70.0)

    it "detects content drift when a file is modified" $ withTempDir $ \tmpDir -> do
      -- Materialize clean workspace
      _ <- generateAndWriteScaffold tmpDir OverwriteExisting testProject
      -- Deliberately mutate .hlint.yaml
      TIO.writeFile (tmpDir </> ".hlint.yaml") "# Divergent HLint configuration\n"

      report <- auditRepository tmpDir testProject canonicalMatrix
      reportDriftCount report `shouldSatisfy` (>= 1)
      let drifts = filterDriftResults report
      map (assetPath . resultAsset) drifts `shouldContain` [".hlint.yaml"]

    it "detects missing assets when a required file is absent" $ withTempDir $ \tmpDir -> do
      -- In an empty directory, all required assets should be missing
      report <- auditRepository tmpDir testProject canonicalMatrix
      reportMissingCount report `shouldSatisfy` (>= 15)
      reportCompliantCount report `shouldBe` 0
      let missings = filterMissingResults report
      map (assetPath . resultAsset) missings `shouldContain` [".hlint.yaml"]
      map (assetPath . resultAsset) missings `shouldContain` [".gitmessage"]

    it "detects permission drift on executable scripts" $ withTempDir $ \tmpDir -> do
      -- Materialize clean workspace
      _ <- generateAndWriteScaffold tmpDir OverwriteExisting testProject
      -- Strip executable bit from .githooks/commit-msg
      let hookPath = tmpDir </> ".githooks" </> "commit-msg"
      perms <- getPermissions hookPath
      setPermissions hookPath (setOwnerExecutable False perms)

      report <- auditRepository tmpDir testProject canonicalMatrix
      let permDrifts = filter (\r -> case resultStatus r of { StatusPermissionDrift _ _ -> True; _ -> False }) (reportResults report)
      map (assetPath . resultAsset) permDrifts `shouldContain` [".githooks/commit-msg"]

    it "renders ASCII diagnostic reports with summary and tables" $ withTempDir $ \tmpDir -> do
      report <- auditRepository tmpDir testProject canonicalMatrix
      let formatted = formatAuditReport report
      formatted `shouldSatisfy` (\t -> "Gachi Standardization Matrix Audit Report" `T.isInfixOf` t)
      formatted `shouldSatisfy` (\t -> "Total Assets:" `T.isInfixOf` t)
      formatted `shouldSatisfy` (\t -> "Missing Required Assets:" `T.isInfixOf` t)

      let str = formatAuditReportString report
      str `shouldSatisfy` (\s -> length s > 100)
