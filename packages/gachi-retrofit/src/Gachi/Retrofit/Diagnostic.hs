{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Module: Gachi.Retrofit.Diagnostic
-- Description: Diagnostic repository inspector and static analysis engine
--
-- This module implements the static analysis engine for inspecting arbitrary
-- codebases (Milestone 4.1, Phase 4). It performs strictly read-only diagnostics
-- across languages, build systems, test suites, documentation, git hooks, and
-- verification harnesses.
--
-- = Architectural Context & Invariants
--
-- Note [Non-Destructive Skeleton Overlay]
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- [tag:note-nondestructive-retrofit]
-- The Non-Destructive Codebase Retrofitting engine ('gachi retrofit') adopts legacy,
-- single-package, or foreign repositories into the canonical multi-package ecosystem
-- hierarchy (~/src/PLAN.md §1.A, Phase 4).
--
-- Core Invariants:
-- 1. __Preservation of Domain Logic:__ Retrofitting operations must never delete,
--    overwrite, or mutate existing domain source files located in @src/@, @app/@,
--    @lib/@, or domain-specific subdirectories.
-- 2. __Pure Observational Diagnosis:__ Milestone 4.1 performs strictly read-only
--    static analysis across six orthogonal dimensions (languages, build systems,
--    test infrastructure, @DOC_STRATEGY.md@ gaps, Git hooks, verification gates)
--    before any mutation or overlay is considered.
-- 3. __Progressive Realization:__ Quality gates are phased incrementally:
--    - Level 0: Scaffolding, documentation skeletons, and verification harnesses.
--    - Level 1: Tagref cross-references and Markdown link integrity.
--    - Level 2: Clean build under @-Wall -Wcompat -Wredundant-constraints@.
--    - Level 3: HLint hints completely eliminated (zero-hint policy).
--
-- Note [Arbitrary Target Codebase Language Classification and Extension Semantics]
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- Automated language classification across arbitrary codebases presents unique challenges:
-- 1. __Pruning Build Artifacts:__ Repositories frequently contain thousands of generated
--    files (e.g. @dist-newstyle@, @node_modules@, @target@, @.stack-work@, @__pycache__@).
--    The crawler explicitly prunes these directories prior to extension matching to prevent
--    skewed distributions or out-of-memory traversal.
-- 2. __Polyglot Workspaces:__ Large systems combine multiple language runtimes (e.g.
--    Haskell core logic, Rust foreign function bindings, C runtime drivers, Python scripts).
--    The scanner computes absolute file counts and proportional percentages across all
--    detected languages, identifying the primary language by relative majority.
-- 3. __Header Disambiguation:__ C and C++ header files (@.h@, @.hpp@) are tracked with
--    their respective language families to provide an accurate overview of native subsystems.
--
-- Note [Test Infrastructure Discovery and Framework Introspection]
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- Rather than executing untrusted test scripts during diagnostic inspection, the analyzer
-- performs static introspection:
-- 1. Discovers standard test directories (@test/@, @tests/@, @spec/@).
-- 2. Scans test source files for known testing framework modules (@Test.Hspec@, @Test.Tasty@,
--    @Test.QuickCheck@, @Hedgehog@, @pytest@, @cargo test@).
-- 3. Identifies declared test targets and reports whether the repository possesses active
--    automated quality gates.
--
-- Note [DOC_STRATEGY.md Corpus Adherence and Gap Categorization]
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- The canonical documentation strategy (@DOC_STRATEGY.md@ §1) establishes that documentation
-- serves distinct audiences with strictly defined fact classes and canonicity.
-- The diagnostic inspector evaluates repositories against this checklist, categorizing
-- missing documents by severity:
-- * __Critical:__ @README.md@ (arrival orientation) and @LICENSE@ (legal terms).
-- * __Recommended:__ @PLAN.md@ / @STATE.md@ (session loop), @AGENTS.md@ (agent advisory),
--   @docs/INDEX.md@ (reading paths), @docs/notes/DOC_STRATEGY.md@ (policy), and
--   @docs/notes/COMMIT_ATTRIBUTION.md@ (RFC 2822 trailer rules).
-- * __Optional:__ @CLAUDE.md@ (symlinks), @CHANGELOG.md@, and tutorial tracks.
--
-- Note [Git Governance, Hook Executability, and RFC 2822 Trailer Verification]
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- To maintain clean copyright and attribution boundaries across the ecosystem, Git hooks
-- enforce strict commit trailer policies:
-- 1. __Trailer Format:__ AI coding assistants must be attributed using RFC 2822 trailers
--    (e.g. @Assisted-by: Antigravity (Google / gemini-3.8-pro)@).
-- 2. __Legal Boundaries:__ AI assistants must NEVER be recorded as @Co-authored-by:@
--    (which implies legal joint copyright authorship) or @Signed-off-by:@ (which certifies
--    the human Developer Certificate of Origin).
-- 3. __Hook Validation:__ The inspector validates that @commit-msg@ exists, has POSIX
-- Note [Heuristic Project Name and Workspace Topography Resolution]
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- Determining the identity and canonical slug of an arbitrary codebase requires a deterministic
-- resolution ladder:
-- 1. __Direct Manifest Discovery:__ If a single @*.cabal@ manifest exists at the root level
--    (e.g. @victim.cabal@), its basename defines the canonical project name.
-- 2. __Multi-Package Workspace Fallback:__ If a multi-package workspace definition (@cabal.project@)
--    is present, individual child package manifests in @packages/*/@ must not be confused with
--    the parent project. In this scenario, the normalized directory basename of the workspace
--    root (e.g. @"gachi"@) serves as the authoritative project identifier.
-- 3. __Absolute Path Canonicalization:__ The scanner resolves relative target paths (e.g. @.@)
--    via 'makeAbsolute' prior to name extraction, ensuring robust identification across subpackage
--    invocations.
--
-- Note [Comprehensive Six-Pillar Diagnostic Scoring Formula]
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- The diagnostic evaluation culminates in a quantitative retrofit score S(P) in [0.0, 100.0]:
-- 1. __Languages & Toolchains (15%):__ Rewards clear language identification (Haskell, Rust, etc.)
--    and recognized declarative build manifests (@cabal.project@, @Cargo.toml@).
-- 2. __Test Infrastructure (20%):__ Evaluates test directories (@test/@, @spec/@), declared suites,
--    and recognized testing frameworks (@Test.Hspec@, @Test.Tasty@, @pytest@).
-- 3. __Documentation Integrity (30%):__ Proportionally scores presence of Critical and Recommended
--    assets per @DOC_STRATEGY.md@ §1.
-- 4. __Git Governance & Attribution (20%):__ Evaluates @.git@, @.githooks@, executable @commit-msg@
--    with RFC 2822 @Assisted-by:@ trailer validation, and @.gitmessage@ commit template pinning.
-- 5. __Verification Harnesses (15%):__ Checks presence and executability of turnkey @bin/*-verify@,
--    Tagref runner, Markdown linkcheck, and CLOC comment density audit scripts.
--
-- Note [Remediation Action Priority Ordering and Phase 4 Transition]
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- The diagnostic analyzer transforms localized defects into an ordered remediation plan:
-- 1. __Sovereign Git Governance:__ Bootstrapping @.githooks@ and commit trailer enforcement must
--    precede any file mutations to guarantee attribution integrity from the first commit.
-- 2. __Physical Verification Harnesses:__ Turnkey test runners (@bin/*-verify@) are provisioned
--    next so every subsequent transformation can be verified immediately.
-- 3. __Critical Documentation Scaffolding:__ @README.md@ and @LICENSE@ establish legal and
--    operational identity.
-- 4. __Recommended Operational Governance:__ @PLAN.md@, @STATE.md@, and @AGENTS.md@ establish
--    the two-file loop and AI assistant boundaries.
-- 5. __Test Suite & Layout Modernization:__ Establishes baseline test coverage and guides
--    single-package repositories toward multi-package workspace modularity.
--
-- Note [Safe Recursive Filesystem Crawling with Zero Allocations]
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- Arbitrary checkouts frequently contain deep recursive structures, broken symlinks, or
-- million-file generated directories (e.g. @node_modules@, @dist-newstyle@, @.stack-work@).
-- To maintain sub-second response times and zero memory exhaustion:
-- 1. __Pre-Descent Pruning:__ The crawler matches directory basenames against 'ignoredDirectories'
--    before calling 'listDirectory', completely preventing traversal of massive trees.
-- 2. __Exception Containment:__ File permission exceptions and dangling symlinks are swallowed
--    gracefully via 'catch', allowing partial audits of restricted file trees.
-- 3. __Relative Path Normalization:__ All discovered paths are returned relative to the root,
--    enabling deterministic matching against canonical templates.
--
-- = Worked Example
--
-- >>> report <- scanRepository "."
-- >>> diagProjectName report
-- "gachi"
-- >>> diagRetrofitScore report >= 50.0
-- True
module Gachi.Retrofit.Diagnostic
  ( -- * High-Level Scanner
    scanRepository

    -- * Dimension Analyzers
  , detectLanguages
  , detectBuildSystems
  , detectTestInfrastructure
  , detectDocumentationGaps
  , detectGitGovernance
  , detectVerificationHarnesses

    -- * Scoring & Remediation Planning
  , computeRetrofitScore
  , computeRemediationPlan
  , inferProjectName

    -- * Filesystem Traversal
  , listRepositoryFiles
  , isIgnoredDirectory
  ) where

import Control.Exception (SomeException, catch)
import Data.Char (toLower)
import Data.List (isPrefixOf, isSuffixOf, nub, partition, sortBy)
import qualified Data.Map.Strict as Map
import Data.Maybe (isJust, mapMaybe)
import Data.Ord (comparing)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import System.Directory
  ( doesDirectoryExist
  , doesFileExist
  , executable
  , getPermissions
  , listDirectory
  , makeAbsolute
  )
import System.Exit (ExitCode(..))
import System.FilePath (dropTrailingPathSeparator, takeDirectory, takeExtension, takeFileName, (</>))
import System.Process (readProcessWithExitCode)

import Gachi.Retrofit.Types

--------------------------------------------------------------------------------
-- 1. Filesystem Traversal
--------------------------------------------------------------------------------

-- | Directory basenames intentionally skipped during diagnostic exploration to avoid
-- infinite loops, deep virtualenvs, or massive build artifacts.
ignoredDirectories :: [String]
ignoredDirectories =
  [ ".git"
  , "dist-newstyle"
  , ".stack-work"
  , "target"
  , "node_modules"
  , "__pycache__"
  , ".venv"
  , "venv"
  , "env"
  , ".cabal-sandbox"
  , ".direnv"
  , "dist"
  , "_build"
  , ".tox"
  ]

-- | Predicate checking whether a directory path should be ignored during traversal.
--
-- Matches known build artifact directories and temporary scratch paths starting
-- with @.tmp@.
--
-- === Examples
--
-- >>> isIgnoredDirectory "dist-newstyle"
-- True
-- >>> isIgnoredDirectory "src"
-- False
isIgnoredDirectory :: FilePath -> Bool
isIgnoredDirectory dirName =
  let base = takeFileName (dropTrailingPathSeparator dirName)
  in base `elem` ignoredDirectories || ".tmp" `isPrefixOf` base

-- | Recursively traverses a target directory collecting relative file paths.
--
-- Automatically prunes ignored directories ('isIgnoredDirectory') and gracefully
-- recovers from filesystem permission errors, broken symlinks, or transient I/O faults.
-- Returns relative paths normalized against the inspected directory root.
listRepositoryFiles :: FilePath -> IO [FilePath]
listRepositoryFiles root = go ""
  where
    go relDir = do
      let fullDir = if null relDir then root else root </> relDir
      isDir <- doesDirectoryExist fullDir `catch` (\(_ :: SomeException) -> pure False)
      if not isDir || (not (null relDir) && isIgnoredDirectory relDir)
        then pure []
        else do
          entries <- listDirectory fullDir `catch` (\(_ :: SomeException) -> pure [])
          concatMapM (processEntry relDir) entries

    processEntry relDir entry
      | isIgnoredDirectory entry = pure []
      | otherwise = do
          let relPath = if null relDir then entry else relDir </> entry
              fullPath = root </> relPath
          isDir <- doesDirectoryExist fullPath `catch` (\(_ :: SomeException) -> pure False)
          if isDir
            then go relPath
            else pure [relPath]

    concatMapM f xs = fmap concat (mapM f xs)

--------------------------------------------------------------------------------
-- 2. Programming Language Detection
--------------------------------------------------------------------------------

-- | Maps a file extension to its corresponding programming language.
--
-- Covers Haskell, Rust, C, C++, Python, Shell, OCaml, Go, Java, JavaScript, and TypeScript.
classifyExtension :: String -> Maybe (Language, Text)
classifyExtension ext = case map toLower ext of
  ".hs"    -> Just (LangHaskell, ".hs")
  ".lhs"   -> Just (LangHaskell, ".lhs")
  ".rs"    -> Just (LangRust, ".rs")
  ".c"     -> Just (LangC, ".c")
  ".h"     -> Just (LangC, ".h")
  ".cpp"   -> Just (LangCpp, ".cpp")
  ".cc"    -> Just (LangCpp, ".cc")
  ".cxx"   -> Just (LangCpp, ".cxx")
  ".hpp"   -> Just (LangCpp, ".hpp")
  ".hxx"   -> Just (LangCpp, ".hxx")
  ".py"    -> Just (LangPython, ".py")
  ".sh"    -> Just (LangShell, ".sh")
  ".bash"  -> Just (LangShell, ".bash")
  ".zsh"   -> Just (LangShell, ".zsh")
  ".ml"    -> Just (LangOCaml, ".ml")
  ".mli"   -> Just (LangOCaml, ".mli")
  ".go"    -> Just (LangGo, ".go")
  ".java"  -> Just (LangJava, ".java")
  ".js"    -> Just (LangJavaScript, ".js")
  ".mjs"   -> Just (LangJavaScript, ".mjs")
  ".cjs"   -> Just (LangJavaScript, ".cjs")
  ".ts"    -> Just (LangTypeScript, ".ts")
  ".tsx"   -> Just (LangTypeScript, ".tsx")
  _        -> Nothing

-- | Purely analyzes a collection of repository file paths to determine programming
-- language distributions, file counts, and percentage breakdowns.
--
-- Groups recognized files by 'Language', sums occurrences, computes percentage
-- share relative to total recognized source files, and sorts descending by file count.
--
-- === Examples
--
-- >>> let stats = detectLanguages ["src/A.hs", "src/B.hs", "native/c.rs"]
-- >>> length stats
-- 2
-- >>> langFiles (head stats)
-- 2
detectLanguages :: [FilePath] -> [LanguageStats]
detectLanguages paths =
  let recognized = mapMaybe (classifyExtension . takeExtension) paths
      totalCount = length recognized
      grouped = foldr insertLang Map.empty recognized
      statsList = Map.foldrWithKey (buildStat totalCount) [] grouped
  in sortBy (comparing (negate . langFiles)) statsList
  where
    insertLang (lang, ext) m =
      let (cnt, exts) = Map.findWithDefault (0, []) lang m
      in Map.insert lang (cnt + 1, if ext `elem` exts then exts else ext : exts) m

    buildStat total lang (cnt, exts) acc =
      let pct = if total > 0 then (fromIntegral cnt / fromIntegral total) * 100.0 else 0.0
          stat = LanguageStats
            { langType       = lang
            , langFiles      = cnt
            , langPercentage = fromIntegral (round (pct * 10 :: Double) :: Int) / 10.0
            , langExtensions = exts
            }
      in stat : acc

--------------------------------------------------------------------------------
-- 3. Build Systems & Layout Detection
--------------------------------------------------------------------------------

-- | Detects build tool manifests and classifies the repository workspace layout.
--
-- === Build Manifest Detection Mechanics
--
-- The analyzer inspects file paths across two topological tiers:
-- 1. __Root Manifests:__ Checks whether authoritative manifests inhabit the repository
--    root directory:
--    - Cabal Workspace: @cabal.project@ establishes multi-package boundaries.
--    - Single Cabal Package: Any @*.cabal@ residing directly in @takeDirectory p == "."@.
--    - Stack Project: @stack.yaml@ defines curated Stackage resolver pins.
--    - Hpack Specification: @package.yaml@ generates @*.cabal@ dynamically.
--    - Rust Cargo: @Cargo.toml@ specifies package or virtual workspace dependencies.
--    - CMake: @CMakeLists.txt@ defines cross-platform native builds.
--    - Make: Standard @Makefile@, @makefile@, or @GNUmakefile@.
--    - Meson: @meson.build@ provides high-speed Ninja-based builds.
--    - Python Packaging: @pyproject.toml@, @setup.py@, @setup.cfg@, @requirements.txt@.
--    - Nix Expressions: @flake.nix@ and @default.nix@ establish hermetic sandbox builds.
--
-- 2. __Subpackage Traversal:__
--    Discovers nested packages within @packages/*/*.cabal@, signaling modern multi-package
--    workspaces.
--
-- === Layout Classification Semantics
--
-- The discovered manifests determine the 'WorkspaceLayout':
-- * 'LayoutMultiPackage': Segregated packages in @packages/*/@. The ideal topology for
--   Gachi ecosystem integration.
-- * 'LayoutSinglePackage': Standalone library or tool located at root. Retrofitting
--   recommends migrating to multi-package modularity when scaling.
-- * 'LayoutPolyglot': Co-existence of multiple heterogeneous build systems (e.g.
--   Haskell + Rust FFI or C + Python bindings). Requires partitioned CI workflows.
-- * 'LayoutUnstructured': Raw source files discovered without any declarative manifest.
--   Requires baseline build system synthesis.
--
-- === Examples
--
-- >>> let (builds, layout) = detectBuildSystems "." ["cabal.project", "packages/core/core.cabal"]
-- >>> layout
-- LayoutMultiPackage
-- >>> BuildCabalProject `elem` builds
-- True
detectBuildSystems :: FilePath -> [FilePath] -> ([BuildSystem], WorkspaceLayout)
detectBuildSystems _root paths =
  let manifests = findBuildManifests paths
      layout = classifyLayout paths manifests
  in (manifests, layout)
  where
    findBuildManifests ps =
      let hasRoot name = name `elem` ps
          hasRootSuffix sfx = any (\p -> takeDirectory p == "." && sfx `isSuffixOf` p) ps
          hasSubCabal = any (\p -> "packages" `isPrefixOf` p && ".cabal" `isSuffixOf` p) ps

          cabalProj = [BuildCabalProject | hasRoot "cabal.project"]
          cabalPkg  = [BuildCabalPackage | hasRootSuffix ".cabal" || hasSubCabal]
          stack     = [BuildStack | hasRoot "stack.yaml"]
          hpack     = [BuildHpack | hasRoot "package.yaml"]
          cargo     = [BuildCargo | hasRoot "Cargo.toml"]
          cmake     = [BuildCMake | hasRoot "CMakeLists.txt"]
          make      = [BuildMake | any (`elem` ps) ["Makefile", "makefile", "GNUmakefile"]]
          meson     = [BuildMeson | hasRoot "meson.build"]
          poetry    = [BuildPoetry | hasRoot "pyproject.toml"]
          setuptools = [BuildSetuptools | hasRoot "setup.py" || hasRoot "setup.cfg"]
          pip       = [BuildPip | hasRoot "requirements.txt"]
          nix       = [BuildNix | hasRoot "flake.nix" || hasRoot "default.nix"]
      in cabalProj ++ cabalPkg ++ stack ++ hpack ++ cargo ++ cmake ++ make ++ meson ++ poetry ++ setuptools ++ pip ++ nix

    classifyLayout ps manifests
      | any (\p -> "packages/" `isPrefixOf` p) ps = LayoutMultiPackage
      | isPolyglot manifests = LayoutPolyglot
      | not (null manifests) = LayoutSinglePackage
      | otherwise            = LayoutUnstructured

    isPolyglot ms =
      let hasHaskell = any (`elem` [BuildCabalProject, BuildCabalPackage, BuildStack, BuildHpack]) ms
          hasRust    = BuildCargo `elem` ms
          hasC       = any (`elem` [BuildCMake, BuildMake, BuildMeson]) ms
          hasPy      = any (`elem` [BuildPoetry, BuildFlit, BuildSetuptools, BuildPip]) ms
          count = length (filter id [hasHaskell, hasRust, hasC, hasPy])
      in count > 1

--------------------------------------------------------------------------------
-- 4. Test Infrastructure Detection
--------------------------------------------------------------------------------

-- | Identifies test directories, declared test suites, and testing frameworks.
--
-- === Static Test Introspection Mechanics
--
-- The analyzer inspects repository file paths to detect automated test infrastructure
-- without compiling or running external scripts:
--
-- 1. __Directory Detection:__ Discovers directories dedicated to testing (@test/@, @tests/@,
--    @spec/@, or subpackage test paths such as @packages/*/test/@).
-- 2. __Test File Counting:__ Identifies test source files matching standard conventions:
--    - Haskell: Files named @*Spec.hs@, @*Test.hs@, or residing inside a @test/@ directory.
--    - Rust: Files containing @"test"@ or residing inside a @tests/@ integration test folder.
--    - Python: Files matching @test_*.py@ or @*_test.py@.
-- 3. __Framework Keyword Introspection:__ Samples discovered test files (up to 5) to inspect
--    their module imports and text content, detecting testing frameworks:
--    - 'FrameworkHspec': BDD testing via @Test.Hspec@.
--    - 'FrameworkTasty': Test runner via @Test.Tasty@.
--    - 'FrameworkQuickCheck': Property testing via @Test.QuickCheck@.
--    - 'FrameworkHedgehog': Integrated property testing via @Hedgehog@.
--    - 'FrameworkCargoTest': Built-in Rust test attributes.
--    - 'FrameworkPytest': Python pytest framework.
--
-- Returns a 'TestInfrastructure' record containing test directories, file counts, and
-- identified frameworks.
detectTestInfrastructure :: FilePath -> [FilePath] -> [BuildSystem] -> IO TestInfrastructure
detectTestInfrastructure root paths _buildSystems = do
  let testDirs = filter isTestDirectory paths
      uniqueDirs = nub (map takeDirectory testDirs)
      testFiles = filter isTestFile paths
      hasAnyTests = not (null testDirs) || not (null testFiles)

  -- Scan discovered test files for framework imports
  discoveredFrameworks <- inspectTestFiles root testFiles
  let suites =
        [ TestSuiteInfo
            { testSuiteName  = "test"
            , testSuitePath  = case uniqueDirs of
                                 (d:_) -> d
                                 []    -> "test"
            , testFrameworks = discoveredFrameworks
            }
        | hasAnyTests
        ]

  pure TestInfrastructure
    { hasTests        = hasAnyTests
    , testSuites      = suites
    , testDirectories = uniqueDirs
    , testFileCount   = length testFiles
    }
  where
    isTestDirectory p =
      let d = takeDirectory p
      in d == "test" || d == "tests" || d == "spec" || "/test" `isInfixOf` d || "/tests" `isInfixOf` d

    isTestFile p =
      let f = takeFileName p
      in (takeExtension p == ".hs" && ("Spec.hs" `isSuffixOf` f || "Test.hs" `isSuffixOf` f || takeDirectory p == "test"))
         || (takeExtension p == ".rs" && ("test" `isInfixOf` f || takeDirectory p == "tests"))
         || (takeExtension p == ".py" && ("test_" `isPrefixOf` f || "_test.py" `isSuffixOf` f))

    inspectTestFiles _ [] = pure []
    inspectTestFiles r files = do
      let sample = take 5 files
      contents <- mapM (\f -> TIO.readFile (r </> f) `catch` (\(_ :: SomeException) -> pure "")) sample
      let allText = T.unwords contents
          hspec  = [FrameworkHspec | "hspec" `T.isInfixOf` T.toLower allText || "Test.Hspec" `T.isInfixOf` allText]
          tasty  = [FrameworkTasty | "tasty" `T.isInfixOf` T.toLower allText || "Test.Tasty" `T.isInfixOf` allText]
          qc     = [FrameworkQuickCheck | "quickcheck" `T.isInfixOf` T.toLower allText]
          hedge  = [FrameworkHedgehog | "hedgehog" `T.isInfixOf` T.toLower allText]
          pytest = [FrameworkPytest | "pytest" `T.isInfixOf` T.toLower allText]
          cargo  = [FrameworkCargoTest | any (\f -> takeExtension f == ".rs") files]
      pure (nub (hspec ++ tasty ++ qc ++ hedge ++ pytest ++ cargo))

    isInfixOf needle haystack = needle `isPrefixOf` haystack || case haystack of
      (_:rest) -> needle `isInfixOf` rest
      []       -> False

--------------------------------------------------------------------------------
-- 5. Documentation Gaps Analysis
--------------------------------------------------------------------------------

-- | Specification of canonical documentation items per @DOC_STRATEGY.md@.
--
-- Establishes the authoritative inventory of twelve standard documentation assets,
-- categorized by purpose and prioritized by severity.
canonicalDocChecklist :: [(FilePath, DocCategory, DocSeverity, Text)]
canonicalDocChecklist =
  [ ( "README.md"
    , DocOrientation
    , SeverityCritical
    , "Orientation and project entry point for newcomers and users."
    )
  , ( "docs/INDEX.md"
    , DocCorpusInventory
    , SeverityRecommended
    , "Curated corpus inventory and reading paths per DOC_STRATEGY.md §1."
    )
  , ( "docs/notes/DOC_STRATEGY.md"
    , DocStrategy
    , SeverityRecommended
    , "Canonical documentation policy, genres, and precedence rules."
    )
  , ( "docs/notes/COMMIT_ATTRIBUTION.md"
    , DocAttribution
    , SeverityRecommended
    , "Commit trailer specification (RFC 2822 Assisted-by: trailers)."
    )
  , ( "PLAN.md"
    , DocGovernance
    , SeverityRecommended
    , "Strategic roadmap and phase milestone tracking (the two-file loop)."
    )
  , ( "STATE.md"
    , DocGovernance
    , SeverityRecommended
    , "Active session frontier and verification status (the two-file loop)."
    )
  , ( "AGENTS.md"
    , DocAdvisory
    , SeverityRecommended
    , "Bounded AI assistant operational context and modular rules pointer."
    )
  , ( "CLAUDE.md"
    , DocAdvisory
    , SeverityOptional
    , "Compatibility pointer symlink to AGENTS.md."
    )
  , ( "docs/TUTORIAL.md"
    , DocTutorial
    , SeverityOptional
    , "End-to-end tutorial track with worked examples."
    )
  , ( "docs/MAINTAINER_GUIDE.md"
    , DocOperational
    , SeverityRecommended
    , "Maintainer operational manual: release lifecycle, gates, and triage."
    )
  , ( "CHANGELOG.md"
    , DocChangelog
    , SeverityOptional
    , "Chronological version history and notable release changes."
    )
  , ( "LICENSE"
    , DocChangelog
    , SeverityCritical
    , "Open source licensing terms (e.g. EUPL-1.2 or Apache-2.0)."
    )
  ]

-- | Evaluates presence of canonical documentation files against @DOC_STRATEGY.md@.
--
-- === Documentation Fact Classes & Canonicity
--
-- In accordance with @DOC_STRATEGY.md@ §1, documentation is partitioned into strict fact
-- classes to prevent documentation drift:
--
-- 1. __Arrivals (@README.md@):__
--    Orientation facts only. Always defers to canonical design notes for technical claims.
-- 2. __Curated Corpus Inventory (@docs/INDEX.md@):__
--    Comprehensive catalog of all documents, their reading order, fact classes, and authority.
-- 3. __Policy & Authority (@docs/notes/DOC_STRATEGY.md@):__
--    Corpus rules, lifecycle, and the Precedence Rule ("code wins at runtime; notes corrected regardless").
-- 4. __Attribution Invariants (@docs/notes/COMMIT_ATTRIBUTION.md@):__
--    Linux kernel RFC 2822 trailer format for human authors and AI coding assistants.
-- 5. __Governance & Session Frontiers (@PLAN.md@, @STATE.md@):__
--    The Two-File Loop: tracking operational roadmap milestones and active session state.
-- 6. __Agent Advisory Layer (@AGENTS.md@):__
--    Bounded (~4 KB) pointer projection into canonical documents, preventing context degradation.
--
-- Compares repository file paths against 'canonicalDocChecklist', recognizing
-- standard variations (e.g. @LICENSE.md@ or @LICENSE.txt@ for @LICENSE@).
detectDocumentationGaps :: FilePath -> [FilePath] -> [DocGap]
detectDocumentationGaps _root paths =
  map checkItem canonicalDocChecklist
  where
    checkItem (path, cat, sev, advice) =
      let present = path `elem` paths || (path == "LICENSE" && any (\p -> p == "LICENSE.md" || p == "LICENSE.txt") paths)
      in DocGap
        { docPath     = path
        , docCategory = cat
        , docPresent  = present
        , docSeverity = sev
        , docAdvice   = advice
        }

--------------------------------------------------------------------------------
-- 6. Git Governance & Attribution Conformance
--------------------------------------------------------------------------------

-- | Inspects Git repository state, hook paths, and commit trailer validation.
--
-- === Git Governance Invariants
--
-- Audits whether the repository conforms to ecosystem source control standards:
--
-- 1. __Repository Initialization:__ Verifies presence of the @.git@ directory at the root.
-- 2. __Dedicated Hooks Directory:__ Validates existence of @.githooks/@ and queries ambient
--    Git configuration (@git config core.hooksPath@) to confirm hooks are pinned to version
--    control rather than local unstaged @.git/hooks/@.
-- 3. __Executable Commit-Msg Hook:__ Confirms presence and POSIX executable bits (+x) for
--    @commit-msg@.
-- 4. __RFC 2822 Trailer Validation:__ Scans @commit-msg@ script logic to certify that
--    Sarutahiko / RFC 2822 @Assisted-by:@ trailers are validated and enforced, while rejecting
--    illicit AI @Co-authored-by:@ and @Signed-off-by:@ tags.
-- 5. __Executable Pre-Commit Hook:__ Confirms presence and executable bits (+x) for @pre-commit@,
--    which runs Tagref, linkcheck, or formatting pre-checks.
-- 6. __Commit Template Pinning:__ Checks presence of @.gitmessage@ and queries Git
--    configuration (@git config commit.template@) to ensure contributors are guided by the
--    standard HEREDOC commit format.
detectGitGovernance :: FilePath -> IO GitGovernanceStatus
detectGitGovernance root = do
  hasGit <- doesDirectoryExist (root </> ".git") `catch` (\(_ :: SomeException) -> pure False)
  hasHooks <- doesDirectoryExist (root </> ".githooks") `catch` (\(_ :: SomeException) -> pure False)

  hooksCfg <- queryGitConfig root "core.hooksPath"
  templateCfg <- queryGitConfig root "commit.template"

  -- Inspect commit-msg hook
  let commitMsgPath = if hasHooks then root </> ".githooks" </> "commit-msg" else root </> ".git" </> "hooks" </> "commit-msg"
  hasCommitMsg <- doesFileExist commitMsgPath `catch` (\(_ :: SomeException) -> pure False)
  commitMsgExec <- if hasCommitMsg
    then (executable <$> getPermissions commitMsgPath) `catch` (\(_ :: SomeException) -> pure False)
    else pure False
  commitMsgContent <- if hasCommitMsg
    then TIO.readFile commitMsgPath `catch` (\(_ :: SomeException) -> pure "")
    else pure ""
  let hasAttributionCheck = "assisted-by" `T.isInfixOf` T.toLower commitMsgContent
                         || "sarutahiko" `T.isInfixOf` T.toLower commitMsgContent
                         || "rfc 2822" `T.isInfixOf` T.toLower commitMsgContent

  -- Inspect pre-commit hook
  let preCommitPath = if hasHooks then root </> ".githooks" </> "pre-commit" else root </> ".git" </> "hooks" </> "pre-commit"
  hasPreCommit <- doesFileExist preCommitPath `catch` (\(_ :: SomeException) -> pure False)
  preCommitExec <- if hasPreCommit
    then (executable <$> getPermissions preCommitPath) `catch` (\(_ :: SomeException) -> pure False)
    else pure False

  -- Inspect .gitmessage template
  hasTemplate <- doesFileExist (root </> ".gitmessage") `catch` (\(_ :: SomeException) -> pure False)

  pure GitGovernanceStatus
    { hasGitRepo                   = hasGit
    , hasHooksDir                  = hasHooks
    , hooksPathConfig              = hooksCfg
    , hasCommitMsgHook             = hasCommitMsg
    , isCommitMsgExecutable        = commitMsgExec
    , hasCommitMsgAttributionCheck = hasAttributionCheck
    , hasPreCommitHook             = hasPreCommit
    , isPreCommitExecutable        = preCommitExec
    , hasGitMessageTemplate        = hasTemplate
    , gitMessageConfig             = templateCfg
    }
  where
    queryGitConfig r key = do
      (code, out, _) <- readProcessWithExitCode "git" ["-C", r, "config", key] "" `catch` (\(_ :: SomeException) -> pure (ExitFailure 1, "", ""))
      case code of
        ExitSuccess ->
          let val = T.strip (T.pack out)
          in pure (if T.null val then Nothing else Just val)
        ExitFailure _ -> pure Nothing

--------------------------------------------------------------------------------
-- 7. Physical Verification Harnesses
--------------------------------------------------------------------------------

-- | Inspects physical verification scripts, Tagref, Linkcheck, and linters.
--
-- === The Five Physical Verification Gates
--
-- The Gachi quality model is founded on deterministic mechanical verification gates
-- that execute without external network dependencies:
--
-- 1. __Gate 1 (HLint Static Linter):__
--    Audits Haskell code with a zero-hint policy under @.hlint.yaml@. Guarantees clean idioms
--    and purges dead code patterns.
-- 2. __Gate 2 (Full Test Suite):__
--    Executes all declared Cabal/Cargo/Python test suites with streamed assertion details.
-- 3. __Gate 3 (Tagref Cross-Reference Gate):__
--    Evaluates @[tag:...]@ definitions and @[ref:...]@ references, certifying zero dangling
--    pointers and zero duplicate tags across code, comments, and documentation.
-- 4. __Gate 4 (Markdown Link & Anchor Integrity Gate):__
--    Verifies all relative and absolute Markdown hyperlinks and section anchors, preventing
--    documentation drift and 404 dead ends.
-- 5. __Gate 5 (CLOC In-Code Comment Density Gate):__
--    Audits in-code comment lines against total code lines, enforcing the minimum 25.0%
--    verification threshold and the 50.0%+ target on production source (@src/@).
--
-- Inspects repository file paths to confirm whether turnkey runner scripts (@bin/*-verify@,
-- @bin/*-tagref@, @bin/*-linkcheck@, @bin/*-cloc@) and configurations (@tagref.yml@,
-- @.hlint.yaml@, @fourmolu.yaml@) exist.
detectVerificationHarnesses :: FilePath -> [FilePath] -> IO VerificationHarnessStatus
detectVerificationHarnesses _root paths = do
  let verifyCandidates = filter (\p -> "bin/" `isPrefixOf` p && ("-verify" `isSuffixOf` p || p == "bin/verify")) paths
      vPath = case verifyCandidates of
        (vc:_) -> Just vc
        []     -> Nothing
      hasVerify = isJust vPath

  let hasTagrefCfg = "tagref.yml" `elem` paths || ".tagref" `elem` paths
      hasTagrefHarn = any (\p -> "bin/" `isPrefixOf` p && ("-tagref" `isSuffixOf` p || p == "bin/tagref")) paths
      hasLinkcheckHarn = any (\p -> "bin/" `isPrefixOf` p && ("-linkcheck" `isSuffixOf` p || p == "bin/linkcheck")) paths
      hasClocHarn = any (\p -> "bin/" `isPrefixOf` p && ("-cloc" `isSuffixOf` p || p == "bin/cloc")) paths
      hasHlint = ".hlint.yaml" `elem` paths
      hasFourmolu = "fourmolu.yaml" `elem` paths

  pure VerificationHarnessStatus
    { hasVerifyScript      = hasVerify
    , verifyScriptPath     = vPath
    , hasTagrefConfig      = hasTagrefCfg
    , hasTagrefHarness     = hasTagrefHarn
    , hasLinkcheckHarness  = hasLinkcheckHarn
    , hasClocHarness       = hasClocHarn
    , hasHlintConfig       = hasHlint
    , hasFourmoluConfig    = hasFourmolu
    }

--------------------------------------------------------------------------------
-- 8. Scoring & Remediation Planning
--------------------------------------------------------------------------------

-- | Computes a quantitative ecosystem retrofit readiness score (0.0 to 100.0).
--
-- Weight distribution across diagnostic pillars:
-- * __Language & Build Systems (15%):__ Coherent language identification and manifest presence.
-- * __Test Infrastructure (20%):__ Test directories present (10%), declared suites with frameworks (10%).
-- * __Documentation Coverage (30%):__ Proportional presence of Critical and Recommended documents.
-- * __Git Governance & Hooks (20%):__ Git repository (5%), .githooks (5%), commit-msg with attribution (5%), pre-commit & template (5%).
-- * __Verification Quality Gates (15%):__ Turnkey verify runner (5%), Tagref (3%), Linkcheck (3%), CLOC (2%), Linters (2%).
computeRetrofitScore
  :: [LanguageStats]
  -> [BuildSystem]
  -> TestInfrastructure
  -> [DocGap]
  -> GitGovernanceStatus
  -> VerificationHarnessStatus
  -> Double
computeRetrofitScore langs builds tests docs gitHarness verifHarness =
  let -- Pillar 1: Language & Build System clarity (max 15.0)
      -- Rewards presence of recognized programming languages and declarative manifests.
      langScore = if not (null langs) && not (null builds) then 15.0 else 5.0

      -- Pillar 2: Test Infrastructure (max 20.0)
      -- 10.0 points for test directory or files; 10.0 points for recognized frameworks and declared suites.
      testScore = (if hasTests tests then 10.0 else 0.0)
                + (if not (null (testSuites tests)) then 10.0 else 0.0)

      -- Pillar 3: Canonical Documentation Coverage (max 30.0)
      -- Proportion of required and recommended documents present per DOC_STRATEGY.md.
      (reqDocs, _optDocs) = partition (\d -> docSeverity d /= SeverityOptional) docs
      presentReq = length (filter docPresent reqDocs)
      totalReq = max 1 (length reqDocs)
      docScore = (fromIntegral presentReq / fromIntegral totalReq) * 30.0

      -- Pillar 4: Sovereign Git Governance & Attribution (max 20.0)
      -- 5.0 points for .git directory; 5.0 for .githooks or core.hooksPath configuration;
      -- 5.0 for commit-msg with RFC 2822 trailer validation; 5.0 for pre-commit and .gitmessage.
      gitScore = (if hasGitRepo gitHarness then 5.0 else 0.0)
               + (if hasHooksDir gitHarness || isJust (hooksPathConfig gitHarness) then 5.0 else 0.0)
               + (if hasCommitMsgHook gitHarness && hasCommitMsgAttributionCheck gitHarness then 5.0 else 0.0)
               + (if hasPreCommitHook gitHarness && hasGitMessageTemplate gitHarness then 5.0 else 0.0)

      -- Pillar 5: Five-Gate Physical Verification Readiness (max 15.0)
      -- 5.0 points for turnkey verify script; 3.0 for Tagref; 3.0 for Linkcheck; 2.0 for CLOC; 2.0 for linters.
      vScore = (if hasVerifyScript verifHarness then 5.0 else 0.0)
             + (if hasTagrefConfig verifHarness || hasTagrefHarness verifHarness then 3.0 else 0.0)
             + (if hasLinkcheckHarness verifHarness then 3.0 else 0.0)
             + (if hasClocHarness verifHarness then 2.0 else 0.0)
             + (if hasHlintConfig verifHarness || hasFourmoluConfig verifHarness then 2.0 else 0.0)

      -- Aggregate sum clamped to [0.0, 100.0] and rounded to one decimal place
      total = langScore + testScore + docScore + gitScore + vScore
  in fromIntegral (round (total * 10 :: Double) :: Int) / 10.0

-- | Generates an ordered, actionable remediation plan addressing diagnosed gaps.
--
-- Synthesizes actionable remediation steps sequenced logically:
-- 1. Git governance and hook installation.
-- 2. Physical verification runner synthesis.
-- 3. Critical and recommended documentation scaffolding.
-- 4. Test infrastructure bootstrapping.
-- 5. Multi-package migration recommendations.
computeRemediationPlan
  :: Text
  -> WorkspaceLayout
  -> TestInfrastructure
  -> [DocGap]
  -> GitGovernanceStatus
  -> VerificationHarnessStatus
  -> [Text]
computeRemediationPlan proj layout tests docs gitHarness verifHarness =
  concat
    [ planGit
    , planVerify
    , planDocs
    , planTests
    , planLayout
    ]
  where
    planGit
      | not (hasGitRepo gitHarness) =
          [ "Initialize Git repository ('git init') and activate canonical hooks." ]
      | not (hasHooksDir gitHarness) || not (hasCommitMsgHook gitHarness) =
          [ "Install .githooks with Sarutahiko RFC 2822 commit trailer attribution enforcement." ]
      | not (hasGitMessageTemplate gitHarness) =
          [ "Install .gitmessage commit template and configure 'git config commit.template .gitmessage'." ]
      | otherwise = []

    planVerify
      | not (hasVerifyScript verifHarness) =
          [ "Generate turnkey 5-gate physical verification harness ('bin/" <> proj <> "-verify')." ]
      | not (hasTagrefHarness verifHarness) =
          [ "Install Tagref cross-reference configuration and verification runner ('bin/" <> proj <> "-tagref')." ]
      | not (hasLinkcheckHarness verifHarness) =
          [ "Install Markdown link and anchor integrity runner ('bin/" <> proj <> "-linkcheck')." ]
      | not (hasClocHarness verifHarness) =
          [ "Install CLOC comment density audit harness ('bin/" <> proj <> "-cloc')." ]
      | otherwise = []

    planDocs =
      let missingCrit = filter (\d -> not (docPresent d) && docSeverity d == SeverityCritical) docs
          missingRec  = filter (\d -> not (docPresent d) && docSeverity d == SeverityRecommended) docs
          critItems = map (\d -> "Scaffold mandatory document: " <> T.pack (docPath d)) missingCrit
          recItems = map (\d -> "Scaffold recommended document: " <> T.pack (docPath d)) missingRec
      in critItems ++ recItems

    planTests
      | not (hasTests tests) =
          [ "Establish baseline test suite in test/ or packages/*/test." ]
      | otherwise = []

    planLayout
      | layout == LayoutSinglePackage =
          [ "Consider migrating from single-package layout to multi-package hierarchy (packages/" <> proj <> "/)." ]
      | otherwise = []

-- | Heuristically infers the canonical project name from directory name or build manifests.
--
-- Inspects root @*.cabal@ manifest filename if present. If absent (e.g. multi-package workspace),
-- falls back to the normalized basename of the workspace root directory.
inferProjectName :: FilePath -> [BuildSystem] -> [FilePath] -> Text
inferProjectName root _builds paths =
  let rootCabalFiles = filter isRootCabal paths
  in case rootCabalFiles of
    (cf:_) ->
      let base = takeFileName cf
          name = take (length base - 6) base
      in if null name then fallback else T.pack name
    [] -> fallback
  where
    isRootCabal p =
      let d = takeDirectory p
      in (d == "." || d == "") && ".cabal" `isSuffixOf` p

    fallback =
      let base = takeFileName (dropTrailingPathSeparator root)
      in if null base || base == "." then "project" else T.pack base

--------------------------------------------------------------------------------
-- 9. Top-Level Scanner Orchestration
--------------------------------------------------------------------------------

-- | Analyzes an arbitrary target repository checkout, evaluating all six diagnostic
-- dimensions and synthesizing a comprehensive 'DiagnosticReport'.
--
-- This operation is strictly read-only and non-destructive:
-- * Zero filesystem mutations occur on the target directory.
-- * Traversal prunes ignored build artifacts (@isIgnoredDirectory@).
-- * Recovers gracefully from permission issues or broken links.
--
-- === Examples
--
-- >>> report <- scanRepository "."
-- >>> diagProjectName report
-- "gachi"
scanRepository :: FilePath -> IO DiagnosticReport
scanRepository rawRoot = do
  absRoot <- makeAbsolute rawRoot
  paths <- listRepositoryFiles absRoot
  let langs = detectLanguages paths
      primaryLang = case langs of
        (top:_) -> Just (langType top)
        []      -> Nothing
      (builds, layout) = detectBuildSystems absRoot paths
      projName = inferProjectName absRoot builds paths

  testInfra <- detectTestInfrastructure absRoot paths builds
  let docGaps = detectDocumentationGaps absRoot paths
      (reqDocs, _) = partition (\d -> docSeverity d /= SeverityOptional) docGaps
      presentReq = length (filter docPresent reqDocs)
      totalReq = max 1 (length reqDocs)
      docPct = fromIntegral (round ((fromIntegral presentReq / fromIntegral totalReq * 100.0) * 10 :: Double) :: Int) / 10.0

  gitGov <- detectGitGovernance absRoot
  verifHarn <- detectVerificationHarnesses absRoot paths

  let score = computeRetrofitScore langs builds testInfra docGaps gitGov verifHarn
      remediation = computeRemediationPlan projName layout testInfra docGaps gitGov verifHarn

  -- Discover package names
  let pkgNames = discoverPackages paths

  pure DiagnosticReport
    { diagTargetDir           = rawRoot
    , diagProjectName         = projName
    , diagPrimaryLanguage     = primaryLang
    , diagLanguages           = langs
    , diagBuildSystems        = builds
    , diagLayout              = layout
    , diagDiscoveredPackages  = pkgNames
    , diagTestInfra           = testInfra
    , diagDocGaps             = docGaps
    , diagDocCompliancePct    = docPct
    , diagGitGovernance       = gitGov
    , diagVerificationHarness = verifHarn
    , diagRetrofitScore       = score
    , diagRemediationPlan     = remediation
    }
  where
    discoverPackages ps =
      let cabalFiles = filter (\p -> ".cabal" `isSuffixOf` p) ps
          names = map (\p -> let f = takeFileName p in T.pack (take (length f - 6) f)) cabalFiles
      in nub names
