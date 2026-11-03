# Gachi Newbie Quickstart & Token-Conservation Guide

**Status:** LIVING DOCUMENT · v1.1 · 2026-11-03  
**Audience:** New Human Contributors & AI Coding Assistant Drivers (Antigravity, Claude Code, Cursor, Aider)  
**Parent Strategy:** [`docs/notes/DOC_STRATEGY.md`](notes/DOC_STRATEGY.md)  
**Corpus Inventory:** [`docs/INDEX.md`](INDEX.md)  
**Interactive Tutorial:** [`docs/TUTORIAL.md`](TUTORIAL.md) · **Maintainer Guide:** [`docs/MAINTAINER_GUIDE.md`](MAINTAINER_GUIDE.md)  

Welcome to `gachi`! This guide provides an efficient orientation for developers and AI drivers, showing how to navigate the 7-package codebase rapidly while minimizing token consumption and preventing context degradation.

---

## 1. The Core Invariant: Never Dump Whole Modules

In high-performance systems code dealing with unboxed primitive arrays, atomic state machines, and algebraic graph rewriting, dumping whole source files into conversation context consumes thousands of tokens and degrades model attention.

Always follow the **3-Level Progressive Disclosure Funnel**:

```
Level 0: Global Navigation  (docs/INDEX.md, tags symbol jump)       →   ~10–50 tokens
Level 1: Structural Outline (module exports, type signatures)       →   ~100–250 tokens
Level 2: Targeted Slice     (view_file StartLine / EndLine)         →   ~200–500 tokens
```

---

## 2. Fast Package & Symbol Navigation (Level 0 — <50 tokens)

Before opening any file, identify the module and package owning the concept:

| If you are looking for... | Module | Package & Source Location |
| :--- | :--- | :--- |
| `OsteoSegment`, `OsteoBytes`, `appendOsteo`, `sliceOsteo` | `Gachi.Osteology` | [`packages/gachi-core/src/Gachi/Osteology.hs`](../packages/gachi-core/src/Gachi/Osteology.hs) |
| `BoneId`, `JointId`, `Skeleton`, `emptySkeleton` | `Gachi.Core` | [`packages/gachi-core/src/Gachi/Core.hs`](../packages/gachi-core/src/Gachi/Core.hs) |
| `BoneMachine`, CAS loops, atomic transitions | `Gachi.Core.Atomic` | [`packages/gachi-core/src/Gachi/Core/Atomic.hs`](../packages/gachi-core/src/Gachi/Core/Atomic.hs) |
| Double-Pushout (DPO) graph rewriting, `ProductionRule` | `Gachi.Core.Rewriting` | [`packages/gachi-core/src/Gachi/Core/Rewriting.hs`](../packages/gachi-core/src/Gachi/Core/Rewriting.hs) |
| Polytropos zero-cost coercions (`segmentToRep`) | `Gachi.Core` | [`packages/gachi-core/src/Gachi/Core.hs`](../packages/gachi-core/src/Gachi/Core.hs) |
| Declarative Dhall project schema (`Project`, `Package`) | `Gachi.Schema.Project` | [`packages/gachi-schema/src/Gachi/Schema/Project.hs`](../packages/gachi-schema/src/Gachi/Schema/Project.hs) |
| Workspace templates & forge-tiered CI synthesis | `Gachi.Scaffold.Templates` | [`packages/gachi-scaffold/src/Gachi/Scaffold/Templates.hs`](../packages/gachi-scaffold/src/Gachi/Scaffold/Templates.hs) |
| Shared asset catalog (`.hlint.yaml`, `.gitmessage`) | `Gachi.Sync.Catalog` | [`packages/gachi-sync/src/Gachi/Sync/Catalog.hs`](../packages/gachi-sync/src/Gachi/Sync/Catalog.hs) |
| Repository audit & propagation engine (`gachi sync`) | `Gachi.Sync.Engine` | [`packages/gachi-sync/src/Gachi/Sync/Engine.hs`](../packages/gachi-sync/src/Gachi/Sync/Engine.hs) |
| 6-pillar diagnostic scanner (`scanRepository`) | `Gachi.Retrofit.Diagnostic` | [`packages/gachi-retrofit/src/Gachi/Retrofit/Diagnostic.hs`](../packages/gachi-retrofit/src/Gachi/Retrofit/Diagnostic.hs) |
| Non-destructive skeleton overlay (`computeOverlayPlan`) | `Gachi.Retrofit.Overlay` | [`packages/gachi-retrofit/src/Gachi/Retrofit/Overlay.hs`](../packages/gachi-retrofit/src/Gachi/Retrofit/Overlay.hs) |
| Penelope polycategorical arrow pipeline (`RetrofitPipeline`) | `Gachi.Retrofit.Pipeline` | [`packages/gachi-retrofit/src/Gachi/Retrofit/Pipeline.hs`](../packages/gachi-retrofit/src/Gachi/Retrofit/Pipeline.hs) |
| Progressive quality gates (L0–L3) | `Gachi.Retrofit.QualityGate` | [`packages/gachi-retrofit/src/Gachi/Retrofit/QualityGate.hs`](../packages/gachi-retrofit/src/Gachi/Retrofit/QualityGate.hs) |
| Detached Git plan store (`~/.plan.git`) | `Gachi.Plan.Store` | [`packages/gachi-plan/src/Gachi/Plan/Store.hs`](../packages/gachi-plan/src/Gachi/Plan/Store.hs) |
| Plan checkpointing & snapshot ledger | `Gachi.Plan.Snapshot` | [`packages/gachi-plan/src/Gachi/Plan/Snapshot.hs`](../packages/gachi-plan/src/Gachi/Plan/Snapshot.hs) |
| Unified CLI command parser & dispatcher | `Gachi.CLI` | [`packages/gachi-cli/src/Gachi/CLI.hs`](../packages/gachi-cli/src/Gachi/CLI.hs) |

---

## 3. Fast Symbol Jump via `./tags` (<30 tokens)

The repository maintains an up-to-date ctags database generated via `./bin/generate-tags`. Use standard shell pattern matching to find exact line locations in milliseconds:

```bash
# Jump directly to definition line
grep "^OsteoSegment" tags
# Output: OsteoSegment  packages/gachi-core/src/Gachi/Osteology.hs  /^data OsteoSegment a = OsteoSegment/;"  d

grep "^scanRepository" tags
# Output: scanRepository  packages/gachi-retrofit/src/Gachi/Retrofit/Diagnostic.hs  /^scanRepository :: FilePath -> IO DiagnosticReport/;"  f
```

Once the line is identified, read only a targeted window (typically 30–60 lines) using `view_file` around that line.

---

## 4. The 15-Minute Contributor Walkthrough

Follow these steps to get your first change tested and verified:

1. **Clone & Setup:**
   Ensure GHC 9.14.1 and Cabal 3.18+ are present.
   ```bash
   cabal build all
   ```

2. **Run All Test Suites:**
   ```bash
   cabal test gachi-core gachi-schema gachi-scaffold gachi-cli gachi-sync gachi-retrofit gachi-plan
   ```

3. **Run the 5-Gate Physical Verification Runner:**
   ```bash
   ./bin/gachi-verify
   ```
   All 5 gates must pass:
   - HLint static analysis (0 hints)
   - Full test suite assertions
   - Tagref cross-references (0 dangling refs)
   - Markdown link integrity (0 broken links)
   - CLOC comment density (target: 50%+)

4. **Verify Commit Governance:**
   Git hooks enforce the Sarutahiko RFC 2822 trailer format. Ensure your commit message contains:
   ```
   Assisted-by: Antigravity (Google DeepMind / Gemini 3.8 Flash)
   ```
   Never use `Co-authored-by:` or `Signed-off-by:` for AI assistants.

---

## 5. Mental Model Demystified

### What is an "Osteological Rig"?
An osteological rig is an unboxed graph representation backed by a contiguous `SmallArray#`. Instead of pointer-chasing through tree nodes on the heap, each "bone" lives at a fixed integer offset in the array. Slicing subgraphs (`sliceOsteo`) adjusts an offset window in $O(1)$ time with zero allocations.

### What is "Chattering Synchronization"?
*Gachi-gachi* is the onomatopoeia for chattering teeth. In our ecosystem, "chattering" refers to high-speed, lock-free state synchronization across concurrent workers, as well as the ecosystem-wide propagation (`gachi sync`) of linting policies, commit templates, git hooks, and AI advisory rules across all satellite checkouts.

### Why a Detached Plan Store?
`~/src/PLAN.md` and `~/src/STATE.md` govern multiple independent repositories. Versioning them inside any single repository causes cross-repo commit pollution. `gachi-plan` isolates strategic planning in a detached Git store (`~/src/.plan.git`) paired with an append-only snapshot ledger (`~/src/plans/snapshots/`), enabling deterministic checkpoints and atomic rollbacks.
