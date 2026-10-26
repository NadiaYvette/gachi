<!--
SPDX-License-Identifier: EUPL-1.2 OR Apache-2.0
-->
# gachi-retrofit — Non-Destructive Codebase Retrofitting & Diagnostic Repository Inspector

`gachi-retrofit` is the codebase migration, diagnostic inspection, and non-destructive skeleton overlay engine of the Gachi ecosystem framework. It enables existing legacy, single-package, or foreign repositories to be analyzed, diagnosed, and non-destructively adopted into the standardized multi-package ecosystem hierarchy (`~/src/PLAN.md` §1.A, Phase 4).

## 1. Architectural Overview

Per Note [Non-Destructive Skeleton Overlay] [ref:note-nondestructive-retrofit], retrofitting operations must **never** delete, overwrite, or mutate domain logic source files (`src/`, `app/`, `lib/`, `test/`). The engine executes through a two-phase architecture:

1. **Milestone 4.1: Diagnostic Repository Inspector:** Conducts rigorous, read-only static analysis across six dimensions (languages, build manifests, test suites, documentation gaps, Git governance, verification gates) and computes quantitative readiness scores.
2. **Milestone 4.2: Non-Destructive Skeleton Overlay:** Computes an explicit `OverlayPlan` categorizing missing standardized assets as `ActionCreate` and pre-existing files as `ActionPreserve`. In live mode, materializes missing documentation, agent rules, Git hooks, and verification runners (`bin/*-verify`) with executable bits, and configures Git governance without touching domain code.

```
Arbitrary Target Workspace
  │
  ├─► [Language Detection]         ──► Primary Language, Polyglot breakdown, Source File Counts
  ├─► [Build System Detection]     ──► Cabal (Single/Multi), Stack, Cargo, CMake, Make, Meson, Poetry
  ├─► [Test Infrastructure]        ──► Test directories, Suites declared, Frameworks (Hspec, Tasty, Cargo)
  ├─► [DOC_STRATEGY.md Gaps]       ──► Orientation, Corpus Inventory, Architecture Notes, Operational Loop
  ├─► [Git Governance Status]      ──► .githooks, commit-msg (RFC 2822 Assisted-by:), pre-commit, .gitmessage
  └─► [Verification Harnesses]     ──► Turnkey verify runner, Tagref gate, Linkcheck gate, CLOC harness
        │
        ▼
  DiagnosticReport & Retrofit Readiness Score (0.0% – 100.0%)
        │
        ▼
  Non-Destructive Overlay Plan (Milestone 4.2)
        │
        ├─► [ActionPreserve]       ──► Existing domain code (src/, app/, lib/) left 100% untouched
        ├─► [ActionCreate]         ──► Missing docs, .agents/rules, .githooks, and bin/*-verify
        └─► [GitGovernanceAction]  ──► core.hooksPath = .githooks, commit.template = .gitmessage
```

## 2. Six Diagnostic Dimensions & Overlay Categories

The diagnostic and overlay pipeline covers six orthogonal dimensions:

1. **Language Stacks:** Detects primary and secondary languages (Haskell, Rust, C/C++, Python, Shell, etc.), measuring file counts and distribution percentages.
2. **Build Systems & Layout:** Identifies build manifests (`cabal.project`, `*.cabal`, `stack.yaml`, `Cargo.toml`, `CMakeLists.txt`, `Makefile`, `pyproject.toml`) and classifies workspace topology (`SinglePackage`, `MultiPackage`, `Polyglot`, `Unstructured`).
3. **Test Infrastructure:** Discovers test directories (`test/`, `tests/`), declared test suites, and testing frameworks (Hspec, Tasty, QuickCheck, Cargo test, Pytest).
4. **Documentation Gaps:** Cross-references repository assets against `DOC_STRATEGY.md` requirements (`README.md`, `docs/INDEX.md`, `docs/notes/*_DESIGN.md`, `PLAN.md`, `STATE.md`, `AGENTS.md`, `CLAUDE.md`, `.agents/rules/`).
5. **Git Governance & Attribution:** Audits and configures `.git`, `core.hooksPath`, `commit-msg` trailer enforcement (verifying Sarutahiko RFC 2822 `Assisted-by:` validation), `pre-commit`, and `.gitmessage` template configuration.
6. **Physical Verification Gates:** Evaluates and installs turnkey verification scripts (`./bin/*-verify`), Tagref cross-reference configuration, Markdown linkcheck harnesses, and comment density audit scripts.

## 3. Module Hierarchy

- `Gachi.Retrofit.Types`: Comprehensive algebraic data models representing diagnostic findings, language statistics, build systems, test suites, documentation gaps, and report structures.
- `Gachi.Retrofit.Diagnostic`: Pure classification combinators, filesystem exploration routines, heuristic scoring, and remediation plan calculation.
- `Gachi.Retrofit.Overlay`: Non-destructive skeleton overlay engine, candidate asset synthesis, plan computation (`computeOverlayPlan`), and materialization (`executeOverlayPlan`).
- `Gachi.Retrofit.Report`: Rich terminal dashboard pretty-printing (aligned ASCII tables, progress bars) and GFM Markdown serialization.
- `Gachi.Retrofit`: Root facade re-exporting the complete public API.

## 4. Usage Example

```haskell
import Gachi.Retrofit

main :: IO ()
main = do
  report <- scanRepository "/path/to/legacy-repo"
  putStrLn (formatDiagnosticReport report)

  -- Preview non-destructive overlay plan
  plan <- computeOverlayPlan "/path/to/legacy-repo" report
  putStrLn (formatOverlayPlan plan)

  -- Execute non-destructive overlay (materializes missing assets, preserves domain code)
  res <- executeOverlayPlan plan
  putStrLn (formatOverlayResult res)
```
