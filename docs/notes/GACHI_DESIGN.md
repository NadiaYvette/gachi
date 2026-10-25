# GACHI_DESIGN.md — Architectural Decisions, Memory Invariants & Ecosystem Governance

Canonical design monograph for `gachi`.

---

## 1. Design Vision & Mythological Metaphor

`gachi` (がちがち) takes its name from the ominous onomatopoeia describing the clicking and chattering teeth of a *gashadokuro* (がしゃどくろ) — the giant skeletal phantom of Japanese legend, assembled from the collected bones of those fallen in battle and famine.

In software systems engineering, two chronic failure modes plague multi-repository ecosystems:
1. **Structural Drift & Fragmentation:** Independent repositories drift in workspace conventions, linting rules, formatting profiles, CI workflows, and agent advisory contexts. Without an authoritative structural skeleton, each repository develops idiosyncratic, brittle build harnesses.
2. **High-Overhead Pointer Topologies:** Hierarchical heap-allocated pointer graphs incur severe CPU cache misses, TLB thrashing, and GHC GC mark-and-sweep latency.

`gachi` resolves both failures through two complementary faces of the same metaphor:
* **The Skeleton (Osteological Rigidity):** An unyielding, declarative repository skeleton generator (`gachi init`) and unboxed contiguous memory model (`gachi-core`). Repositories share a bone-rigid, standardized architectural framework (multi-package DAGs, `packages/`, `docs/`, `bin/`, `.githooks/`).
* **The Chattering (*gachi-gachi* Synchronization):** Rhythmic, high-speed harmonic synchronization (`gachi sync`) that propagates formatting improvements, linter guardrails, git hooks, and agent guidance across all interconnected repositories in lockstep.

---

## 2. Canonical Architectural Decisions

### D1: Contiguous Unboxed Osteology (`SmallArray#` / `ByteArray#`)
- **Decision:** Structural nodes and edges are stored within flat, contiguous primitive arrays indexed by strictly typed bone handles (`BoneId`, `JointId`).
- **Rationale:** Flat array indexing eliminates pointer indirection, preserves L1/L2 CPU cache locality, and completely relieves GHC GC traversal overhead.
- **Reference:** Note [Osteological Contiguous Memory Layout] `[ref:note-osteology-memory-layout]`

### D2: Lock-Free Chattering State Synchronization
- **Decision:** Concurrency across osteological joints is governed by atomic compare-and-swap (CAS) primitives and optimistic read-copy-update semantics rather than mutexes.
- **Rationale:** Lock-free state progression guarantees race-freedom, immunity to deadlocks, and bounded latency.
- **Reference:** Note [Chattering Lock-Free Atomic Synchronization] `[ref:note-chattering-synchronization]`

### D3: Declarative Skeleton Generation via `polytropos-dhall` (`gachi init`)
- **Decision:** Repository and package schemas are authored in typed Dhall expressions and decoded into osteological structures via `polytropos-dhall` generic adapters (`GenericDhall` / `FromDhall`).
- **Rationale:** Dhall provides total, deterministic, hermetic configuration without Turing-complete vulnerabilities, while `polytropos-dhall` delivers direct linear unrolling into flat memory without intermediate binary tree allocations.
- **Reference:** Note [Dhall Parameterized Skeleton Templating] `[ref:note-dhall-skeleton-templating]`

### D4: Harmonic Chattering Propagation across `~/src/*` (`gachi sync`)
- **Decision:** Upstream improvements discovered in one repository are propagated idempotently across all ecosystem checkouts (`polytropos`, `gargamelle`, `sarutahiko`, `telix`, etc.) via differential file hashing.
- **Scope:** Covers code formatters (Fourmolu, Ormolu, rustfmt), static analysis (`.hlint.yaml`), git governance (`.gitmessage`, `.githooks/`), and agent guidance (`AGENTS.md`, `.agents/rules/`, `.agents/skills/`).
- **Reference:** Note [Ecosystem Standardization Invariants] `[ref:note-ecosystem-standardization]`

### D5: Non-Destructive Repository Retrofitting (`gachi retrofit`)
- **Decision:** When retrofitting existing or external codebases into the ecosystem standard, `gachi` overlays the canonical skeleton non-destructively: preserving domain source files while installing the missing documentation hierarchy, git hooks, and verification harnesses.
- **Reference:** Note [Non-Destructive Skeleton Overlay] `[ref:note-nondestructive-retrofit]`

### D6: Detached Git Store & Snapshot Ledger for Plan Rollback (`gachi plan`)
- **Decision:** Ecosystem planning files (`~/src/PLAN.md`, `~/src/STATE.md`) are version-controlled via an isolated detached Git repository (`--git-dir=/home/nyc/src/.plan.git --work-tree=/home/nyc/src`) and an append-only pre-mutation snapshot ledger (`~/src/plans/snapshots/`) with SHA256 checksums.
- **Rationale:** Maintains complete commit history, diffing, and atomic rollback capability without creating a nested `~/src/.git` that would conflict with child project repositories.
- **Reference:** Note [Plan Governance and Rollback Mechanics] `[ref:note-plan-governance-rollback]`

### D7: Strict Separation of Structural Rigidity and Dynamic Payload
- **Decision:** Osteological bone graphs maintain fixed topological rigidity. Dynamic attributes and payloads attach via secondary flat arrays or typed indices.
- **Rationale:** Decoupling topology from mutable payload permits zero-copy structural transformations without rewriting attribute tables.

### D8: Zero-Warning Compiler Verification & Precedence
- **Decision:** Every package compiles under `-Wall -Wcompat -Wredundant-constraints` and `-Werror`.
- **Precedence Rule:** Per `DOC_STRATEGY.md` §4, code wins at runtime; when code changes contradict this document, this document must be corrected in the same commit.

---

## 3. Grounded Notes Architecture

- **Note [Osteological Contiguous Memory Layout]** (`Gachi.Osteology`) [ref:note-osteology-memory-layout]:
  Defines flat memory layout invariants, alignment boundaries, zero-allocation indexing, and GC minimization.
- **Note [Zero-Copy Sub-Segment Slicing]** (`Gachi.Osteology`) [ref:note-zero-copy-slicing]:
  Specifies pure O(1) pointer-windowed sub-segment slicing without heap array reallocations.
- **Note [Geometric Capacity Expansion and Reallocation]** (`Gachi.Osteology`) [ref:note-geometric-capacity-expansion]:
  Specifies amortized O(1) doubling discipline for dynamic bone/node appending.
- **Note [Chattering Lock-Free Atomic Synchronization]** (`Gachi.Core`) [ref:note-chattering-synchronization]:
  Details lock-free CAS mechanics, optimistic concurrency retry loops, and atomic state transitions.
- **Note [Monotonic Identifier Allocation and Contiguous Indexing]** (`Gachi.Core`) [ref:note-monotonic-id-allocation]:
  Establishes contiguous 1:1 identity mapping between monotonically allocated 64-bit identifiers and array offsets.
- **Note [Directional Joints and Incident Traversal]** (`Gachi.Core`) [ref:note-directional-joints-traversal]:
  Specifies directed multigraph connections and sequential incident edge resolution across contiguous segments.
- **Note [Ecosystem Standardization Invariants]** (`Gachi.Scaffold`) [ref:note-ecosystem-standardization]:
  Defines cross-project invariants for workspace layout, formatters, linters, git hooks, and agent advisory layers across `~/src/*` per `~/src/PLAN.md` §1.A.
- **Note [Dhall Parameterized Skeleton Templating]** (`Gachi.Schema`) [ref:note-dhall-skeleton-templating]:
  Specifies the Dhall configuration schema and code-generation rules for multi-package workspace skeletons leveraging `polytropos-dhall`.
- **Note [Plan Governance and Rollback Mechanics]**
  [tag:note-plan-governance-rollback]
  Details the detached Git metadata store (`~/src/.plan.git`) and snapshot ledger operations for ecosystem plan delta tracking and atomic rollback.
- **Note [Non-Destructive Skeleton Overlay]**
  [tag:note-nondestructive-retrofit]
  Specifies the diagnostic analyzer and non-destructive file overlay semantics for adopting legacy projects into the canonical ecosystem skeleton.
- **Note [CLI Ergonomics and Non-Destructive Initialization]** (`Gachi.CLI.Init`) [ref:note-cli-init-ergonomics]:
  Defines dual-path specification, execution modes, turnkey Git governance, and five-gate readiness for `gachi init`.
