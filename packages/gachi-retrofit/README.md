<!--
SPDX-License-Identifier: EUPL-1.2 OR Apache-2.0
-->
# gachi-retrofit — Non-Destructive Codebase Retrofitting & Diagnostic Repository Inspector

`gachi-retrofit` is the codebase migration and diagnostic inspection engine of the Gachi ecosystem framework. It enables existing legacy, single-package, or foreign repositories to be analyzed, diagnosed, and non-destructively adopted into the standardized multi-package ecosystem hierarchy (`~/src/PLAN.md` §1.A, Phase 4).

## 1. Architectural Overview

Per Note [Non-Destructive Skeleton Overlay] [ref:note-nondestructive-retrofit], retrofitting operations must **never** delete, overwrite, or mutate domain logic source files (`src/`, `app/`, `lib/`). Before any scaffolding or overlay actions can be synthesized (Milestone 4.2), the system must perform a rigorous, read-only static analysis of the target workspace.

`gachi-retrofit` provides this capability through **Milestone 4.1: Diagnostic Repository Inspector**:

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
```

## 2. Six Diagnostic Dimensions

The diagnostic analyzer evaluates arbitrary checkouts across six orthogonal dimensions:

1. **Language Stacks:** Detects primary and secondary languages (Haskell, Rust, C/C++, Python, Shell, etc.), measuring file counts and distribution percentages.
2. **Build Systems & Layout:** Identifies build manifests (`cabal.project`, `*.cabal`, `stack.yaml`, `Cargo.toml`, `CMakeLists.txt`, `Makefile`, `pyproject.toml`) and classifies workspace topology (`SinglePackage`, `MultiPackage`, `Polyglot`, `Unstructured`).
3. **Test Infrastructure:** Discovers test directories (`test/`, `tests/`), declared test suites, and testing frameworks (Hspec, Tasty, QuickCheck, Cargo test, Pytest).
4. **Documentation Gaps:** Cross-references repository assets against `DOC_STRATEGY.md` requirements (`README.md`, `docs/INDEX.md`, `docs/notes/*_DESIGN.md`, `PLAN.md`, `STATE.md`, `AGENTS.md`, `CLAUDE.md`, `.agents/rules/`).
5. **Git Governance & Attribution:** Audits `.git` configuration, `core.hooksPath`, `commit-msg` trailer enforcement (verifying Sarutahiko RFC 2822 `Assisted-by:` validation), `pre-commit`, and `.gitmessage` template configuration.
6. **Physical Verification Gates:** Evaluates turnkey verification scripts (`./bin/*-verify`), Tagref cross-reference configuration, Markdown linkcheck harnesses, and comment density audit scripts.

## 3. Module Hierarchy

- `Gachi.Retrofit.Types`: Comprehensive algebraic data models representing diagnostic findings, language statistics, build systems, test suites, documentation gaps, and report structures.
- `Gachi.Retrofit.Diagnostic`: Pure classification combinators, filesystem exploration routines, heuristic scoring, and remediation plan calculation.
- `Gachi.Retrofit.Report`: Rich terminal dashboard pretty-printing (aligned ASCII tables, progress bars) and GFM Markdown serialization.
- `Gachi.Retrofit`: Root facade re-exporting the complete public API.

## 4. Usage Example

```haskell
import Gachi.Retrofit

main :: IO ()
main = do
  report <- scanRepository "/path/to/legacy-repo"
  putStrLn (formatDiagnosticReport report)
```
