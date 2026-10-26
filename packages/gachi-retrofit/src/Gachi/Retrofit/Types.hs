{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Module: Gachi.Retrofit.Types
-- Description: Core algebraic data types for repository inspection and retrofitting
--
-- This module defines the complete data modeling layer for the diagnostic repository
-- inspector and non-destructive retrofitting engine (Milestone 4.1, Phase 4).
--
-- = Architectural Context & Invariants
--
-- Per Note [Non-Destructive Skeleton Overlay] [ref:note-nondestructive-retrofit],
-- retrofitting operations adopt legacy, single-package, or foreign repositories into
-- the canonical multi-package ecosystem hierarchy without altering or perturbing
-- domain logic source files (@src/@, @app/@, @lib/@).
--
-- To achieve this safely, the diagnostic analyzer produces a strongly-typed
-- 'DiagnosticReport' assessing six orthogonal quality and structural dimensions:
--
-- 1. __Language Stacks & Distributions:__
--    Classifies discovered source code files into recognized language families ('Language')
--    and computes aggregate file counts and proportions ('LanguageStats'). Identifies the
--    dominant language informing toolchain decisions.
--
-- 2. __Build Systems & Topographical Layout:__
--    Discovers build system manifests ('BuildSystem') spanning Cabal, Stack, Cargo,
--    CMake, Make, Meson, Poetry, and Flit. Classifies overall repository layout
--    ('WorkspaceLayout') into single-package, multi-package, polyglot, or unstructured trees.
--
-- 3. __Test Infrastructure & Frameworks:__
--    Detects test directories, declared test targets, and testing libraries ('TestFramework',
--    'TestSuiteInfo', 'TestInfrastructure'). Distinguishes active verification setups from
--    untested codebases.
--
-- 4. __Documentation Gaps Relative to DOC_STRATEGY.md:__
--    Audits repository assets against canonical documentation genres ('DocCategory',
--    'DocSeverity', 'DocGap') per @DOC_STRATEGY.md@ §1, identifying missing orientation,
--    corpus inventory, design rationale, and operational manuals.
--
-- 5. __Git Governance, Hook Executability & AI Attribution:__
--    Audits @.git@ directory existence, @core.hooksPath@ configuration, @commit-msg@ hook
--    executability, Sarutahiko / RFC 2822 @Assisted-by:@ trailer validation, @pre-commit@
--    gates, and @.gitmessage@ commit template pinning ('GitGovernanceStatus').
--
-- 6. __Physical Verification Harnesses & Quality Gates:__
--    Evaluates turnkey test runners (@bin/*-verify@), Tagref cross-reference configuration,
--    Markdown link integrity checkers, and CLOC comment density audit harnesses
--    ('VerificationHarnessStatus').
--
-- = The Six Evaluation Dimensions
--
-- @
--  +-------------------------------------------------------------------------------+
--  |                       Diagnostic Repository Inspector                         |
--  +-------------------------------------------------------------------------------+
--  | [1] Languages      : Haskell (92.5%), Shell (7.5%)                            |
--  | [2] Build Systems  : Cabal Multi-Package Workspace (cabal.project)           |
--  | [3] Test Infra     : Hspec test suite (5 files in test/)                     |
--  | [4] Documentation  : DOC_STRATEGY.md Compliance 90.0% (10/12 present)         |
--  | [5] Git Governance : .githooks active, RFC 2822 Assisted-by: trailer checked |
--  | [6] Quality Gates  : Turnkey verify, Tagref, Linkcheck, CLOC active          |
--  +-------------------------------------------------------------------------------+
-- @
--
-- = Worked Example
--
-- >>> let lang = LangHaskell
-- >>> languageName lang
-- "Haskell"
-- >>> let bld = BuildCabalProject
-- >>> buildSystemName bld
-- "Cabal Multi-Package Workspace (cabal.project)"
-- >>> let sev = SeverityCritical
-- >>> docSeverityName sev
-- "CRITICAL"
module Gachi.Retrofit.Types
  ( -- * Programming Language Classification
    Language(..)
  , LanguageStats(..)
  , languageName

    -- * Build Systems & Layout
  , BuildSystem(..)
  , WorkspaceLayout(..)
  , buildSystemName
  , layoutName

    -- * Test Infrastructure
  , TestFramework(..)
  , TestSuiteInfo(..)
  , TestInfrastructure(..)
  , testFrameworkName

    -- * Documentation Gaps & Categories
  , DocCategory(..)
  , DocSeverity(..)
  , DocGap(..)
  , docCategoryName
  , docSeverityName

    -- * Git Governance & Hooks
  , GitGovernanceStatus(..)

    -- * Physical Verification Harnesses
  , VerificationHarnessStatus(..)

    -- * Comprehensive Diagnostic Report
  , DiagnosticReport(..)
  ) where

import Data.Text (Text)

--------------------------------------------------------------------------------
-- 1. Programming Language Modeling
--------------------------------------------------------------------------------

-- | Recognized programming language families identified during repository inspection.
--
-- Language classification is performed by inspecting source file extensions across
-- the workspace, excluding known build artifact directories (e.g. @dist-newstyle@,
-- @target@, @node_modules@, @.venv@).
data Language
  = LangHaskell
    -- ^ Haskell source code files (@.hs@, @.lhs@). Primary target for Gachi multi-package
    -- workspace scaffolding, Cabal 3.18 / GHC 9.14 compiler stanzas, and HLint policies.
  | LangRust
    -- ^ Rust source code files (@.rs@). Target for Cargo workspace layouts, @rustfmt.toml@,
    -- and clippy verification gates.
  | LangC
    -- ^ C source and header files (@.c@, @.h@). Target for Make, CMake, and @.clang-format@.
  | LangCpp
    -- ^ C++ source and header files (@.cpp@, @.cc@, @.cxx@, @.hpp@, @.hxx@).
  | LangPython
    -- ^ Python source code files (@.py@). Target for Poetry, Flit, and pytest.
  | LangShell
    -- ^ POSIX Shell / Bash / Zsh scripts (@.sh@, @.bash@, @.zsh@). Typical in @bin/@.
  | LangOCaml
    -- ^ OCaml source code files (@.ml@, @.mli@).
  | LangGo
    -- ^ Go source code files (@.go@).
  | LangJava
    -- ^ Java source code files (@.java@).
  | LangJavaScript
    -- ^ JavaScript source files (@.js@, @.mjs@, @.cjs@).
  | LangTypeScript
    -- ^ TypeScript source files (@.ts@, @.tsx@).
  | LangOther !Text
    -- ^ Other programming language identified by file extension.
  deriving stock (Eq, Ord, Show)

-- | Detailed file count and percentage metrics for a detected programming language.
--
-- Summarizes the prevalence of a language across the scanned codebase. Used to
-- compute the 'diagPrimaryLanguage' and inform build toolchain selection.
data LanguageStats = LanguageStats
  { langType        :: !Language
    -- ^ Classified language family.
  , langFiles       :: !Int
    -- ^ Total number of matching source files discovered across the repository.
  , langPercentage  :: !Double
    -- ^ Proportion of this language relative to total source files (0.0 to 100.0).
  , langExtensions  :: ![Text]
    -- ^ Unique file extensions associated with this language detection (e.g. @[".hs", ".lhs"]@).
  } deriving stock (Eq, Show)

-- | Converts a 'Language' into its canonical human-readable display title.
--
-- === Examples
--
-- >>> languageName LangHaskell
-- "Haskell"
-- >>> languageName LangRust
-- "Rust"
-- >>> languageName (LangOther "Zig")
-- "Zig"
languageName :: Language -> Text
languageName LangHaskell      = "Haskell"
languageName LangRust         = "Rust"
languageName LangC            = "C"
languageName LangCpp          = "C++"
languageName LangPython       = "Python"
languageName LangShell        = "Shell / Bash"
languageName LangOCaml        = "OCaml"
languageName LangGo           = "Go"
languageName LangJava         = "Java"
languageName LangJavaScript   = "JavaScript"
languageName LangTypeScript   = "TypeScript"
languageName (LangOther name) = name

--------------------------------------------------------------------------------
-- 2. Build Systems & Workspace Layout
--------------------------------------------------------------------------------

-- | Build system manifests and toolchains discovered in the target repository.
--
-- Identifies declarative build manifests at the repository root and package subdirectories.
-- Informs the retrofitting engine whether a repository can be adopted directly or requires
-- multi-package scaffolding.
data BuildSystem
  = BuildCabalProject
    -- ^ Haskell Cabal multi-package workspace definition (@cabal.project@).
    -- Indicates a modern Cabal workspace supporting cross-package dependencies.
  | BuildCabalPackage
    -- ^ Haskell Cabal single-package manifest (@*.cabal@ at repository root).
    -- Indicates a legacy single-package repository or standalone library.
  | BuildStack
    -- ^ Haskell Stack build tool definition (@stack.yaml@).
  | BuildHpack
    -- ^ Haskell Hpack package generator (@package.yaml@).
  | BuildCargo
    -- ^ Rust Cargo workspace or package manifest (@Cargo.toml@).
  | BuildCMake
    -- ^ CMake build system definition (@CMakeLists.txt@).
  | BuildMake
    -- ^ Standard Makefile / GNUmakefile build system.
  | BuildMeson
    -- ^ Meson build definition (@meson.build@).
  | BuildPoetry
    -- ^ Python Poetry dependency configuration (@pyproject.toml@).
  | BuildFlit
    -- ^ Python Flit packaging manifest (@pyproject.toml@).
  | BuildSetuptools
    -- ^ Python Setuptools manifest (@setup.py@ / @setup.cfg@).
  | BuildPip
    -- ^ Python pip requirements file (@requirements.txt@).
  | BuildNix
    -- ^ Nix build expression or flake (@flake.nix@ / @default.nix@).
  | BuildOther !Text
    -- ^ Custom or unrecognized build configuration.
  deriving stock (Eq, Ord, Show)

-- | High-level architectural workspace layout of the target repository.
--
-- Categorizes repository topography into canonical patterns to determine the appropriate
-- overlay strategy in Phase 4:
--
-- * 'LayoutMultiPackage': Standard Gachi multi-package hierarchy (@packages/*/@).
-- * 'LayoutSinglePackage': Standalone single-package project with root manifest.
-- * 'LayoutPolyglot': Multi-language repository with multiple heterogeneous build tools.
-- * 'LayoutUnstructured': Raw source files without a recognizable build manifest.
data WorkspaceLayout
  = LayoutSinglePackage
    -- ^ Single package located at repository root (e.g. root @my-project.cabal@).
  | LayoutMultiPackage
    -- ^ Canonical multi-package layout with packages segregated in @packages/*/@.
  | LayoutPolyglot
    -- ^ Polyglot repository containing multiple heterogeneous build systems (e.g. Haskell + Rust).
  | LayoutUnstructured
    -- ^ Source files discovered without a recognized build manifest.
  deriving stock (Eq, Ord, Show)

-- | Converts a 'BuildSystem' into a descriptive string.
--
-- === Examples
--
-- >>> buildSystemName BuildCabalProject
-- "Cabal Multi-Package Workspace (cabal.project)"
-- >>> buildSystemName BuildCargo
-- "Cargo Package / Workspace (Cargo.toml)"
buildSystemName :: BuildSystem -> Text
buildSystemName BuildCabalProject = "Cabal Multi-Package Workspace (cabal.project)"
buildSystemName BuildCabalPackage = "Cabal Single-Package Manifest (*.cabal)"
buildSystemName BuildStack        = "Stack Project Definition (stack.yaml)"
buildSystemName BuildHpack        = "Hpack Package Specification (package.yaml)"
buildSystemName BuildCargo        = "Cargo Package / Workspace (Cargo.toml)"
buildSystemName BuildCMake        = "CMake Build Configuration (CMakeLists.txt)"
buildSystemName BuildMake         = "GNU Make / POSIX Makefile (Makefile)"
buildSystemName BuildMeson        = "Meson Build Definition (meson.build)"
buildSystemName BuildPoetry       = "Python Poetry Project (pyproject.toml)"
buildSystemName BuildFlit         = "Python Flit Package (pyproject.toml)"
buildSystemName BuildSetuptools   = "Python Setuptools (setup.py)"
buildSystemName BuildPip          = "Python Pip Requirements (requirements.txt)"
buildSystemName BuildNix          = "Nix Build Expression (flake.nix / default.nix)"
buildSystemName (BuildOther desc) = desc

-- | Converts a 'WorkspaceLayout' into a descriptive string.
--
-- === Examples
--
-- >>> layoutName LayoutMultiPackage
-- "Multi-Package Workspace Layout (packages/*)"
-- >>> layoutName LayoutSinglePackage
-- "Single-Package Root Layout"
layoutName :: WorkspaceLayout -> Text
layoutName LayoutSinglePackage = "Single-Package Root Layout"
layoutName LayoutMultiPackage  = "Multi-Package Workspace Layout (packages/*)"
layoutName LayoutPolyglot      = "Polyglot Multi-Toolchain Workspace"
layoutName LayoutUnstructured  = "Unstructured Source Code Tree"

--------------------------------------------------------------------------------
-- 3. Test Infrastructure Modeling
--------------------------------------------------------------------------------

-- | Testing frameworks identified in repository manifests or source files.
--
-- Introspects test imports and dependency manifests to determine the active testing
-- harness without executing arbitrary code.
data TestFramework
  = FrameworkHspec
    -- ^ Haskell Hspec BDD testing framework (@Test.Hspec@).
  | FrameworkTasty
    -- ^ Haskell Tasty test runner (@Test.Tasty@).
  | FrameworkQuickCheck
    -- ^ QuickCheck property-based testing (@Test.QuickCheck@).
  | FrameworkHedgehog
    -- ^ Hedgehog property testing library (@Hedgehog@).
  | FrameworkCargoTest
    -- ^ Built-in Rust test harness (@cargo test@ / @#[cfg(test)]@).
  | FrameworkPytest
    -- ^ Python pytest test framework (@pytest@).
  | FrameworkUnittest
    -- ^ Python standard unittest library (@unittest@).
  | FrameworkCTest
    -- ^ CTest / CMake test runner.
  | FrameworkUnknown !Text
    -- ^ Other test framework identifier.
  deriving stock (Eq, Ord, Show)

-- | Converts a 'TestFramework' into its canonical title.
--
-- === Examples
--
-- >>> testFrameworkName FrameworkHspec
-- "Hspec"
-- >>> testFrameworkName FrameworkTasty
-- "Tasty"
testFrameworkName :: TestFramework -> Text
testFrameworkName FrameworkHspec         = "Hspec"
testFrameworkName FrameworkTasty         = "Tasty"
testFrameworkName FrameworkQuickCheck    = "QuickCheck"
testFrameworkName FrameworkHedgehog      = "Hedgehog"
testFrameworkName FrameworkCargoTest     = "Cargo Test"
testFrameworkName FrameworkPytest        = "pytest"
testFrameworkName FrameworkUnittest      = "unittest"
testFrameworkName FrameworkCTest         = "CTest"
testFrameworkName (FrameworkUnknown txt) = txt

-- | Information describing an identified test suite or test target.
--
-- Records the declared test suite identifier, its primary entry point or test directory,
-- and all discovered test frameworks.
data TestSuiteInfo = TestSuiteInfo
  { testSuiteName       :: !Text
    -- ^ Declared test suite name (e.g. @"tests"@, @"spec"@).
  , testSuitePath       :: !FilePath
    -- ^ Primary entry point or test directory (e.g. @"test"@, @"test/Main.hs"@).
  , testFrameworks      :: ![TestFramework]
    -- ^ Identified test framework dependencies.
  } deriving stock (Eq, Show)

-- | Aggregate test infrastructure status discovered during repository inspection.
--
-- Assesses whether the repository contains verifiable test suites, counts test files,
-- and catalogs declared test targets.
data TestInfrastructure = TestInfrastructure
  { hasTests            :: !Bool
    -- ^ True if test directories, manifests, or suites were found.
  , testSuites          :: ![TestSuiteInfo]
    -- ^ Specific test suites discovered or declared.
  , testDirectories     :: ![FilePath]
    -- ^ Existing test directories (e.g. @"test"@, @"tests"@, @"spec"@).
  , testFileCount       :: !Int
    -- ^ Total number of test source files located.
  } deriving stock (Eq, Show)

--------------------------------------------------------------------------------
-- 4. Documentation Gaps & Categories
--------------------------------------------------------------------------------

-- | Documentation category classifications per @DOC_STRATEGY.md@ §1.
--
-- Classifies documentation into purpose-built genres serving three distinct audiences:
-- 1. __Arrivals:__ Newcomers seeking immediate orientation (@README.md@).
-- 2. __API Consumers:__ Developers looking for reference guides, types, and invariants.
-- 3. __Maintainers:__ Core contributors governing architectural decisions, notes, and roadmap.
-- 4. __AI Coding Assistants:__ Modular rules and bounded context projections (@AGENTS.md@).
data DocCategory
  = DocOrientation
    -- ^ Newcomer orientation, introductory facts, and project vision (@README.md@).
  | DocCorpusInventory
    -- ^ Curated inventory and reading paths per @DOC_STRATEGY.md@ §1 (@docs/INDEX.md@).
  | DocDesignRationale
    -- ^ Architectural decisions, trade-offs, and open questions (@docs/notes/*_DESIGN.md@).
  | DocStrategy
    -- ^ Corpus policies, lifecycle, precedence rules, and authority (@docs/notes/DOC_STRATEGY.md@).
  | DocGovernance
    -- ^ Strategic roadmaps and session frontiers (@PLAN.md@, @STATE.md@).
  | DocOperational
    -- ^ Maintenance manuals, gate triage, and release procedures (@docs/MAINTAINER_GUIDE.md@).
  | DocTutorial
    -- ^ Worked examples and newcomer tutorials (@docs/TUTORIAL.md@, @docs/NEWBIE_GUIDE.md@).
  | DocAdvisory
    -- ^ AI coding assistant advisories and modular rules (@AGENTS.md@, @.agents/rules/@).
  | DocAttribution
    -- ^ Commit trailer attribution policy per RFC 2822 (@docs/notes/COMMIT_ATTRIBUTION.md@).
  | DocChangelog
    -- ^ Release history, licensing terms, and code of conduct (@CHANGELOG.md@, @LICENSE@).
  deriving stock (Eq, Ord, Show)

-- | Severity level associated with a missing documentation asset.
--
-- Prioritizes documentation remediation actions during retrofitting:
-- * 'SeverityCritical': Essential files without which repository cannot function cleanly.
-- * 'SeverityRecommended': Standard documentation practices required by @DOC_STRATEGY.md@.
-- * 'SeverityOptional': Contextual or supplementary documents.
data DocSeverity
  = SeverityCritical
    -- ^ Essential ecosystem document; retrofitting cannot succeed without it (e.g. @README.md@, @LICENSE@).
  | SeverityRecommended
    -- ^ Standard documentation practice per @DOC_STRATEGY.md@ (e.g. @PLAN.md@, @STATE.md@, @AGENTS.md@).
  | SeverityOptional
    -- ^ Nice-to-have or contextual document (e.g. @CLAUDE.md@, @CHANGELOG.md@).
  deriving stock (Eq, Ord, Show)

-- | Represents an individual documentation item audited against the canonical corpus.
--
-- Evaluates presence on disk and provides actionable remediation guidance.
data DocGap = DocGap
  { docPath             :: !FilePath
    -- ^ Relative file path of the documentation asset.
  , docCategory         :: !DocCategory
    -- ^ Functional category of this document.
  , docPresent          :: !Bool
    -- ^ True if the file physically exists on disk.
  , docSeverity         :: !DocSeverity
    -- ^ Priority level of this document.
  , docAdvice           :: !Text
    -- ^ Remediation guidance or explanation describing the document's purpose.
  } deriving stock (Eq, Show)

-- | Converts a 'DocCategory' into a human-readable title.
--
-- === Examples
--
-- >>> docCategoryName DocOrientation
-- "Arrivals & Orientation"
-- >>> docCategoryName DocDesignRationale
-- "Architecture & Rationale"
docCategoryName :: DocCategory -> Text
docCategoryName DocOrientation     = "Arrivals & Orientation"
docCategoryName DocCorpusInventory = "Corpus Inventory"
docCategoryName DocDesignRationale = "Architecture & Rationale"
docCategoryName DocStrategy        = "Documentation Policy"
docCategoryName DocGovernance      = "Strategic Governance"
docCategoryName DocOperational     = "Operational Guides"
docCategoryName DocTutorial        = "Tutorial Track"
docCategoryName DocAdvisory        = "Agent Advisory Layer"
docCategoryName DocAttribution     = "Commit Attribution"
docCategoryName DocChangelog       = "Changelog & Licensing"

-- | Converts a 'DocSeverity' into a formatted status label.
--
-- === Examples
--
-- >>> docSeverityName SeverityCritical
-- "CRITICAL"
-- >>> docSeverityName SeverityRecommended
-- "RECOMMENDED"
docSeverityName :: DocSeverity -> Text
docSeverityName SeverityCritical    = "CRITICAL"
docSeverityName SeverityRecommended = "RECOMMENDED"
docSeverityName SeverityOptional    = "OPTIONAL"

--------------------------------------------------------------------------------
-- 5. Git Governance & Hook Conformance
--------------------------------------------------------------------------------

-- | Evaluation of Git repository configuration, hooks, and commit trailer enforcement.
--
-- Inspects repository configuration to verify compliance with ecosystem standards:
-- * Dedicated hooks directory (@.githooks/@) configured via @git config core.hooksPath@.
-- * @commit-msg@ hook with POSIX executable permissions (+x) validating RFC 2822 @Assisted-by:@ trailers.
-- * @pre-commit@ hook enforcing Tagref and link integrity checks prior to commit recording.
-- * Standard commit template (@.gitmessage@) configured via @git config commit.template@.
data GitGovernanceStatus = GitGovernanceStatus
  { hasGitRepo                     :: !Bool
    -- ^ True if a valid @.git@ directory exists at the repository root.
  , hasHooksDir                    :: !Bool
    -- ^ True if a dedicated @.githooks@ directory exists.
  , hooksPathConfig                :: !(Maybe Text)
    -- ^ Value of @git config core.hooksPath@ if explicitly configured.
  , hasCommitMsgHook               :: !Bool
    -- ^ True if @commit-msg@ hook exists.
  , isCommitMsgExecutable          :: !Bool
    -- ^ True if @commit-msg@ has POSIX executable permission (+x).
  , hasCommitMsgAttributionCheck   :: !Bool
    -- ^ True if @commit-msg@ validates Sarutahiko / RFC 2822 @Assisted-by:@ trailers.
  , hasPreCommitHook               :: !Bool
    -- ^ True if @pre-commit@ hook exists.
  , isPreCommitExecutable          :: !Bool
    -- ^ True if @pre-commit@ has POSIX executable permission (+x).
  , hasGitMessageTemplate          :: !Bool
    -- ^ True if @.gitmessage@ template file exists.
  , gitMessageConfig               :: !(Maybe Text)
    -- ^ Value of @git config commit.template@ if explicitly configured.
  } deriving stock (Eq, Show)

--------------------------------------------------------------------------------
-- 6. Physical Verification Harnesses
--------------------------------------------------------------------------------

-- | Evaluation of physical verification scripts, linters, and quality gates.
--
-- Assesses presence and executability of the turnkey 5-gate verification suite:
-- 1. Turnkey verification runner (@bin/<project>-verify@).
-- 2. Tagref cross-reference configuration (@tagref.yml@) and runner (@bin/<project>-tagref@).
-- 3. Markdown link & anchor integrity checker (@bin/<project>-linkcheck@).
-- 4. In-code comment density audit harness (@bin/<project>-cloc@).
-- 5. Static linter configurations (@.hlint.yaml@, @fourmolu.yaml@).
data VerificationHarnessStatus = VerificationHarnessStatus
  { hasVerifyScript                :: !Bool
    -- ^ True if a turnkey verification script (e.g. @bin/*-verify@) exists.
  , verifyScriptPath               :: !(Maybe FilePath)
    -- ^ Relative file path of the primary verification runner if found.
  , hasTagrefConfig                :: !Bool
    -- ^ True if @tagref.yml@ or @.tagref@ exists.
  , hasTagrefHarness               :: !Bool
    -- ^ True if @bin/*-tagref@ runner script exists.
  , hasLinkcheckHarness            :: !Bool
    -- ^ True if @bin/*-linkcheck@ runner script exists.
  , hasClocHarness                 :: !Bool
    -- ^ True if @bin/*-cloc@ comment density runner script exists.
  , hasHlintConfig                 :: !Bool
    -- ^ True if @.hlint.yaml@ linter configuration exists.
  , hasFourmoluConfig              :: !Bool
    -- ^ True if @fourmolu.yaml@ code formatter configuration exists.
  } deriving stock (Eq, Show)

--------------------------------------------------------------------------------
-- 7. Comprehensive Diagnostic Report
--------------------------------------------------------------------------------

-- | The unified diagnostic evaluation report produced by inspecting a target codebase.
--
-- Combines language statistics, build systems, test infrastructure, documentation gaps,
-- git governance, verification harness status, and computes a quantitative retrofit score.
--
-- Per Note [Non-Destructive Skeleton Overlay] [ref:note-nondestructive-retrofit],
-- generating this report is strictly observational and non-destructive.
data DiagnosticReport = DiagnosticReport
  { diagTargetDir            :: !FilePath
    -- ^ Inspected target directory path.
  , diagProjectName          :: !Text
    -- ^ Inferred or detected project identifier.
  , diagPrimaryLanguage      :: !(Maybe Language)
    -- ^ Dominant programming language identified.
  , diagLanguages            :: ![LanguageStats]
    -- ^ Complete breakdown of all detected programming languages.
  , diagBuildSystems         :: ![BuildSystem]
    -- ^ All build manifests discovered.
  , diagLayout               :: !WorkspaceLayout
    -- ^ Classified repository workspace topology.
  , diagDiscoveredPackages   :: ![Text]
    -- ^ List of package names discovered across the codebase.
  , diagTestInfra            :: !TestInfrastructure
    -- ^ Status of test directories, declarations, and frameworks.
  , diagDocGaps              :: ![DocGap]
    -- ^ Detailed inventory of documentation gaps against @DOC_STRATEGY.md@.
  , diagDocCompliancePct     :: !Double
    -- ^ Percentage of required and recommended documents present (0.0 to 100.0).
  , diagGitGovernance        :: !GitGovernanceStatus
    -- ^ Status of Git hooks, attribution trailers, and commit templates.
  , diagVerificationHarness  :: !VerificationHarnessStatus
    -- ^ Status of 5-gate physical verification infrastructure.
  , diagRetrofitScore        :: !Double
    -- ^ Overall weighted ecosystem retrofit readiness score (0.0 to 100.0).
  , diagRemediationPlan      :: ![Text]
    -- ^ Prioritized list of actionable remediation steps for Phase 4.
  } deriving stock (Eq, Show)
