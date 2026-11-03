# gachi — がちがち

> **gachi** (*onomatopoeia* がちがち): The sharp, rhythmic clicking and chattering of the teeth of a *gashadokuro* (がしゃどくろ) — the colossal mythical skeleton formed from the spirits of those fallen in famine and battle.
>
> When the gashadokuro approaches, its towering bones vibrate in ominous unison, emitting the rhythmic *gachi-gachi* cadence that warns all in its shadow of an unyielding, unified presence. In Japanese colloquial idiom, がち (*gachi*) conveys seriousness, steadfastness, and unshakeable resolve; in Korean, 가치 (*gachi*) signifies intrinsic value and worth, while 같이 (*gachi*) expresses unity, togetherness, and acting in lockstep synchrony.

In our software engineering ecosystem, `gachi` is the **Project Skeleton & Configuration Propagation Infrastructure** across `~/src/*` (governed by `~/src/PLAN.md` §1), paired with an unboxed, high-performance osteological computation substrate.

Just as a biological skeleton forms the rigid, immutable osseous scaffold that preserves anatomical integrity, `gachi` establishes and guarantees the canonical structural skeletons of our repositories. And just as the teeth of the gashadokuro chatter in rapid harmonic resonance, `gachi` propagates formatting standards, linter rules, git hooks, CI matrices, and agent advisory contexts across all ecosystem repositories in lockstep.

---

## Architectural Vision & Core Invariants

`gachi` reconciles two foundational engineering obligations:

1. **The Osteological Memory Substrate:**
   High-performance symbolic and structural computation demands flat, contiguous, unboxed representations. Standard Haskell recursive algebraic data types (trees, linked lists, pointer-heavy graphs) incur severe pointer-indirection overhead and GC traversal pressure. `gachi-core` provides flat contiguous slices (`OsteoSegment`, `OsteoBytes`) backed by GHC primitive `SmallArray#` and `ByteArray#`, paired with compile-time bone indices, lock-free chattering state machines, double-pushout (DPO) algebraic graph transformations, and zero-cost coercions to `polytropos-core` representations.

2. **The Sovereign Ecosystem Infrastructure:**
   A multi-repository ecosystem quickly suffers from configuration drift, fragmented linter rules, rotting CI configurations, and inconsistent agent advisories. `gachi` acts as the sovereign ecosystem governor:
   - Declaratively initializes new multi-package repositories from Dhall schemas (`gachi init`).
   - Propagates shared governance assets and linter rules across checkouts in lockstep (`gachi sync`).
   - Non-destructively retrofits legacy and single-package codebases into the canonical hierarchy (`gachi retrofit`).
   - Governs strategic ecosystem planning documents with detached Git stores and snapshot ledgers (`gachi plan`).

---

## Subsystem Architecture & Package Catalog

The `gachi` codebase is organized into seven modular packages:

```
packages/
  ├── gachi-core/        -- Contiguous osteology, lock-free CAS, DPO graph rewriting, Polytropos coercions
  ├── gachi-schema/      -- Declarative Dhall schemas, project decoders, and Polytropos row isomorphisms
  ├── gachi-scaffold/    -- Workspace generator, template synthesis, CI matrix & verification harness builder
  ├── gachi-sync/        -- Ecosystem audit engine, asset catalog, and differential propagation engine
  ├── gachi-retrofit/    -- 6-pillar diagnostic scanner, non-destructive overlay, and Penelope effect pipeline
  ├── gachi-plan/        -- Detached Git metadata store (~/.plan.git), snapshot ledger, and rollback engine
  └── gachi-cli/         -- Unified command-line interface driver and subcommand dispatcher
```

### 1. `gachi-core` — High-Performance Osteological Computing
- **Contiguous Layouts:** `OsteoSegment a` and `OsteoBytes` encapsulate contiguous unboxed slices with $O(1)$ zero-copy slicing via pure pointer offset windows (`sliceOsteo`).
- **Amortized Geometric Growth:** Dynamic bone appending with amortized $O(1)$ reallocations (`appendOsteo`).
- **Monotonic Indexing:** `BoneId` and `JointId` are unboxed integer handles mapping directly to array offsets without hashing or search trees.
- **Lock-Free Chattering Concurrency:** `BoneMachine` and `Gachi.Core.Atomic` implement atomic state transitions over bone graphs via CAS loops and compare-and-swap primitives.
- **Double-Pushout (DPO) Graph Rewriting:** Categorical graph transformation in the adhesive category $\mathbf{Graph}_{\text{osteo}}$ via production rules $L \stackrel{l}{\hookleftarrow} K \stackrel{r}{\hookrightarrow} R$, verifying pushout complement existence before atomic materialization.
- **Polytropos Zero-Cost Coercions:** Bidirectional algebraic isomorphisms between `OsteoSegment (f Any)` and Polytropos `Rep f a` (`segmentToRep`, `repToSegment`, `bonePayloadToRecord`, `recordToBonePayload`) with zero linked-list allocation detours.

### 2. `gachi-schema` — Declarative Dhall Specifications
- Declarative project manifests written in Dhall, validated by `polytropos-dhall` and `polytropos-core`.
- Type-safe decoding into `Project`, `Package`, `Author`, `License`, and forge specifications.
- Bijective conversions between nominal record models and structural open records.

### 3. `gachi-scaffold` — Workspace Scaffolding & CI Synthesis
- Generates canonical multi-package repository trees: `packages/<name>/<name>.cabal`, `cabal.project`, `cabal.project.local.example`.
- Materializes documentation hierarchies: `README.md`, `PLAN.md`, `STATE.md`, `docs/INDEX.md`, `docs/TUTORIAL.md`, `docs/NEWBIE_GUIDE.md`, `docs/MAINTAINER_GUIDE.md`, `docs/notes/DOC_STRATEGY.md`, `docs/notes/COMMIT_ATTRIBUTION.md`.
- Generates forge-tiered CI matrices for GitHub Actions (`.github/workflows/ci.yml`) and GitLab CI (`.gitlab-ci.yml`) testing across GHC versions.
- Provisions turnkey 5-gate verification harnesses (`bin/<project>-verify`, `bin/<project>-tagref`, `bin/<project>-linkcheck`, `bin/<project>-cloc`, `bin/generate-tags`) with POSIX executable permissions (`+x`).

### 4. `gachi-sync` — Chattering Configuration Synchronization
- Maintains the canonical shared asset catalog (`Gachi.Sync.Catalog`): `.hlint.yaml`, `fourmolu.yaml`, `.gitmessage`, `.githooks/commit-msg` (Sarutahiko RFC 2822 trailer validation), `.githooks/pre-commit`, and AI agent guidance (`AGENTS.md`, `.agents/rules/`).
- Computes structural diffs across all checkouts in `~/src/*` without overwriting repository-specific code.
- Audits remote replication topologies (`gachi sync --remotes`) across five canonical remotes: Radicle (`rad`), GitHub, GitCode, Framagit, and Disroot.

### 5. `gachi-retrofit` — Non-Destructive Codebase Retrofitting
- **6-Pillar Static Inspection:** Pure read-only diagnosis across Languages, Build Systems, Test Infrastructure, Documentation Gaps (`DOC_STRATEGY.md`), Git Governance, and Verification Harnesses.
- **Quantitative Retrofit Scoring:** Computes an ecosystem readiness score $S(P) \in [0.0, 100.0]$ with prioritized remediation recommendations.
- **Non-Destructive Skeleton Overlay:** Synthesizes missing ecosystem assets while strictly preserving all existing domain logic in `src/`, `app/`, `test/`.
- **Penelope Arrow Pipeline Integration:** Models the retrofit analysis, plan construction, sandboxed execution, and disk materialization as an extensible polycategorical arrow pipeline (`PenelopeRope '[] '[]` / `P.Rope`) powered by `penelope-core` and `gargamelle-sandbox`.
- **Progressive Quality Gate Realization:** Evaluates monotonic compliance progression from Level 0 (Foundation) through Level 1 (Structural Integrity), Level 2 (Compiler Discipline), and Level 3 (Static Analysis Purity).

### 6. `gachi-plan` — Ecosystem Plan Governance & Rollback
- Governs strategic planning documents (`~/src/PLAN.md`, `~/src/STATE.md`).
- Operates a detached Git metadata store located at `~/src/.plan.git` (completely isolated from child repository `.git` directories).
- Maintains an append-only snapshot ledger (`~/src/plans/snapshots/`) with SHA256 integrity checksums.
- Enables instantaneous diffing (`gachi plan diff`), checkpointing (`gachi plan checkpoint`), and atomic rollback (`gachi plan rollback`).

### 7. `gachi-cli` — Unified Command-Line Driver
- Ergonomic CLI parsing via `optparse-applicative` with unified terminal dashboards and GitHub-Flavored Markdown report formatting.

---

## Memory Physics & Osteological Substrate

Conventional Haskell data structures represent abstract trees as nested pointer graphs:

```
[Traditional Linked/Tree Representation]
  Node ──> [ Thunk / Indirection Pointer ] ──> Heap Header ──> Payload
       ──> [ Thunk / Indirection Pointer ] ──> Heap Header ──> Payload
  Result: Cache misses, nursery fragmentation, GC traversal overhead.

[Gachi Osteological Contiguous Layout]
  OsteoSegment:
  ┌──────┬────────┬────────┬────────┬────────┬────────┐
  │ Tag# │ Bone 0 │ Bone 1 │ Bone 2 │ Bone 3 │ Bone 4 │ ... contiguous SmallArray#
  └──────┴────────┴────────┴────────┴────────┴────────┘
  Result: Single cache-line residency, zero pointer chasing, O(1) window slicing.
```

### Memory Layout Metrics

| Feature | Linked List (`[a]`) | Traditional AST (`Tree a`) | Gachi `OsteoSegment a` |
| :--- | :--- | :--- | :--- |
| **Heap Allocations per Node** | 1 cons-cell (2 words) | 1 constructor (3+ words) | **0** (flat contiguous array) |
| **Pointer Indirections** | Linear $O(N)$ | Logarithmic $O(\log N)$ | **$O(1)$** direct offset index |
| **Sub-Segment Slicing** | $O(K)$ allocation copy | Subtree traversal | **$O(1)$** pointer window slice |
| **GC Nursery Pressure** | Extreme | Moderate | **Minimal** (single array object) |
| **Polytropos Interop** | $O(N)$ translation | Custom traversal | **$O(1)$** zero-cost memory coercion |

---

## Category-Theoretic Graph Transformations (DPO)

Structural transformations of osteological rigs are expressed categorically via Double-Pushout (DPO) rewriting in the adhesive category $\mathbf{Graph}_{\text{osteo}}$:

```
       l           r
  L  <────  K  ─────>  R       (Production Rule P)
  │         │          │
m │ (PO 1)  │  (PO 2)  │
  ▼         ▼          ▼
  G  <────  D  ─────>  H       (Host Graph Rewrite)
       k           g
```

1. **Rule Definition:** A production $p = (L \stackrel{l}{\hookleftarrow} K \stackrel{r}{\hookrightarrow} R)$ specifies a pattern $L$ to match, an invariant interface $K$ to preserve, and replacement structure $R$ to insert.
2. **Pushout Complement (PO 1):** Given a valid match morphism $m : L \to G$, `gachi-core` verifies the **Dangling Condition** (no joint in $G \setminus m(L)$ is left incident to an erased bone in $m(L \setminus l(K))$) and the **Identification Condition** before constructing the unique pushout complement $D$.
3. **Pushout Materialization (PO 2):** Computes pushout $H = D +_K R$, materializing the rewritten osteological graph atomically with guaranteed topological consistency.

---

## CLI Command Reference

```bash
# Initialize a new standardized multi-package repository from a Dhall specification
gachi init project.dhall

# Audit configuration drift across all ~/src/* repositories
gachi sync --check

# Propagate canonical linters, hooks, and agent rules across all checkouts
gachi sync --all

# Audit and reconcile remote URLs against the 5-remote replication topology
gachi sync --remotes

# Diagnose an existing codebase against the 6-pillar ecosystem standard
gachi retrofit --target /path/to/repo --dry-run

# Apply non-destructive skeleton overlay and install verification harnesses
gachi retrofit --target /path/to/repo

# Create an immutable planning checkpoint for ~/src/PLAN.md
gachi plan checkpoint "Refine milestone specifications"

# View diff between active planning state and prior checkpoint
gachi plan diff HEAD~1

# Restore an earlier strategic planning state atomically
gachi plan rollback <checkpoint-sha>

# Run ecosystem-wide health audit and cellular sheaf coherence verification
gachi doctor --sheaf
```

---

## The 5-Gate Physical Verification Discipline

Every repository governed by `gachi` provisions and runs a deterministic 5-gate physical verification harness (`./bin/<project>-verify`):

```bash
./bin/gachi-verify
```

1. **HLint Static Analysis:** Zero hints enforced (`0 hints` policy) across all source modules under `.hlint.yaml`.
2. **Full Cabal Test Suite:** All test assertions pass cleanly with 0 failures under `-Wall -Wcompat -Wredundant-constraints`.
3. **Tagref Cross-Reference Gate:** Zero dangling references and zero duplicate tags across code, design monographs, and documentation.
4. **Markdown Link & Anchor Integrity Gate:** Zero broken intra-corpus markdown links or relative file anchors.
5. **CLOC Comment Density Gate:** Continuous monitoring maintaining the **50%+ comment density target** on domain source code.

---

## Documentation Corpus & Reading Paths

The documentation is organized per [`docs/notes/DOC_STRATEGY.md`](docs/notes/DOC_STRATEGY.md) into purpose-built genres serving four distinct audiences:

1. **[`docs/INDEX.md`](docs/INDEX.md)** — Comprehensive corpus inventory, authority matrix, and reading map.
2. **[`docs/TUTORIAL.md`](docs/TUTORIAL.md)** — Step-by-step interactive 9-lesson tutorial track.
3. **[`docs/NEWBIE_GUIDE.md`](docs/NEWBIE_GUIDE.md)** — Onboarding funnel, token-conservation rules, and fast symbol navigation.
4. **[`docs/MAINTAINER_GUIDE.md`](docs/MAINTAINER_GUIDE.md)** — Architectural invariants (I1–I10), cellular sheaf coherence ($H^0, H^1$), and triage runbooks.
5. **[`docs/notes/GACHI_DESIGN.md`](docs/notes/GACHI_DESIGN.md)** — Canonical design monograph: architectural decisions D1–D10.
6. **[`docs/notes/DOC_STRATEGY.md`](docs/notes/DOC_STRATEGY.md)** — Documentation policies, authority tiers, and the Section 4 precedence rule.
7. **[`docs/notes/COMMIT_ATTRIBUTION.md`](docs/notes/COMMIT_ATTRIBUTION.md)** — Linux kernel RFC 2822 commit trailer attribution standards.
8. **[`AGENTS.md`](AGENTS.md)** — Advisory guidance and modular operational rules for AI coding assistants.

---

## Quick Start & Verification

### Toolchain Requirements
- GHC 9.14.1
- Cabal 3.18.1.0+

### Building & Running Verification
```bash
# Build all 7 packages
cabal build all

# Run full test suite across all 7 packages
cabal test gachi-core gachi-schema gachi-scaffold gachi-cli gachi-sync gachi-retrofit gachi-plan

# Run 5-gate physical verification harness
./bin/gachi-verify
```

---

## Contributing & AI Pair Programming

All commits adhere to the Linux kernel RFC 2822 trailer format with `Assisted-by:` trailers.
AI assistants must never be credited as `Co-authored-by:` or `Signed-off-by:`.
See [`AGENTS.md`](AGENTS.md) and [`docs/notes/COMMIT_ATTRIBUTION.md`](docs/notes/COMMIT_ATTRIBUTION.md).

## License

European Union Public Licence (EUPL-1.2). See [`LICENSE`](LICENSE).
