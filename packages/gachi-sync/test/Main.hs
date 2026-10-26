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
-- 6. Forge-tiered CI matrix generation, asymmetric runner allocation, and classification (Milestone 3.3).
module Main (main) where

import Control.Exception (bracket)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import System.Directory
  ( createDirectoryIfMissing
  , doesFileExist
  , executable
  , getPermissions
  , removeDirectoryRecursive
  , setPermissions
  , setOwnerExecutable
  )
import System.FilePath ((</>), takeFileName)
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
    cleanupTemp = removeDirectoryRecursive

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

  describe "Gachi.Sync.Hash (Differential Cryptographic Hashing)" $ do
    it "computes standard FIPS 180-2 SHA-256 test vectors" $ do
      -- NIST Empty String Vector
      sha256Text "" `shouldBe` "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
      -- NIST 3-character Vector
      sha256Text "abc" `shouldBe` "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
      -- NIST Pangram Vector
      sha256Text "The quick brown fox jumps over the lazy dog"
        `shouldBe` "d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592"

    it "computes consistent hashes across text and file representations" $ withTempDir $ \tmpDir -> do
      let sampleText = "Author: Nadia Yvette Chambers\nLicense: EUPL-1.2\n"
          filePath = tmpDir </> "test-hash.txt"
      TIO.writeFile filePath sampleText
      fileHash <- sha256File filePath
      let textHash = sha256Text sampleText
      fileHash `shouldBe` textHash

  describe "Gachi.Sync.Engine (Harmonic Chattering Synchronization)" $ do
    it "computes a sync plan proposing creation of all assets in an empty workspace" $ withTempDir $ \tmpDir -> do
      plan <- computeSyncPlan tmpDir testProject canonicalMatrix
      planProjectName plan `shouldBe` "audit-test"
      planCreatedCount plan `shouldSatisfy` (>= 20)
      planUpdatedCount plan `shouldBe` 0
      planChmodCount plan `shouldBe` 0
      isPlanClean plan `shouldBe` False

    it "executes sync plan in DryRun mode without creating files on disk" $ withTempDir $ \tmpDir -> do
      plan <- computeSyncPlan tmpDir testProject canonicalMatrix
      res <- executeSyncPlan DryRun plan
      resultMode res `shouldBe` DryRun
      resultSuccess res `shouldBe` True
      length (resultCreated res) `shouldSatisfy` (>= 20)
      -- Assert disk files remain untouched
      doesFileExist (tmpDir </> ".hlint.yaml") `shouldReturn` False
      doesFileExist (tmpDir </> ".gitmessage") `shouldReturn` False

    it "executes sync plan in ApplySync mode and creates files on disk" $ withTempDir $ \tmpDir -> do
      plan <- computeSyncPlan tmpDir testProject canonicalMatrix
      res <- executeSyncPlan ApplySync plan
      resultMode res `shouldBe` ApplySync
      resultSuccess res `shouldBe` True
      length (resultCreated res) `shouldSatisfy` (>= 20)
      -- Assert disk files exist
      doesFileExist (tmpDir </> ".hlint.yaml") `shouldReturn` True
      doesFileExist (tmpDir </> ".gitmessage") `shouldReturn` True
      -- Assert executable bit
      let hookPath = tmpDir </> ".githooks" </> "commit-msg"
      perms <- getPermissions hookPath
      executable perms `shouldBe` True

    it "satisfies the mathematical idempotency guarantee: f(f(x)) = f(x)" $ withTempDir $ \tmpDir -> do
      -- 1. First synchronization pass: applies all creations
      res1 <- syncRepository ApplySync tmpDir testProject canonicalMatrix
      resultSuccess res1 `shouldBe` True
      length (resultCreated res1) `shouldSatisfy` (>= 20)

      -- 2. Second synchronization pass: must produce zero modifications
      res2 <- syncRepository ApplySync tmpDir testProject canonicalMatrix
      resultSuccess res2 `shouldBe` True
      length (resultCreated res2) `shouldBe` 0
      length (resultUpdated res2) `shouldBe` 0
      length (resultChmodded res2) `shouldBe` 0
      length (resultUnchanged res2) `shouldSatisfy` (>= 20)
      length (resultErrors res2) `shouldBe` 0

      -- 3. Verify that re-computing the plan yields isPlanClean == True
      plan2 <- computeSyncPlan tmpDir testProject canonicalMatrix
      isPlanClean plan2 `shouldBe` True

    it "detects and repairs content drift and permission drift non-destructively" $ withTempDir $ \tmpDir -> do
      -- 1. Initial synchronization
      _ <- syncRepository ApplySync tmpDir testProject canonicalMatrix

      -- 2. Mutate .hlint.yaml (content drift)
      let hlintPath = tmpDir </> ".hlint.yaml"
      TIO.writeFile hlintPath "# Corrupted or drifted HLint file\n"

      -- 3. Strip executable bit from .githooks/commit-msg (permission drift)
      let hookPath = tmpDir </> ".githooks" </> "commit-msg"
      hookPerms <- getPermissions hookPath
      setPermissions hookPath (setOwnerExecutable False hookPerms)

      -- 4. Compute plan and verify drift detection
      driftPlan <- computeSyncPlan tmpDir testProject canonicalMatrix
      planUpdatedCount driftPlan `shouldBe` 1
      planChmodCount driftPlan `shouldBe` 1
      isPlanClean driftPlan `shouldBe` False

      -- 5. Synchronize with ApplySync to repair drift
      repairRes <- syncRepository ApplySync tmpDir testProject canonicalMatrix
      resultSuccess repairRes `shouldBe` True
      resultUpdated repairRes `shouldBe` [".hlint.yaml"]
      resultChmodded repairRes `shouldBe` [".githooks/commit-msg"]

      -- 6. Verify restored state is clean
      postPlan <- computeSyncPlan tmpDir testProject canonicalMatrix
      isPlanClean postPlan `shouldBe` True
      permsAfter <- getPermissions hookPath
      executable permsAfter `shouldBe` True

    it "discovers sibling ecosystem repositories" $ withTempDir $ \tmpDir -> do
      -- Create repository A (has .git)
      let repoA = tmpDir </> "repo-alpha"
      createDirectoryIfMissing True (repoA </> ".git")

      -- Create repository B (has project.dhall)
      let repoB = tmpDir </> "repo-beta"
      createDirectoryIfMissing True repoB
      TIO.writeFile (repoB </> "project.dhall") "-- test dhall"

      -- Create non-repository directory
      let plainDir = tmpDir </> "plain-notes"
      createDirectoryIfMissing True plainDir

      discovered <- discoverEcosystemRepositories tmpDir
      length discovered `shouldBe` 2
      map takeFileName discovered `shouldMatchList` ["repo-alpha", "repo-beta"]

    it "renders formatted diagnostic sync plan and sync result tables" $ withTempDir $ \tmpDir -> do
      plan <- computeSyncPlan tmpDir testProject canonicalMatrix
      let planText = formatSyncPlan plan
      planText `shouldSatisfy` (\t -> "Gachi Synchronization Plan" `T.isInfixOf` t)
      planText `shouldSatisfy` (\t -> "Actions Planned:" `T.isInfixOf` t)

      res <- executeSyncPlan DryRun plan
      let resText = formatSyncResult res
      resText `shouldSatisfy` (\t -> "Gachi Synchronization Execution Summary" `T.isInfixOf` t)
      resText `shouldSatisfy` (\t -> "DRY RUN" `T.isInfixOf` t)

  describe "Gachi.Sync.CI (Forge-Tiered CI Matrix Synthesis)" $ do
    it "classifies forge types from standard workflow paths" $ do
      classifyForge ".github/workflows/ci.yml" `shouldBe` Just ForgeGitHub
      classifyForge ".github/workflows/verify.yaml" `shouldBe` Just ForgeGitHub
      classifyForge ".gitlab-ci.yml" `shouldBe` Just ForgeGitLab
      classifyForge ".woodpecker.yml" `shouldBe` Just ForgeWoodpecker
      classifyForge ".woodpecker/verify.yml" `shouldBe` Just ForgeWoodpecker
      classifyForge ".forgejo/workflows/ci.yml" `shouldBe` Just ForgeForgejo
      classifyForge ".radicle/ci.yaml" `shouldBe` Just ForgeRadicle
      classifyForge "docs/INDEX.md" `shouldBe` Nothing

    it "classifies resource tiers accurately from paths and specifications" $ do
      classifyTier ".github/workflows/ci.yml" `shouldBe` Just TierHighResource
      classifyTier ".gitlab-ci.yml" `shouldBe` Just TierLightweightStatic
      classifyTier ".woodpecker.yml" `shouldBe` Just TierLightweightStatic
      classifyTier ".forgejo/workflows/ci.yml" `shouldBe` Just TierHighResource
      classifyTier ".radicle/ci.yaml" `shouldBe` Just TierLightweightStatic
      classifyTier "docs/INDEX.md" `shouldBe` Nothing

      isHighResource defaultGitHubSpec `shouldBe` True
      isLightweight defaultGitHubSpec `shouldBe` False

      isLightweight defaultGitLabSpec `shouldBe` True
      isHighResource defaultGitLabSpec `shouldBe` False

      isLightweight defaultWoodpeckerSpec `shouldBe` True
      isHighResource defaultForgejoSpec `shouldBe` True
      isLightweight defaultRadicleSpec `shouldBe` True

    it "synthesizes complete high-resource GitHub Actions workflows" $ do
      let wf = generateGitHubWorkflow defaultGitHubSpec testProject
      wf `shouldSatisfy` ("actions/checkout@v4" `T.isInfixOf`)
      wf `shouldSatisfy` ("actions/cache@v4" `T.isInfixOf`)
      wf `shouldSatisfy` ("haskell-actions/setup@v2" `T.isInfixOf`)
      wf `shouldSatisfy` ("ghc-version: '9.14.1'" `T.isInfixOf`)
      wf `shouldSatisfy` ("cabal-version: '3.18.1.0'" `T.isInfixOf`)
      wf `shouldSatisfy` ("cabal build all --enable-tests" `T.isInfixOf`)
      wf `shouldSatisfy` ("./bin/audit-test-cloc --check" `T.isInfixOf`)
      wf `shouldSatisfy` ("./bin/audit-test-verify" `T.isInfixOf`)
      wf `shouldSatisfy` ("./bin/audit-test-tagref" `T.isInfixOf`)
      wf `shouldSatisfy` ("./bin/audit-test-linkcheck" `T.isInfixOf`)
      wf `shouldSatisfy` ("sudo apt-get install -y bubblewrap sqlite3 z3" `T.isInfixOf`)
      wf `shouldSatisfy` ("kernel.apparmor_restrict_unprivileged_userns=0" `T.isInfixOf`)
      wf `shouldSatisfy` ("url.\"https://github.com/\".insteadOf" `T.isInfixOf`)

    it "synthesizes lightweight community GitLab CI workflows without compiler overhead" $ do
      let wf = generateGitLabWorkflow defaultGitLabSpec testProject
      wf `shouldSatisfy` ("image: debian:bookworm-slim" `T.isInfixOf`)
      wf `shouldSatisfy` ("stages:" `T.isInfixOf`)
      wf `shouldSatisfy` ("tagref-check:" `T.isInfixOf`)
      wf `shouldSatisfy` ("./bin/audit-test-tagref" `T.isInfixOf`)
      wf `shouldSatisfy` ("./bin/audit-test-linkcheck" `T.isInfixOf`)
      wf `shouldSatisfy` ("./bin/audit-test-cloc --check" `T.isInfixOf`)
      -- Crucial invariant: No heavy GHC build steps in lightweight community CI
      wf `shouldNotSatisfy` ("cabal build" `T.isInfixOf`)
      wf `shouldNotSatisfy` ("ghc-version" `T.isInfixOf`)

    it "synthesizes lightweight Woodpecker CI pipelines" $ do
      let wf = generateWoodpeckerWorkflow defaultWoodpeckerSpec testProject
      wf `shouldSatisfy` ("pipeline:" `T.isInfixOf`)
      wf `shouldSatisfy` ("image: debian:bookworm-slim" `T.isInfixOf`)
      wf `shouldSatisfy` ("./bin/audit-test-tagref" `T.isInfixOf`)
      wf `shouldSatisfy` ("./bin/audit-test-linkcheck" `T.isInfixOf`)
      wf `shouldSatisfy` ("./bin/audit-test-cloc --check" `T.isInfixOf`)
      wf `shouldNotSatisfy` ("cabal build" `T.isInfixOf`)

    it "synthesizes Radicle P2P local verification broker configurations" $ do
      let wf = generateRadicleWorkflow defaultRadicleSpec testProject
      wf `shouldSatisfy` ("version: 1" `T.isInfixOf`)
      wf `shouldSatisfy` ("pipelines:" `T.isInfixOf`)
      wf `shouldSatisfy` ("./bin/audit-test-tagref" `T.isInfixOf`)
      wf `shouldSatisfy` ("./bin/audit-test-linkcheck" `T.isInfixOf`)
      wf `shouldSatisfy` ("./bin/audit-test-cloc --check" `T.isInfixOf`)

    it "converts CI specifications into standard matrix assets in CategoryCIWorkflow" $ do
      let assets = synthesizeCIAssets canonicalForgeSpecs
      length assets `shouldBe` 3
      all (\a -> assetCategory a == CategoryCIWorkflow) assets `shouldBe` True
      map assetPath assets `shouldMatchList`
        [ ".github/workflows/ci.yml"
        , ".gitlab-ci.yml"
        , ".woodpecker.yml"
        ]
      map assetRequired assets `shouldMatchList` [True, True, False]
      any assetExecutable assets `shouldBe` False

    it "extracts CI workflow assets from canonicalMatrix via ciWorkflowAssets" $ do
      let ciAssets = ciWorkflowAssets canonicalMatrix
      length ciAssets `shouldSatisfy` (>= 2)
      map assetPath ciAssets `shouldContain` [".github/workflows/ci.yml", ".gitlab-ci.yml"]
      all (\a -> assetCategory a == CategoryCIWorkflow) ciAssets `shouldBe` True

    it "supports high-resource GitLab and lightweight GitHub overrides via forgeDefaultSpec" $ do
      let highGitLab = forgeDefaultSpec ForgeGitLab TierHighResource
      ciTier highGitLab `shouldBe` TierHighResource
      ciEnableTests highGitLab `shouldBe` True
      ciContainerImage highGitLab `shouldBe` "haskell:9.14"

      let lightGH = forgeDefaultSpec ForgeGitHub TierLightweightStatic
      ciTier lightGH `shouldBe` TierLightweightStatic
      ciEnableTests lightGH `shouldBe` False
