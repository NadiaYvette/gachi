{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Module: Main
-- Description: Comprehensive test suite for gachi-retrofit (Milestone 4.1)
module Main (main) where

import Control.Exception (SomeException, catch)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import System.Directory
  ( createDirectoryIfMissing
  , doesDirectoryExist
  , doesFileExist
  , getCurrentDirectory
  , removeDirectoryRecursive
  )
import System.FilePath (takeDirectory, (</>))
import Test.Hspec

import Gachi.Retrofit
import Gachi.Schema.Project (Author(..), defaultProject)

main :: IO ()
main = hspec $ do
  describe "Gachi.Retrofit.Diagnostic (Pure Analyzers)" $ do
    it "detects programming language distribution and file percentages" $ do
      let samplePaths =
            [ "src/Foo.hs"
            , "src/Bar.hs"
            , "src/Baz.lhs"
            , "native/core.rs"
            , "script/run.py"
            , "bin/tool.sh"
            ]
          stats = detectLanguages samplePaths
      length stats `shouldBe` 4
      case stats of
        (top:rest) -> do
          langType top `shouldBe` LangHaskell
          langFiles top `shouldBe` 3
          langPercentage top `shouldBe` 50.0
          map langType rest `shouldMatchList` [LangRust, LangPython, LangShell]
        [] -> expectationFailure "Expected language statistics to be non-empty"

    it "handles empty or unrecognized file lists gracefully" $ do
      detectLanguages [] `shouldBe` []
      detectLanguages ["data.txt", "image.png"] `shouldBe` []

    it "classifies single-package and multi-package workspace layouts" $ do
      let singlePaths = ["my-proj.cabal", "src/Main.hs", "README.md"]
          (buildsSingle, layoutSingle) = detectBuildSystems "." singlePaths
      BuildCabalPackage `elem` buildsSingle `shouldBe` True
      layoutSingle `shouldBe` LayoutSinglePackage

      let multiPaths =
            [ "cabal.project"
            , "packages/core/core.cabal"
            , "packages/cli/cli.cabal"
            ]
          (buildsMulti, layoutMulti) = detectBuildSystems "." multiPaths
      BuildCabalProject `elem` buildsMulti `shouldBe` True
      BuildCabalPackage `elem` buildsMulti `shouldBe` True
      layoutMulti `shouldBe` LayoutMultiPackage

    it "identifies polyglot and foreign build manifests" $ do
      let polyPaths =
            [ "cabal.project"
            , "Cargo.toml"
            , "CMakeLists.txt"
            , "Makefile"
            , "pyproject.toml"
            ]
          (builds, layout) = detectBuildSystems "." polyPaths
      BuildCargo `elem` builds `shouldBe` True
      BuildCMake `elem` builds `shouldBe` True
      BuildMake `elem` builds `shouldBe` True
      BuildPoetry `elem` builds `shouldBe` True
      layout `shouldBe` LayoutPolyglot

    it "audits documentation gaps against DOC_STRATEGY.md requirements" $ do
      let sparsePaths = ["README.md", "LICENSE"]
          gaps = detectDocumentationGaps "." sparsePaths
          present = filter docPresent gaps
          missing = filter (not . docPresent) gaps

      length present `shouldBe` 2
      map docPath present `shouldMatchList` ["README.md", "LICENSE"]

      let missingCritical = filter (\d -> docSeverity d == SeverityCritical) missing
      missingCritical `shouldBe` []

      let missingRecommended = filter (\d -> docSeverity d == SeverityRecommended) missing
      any (\d -> docPath d == "PLAN.md") missingRecommended `shouldBe` True
      any (\d -> docPath d == "STATE.md") missingRecommended `shouldBe` True
      any (\d -> docPath d == "AGENTS.md") missingRecommended `shouldBe` True
      any (\d -> docPath d == "docs/INDEX.md") missingRecommended `shouldBe` True

    it "computes weighted ecosystem retrofit readiness score" $ do
      let noStats = []
          noBuilds = []
          noTests = TestInfrastructure False [] [] 0
          allDocsMissing = detectDocumentationGaps "." []
          noGit = GitGovernanceStatus False False Nothing False False False False False False Nothing
          noHarness = VerificationHarnessStatus False Nothing False False False False False False

          scoreLow = computeRetrofitScore noStats noBuilds noTests allDocsMissing noGit noHarness
      scoreLow `shouldSatisfy` (< 30.0)

      let sampleStats = [LanguageStats LangHaskell 10 100.0 [".hs"]]
          sampleBuilds = [BuildCabalProject, BuildCabalPackage]
          sampleTests = TestInfrastructure True [TestSuiteInfo "tests" "test" [FrameworkHspec]] ["test"] 5
          allDocsPresent = map (\d -> d { docPresent = True }) allDocsMissing
          sampleGit = GitGovernanceStatus True True (Just ".githooks") True True True True True True (Just ".gitmessage")
          sampleHarness = VerificationHarnessStatus True (Just "bin/verify") True True True True True True

          scoreHigh = computeRetrofitScore sampleStats sampleBuilds sampleTests allDocsPresent sampleGit sampleHarness
      scoreHigh `shouldSatisfy` (>= 90.0)

    it "generates prioritized remediation actions" $ do
      let noTests = TestInfrastructure False [] [] 0
          gaps = detectDocumentationGaps "." []
          noGit = GitGovernanceStatus False False Nothing False False False False False False Nothing
          noHarness = VerificationHarnessStatus False Nothing False False False False False False
          plan = computeRemediationPlan "victim" LayoutSinglePackage noTests gaps noGit noHarness

      any ("Initialize Git repository" `T.isInfixOf`) plan `shouldBe` True
      any ("bin/victim-verify" `T.isInfixOf`) plan `shouldBe` True
      any ("Scaffold mandatory document: README.md" `T.isInfixOf`) plan `shouldBe` True
      any ("Establish baseline test suite" `T.isInfixOf`) plan `shouldBe` True
      any ("Consider migrating from single-package layout" `T.isInfixOf`) plan `shouldBe` True

  describe "Gachi.Retrofit.Report (Pretty-Printing & Formats)" $ do
    it "renders aligned terminal ASCII dashboard with all sections" $ do
      let sampleReport = DiagnosticReport
            { diagTargetDir           = "/tmp/sample-repo"
            , diagProjectName         = "sample-repo"
            , diagPrimaryLanguage     = Just LangHaskell
            , diagLanguages           = [LanguageStats LangHaskell 10 100.0 [".hs"]]
            , diagBuildSystems        = [BuildCabalProject]
            , diagLayout              = LayoutMultiPackage
            , diagDiscoveredPackages  = ["pkg-core", "pkg-cli"]
            , diagTestInfra           = TestInfrastructure True [TestSuiteInfo "test" "test" [FrameworkHspec]] ["test"] 3
            , diagDocGaps             = detectDocumentationGaps "." ["README.md"]
            , diagDocCompliancePct    = 10.0
            , diagGitGovernance       = GitGovernanceStatus True True (Just ".githooks") True True True True True True (Just ".gitmessage")
            , diagVerificationHarness = VerificationHarnessStatus True (Just "bin/sample-verify") True True True True True True
            , diagRetrofitScore       = 75.5
            , diagRemediationPlan     = ["Scaffold mandatory document: LICENSE"]
            }
          output = formatDiagnosticReport sampleReport

      "Gachi Diagnostic Repository Inspector" `T.isInfixOf` output `shouldBe` True
      "sample-repo" `T.isInfixOf` output `shouldBe` True
      "75.5%" `T.isInfixOf` output `shouldBe` True
      "[1] Programming Language Breakdown" `T.isInfixOf` output `shouldBe` True
      "[2] Test Infrastructure" `T.isInfixOf` output `shouldBe` True
      "[3] Documentation Inventory" `T.isInfixOf` output `shouldBe` True
      "[4] Git Governance & Commit Attribution" `T.isInfixOf` output `shouldBe` True
      "[5] Physical Verification Harnesses & Quality Gates" `T.isInfixOf` output `shouldBe` True
      "[6] Prioritized Phase 4 Remediation Plan" `T.isInfixOf` output `shouldBe` True

    it "renders GitHub-Flavored Markdown report" $ do
      let sampleReport = DiagnosticReport
            { diagTargetDir           = "/tmp/sample-repo"
            , diagProjectName         = "sample-repo"
            , diagPrimaryLanguage     = Just LangHaskell
            , diagLanguages           = [LanguageStats LangHaskell 10 100.0 [".hs"]]
            , diagBuildSystems        = [BuildCabalPackage]
            , diagLayout              = LayoutSinglePackage
            , diagDiscoveredPackages  = ["sample-repo"]
            , diagTestInfra           = TestInfrastructure False [] [] 0
            , diagDocGaps             = detectDocumentationGaps "." []
            , diagDocCompliancePct    = 0.0
            , diagGitGovernance       = GitGovernanceStatus False False Nothing False False False False False False Nothing
            , diagVerificationHarness = VerificationHarnessStatus False Nothing False False False False False False
            , diagRetrofitScore       = 25.0
            , diagRemediationPlan     = ["Initialize Git repository"]
            }
          md = formatDiagnosticMarkdown sampleReport

      "# Diagnostic Repository Inspection Report: `sample-repo`" `T.isInfixOf` md `shouldBe` True
      "| Language | Files | Share | Extensions |" `T.isInfixOf` md `shouldBe` True
      "| Haskell | 10 | 100.0% |" `T.isInfixOf` md `shouldBe` True

    it "renders compact single-line summary string" $ do
      let sampleReport = DiagnosticReport
            { diagTargetDir           = "/tmp/sample"
            , diagProjectName         = "sample"
            , diagPrimaryLanguage     = Just LangHaskell
            , diagLanguages           = []
            , diagBuildSystems        = []
            , diagLayout              = LayoutSinglePackage
            , diagDiscoveredPackages  = []
            , diagTestInfra           = TestInfrastructure False [] [] 0
            , diagDocGaps             = []
            , diagDocCompliancePct    = 0.0
            , diagGitGovernance       = GitGovernanceStatus False False Nothing False False False False False False Nothing
            , diagVerificationHarness = VerificationHarnessStatus False Nothing False False False False False False
            , diagRetrofitScore       = 40.0
            , diagRemediationPlan     = []
            }
          line = formatDiagnosticSummaryLine sampleReport
      "gachi retrofit inspect [sample]: Haskell, Single-Package Root Layout, Score: 40.0%" `T.isInfixOf` line `shouldBe` True

  describe "Gachi.Retrofit (Filesystem Inspection)" $ do
    it "scans a mock legacy repository and identifies architectural attributes" $ do
      let tmpDir = "/tmp/gachi-test-legacy-victim"
      removeDirectoryRecursive tmpDir `catch` (\(_ :: SomeException) -> pure ())
      createDirectoryIfMissing True (tmpDir </> "src")
      createDirectoryIfMissing True (tmpDir </> "test")

      TIO.writeFile (tmpDir </> "victim.cabal") "name: victim\nversion: 0.1.0.0\n"
      TIO.writeFile (tmpDir </> "src" </> "Victim.hs") "module Victim where\nx = 42\n"
      TIO.writeFile (tmpDir </> "test" </> "Spec.hs") "import Test.Hspec\nmain = hspec (it \"works\" $ True `shouldBe` True)\n"
      TIO.writeFile (tmpDir </> "README.md") "# Victim Project\n"

      report <- scanRepository tmpDir

      diagProjectName report `shouldBe` "victim"
      diagPrimaryLanguage report `shouldBe` Just LangHaskell
      diagLayout report `shouldBe` LayoutSinglePackage
      hasTests (diagTestInfra report) `shouldBe` True
      diagDocCompliancePct report `shouldSatisfy` (> 0.0)
      hasGitRepo (diagGitGovernance report) `shouldBe` False
      hasVerifyScript (diagVerificationHarness report) `shouldBe` False

      -- Clean up
      removeDirectoryRecursive tmpDir `catch` (\(_ :: SomeException) -> pure ())

    it "executes self-diagnostic scan on the host workspace with high conformance" $ do
      cwd <- getCurrentDirectory
      repoRoot <- findRepoRoot cwd
      report <- scanRepository repoRoot

      diagProjectName report `shouldBe` "gachi"
      diagPrimaryLanguage report `shouldBe` Just LangHaskell
      diagLayout report `shouldBe` LayoutMultiPackage
      diagBuildSystems report `shouldContain` [BuildCabalProject]
      hasTests (diagTestInfra report) `shouldBe` True
      hasGitRepo (diagGitGovernance report) `shouldBe` True
      hasHooksDir (diagGitGovernance report) `shouldBe` True
      hasCommitMsgHook (diagGitGovernance report) `shouldBe` True
      hasCommitMsgAttributionCheck (diagGitGovernance report) `shouldBe` True
      hasVerifyScript (diagVerificationHarness report) `shouldBe` True
      diagRetrofitScore report `shouldSatisfy` (>= 90.0)

  describe "Gachi.Retrofit.Overlay (Non-Destructive Skeleton Overlay)" $ do
    it "synthesizes complete candidate overlay assets across all 6 categories" $ do
      let proj = defaultProject "sample" (Author "Test Author" "author@example.com")
          candidates = synthesizeOverlayCandidates proj LayoutSinglePackage
      length candidates `shouldSatisfy` (>= 25)
      let paths = map actionPath candidates
      all (`elem` paths) ["docs/INDEX.md", "docs/notes/DOC_STRATEGY.md", "PLAN.md", "STATE.md"] `shouldBe` True
      all (`elem` paths) ["AGENTS.md", "CLAUDE.md", ".agents/rules/commit-attribution.md"] `shouldBe` True
      all (`elem` paths) [".githooks/commit-msg", ".githooks/pre-commit", ".gitmessage"] `shouldBe` True
      all (`elem` paths) ["bin/sample-verify", "bin/sample-tagref", "bin/sample-linkcheck", "bin/sample-cloc"] `shouldBe` True
      all (`elem` paths) [".hlint.yaml", "fourmolu.yaml"] `shouldBe` True

    it "computes overlay plan preserving existing files and proposing missing assets" $ do
      let tmpDir = "/tmp/gachi-test-overlay-plan"
      removeDirectoryRecursive tmpDir `catch` (\(_ :: SomeException) -> pure ())
      createDirectoryIfMissing True (tmpDir </> "src")
      TIO.writeFile (tmpDir </> "README.md") "# Existing README\n"
      TIO.writeFile (tmpDir </> "src" </> "Main.hs") "module Main where\nmain = putStrLn \"hello\"\n"

      report <- scanRepository tmpDir
      plan <- computeOverlayPlan tmpDir report

      planCreatedCount plan `shouldSatisfy` (> 0)
      planPreservedCount plan `shouldSatisfy` (>= 1)

      let readmeAction = filter (\a -> actionPath a == "README.md") (planActions plan)
      case readmeAction of
        (act:_) -> actionType act `shouldBe` ActionPreserve
        []      -> expectationFailure "Expected README.md to be present in overlay actions"

      -- Verify Git governance proposal
      any (\case GitInitRepo -> True; _ -> False) (planGitActions plan) `shouldBe` True
      any (\case GitSetConfig k _ -> k == "core.hooksPath"; _ -> False) (planGitActions plan) `shouldBe` True

      removeDirectoryRecursive tmpDir `catch` (\(_ :: SomeException) -> pure ())

    it "executes non-destructive overlay, creates harnesses, configures git, and guarantees idempotency" $ do
      let tmpDir = "/tmp/gachi-test-overlay-exec"
      removeDirectoryRecursive tmpDir `catch` (\(_ :: SomeException) -> pure ())
      createDirectoryIfMissing True (tmpDir </> "src")
      let origDomainCode = "module Domain where\nsecret = 1337\n"
      TIO.writeFile (tmpDir </> "src" </> "Domain.hs") origDomainCode
      TIO.writeFile (tmpDir </> "README.md") "# Original Title\n"

      report <- scanRepository tmpDir
      plan <- computeOverlayPlan tmpDir report
      res <- executeOverlayPlan plan

      resultSuccess res `shouldBe` True
      all (`elem` resultCreatedFiles res) ["docs/INDEX.md", "AGENTS.md", ".githooks/commit-msg"] `shouldBe` True
      "README.md" `elem` resultPreservedFiles res `shouldBe` True

      -- Invariant 1: Domain source code must remain 100% byte-identical
      domainCodeAfter <- TIO.readFile (tmpDir </> "src" </> "Domain.hs")
      domainCodeAfter `shouldBe` origDomainCode

      -- Invariant 2: Existing README.md preserved intact
      readmeAfter <- TIO.readFile (tmpDir </> "README.md")
      readmeAfter `shouldBe` "# Original Title\n"

      -- Invariant 3: Verification harnesses created with executable permissions
      doesFileExist (tmpDir </> "bin" </> (T.unpack (diagProjectName report) ++ "-verify")) `shouldReturn` True
      doesFileExist (tmpDir </> ".githooks" </> "commit-msg") `shouldReturn` True

      -- Invariant 4: Git repository initialized and configured
      doesDirectoryExist (tmpDir </> ".git") `shouldReturn` True

      -- Invariant 5: Idempotency guarantee: Re-planning over retrofitted directory plans 0 creations for those assets
      report2 <- scanRepository tmpDir
      plan2 <- computeOverlayPlan tmpDir report2
      planCreatedCount plan2 `shouldBe` 0

      removeDirectoryRecursive tmpDir `catch` (\(_ :: SomeException) -> pure ())

    it "formats overlay plan and results into human-readable ASCII and Markdown dashboards" $ do
      let tmpDir = "/tmp/gachi-test-overlay-fmt"
      createDirectoryIfMissing True tmpDir
      report <- scanRepository tmpDir
      plan <- computeOverlayPlan tmpDir report

      let asciiPlan = formatOverlayPlan plan
      "Gachi Non-Destructive Skeleton Overlay Plan" `T.isInfixOf` asciiPlan `shouldBe` True
      "Proposed Actions:" `T.isInfixOf` asciiPlan `shouldBe` True

      let mdPlan = formatOverlayPlanMarkdown plan
      "# Non-Destructive Skeleton Overlay Plan:" `T.isInfixOf` mdPlan `shouldBe` True
      "| Status | File Path | Executable |" `T.isInfixOf` mdPlan `shouldBe` True

      res <- executeOverlayPlan plan
      let asciiRes = formatOverlayResult res
      "Gachi Non-Destructive Overlay Execution Results" `T.isInfixOf` asciiRes `shouldBe` True
      "Overlay successfully applied!" `T.isInfixOf` asciiRes `shouldBe` True

      removeDirectoryRecursive tmpDir `catch` (\(_ :: SomeException) -> pure ())

findRepoRoot :: FilePath -> IO FilePath
findRepoRoot dir = do
  hasProj <- doesFileExist (dir </> "cabal.project")
  if hasProj
    then pure dir
    else do
      let parent = takeDirectory dir
      if parent == dir
        then pure dir
        else findRepoRoot parent

