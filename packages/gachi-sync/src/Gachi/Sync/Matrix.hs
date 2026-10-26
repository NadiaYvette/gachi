{-# LANGUAGE OverloadedStrings #-}

-- | Module: Gachi.Sync.Matrix
-- Description: Canonical 9-dimensional Standardization Matrix definition and queries
--
-- This module implements the authoritative Standardization Matrix defined in
-- ~/src/PLAN.md §1.A. It registers every standardized ecosystem asset across the
-- nine canonical dimensions, pairs them with pure deterministic generators, and
-- provides query combinators for repository audits and configuration propagation.
--
-- = Architectural Context & Invariants
--
-- In accordance with Note [Ecosystem Standardization Invariants]
-- [ref:note-ecosystem-standardization] and Note [Cross-Repository Standardization Matrix and Audit Semantics]
-- [ref:note-standardization-matrix], all repositories across ~/src/* share an
-- authoritative structural skeleton. This module provides the central matrix
-- registry from which audit tools and sync commands derive their expectations.
--
-- = Note [Cross-Repository Standardization Matrix and Audit Semantics]
-- [tag:note-standardization-matrix]
--
-- Multi-repository ecosystems face constant structural entropy. As individual
-- libraries evolve, their formatting configurations, compiler warning flags,
-- git commit hooks, CI workflows, and AI pair programming instructions diverge.
-- Over time, this divergence creates friction when developers or AI assistants
-- navigate across repositories.
--
-- To prevent this fragmentation, Gachi defines a 9-dimensional Standardization
-- Matrix (~/src/PLAN.md §1.A) that is non-negotiably enforced across all checkouts:
--
-- 1.  __Workspace Layout (Dimension 1):__
--     Standardized multi-package DAG (`packages/*/`), central documentation
--     corpus (`docs/INDEX.md`, `docs/notes/`), and the two-file operational
--     planning loop (`PLAN.md`, `STATE.md`). Ensures that any contributor or
--     automated agent arriving in any checkout can immediately locate documentation,
--     active milestones, and the operational frontier without cognitive disorientation.
--
-- 2.  __Code Formatters (Dimension 2):__
--     Deterministic AST-preserving formatting profiles across Haskell
--     (@fourmolu.yaml@), Rust (@rustfmt.toml@), and C/C++ (@.clang-format@).
--     Prevents superficial whitespace and layout diffs from polluting code review
--     and git blame histories during cross-repository refactorings.
--
-- 3.  __Linters & Guardrails (Dimension 3):__
--     Strict zero-hint HLint policy (@.hlint.yaml@) enforcing modern GHC
--     idioms such as @OverloadedRecordDot@. Prohibits outdated patterns and ensures
--     consistent language extension usage across all packages.
--
-- 4.  __Build Conventions (Dimension 4):__
--     Toolchain pinning (@cabal.project@) targeting GHC 9.14.1 and Cabal 3.18,
--     with standard developer override stanzas (@cabal.project.local.example@).
--     Guarantees hermetic, reproducible builds across developer laptops and CI nodes.
--
-- 5.  __Git Governance (Dimension 5):__
--     Linux kernel RFC 2822 commit trailer rules (@.gitmessage@), Tagref
--     configuration (@tagref.yml@), and executable git hooks (@.githooks/commit-msg@,
--     @.githooks/pre-commit@). Enforces legal DCO boundaries, transparent AI
--     attribution, and pre-commit verification before code leaves local workstations.
--
-- 6.  __Remote Topology (Dimension 6):__
--     Multi-forge replication topology separating Radicle peer-to-peer from
--     commercial and community mirrors, documented in @docs/MAINTAINER_GUIDE.md@.
--     Guarantees sovereign, censorship-resistant repository distribution.
--
-- 7.  __Tiered CI Workflows (Dimension 7):__
--     Asymmetric forge resource allocation: full physical verification on
--     high-resource GitHub Actions (@.github/workflows/ci.yml@) versus lightweight
--     static verification gates on community forges (@.gitlab-ci.yml@).
--     Conserves shared community runner quotas while enforcing rigorous testing.
--     See Note [Forge-Tiered CI Resource Allocation and Static Gate Partitioning]
--     [ref:note-forge-tiered-ci].
--
-- 8.  __Polyglot Invariants (Dimension 8):__
--     Cross-language FFI boundary invariants, C/C++ clang-format styling,
--     and rustfmt rules for non-Haskell components. Ensures consistent ergonomics
--     when Haskell interfaces with low-level systems code or Rust libraries.
--
-- 9.  __Agent Advisory Layer (Dimension 9):__
--     Context-budgeted AI agent instructions (@AGENTS.md@, ~4 KB limit),
--     compatibility pointers (@CLAUDE.md@), and modular rules in @.agents/rules/@.
--     Prevents LLM context saturation and prompt drift across agent sessions.
--
-- 10. __Physical Verification Harnesses:__
--     Turnkey shell scripts in @bin/@ enforcing the five physical gates:
--     HLint cleanliness, Cabal test suite, Tagref cross-references, Markdown
--     link integrity, and CLOC comment density.
--
-- == Audit Semantics
--
-- The repository audit engine operates under strict invariants:
-- * __Read-Only Purity:__ Audits inspect disk state without mutating any files.
-- * __Total Classification:__ Every audited asset is classified into exactly one
--   'AssetAuditStatus': 'StatusCompliant', 'StatusMissing', 'StatusContentDrift',
--   'StatusPermissionDrift', or 'StatusIOError'.
-- * __Deterministic Generators:__ Expected contents are produced purely by
--   evaluating generators against the target repository's 'Project' schema.
--
-- = Worked Example
--
-- >>> import Gachi.Sync.Matrix
-- >>> length (matrixAssets canonicalMatrix) >= 20
-- True
-- >>> length (matrixDimensions canonicalMatrix) == 10
-- True
module Gachi.Sync.Matrix
  ( -- * Canonical Standardization Matrix
    canonicalMatrix
  , canonicalAssets
  , canonicalDimensions

    -- * Query & Filter Combinators
  , assetsForCategory
  , ciWorkflowAssets
  , requiredAssets
  , optionalAssets
  , executableAssets
  , findAssetByPath
  , countByCategory
  ) where

import Data.List (find)

import Gachi.Scaffold.Templates
  ( docsCommitAttributionTemplate
  , docsIndexTemplate
  , docsMaintainerGuideTemplate
  , docsStrategyTemplate
  , planTemplate
  , stateTemplate
  )
import Gachi.Sync.Catalog
  ( agentsTemplate
  , cabalProjectLocalTemplate
  , cabalProjectTemplate
  , clangFormatTemplate
  , claudeTemplate
  , clocScriptTemplate
  , codeNavigationRuleTemplate
  , commitAttributionRuleTemplate
  , commitMsgHookTemplate
  , compilerVerificationRuleTemplate
  , documentationPrecedenceRuleTemplate
  , fourmoluTemplate
  , generateTagsTemplate
  , githubCiTemplate
  , gitlabCiTemplate
  , gitmessageTemplate
  , hlintTemplate
  , linkcheckScriptTemplate
  , preCommitHookTemplate
  , rustfmtTemplate
  , tagrefConfigTemplate
  , tagrefScriptTemplate
  , verifyScriptTemplate
  )
import Gachi.Sync.Types
  ( AssetCategory(..)
  , StandardAsset(..)
  , StandardizationMatrix(..)
  )

--------------------------------------------------------------------------------
-- 1. Canonical Dimensions
--------------------------------------------------------------------------------

-- | The complete list of standardization dimensions enforced across the ecosystem.
--
-- Covers all nine dimensions specified in ~/src/PLAN.md §1.A plus the physical
-- verification harness category.
--
-- Dimensions are ordered logically from fundamental repository structure to
-- high-level tooling and verification:
--
-- 1. 'CategoryLayout': Directory hierarchies and operational planning files.
-- 2. 'CategoryFormatter': Code layout and styling profiles across all languages.
-- 3. 'CategoryLinter': Static analysis policies and compiler guardrails.
-- 4. 'CategoryBuild': Build toolchain pinning and package manifest conventions.
-- 5. 'CategoryGitGovernance': Git commit hooks, commit templates, and tag references.
-- 6. 'CategoryRemoteTopology': Multi-forge replication and mirror definitions.
-- 7. 'CategoryCIWorkflow': Tiered continuous integration configurations.
-- 8. 'CategoryPolyglot': Multi-language FFI boundary invariants and foreign code.
-- 9. 'CategoryAgentAdvisory': AI pair programming instructions and context bounds.
-- 10. 'CategoryVerification': Physical gate test scripts and verification harnesses.
canonicalDimensions :: [AssetCategory]
canonicalDimensions =
  [ CategoryLayout
  , CategoryFormatter
  , CategoryLinter
  , CategoryBuild
  , CategoryGitGovernance
  , CategoryRemoteTopology
  , CategoryCIWorkflow
  , CategoryPolyglot
  , CategoryAgentAdvisory
  , CategoryVerification
  ]

--------------------------------------------------------------------------------
-- 2. Canonical Assets Registry
--------------------------------------------------------------------------------

-- | Canonical list of standardized ecosystem assets.
--
-- Each asset pairs its relative workspace path with its governing category,
-- necessity flag ('assetRequired'), executable permission requirement
-- ('assetExecutable'), descriptive synopsis, and pure generator function.
--
-- === Rationale by Dimension
--
-- * __Dimension 1 (Layout):__
--   Provides the foundational documentation corpus (@docs/@) and the operational
--   two-file planning loop (@PLAN.md@, @STATE.md@) ensuring orientation.
--
-- * __Dimension 2 (Formatters):__
--   Deterministic styling via Fourmolu, rustfmt, and clang-format prevents
--   cosmetic git churn during refactoring across packages.
--
-- * __Dimension 3 (Linters):__
--   Zero-hint HLint policy eliminates dead code, enforces modern record dot syntax,
--   and ensures uniform GHC extension discipline.
--
-- * __Dimension 4 (Build):__
--   Hermetic Cabal project configuration pins GHC 9.14.1 and standardizes warnings
--   while allowing local machine overrides via @cabal.project.local@.
--
-- * __Dimension 5 (Git Governance):__
--   Enforces Linux kernel RFC 2822 trailer format for AI attribution, Tagref
--   cross-referencing, and pre-commit integrity checking.
--
-- * __Dimension 6 (Remote Topology):__
--   Maintainer guidance for 5-forge replication across Radicle, GitHub, GitCode,
--   Framagit, and Disroot.
--
-- * __Dimension 7 (Tiered CI):__
--   Resource-differentiated CI: heavy verification on GitHub Actions vs lightweight
--   static checks on community GitLab runners.
--
-- * __Dimension 8 (Polyglot):__
--   Ensures C/C++ components follow LLVM/Linux formatting standards without tab drift.
--
-- * __Dimension 9 (Agent Advisory):__
--   Token-budgeted pointer file (@AGENTS.md@, ~4 KB) and modular rules for AI assistants.
--
-- * __Dimension 10 (Verification):__
--   Self-contained executable scripts implementing the five physical verification gates.
canonicalAssets :: [StandardAsset]
canonicalAssets =
  -- Dimension 1: Workspace Layout & Documentation Corpus
  [ StandardAsset
      "docs/INDEX.md"
      CategoryLayout
      True
      False
      "Central documentation index, reading order, and document map"
      docsIndexTemplate
  , StandardAsset
      "docs/notes/DOC_STRATEGY.md"
      CategoryLayout
      True
      False
      "Documentation strategy, four canonical genres, and precedence rules"
      docsStrategyTemplate
  , StandardAsset
      "docs/notes/COMMIT_ATTRIBUTION.md"
      CategoryLayout
      True
      False
      "Commit attribution specification for Linux kernel RFC 2822 trailers"
      docsCommitAttributionTemplate
  , StandardAsset
      "PLAN.md"
      CategoryLayout
      True
      False
      "Strategic roadmap, phased milestones, and architecture deliverables"
      planTemplate
  , StandardAsset
      "STATE.md"
      CategoryLayout
      True
      False
      "Operational frontier, active milestones, and two-file loop tracking"
      stateTemplate

  -- Dimension 2: Code Formatters
  , StandardAsset
      "fourmolu.yaml"
      CategoryFormatter
      True
      False
      "Canonical Fourmolu configuration enforcing deterministic Haskell formatting"
      (const fourmoluTemplate)
  , StandardAsset
      "rustfmt.toml"
      CategoryFormatter
      False
      False
      "Canonical rustfmt configuration for polyglot Rust components"
      (const rustfmtTemplate)
  , StandardAsset
      ".clang-format"
      CategoryFormatter
      False
      False
      "Canonical .clang-format configuration based on LLVM/Linux style"
      (const clangFormatTemplate)

  -- Dimension 3: Static Analysis & Linters
  , StandardAsset
      ".hlint.yaml"
      CategoryLinter
      True
      False
      "Strict zero-hint HLint static analysis configuration"
      (const hlintTemplate)

  -- Dimension 4: Build Conventions
  , StandardAsset
      "cabal.project"
      CategoryBuild
      True
      False
      "Root Cabal project file pinning GHC 9.14.1 and compiler warning flags"
      cabalProjectTemplate
  , StandardAsset
      "cabal.project.local.example"
      CategoryBuild
      True
      False
      "Developer local override configuration template"
      (const cabalProjectLocalTemplate)

  -- Dimension 5: Git Governance & Hooks
  , StandardAsset
      ".gitmessage"
      CategoryGitGovernance
      True
      False
      "Git commit message template specifying RFC 2822 trailer format"
      (const gitmessageTemplate)
  , StandardAsset
      "tagref.yml"
      CategoryGitGovernance
      True
      False
      "Tagref cross-reference configuration file"
      tagrefConfigTemplate
  , StandardAsset
      ".githooks/commit-msg"
      CategoryGitGovernance
      True
      True
      "Git commit-msg hook enforcing AI attribution and commit message rules"
      (const commitMsgHookTemplate)
  , StandardAsset
      ".githooks/pre-commit"
      CategoryGitGovernance
      True
      True
      "Git pre-commit hook guarding Tagref references and markdown links"
      preCommitHookTemplate

  -- Dimension 6: Remote Topology & Multi-Forge Mirroring
  , StandardAsset
      "docs/MAINTAINER_GUIDE.md"
      CategoryRemoteTopology
      True
      False
      "Maintainer guide documenting the 5-remote topology and push mirrors"
      docsMaintainerGuideTemplate

  -- Dimension 7: Forge-Tiered CI Workflows
  , StandardAsset
      ".github/workflows/ci.yml"
      CategoryCIWorkflow
      True
      False
      "High-resource GitHub Actions workflow running complete physical gates"
      githubCiTemplate
  , StandardAsset
      ".gitlab-ci.yml"
      CategoryCIWorkflow
      True
      False
      "Lightweight GitLab CI workflow for resource-constrained community forges"
      gitlabCiTemplate

  -- Dimension 8: Polyglot Invariants
  , StandardAsset
      ".clang-format"
      CategoryPolyglot
      False
      False
      "Polyglot C/C++ ABI formatting and style definition"
      (const clangFormatTemplate)

  -- Dimension 9: Agent Advisory Layer
  , StandardAsset
      "AGENTS.md"
      CategoryAgentAdvisory
      True
      False
      "Context-budgeted AI coding assistant advisory guide (~4 KB limit)"
      agentsTemplate
  , StandardAsset
      "CLAUDE.md"
      CategoryAgentAdvisory
      True
      False
      "Agent compatibility symlink/pointer to AGENTS.md"
      claudeTemplate
  , StandardAsset
      ".agents/rules/commit-attribution.md"
      CategoryAgentAdvisory
      True
      False
      "Modular rule: Linux kernel RFC 2822 trailer format and DCO boundaries"
      (const commitAttributionRuleTemplate)
  , StandardAsset
      ".agents/rules/code-navigation.md"
      CategoryAgentAdvisory
      True
      False
      "Modular rule: Token-conserving code navigation funnel"
      (const codeNavigationRuleTemplate)
  , StandardAsset
      ".agents/rules/compiler-verification.md"
      CategoryAgentAdvisory
      True
      False
      "Modular rule: Zero-warning compiler verification and zero-contamination"
      (const compilerVerificationRuleTemplate)
  , StandardAsset
      ".agents/rules/documentation-precedence.md"
      CategoryAgentAdvisory
      True
      False
      "Modular rule: Precedence rule and the two-file operational loop"
      (const documentationPrecedenceRuleTemplate)

  -- Dimension 10: Physical Verification Harnesses
  , StandardAsset
      "bin/:name:-verify"
      CategoryVerification
      True
      True
      "Primary physical verification runner executing all 5 non-negotiable gates"
      verifyScriptTemplate
  , StandardAsset
      "bin/:name:-tagref"
      CategoryVerification
      True
      True
      "Tagref cross-reference verification script"
      tagrefScriptTemplate
  , StandardAsset
      "bin/:name:-linkcheck"
      CategoryVerification
      True
      True
      "Markdown relative link and section anchor integrity checker"
      linkcheckScriptTemplate
  , StandardAsset
      "bin/:name:-cloc"
      CategoryVerification
      True
      True
      "CLOC comment density enforcement script requiring >= 50% comments"
      clocScriptTemplate
  , StandardAsset
      "bin/generate-tags"
      CategoryVerification
      True
      True
      "Universal ctags symbol table generator for fast token-efficient lookup"
      (const generateTagsTemplate)
  ]

--------------------------------------------------------------------------------
-- 3. Canonical Matrix
--------------------------------------------------------------------------------

-- | Authoritative singleton Standardization Matrix for the Gachi ecosystem.
--
-- Combines 'canonicalAssets' across all 'canonicalDimensions'.
--
-- Serves as the primary reference matrix for:
-- * 'Gachi.Sync.Audit.auditRepository': Inspecting workspaces for drift or missing files.
-- * 'Gachi.Sync.Audit.auditRepositoryQuick': Fast, zero-argument workspace verification.
-- * 'Gachi.Sync': Differential synchronization across repository checkouts.
canonicalMatrix :: StandardizationMatrix
canonicalMatrix = StandardizationMatrix
  { matrixAssets     = canonicalAssets
  , matrixDimensions = canonicalDimensions
  }

--------------------------------------------------------------------------------
-- 4. Query & Filter Combinators
--------------------------------------------------------------------------------

-- | Extracts all standardized assets belonging to a specific 'AssetCategory'.
--
-- Filters 'matrixAssets' by matching 'assetCategory'.
--
-- === Worked Example
--
-- >>> let formatters = assetsForCategory CategoryFormatter canonicalMatrix
-- >>> map assetPath formatters
-- ["fourmolu.yaml","rustfmt.toml",".clang-format"]
assetsForCategory :: AssetCategory -> StandardizationMatrix -> [StandardAsset]
assetsForCategory cat matrix =
  filter (\a -> assetCategory a == cat) (matrixAssets matrix)

-- | Extracts all forge-tiered CI workflow assets (Dimension 7) from a matrix.
--
-- Filters assets belonging to 'CategoryCIWorkflow'.
--
-- See Note [Forge-Tiered CI Resource Allocation and Static Gate Partitioning]
-- [ref:note-forge-tiered-ci].
--
-- === Worked Example
--
-- >>> let ciAssets = ciWorkflowAssets canonicalMatrix
-- >>> map assetPath ciAssets
-- [".github/workflows/ci.yml",".gitlab-ci.yml"]
ciWorkflowAssets :: StandardizationMatrix -> [StandardAsset]
ciWorkflowAssets = assetsForCategory CategoryCIWorkflow

-- | Extracts all required assets from a matrix.
--
-- An asset is required if its absence from disk constitutes an audit violation.
-- Required assets must be present in every production repository checkout.
--
-- === Worked Example
--
-- >>> let reqs = requiredAssets canonicalMatrix
-- >>> all assetRequired reqs
-- True
requiredAssets :: StandardizationMatrix -> [StandardAsset]
requiredAssets matrix =
  filter assetRequired (matrixAssets matrix)

-- | Extracts all optional assets from a matrix.
--
-- Optional assets (e.g. polyglot formatting rules for C/Rust) do not cause
-- audit failures when omitted from repositories that lack those language components.
--
-- === Worked Example
--
-- >>> let opts = optionalAssets canonicalMatrix
-- >>> all (not . assetRequired) opts
-- True
optionalAssets :: StandardizationMatrix -> [StandardAsset]
optionalAssets matrix =
  filter (not . assetRequired) (matrixAssets matrix)

-- | Extracts all assets requiring POSIX executable permissions (@+x@).
--
-- Includes verification scripts in @bin/@ and git hooks in @.githooks/@.
-- The audit engine validates that files on disk have the executable bit set.
--
-- === Worked Example
--
-- >>> let execs = executableAssets canonicalMatrix
-- >>> all assetExecutable execs
-- True
executableAssets :: StandardizationMatrix -> [StandardAsset]
executableAssets matrix =
  filter assetExecutable (matrixAssets matrix)

-- | Looks up a standard asset by its relative file path.
--
-- Searches 'matrixAssets' for an exact match against 'assetPath'.
-- Returns 'Nothing' if the path is not registered in the matrix.
--
-- === Worked Example
--
-- >>> let maybeHlint = findAssetByPath ".hlint.yaml" canonicalMatrix
-- >>> fmap assetCategory maybeHlint
-- Just CategoryLinter
findAssetByPath :: FilePath -> StandardizationMatrix -> Maybe StandardAsset
findAssetByPath path matrix =
  find (\a -> assetPath a == path) (matrixAssets matrix)

-- | Computes asset counts grouped by 'AssetCategory'.
--
-- Returns a list of pairs associating each category with its total registered asset count.
-- Guarantees that every category in 'matrixDimensions' appears in the result list.
--
-- === Worked Example
--
-- >>> let counts = countByCategory canonicalMatrix
-- >>> all (\(_, c) -> c > 0) counts
-- True
countByCategory :: StandardizationMatrix -> [(AssetCategory, Int)]
countByCategory matrix =
  map (\cat -> (cat, length (assetsForCategory cat matrix))) (matrixDimensions matrix)
