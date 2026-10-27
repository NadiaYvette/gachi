-- | Module: Gachi.Retrofit
-- Description: Non-destructive codebase retrofitting engine & diagnostic inspector
--
-- This is the root library module for @gachi-retrofit@. It provides the unified
-- public API for inspecting legacy, single-package, or foreign repositories, evaluating
-- six diagnostic dimensions, and computing actionable remediation plans per
-- Phase 4 and Milestone 4.1.
--
-- = Monograph: The Theory of Non-Destructive Codebase Retrofitting
--
-- == 1. The Retrofitting Problem and the Conservation of Domain Logic
--
-- Software ecosystems face a perennial tension between standardization and legacy codebases.
-- High-assurance development environments require strict invariants: zero-warning builds under
-- @-Wall -Wcompat -Wredundant-constraints@, clean linters (zero HLint hints), bi-directional
-- Tagref cross-references, unbroken documentation hyperlinks, and measured in-code comment
-- density. However, existing repositories—whether single-package libraries, ad-hoc research
-- prototypes, or foreign language checkouts—rarely conform to these contracts initially.
--
-- Traditional migration approaches either:
-- 1. Demand exhaustive manual refactoring, creating high friction and human error.
-- 2. Force destructive scaffolding re-generation, risking clobbering, overwriting, or deleting
--    irreplaceable domain logic.
--
-- The Gachi Retrofitting Engine establishes an alternative: __Non-Destructive Codebase Retrofitting__.
-- Let \(\mathcal{P}\) denote the universe of repositories. A repository \(P \in \mathcal{P}\) is
-- modeled as a pair:
--
-- \[
--   P = (D, S)
-- \]
--
-- where \(D\) represents the __domain logic__ (the algorithmic core, modules, data types, and
-- mathematical structures inhabiting @src/@, @app/@, @lib/@) and \(S\) represents the __scaffolding__
-- (build tool manifests, documentation, git hooks, CI matrices, and verification harnesses).
--
-- === The Inviolable Conservation Law of Domain Logic
--
-- Any retrofitting transformation \(R : \mathcal{P} \to \mathcal{P}\) must strictly satisfy the
-- __Conservation of Domain Logic__:
--
-- \[
--   \pi_{\text{domain}}(R(P)) = \pi_{\text{domain}}(P)
-- \]
--
-- That is, no retrofitting operation may ever delete, truncate, overwrite, or mutate any domain
-- logic file. All standardization occurs exclusively in the scaffolding component \(S\).
--
-- == 2. Phased Stratification of the Retrofitting Pipeline
--
-- To guarantee safety and transparency, the retrofitting engine decomposes into four
-- phased operational milestones across Phase 4:
--
-- * __Milestone 4.1 (Diagnostic Repository Inspector):__
--   Strictly observational, read-only static analysis. Evaluates the target repository across
--   six orthogonal dimensions, producing a strongly typed 'DiagnosticReport' and quantitative
--   retrofit readiness score \(S(P) \in [0.0, 100.0]\).
--
-- * __Milestone 4.2 (Non-Destructive Skeleton Overlay):__
--   Synthesizes missing ecosystem infrastructure: @.githooks/@, @.gitmessage@, turnkey verification
--   harnesses (@bin/*-verify@, @bin/*-tagref@, @bin/*-linkcheck@, @bin/*-cloc@), documentation
--   skeletons (@docs/INDEX.md@, @docs/notes/*_DESIGN.md@, @docs/notes/DOC_STRATEGY.md@), and
--   agent operational layers (@PLAN.md@, @STATE.md@, @AGENTS.md@).
--
-- * __Milestone 4.3 (Progressive Quality Gate Realization):__
--   Incremental quality remediation stepping through four compliance levels:
--   - Level 0: Toolchain and verification harness installation.
--   - Level 1: Tagref and Markdown link integrity certification.
--   - Level 2: Build warnings resolved under @-Wall -Wcompat@.
--   - Level 3: HLint hints completely eliminated under zero-hint policy.
--
-- * __Milestone 4.4 (Empirical Victim Project Crucible):__
--   End-to-end validation against real-world targets, beginning with @~/src/gongju/@ ("tools/implement").
--
-- == 3. The Six Orthogonal Diagnostic Dimensions
--
-- The diagnostic analyzer ('scanRepository') evaluates target workspaces across six dimensions:
--
-- @
--  +-------------------------------------------------------------------------------+
--  |                       Six Diagnostic Dimensions                               |
--  +-------------------------------------------------------------------------------+
--  | [1] Language Stacks    : Haskell, Rust, C/C++, Python, Shell (File counts & %) |
--  | [2] Build Systems      : Cabal Multi/Single, Stack, Cargo, CMake, Make, Meson |
--  | [3] Test Infra         : Hspec, Tasty, QuickCheck, Cargo test, Pytest, CTest  |
--  | [4] Documentation Gaps : DOC_STRATEGY.md Checklist (Critical, Recommended)    |
--  | [5] Git Governance     : .githooks, commit-msg RFC 2822 trailers, .gitmessage |
--  | [6] Quality Gates      : Turnkey verify runner, Tagref, Linkcheck, CLOC gate  |
--  +-------------------------------------------------------------------------------+
-- @
--
-- == 4. Quantitative Readiness Scoring Formula
--
-- The ecosystem retrofit readiness score \(S(P)\) is a weighted sum normalized to \([0.0, 100.0]\):
--
-- \[
--   S(P) = w_{\text{lang}} \cdot s_{\text{lang}}
--        + w_{\text{test}} \cdot s_{\text{test}}
--        + w_{\text{doc}} \cdot s_{\text{doc}}
--        + w_{\text{git}} \cdot s_{\text{git}}
--        + w_{\text{verif}} \cdot s_{\text{verif}}
-- \]
--
-- where:
-- * \(w_{\text{lang}} = 15\%\): Clear primary language and coherent build manifest.
-- * \(w_{\text{test}} = 20\%\): Active test directories (10%) and declared suites with frameworks (10%).
-- * \(w_{\text{doc}} = 30\%\): Proportion of present Critical and Recommended documents per @DOC_STRATEGY.md@.
-- * \(w_{\text{git}} = 20\%\): Git repository (5%), .githooks (5%), commit-msg with attribution (5%), template (5%).
-- * \(w_{\text{verif}} = 15\%\): Turnkey verify runner (5%), Tagref (3%), Linkcheck (3%), CLOC (2%), Linters (2%).
--
-- = Worked Example
--
-- >>> import Gachi.Retrofit
-- >>> report <- scanRepository "."
-- >>> diagProjectName report
-- "gachi"
-- >>> diagRetrofitScore report >= 90.0
-- True
-- >>> let dashboard = formatDiagnosticReport report
-- >>> T.null dashboard
-- False
module Gachi.Retrofit
  ( -- * Re-exports from Gachi.Retrofit.Diagnostic
    scanRepository
  , detectLanguages
  , detectBuildSystems
  , detectTestInfrastructure
  , detectDocumentationGaps
  , detectGitGovernance
  , detectVerificationHarnesses
  , computeRetrofitScore
  , computeRemediationPlan
  , inferProjectName
  , listRepositoryFiles
  , isIgnoredDirectory

    -- * Re-exports from Gachi.Retrofit.Report
  , formatDiagnosticReport
  , formatDiagnosticMarkdown
  , formatDiagnosticSummaryLine
  , renderScoreBar
  , scoreClassification
  , padRight

    -- * Re-exports from Gachi.Retrofit.Overlay
  , OverlayActionType(..)
  , OverlayCategory(..)
  , OverlayAction(..)
  , GitGovernanceAction(..)
  , OverlayPlan(..)
  , OverlayResult(..)
  , computeOverlayPlan
  , synthesizeOverlayCandidates
  , detectGitAuthor
  , executeOverlayPlan
  , overlayRepository
  , formatOverlayPlan
  , formatOverlayPlanMarkdown
  , formatOverlayResult
  , overlayCategoryName

    -- * Re-exports from Gachi.Retrofit.Types
  , Language(..)
  , LanguageStats(..)
  , languageName
  , BuildSystem(..)
  , WorkspaceLayout(..)
  , buildSystemName
  , layoutName
  , TestFramework(..)
  , TestSuiteInfo(..)
  , TestInfrastructure(..)
  , testFrameworkName
  , DocCategory(..)
  , DocSeverity(..)
  , DocGap(..)
  , docCategoryName
  , docSeverityName
  , GitGovernanceStatus(..)
  , VerificationHarnessStatus(..)
  , DiagnosticReport(..)

    -- * Re-exports from Gachi.Retrofit.QualityGate (Milestone 4.3)
  , QualityLevel(..)
  , qualityLevelName
  , qualityLevelOrdinal
  , GateCheck(..)
  , GateResult(..)
  , QualityGateReport(..)
  , RemediationStep(..)
  , RemediationPriority(..)
  , remediationPriorityName
  , level0Gates
  , level1Gates
  , level2Gates
  , level3Gates
  , allLevelGates
  , evaluateQualityGates
  , evaluateGateCheck
  , computeAchievedLevel
  , computeRemediationSteps
  , formatQualityGateReport
  , formatQualityGateMarkdown
  ) where

import Gachi.Retrofit.Diagnostic
import Gachi.Retrofit.Overlay
import Gachi.Retrofit.QualityGate
import Gachi.Retrofit.Report
import Gachi.Retrofit.Types
