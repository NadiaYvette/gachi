<!--
SPDX-License-Identifier: EUPL-1.2 OR Apache-2.0
-->
# gachi — Implementation Plan (`IMPLEMENTATION_PLAN.md`)

**Status:** SPECIFICATION · v1.0 · 2026-10-24 · blessed  
**Scope:** Canonical Implementation Plan for the `gachi` Substrate, Project Skeleton Generator (`gachi init`), Configuration Propagation Engine (`gachi sync`), Retrofitting Pipeline (`gachi retrofit`), and Strategic Plan Governance Architecture (`gachi plan` / `plan-ctl`).  
**Canonical Anchors:**
- Upstream Ecosystem Infrastructure Mandate: [`~/src/PLAN.md` §1](../../../PLAN.md#1-project-skeleton-&-configuration-propagation-infrastructure-gachi)
- Architectural Decisions & Memory Invariants: [`GACHI_DESIGN.md`](GACHI_DESIGN.md) (Decisions D1–D8)
- Operational Roadmaps: [`PLAN.md`](../../PLAN.md) & [`STATE.md`](../../STATE.md)
- Documentation Policy: [`DOC_STRATEGY.md`](DOC_STRATEGY.md) §4 (Code wins at runtime; notes corrected regardless)

---

## 1. Guiding Principles & Execution Strategy

The name **`gachi`** (がちがち) evokes the rhythmic, resonant clicking of the teeth of a *gashadokuro* (がしゃどくろ) — the mythical colossal skeleton formed from the spirits of fallen warriors. In our software engineering ecosystem, `gachi` serves as the rigid structural framework and harmonic synchronization mechanism that keeps independent repositories aligned, performant, and resilient against entropy.

The implementation plan is governed by seven immutable architectural principles:

1. **Rigidity Before Concurrency:**  
   Establish deterministic, contiguous, unboxed memory representations and baseline workspace skeletons before introducing lock-free atomic concurrency, multi-agent coordination, or graph-rewriting engines.
2. **Idempotence & Non-Destruction:**  
   All skeleton generation (`gachi init`), project retrofitting (`gachi retrofit`), and configuration propagation (`gachi sync`) operations must be mathematically idempotent ($f(f(x)) = f(x)$) and non-destructive toward existing domain logic.
3. **Hermetic Declarative Templating:**  
   Configuration schemas and project templates must be authored in total, typed Dhall expressions via `polytropos-dhall`, eliminating the security vulnerabilities and non-determinism of Turing-complete shell or templating scripts.
4. **Detached Governance Isolation:**  
   Ecosystem-wide strategic plan versioning and rollback (`gachi plan`) operates exclusively through an isolated, detached Git metadata store (`~/src/.plan.git`) and append-only snapshot ledger (`~/src/plans/snapshots/`), preventing pollution of or conflicts with child repository `.git/` trees.
5. **Arrow & Profunctor Strand Decoupling ([`kernmantle-polytropos`](../../../kernmantle)):**  
   Operational workflows (`retrofit`, `sync`, `plan`) are modeled as extensible arrow effect ropes (`Rope record mantle core a b`) where diagnostic inspection, AST parsing, pushout merging, sandboxed execution, verification, and filesystem mutations are discrete profunctor strands. Utilizing `polytropos`' unboxed flat `RecordF` (`SmallArray Any`) provides $O(1)$ strand lookup and zero-allocation re-twining (`retwine`), enabling seamless multi-mode execution (Live I/O, Dry-Run, Mock/Sandbox).
6. **Institutional Pushout Amalgamation & Sheaf Coherence ([`gargamelle`](../../../gargamelle)):**  
   Non-destructive configuration updating is formalized as a categorical pushout ($B \amalg_C W$) over Goguen-Burstall institutions (`gargamelle-core`), preserving satisfaction conditions across merged stanzas. External verification and untrusted inspection runs are isolated within Linux namespace containers (`gargamelle-sandbox` via `/usr/bin/bwrap`). Global ecosystem consistency is audited via 1-D cellular sheaf cohomology (`gargamelle-sheaf`), where $H^1$ obstructions pinpoint boundary and dependency drifts. Monolithic SMT/CEGIS pipelines are intentionally excluded from core CLI paths to keep operations lightweight.
7. **Empirical Victim Project Crucible ([`gongju`](../../../gongju)):**  
   Validation of `gachi retrofit` and `gachi sync` is performed against real uninitialized or legacy projects—beginning with `~/src/gongju/` as the primary crucible. The retrofitted scaffolding must successfully host and verify the domain library (pure Peano type-level arity combinators and permutations) under all 5 physical verification gates.

---

## 2. Multi-Package Architecture & Ecosystem Topology

`gachi` is structured as a modular Haskell workspace conforming to the ecosystem standardization matrix:

```
gachi/
├── cabal.project
├── bin/
│   ├── gachi-verify         # 5-gate physical verification runner
│   ├── gachi-tagref         # Cross-reference integrity validator
│   ├── gachi-linkcheck      # Markdown link & anchor integrity auditor
│   ├── gachi-cloc           # CLOC comment density verification gate
│   └── generate-tags        # Symbol jumping tag generator
├── docs/
│   ├── INDEX.md             # Corpus index & reading paths
│   ├── TUTORIAL.md          # End-to-end tutorial for CLI & data structures
│   ├── NEWBIE_GUIDE.md      # Onboarding guide & token-conservation funnel
│   ├── MAINTAINER_GUIDE.md  # Architectural governance & memory invariants
│   └── notes/
│       ├── GACHI_DESIGN.md        # Canonical design monograph (D1–D8)
│       ├── IMPLEMENTATION_PLAN.md # This document
│       ├── DOC_STRATEGY.md        # Documentation policy & lifecycle rules
│       └── COMMIT_ATTRIBUTION.md  # RFC 2822 commit trailer standards
└── packages/
    ├── gachi-core/          # Unboxed osteology primitives & lock-free sync
    ├── gachi-schema/        # Dhall schemas & polytropos-dhall deserializers
    ├── gachi-pipeline/      # Kernmantle arrow Rope effect engine & swappable strands
    ├── gachi-scaffold/      # Skeleton synthesis & AST code generation
    ├── gachi-sync/          # Pushout propagation (gargamelle-core) & sheaf auditing (gargamelle-sheaf)
    ├── gachi-retrofit/      # Sandboxed overlay (gargamelle-sandbox) & diagnostic inspector
    ├── gachi-plan/          # Detached git store & snapshot rollback engine
    └── gachi-cli/           # Unified CLI executable (`gachi` / `plan-ctl`)
```

### Dependency DAG

```
                      ┌───────────────┐
                      │  gachi-core   │
                      └───────┬───────┘
                              │
                      ┌───────▼───────┐
                      │ gachi-schema  │◄─── polytropos-dhall
                      └───────┬───────┘
                              │
                      ┌───────▼───────┐
                      │gachi-pipeline │◄─── kernmantle-polytropos
                      └───────┬───────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
┌───────▼────────┐    ┌───────▼────────┐    ┌───────▼────────┐
│ gachi-scaffold │    │   gachi-sync   │    │ gachi-retrofit │
└───────┬────────┘    └───────┬────────┘    └───────┬────────┘
        │                     │                     │
        │               (gargamelle-core)    (gargamelle-sandbox)
        │              (gargamelle-sheaf)           │
        │                     │                     │
        └─────────────────────┼─────────────────────┘
                              │
                      ┌───────▼───────┐
                      │  gachi-plan   │
                      └───────┬───────┘
                              │
                      ┌───────▼───────┐
                      │   gachi-cli   │
                      └───────────────┘
```

---

## 3. Phase Breakdown & Milestone Specifications

### Phase 1: Foundational Skeleton & Osteological Memory (`gachi-core`)

**Objective:** Implement high-performance contiguous primitive memory structures and lock-free concurrency foundations.

#### Milestone 1.1: Canonical Repository Grounding [COMPLETED]
- Git repository initialization, EUPL-1.2 / Apache-2.0 dual licensing.
- GHC 9.14.1 / Cabal 3.18.1.0 build configuration with `-Wall -Wcompat -Wredundant-constraints`.
- Physical verification harness (`./bin/gachi-verify`) with 5 gates.
- Sarutahiko commit attribution trailer hooks (`.githooks/commit-msg`, `.gitmessage`).

#### Milestone 1.2: Contiguous Osteological Storage (`Gachi.Osteology`)
- **Deliverables:**
  - `OsteoSegment a`: Contiguous primitive arrays utilizing `Data.Primitive.SmallArray` with amortized geometric reallocation.
  - Zero-allocation index arithmetic: $O(1)$ dereferencing via `indexOsteo`.
  - Compile-time handles: Strongly-typed `BoneId` and `JointId` wrapper types over `Word64`.
  - Zero-copy slicing: `sliceOsteo :: Int -> Int -> OsteoSegment a -> OsteoSegment a` referencing contiguous sub-ranges without memory reallocation.
- **Invariants:**
  - Note [Osteological Contiguous Memory Layout] `[ref:note-osteology-memory-layout]`: Memory allocations must remain spatially contiguous to minimize GC traversal latency and TLB misses.
- **Verification:**
  - Hspec and QuickCheck property tests validating capacity growth invariants, bounds safety, and roundtrip element fidelity.

#### Milestone 1.3: Tagref Architecture & Notes Grounding
- Anchor formal GHC Notes in code:
  - Note [Osteological Contiguous Memory Layout] `[ref:note-osteology-memory-layout]` in `Gachi.Osteology`.
  - Note [Chattering Lock-Free Atomic Synchronization] `[ref:note-chattering-synchronization]` in `Gachi.Core`.
  - Note [Ecosystem Standardization Invariants] `[ref:note-ecosystem-standardization]` in `docs/notes/GACHI_DESIGN.md`.
- Verify zero dangling references via `./bin/gachi-tagref`.

---

### Phase 2: Declarative Project Skeleton Generator (`gachi init`)

**Objective:** Provide turnkey instantiation of standardized ecosystem repositories and packages via Dhall-parameterized schemas.

#### Milestone 2.1: Declarative Schemas (`packages/gachi-schema`)
- **Deliverables:**
  - Dhall types defining project metadata:
    ```dhall
    let Project =
      { name : Text
      , description : Text
      , license : Text
      , author : { name : Text, email : Text }
      , ghcVersion : Text
      , cabalVersion : Text
      , packages : List { name : Text, synopsis : Text, exposes : List Text }
      , remotes : List { name : Text, url : Text }
      }
    ```
  - Strongly-typed deserialization using `polytropos-dhall`'s `FromDhall` / `GenericDhall` adapters.
- **Invariants:**
  - Note [Dhall Parameterized Skeleton Templating] `[ref:note-dhall-skeleton-templating]`: All template expansions must derive from deterministic, total Dhall expressions with zero ambient filesystem or network side-effects during decoding.

#### Milestone 2.2: Workspace Scaffolding Engine (`packages/gachi-scaffold`)
- **Deliverables:**
  - Structural generators for canonical repository assets:
    - Multi-package hierarchy: `packages/<name>/src`, `packages/<name>/test`, `packages/<name>/<name>.cabal`.
    - Documentation corpus: `docs/notes/<PROJECT>_DESIGN.md`, `docs/INDEX.md`, `docs/TUTORIAL.md`, `docs/NEWBIE_GUIDE.md`, `docs/MAINTAINER_GUIDE.md`.
    - Governance & Operational loop: `PLAN.md`, `STATE.md`, `AGENTS.md`, `CLAUDE.md`, `.agents/rules/`, `.agents/skills/`.
    - Verification suite: Turnkey `bin/<project>-verify`, `bin/<project>-tagref`, `bin/<project>-linkcheck`, `bin/<project>-cloc`, `bin/generate-tags`.
    - Toolchain configurations: `cabal.project`, `cabal.project.local.example`, `.hlint.yaml`, `.gitmessage`, `.githooks/`.
- **Invariants:**
  - Note [Ecosystem Standardization Invariants] `[ref:note-ecosystem-standardization]`: Generated skeletons must satisfy all 5 physical verification gates immediately upon creation.

#### Milestone 2.3: CLI Subcommand (`gachi init`)
- **Deliverables:**
  - `gachi init [project-name]` interactive wizard.
  - Headless instantiation: `gachi init --config project.dhall [--target-dir <path>]`.
  - Automatic git initialization with `git config core.hooksPath .githooks` and `git config commit.template .gitmessage`.

---

### Phase 3: Harmonic Chattering Configuration Propagation (`gachi sync`)

**Objective:** Propagate toolchain, linter, formatting, and advisory improvements discovered in one repository across all ecosystem checkouts in lockstep.

#### Milestone 3.1: Cross-Repository Standardization Matrix (`~/src/PLAN.md` §1.A)
- **Deliverables:**
  - Shared asset catalog:
    - Code formatters: `fourmolu.yaml`, `rustfmt.toml`, `.clang-format`.
    - Linters: `.hlint.yaml` with zero-hint clean policy.
    - Git governance: `.gitmessage`, `.githooks/commit-msg`, `.githooks/pre-commit`.
    - Agent advisory layers: `AGENTS.md` core advisories, `.agents/rules/*`, `.agents/skills/*`.
    - CI workflows: Multi-forge CI pipeline definitions.
- **Invariants:**
  - Note [Ecosystem Standardization Invariants] `[ref:note-ecosystem-standardization]`: Shared configurations must remain synchronized across all active checkouts in `~/src/*` (`polytropos`, `gargamelle`, `sarutahiko`, `telix`, etc.).

#### Milestone 3.2: Differential Chattering Synchronization Engine (`packages/gachi-sync`)
- **Deliverables:**
  - SHA256 differential scanning: Compares existing workspace files against canonical master templates.
  - Institutional Pushout AST Merging ([`gargamelle-core`](../../../gargamelle)): Integrates updated common stanzas (e.g. `cabal.project` flags, `.hlint.yaml` rules) via categorical pushouts ($B \amalg_C W$) over Goguen-Burstall signatures, guaranteeing preservation of local customizations without destructive line-level clobbering.
  - CLI subcommand: `gachi sync [--dry-run] [--target <path>|--all]`.
- **Invariants:**
  - Idempotency guarantee: Executing `gachi sync` repeatedly on a clean repository results in a no-op ($f(f(x)) = f(x)$).

#### Milestone 3.3: Forge-Tiered CI Matrix Synthesizer
- **Deliverables:**
  - Automated generation of forge-specific CI files tailored to runner resource constraints:
    - **High-Resource (GitHub Actions):** Full physical verification, compilation of all packages with `--enable-tests`, haddock documentation coverage, tagref verification, literate doccheck.
    - **Resource-Constrained (GitLab, Framagit, Disroot):** Lightweight static gates only (Tagref 0 dangling references, Linkcheck 0 broken links, CLOC comment density audit).
- **Invariants:**
  - Prevents resource exhaustion on self-hosted community runners while maintaining strict upstream verification gates.

#### Milestone 3.4: Multi-Remote Topology Management
- **Deliverables:**
  - Automatic auditing and configuration of standard multi-mirror remotes:
    - `rad` (Radicle peer-to-peer identity).
    - `github`, `gitcode`, `framagit`, `disroot`.
  - Exclusion filter for non-compliant hosting providers (e.g. SourceHut).

#### Milestone 3.5: Cellular Sheaf Coherence Auditor (`gachi doctor --sheaf`)
- **Deliverables:**
  - 1-D cellular sheaf model over `~/src/*` implemented via [`gargamelle-sheaf`](../../../gargamelle):
    - Vertices ($V$): Repositories (`polytropos`, `gargamelle`, `sarutahiko`, `gachi`, `gongju`).
    - Edges ($E$): Shared version and standardization contracts.
    - Stalks ($\mathcal{F}$): Configuration states.
    - Coboundary Operator ($\delta^0$): Discrepancies along boundary contracts.
  - $H^0$ harmonic equilibrium check: Reports 0 drift when all checkouts satisfy ecosystem contracts.
  - $H^1$ cohomology obstruction localization: Pinpoints exact repositories and drifting interface contracts.

---

### Phase 4: Non-Destructive Project Retrofitting Engine (`gachi retrofit`)

**Objective:** Adopt legacy, single-package, or external repositories into the canonical ecosystem skeleton non-destructively.

#### Milestone 4.1: Diagnostic Repository Inspector (`packages/gachi-retrofit`)
- **Deliverables:**
  - Automated repository scanner analyzing:
    - Primary languages (Haskell, Rust, C/C++, Python).
    - Build systems (`cabal.project`, `stack.yaml`, `Cargo.toml`, `Makefile`).
    - Existing test infrastructure and coverage.
    - Documentation gaps relative to `DOC_STRATEGY.md`.
    - Git hook and commit attribution conformance.

#### Milestone 4.2: Non-Destructive Overlay & Sandboxed Execution (`packages/gachi-retrofit`)
- **Deliverables:**
  - Profunctor Arrow Rope Engine ([`kernmantle-polytropos`](../../../kernmantle)): Retrofit stages are composed as independent effect strands woven into a `Rope`:
    - `StrandDiagnostic`: Read workspace files, probe tools.
    - `StrandPushoutMerge`: Amalgamate configs via `gargamelle-core`.
    - `StrandSandboxExec`: Run verification in disposable Linux namespaces (`gargamelle-sandbox` via `/usr/bin/bwrap`).
    - `StrandMutation`: Write out synthesized assets.
    - `StrandVerify`: Execute `./bin/<project>-verify`.
  - Turnkey overlay installer:
    - Scaffolds missing `docs/INDEX.md`, `docs/notes/`, `docs/MAINTAINER_GUIDE.md`.
    - Injects `AGENTS.md` and symlinks (`CLAUDE.md`, `.hermes.md`).
    - Installs `.githooks/` and `.gitmessage`.
    - Generates customized `bin/<project>-verify` and helper scripts.
- **Invariants:**
  - Note [Non-Destructive Skeleton Overlay] `[ref:note-nondestructive-retrofit]`: Retrofitting operations must never delete, overwrite, or mutate domain logic source files (`src/`, `app/`, `lib/`).

#### Milestone 4.3: Progressive Quality Gate Remediation
- **Deliverables:**
  - Incremental remediation pipelines:
    - Level 0: Scaffolding and verification scripts installed.
    - Level 1: Tagref cross-references and Markdown links validated.
    - Level 2: Build warnings cleaned under `-Wall -Wcompat`.
    - Level 3: HLint hints completely eliminated (zero-hint policy).

#### Milestone 4.4: Empirical Victim Project Crucible: `~/src/gongju/`
- **Deliverables:**
  - Primary external validation target: [`~/src/gongju/`](../../../gongju) ("tools/implement").
  - Automated retrofitting: Scaffold uninitialized repository into standard single-package/multi-package workspace.
  - Domain implementation validation: Implement and verify the pure Peano type-level utility functions from `gemini-type-level-utility-functions.pdf`:
    - `Gongju.Peano`: `Peano`, `ToPeano`, `FromPeano`.
    - `Gongju.Composition`: `ComposeN` (`compN @n`), `FmapN` (`fmapN @n`).
    - `Gongju.Positional`: `Yank` (`slipr @n`), `Shove` (`slipl @n`), `Twist` (`twist @n`).
    - `Gongju.Permute`: Curried argument permutation `Permute` (`permute @'[2, 0, 1]`) via iterated `Yank` and `Adjust`.
  - Verification: Complete passage of all 5 physical verification gates (`bin/gongju-verify`).

---

### Phase 5: Ecosystem Plan Governance & Rollback (`gachi plan` / `plan-ctl`)

**Objective:** Implement deterministic point-in-time recovery, delta tracking, and rollback for ecosystem-wide planning files (`~/src/PLAN.md`, `~/src/STATE.md`).

#### Milestone 5.1: Detached Git Store Architecture (`packages/gachi-plan`)
- **Deliverables:**
  - Isolated Git repository management:
    - Path: `/home/nyc/src/.plan.git` (or configured via environment `PLAN_GIT_DIR`).
    - Work tree: `/home/nyc/src` (`--work-tree=/home/nyc/src`).
    - Scope: Exclusively tracks `PLAN.md`, `STATE.md`, and top-level governance documentation.
- **Invariants:**
  - Note [Plan Governance and Rollback Mechanics] `[ref:note-plan-governance-rollback]`: The detached Git store must remain completely separate from child git checkouts (`~/src/gachi/.git`, `~/src/polytropos/.git`), avoiding nested git repository collisions.

#### Milestone 5.2: Append-Only Snapshot Ledger
- **Deliverables:**
  - Pre-mutation snapshot manager writing to `~/src/plans/snapshots/`:
    - File naming: `YYYY-MM-DD-HHMMSS-PLAN.md`.
    - Integrity sidecar: companion `.sha256` digest verifying byte-level fidelity.
  - Automated pruning policy: Retains recent snapshots while preserving milestone checkpoints indefinitely.

#### Milestone 5.3: CLI Subcommands (`gachi plan` / `plan-ctl`)
- **Deliverables:**
  - `gachi plan checkpoint [message]`: Commits active planning files to the detached store and writes a snapshot ledger entry.
  - `gachi plan diff [ref]`: Displays semantic unified diff between working plan and specified revision.
  - `gachi plan log`: Renders chronological commit history of planning decisions with commit trailers.
  - `gachi plan rollback <checkpoint>`: Atomically restores `PLAN.md` and `STATE.md` to a chosen historical checkpoint.
  - `gachi plan status`: Reports dirty state and divergence between working plan files and detached repository HEAD.

---

### Phase 6: Lock-Free Chattering Concurrency & Graph Transformations

**Objective:** Complete the high-performance osteological computation engine with lock-free atomic concurrency and double-pushout algebraic rewriting.

#### Milestone 6.1: Atomic Bone State Machines (`Gachi.Core`)
- **Deliverables:**
  - Lock-free atomic synchronization for joint transitions.
  - Single-instruction compare-and-swap (CAS) primitives on joint state references.
  - Exponential backoff retry protocol for contending threads, ensuring wait-free progression for read traversals.
- **Invariants:**
  - Note [Chattering Lock-Free Atomic Synchronization] `[ref:note-chattering-synchronization]`: State progression across skeletal joints must remain strictly lock-free and immune to deadlocks and priority inversions.

#### Milestone 6.2: Multi-Agent Concurrent Traversal
- **Deliverables:**
  - Concurrent traversal engine allowing multiple agents to query and navigate osteological graphs simultaneously without acquiring global read/write locks.

#### Milestone 6.3: Double-Pushout (DPO) Algebraic Graph Rewriting
- **Deliverables:**
  - Formal category-theoretic rewriting rules ($L \leftarrow K \rightarrow R$) over osteological bone graphs.
  - Integration with `gargamelle` rewriting and pattern-matching engines.

#### Milestone 6.4: Polytropos Zero-Cost Coercions
- **Deliverables:**
  - Zero-copy mapping between `OsteoSegment` contiguous arrays and `polytropos-core` flat `Rep` structures.
  - Bidirectional type-safe conversions between osteological bone payloads and polytropos open sums/products.

---

## 4. Verification & Testing Strategy

Quality assurance in `gachi` is enforced through continuous physical verification:

### 4.1 The 5 Physical Verification Gates (`./bin/gachi-verify`)
1. **Gate 1: HLint Static Analysis:** Zero hints allowed across all source packages under `.hlint.yaml`.
2. **Gate 2: Full Cabal Test Suite:** All Hspec, QuickCheck, and Tasty assertions must pass with zero failures.
3. **Gate 3: Tagref Cross-Reference Gate:** Zero dangling references and zero duplicate tags verified across all repository files via `./bin/gachi-tagref`.
4. **Gate 4: Markdown Link & Anchor Integrity:** Every intra-corpus relative link and anchor slug must resolve cleanly via `./bin/gachi-linkcheck`.
5. **Gate 5: CLOC Comment Density Gate:** Comment density must satisfy strict documentation thresholds (minimum 30% overall, 45%+ in library source directories) via `./bin/gachi-cloc`.

### 4.2 Property-Based & Differential Testing
- **Capacity & Bounds Testing:** QuickCheck generators testing `OsteoSegment` append sequences, random indexing, and resize boundaries.
- **Idempotence Property Testing:** Automated tests verifying that running `gachi sync` twice produces zero filesystem deltas.
- **Rollback Invariant Verification:** Automated tests verifying that modifying `PLAN.md`, recording a checkpoint, rolling back, and checking SHA256 hashes produces identical byte streams.

### 4.3 Benchmarking & Memory Overhead
- Micro-benchmarks under `tasty-bench` / `criterion` comparing:
  - Lookup latency: `OsteoSegment` ($O(1)$ contiguous array) vs `Data.Map` ($O(\log N)$ tree).
  - Allocation overhead: GHC GC scavenge duration under 100,000 nodes.
  - Lock-free CAS throughput under varying concurrency contention levels.

---

## 5. Risk Matrix & Mitigations

| Risk | Trigger | Impact | Engineering Mitigation |
|---|---|---|---|
| **Dhall Template Drift** | Upstream toolchain updates (e.g. GHC 9.16) invalidate generated stanzas | Newly generated skeletons fail verification gates | Pinned Dhall schemas with automated CI regression testing against multiple GHC targets. |
| **Sync Clobbering** | `gachi sync` overwrites intentional local repository customizations | Developer frustration; loss of project-specific configurations | AST-aware differential merging; explicit exemption stanzas in `.gachi-ignore`. |
| **Detached Git Collisions** | Running `gachi plan` inside child repo with misconfigured environment | Child `.git/` history polluted with plan commits | Explicit validation of `--git-dir` and `--work-tree` paths before executing any git operations. |
| **Cache Invalidation in Osteology** | Resizing contiguous arrays under concurrent reads | Stale reads or memory faults in lock-free reader agents | Copy-on-write segment freezing; old segment arrays remain valid and GC-managed until all reader references drop. |
| **Link Slugification Desynchronization** | GitHub Markdown slugifier rules diverge from custom regex | Broken links reported in CI gates | Strict adherence to GitHub slugification semantics in `bin/gachi-linkcheck` (retaining `&`, stripping punctuation). |

---

## 6. Document History & Revision Register

| Version | Date | Author / Agent | Changes |
|---|---|---|---|
| **v1.0** | 2026-10-24 | Antigravity (Google / gemini-3.8-pro) | Initial canonical implementation plan establishing Phases 1–6, multi-package architecture, verification gates, and risk mitigations. |
| **v1.1** | 2026-10-24 | Antigravity (Google / gemini-3.8-pro) | Integrate kernmantle-polytropos effect pipeline architecture, selective gargamelle integration (pushouts, sandbox, sheaf coherence), and adopt ~/src/gongju/ as the victim project crucible. |
| **v1.2** | 2026-10-25 | Antigravity (Google / gemini-3.8-pro) | Record deferred tooling & exploration workqueue (§7) covering updo, shake, okf, pandoc, dhall-haskell, and codec substrates. |

---

## 7. Deferred Tooling & Exploration Workqueue

The following architectural investigations and external integrations are formally logged in our long-term research workqueue to evaluate as the ecosystem evolves:

1. **`~/src/updo/` (Dhall-Parameterized Project Generation & Upgrades):**
   - **Scope:** Evaluate `updo`'s package dependency constraint solver, multi-version GHC upgrade matrix (`ghc-version-projects.mk`, `ghc-upgrade-projects.mk`), and Dhall-based package specifications (`types.dhall`, `package.dhall`).
   - **Integration Point:** Potential synergy with `gachi sync` (Milestone 3.2) and `gachi retrofit` (Phase 4) for dependency constraint reconciliation and automated GHC upgrade migrations.
2. **`~/src/shake/` (Monadic Dynamic Dependency Build System):**
   - **Scope:** Evaluate Shake's dynamic dependency graph scheduling, suspension, and incremental file caching for high-speed cross-repository synchronization.
   - **Integration Point:** Potential execution engine underneath `gachi sync` and `gachi doctor --sheaf` when auditing hundreds of interconnected files across `~/src/*`.
3. **`~/src/okf/` (Profunctor Document & Frontmatter Pipelines):**
   - **Scope:** Investigate `okf-core`'s document representations, YAML frontmatter codecs, and profunctor pipeline transformations.
   - **Integration Point:** Advanced document generation pipelines in `Gachi.Scaffold.Markdown` when bridging structured frontmatter with rich GFM bodies.
4. **`~/src/pandoc/` (Bidirectional Document AST Bridging):**
   - **Scope:** General Pandoc AST bridge allowing lossless roundtripping between Polytropos records, Dhall models, and arbitrary document targets (PDF, LaTeX, HTML, EPUB).
   - **Integration Point:** Defer full Pandoc dependency to an opt-in satellite package to preserve `gachi-scaffold`'s lean, zero-transitive-dependency footprint.
5. **`~/src/dhall-haskell/` (Template Haskell Lift Fixes & Dhall Markdown Rendering):**
   - **Scope:** Maintain local fork patches for the Template Haskell `Lift` instance error in `dhall 1.42.3` under GHC 9.14; explore native Dhall AST to Markdown rendering expressions.
   - **Integration Point:** Upstream contribution or mirror across Disroot, Framagit, GitCode, and Radicle.
6. **`~/src/codec/` & `~/src/binary-bits/` (Profunctor Codecs & Bit-Level Serialization):**
   - **Scope:** Evaluate profunctor codecs for zero-copy binary serialization of osteological state snapshots (`gachi plan`) and network replication.
   - **Integration Point:** Low-level storage encoding in `packages/gachi-plan` and `packages/gachi-core`.
