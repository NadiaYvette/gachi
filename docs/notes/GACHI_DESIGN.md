# GACHI_DESIGN.md — Architectural Decisions & Memory Invariants

Canonical design note for `gachi`.

---

## 1. Design Vision & Mythological Metaphor

`gachi` (がちがち) takes its name from the ominous onomatopoeia describing the clicking and chattering teeth of a *gashadokuro* (がしゃどくろ) — the giant skeletal phantom of Japanese legend.

In software systems engineering, complex hierarchical pointer graphs incur steep costs:
1. Pointer-indirection chasing stalls CPU caches and TLBs.
2. High pointer densities overwhelm GHC garbage collection mark-and-sweep phases.
3. Lock-based synchronization creates convoy phenomena and priority inversion.

`gachi` collapses this overhead into flat, contiguous, unboxed *osteological* structures with deterministic, lock-free *chattering* synchronization.

---

## 2. Canonical Architectural Decisions

### D1: Contiguous Unboxed Osteology (`SmallArray#` / `ByteArray#`)
- **Decision:** All structural nodes and edges are stored within flat, contiguous primitive arrays indexed by strictly typed bone handles (`BoneId`, `JointId`).
- **Reference:** Note [Osteological Contiguous Memory Layout] `[ref:note-osteology-memory-layout]`

### D2: Lock-Free Chattering State Synchronization
- **Decision:** Concurrency across osteological joints is governed by atomic compare-and-swap (CAS) primitives and optimistic read-copy-update semantics rather than mutexes.
- **Rationale:** Lock-free state progression guarantees race-freedom, immunity to deadlocks, and bounded latency.
- **Reference:** Note [Chattering Lock-Free Atomic Synchronization] `[ref:note-chattering-synchronization]`

### D3: Strict Separation of Structural Rigidity and Dynamic Payload
- **Decision:** Osteological bone graphs maintain fixed topological rigidity. Dynamic attributes and payloads attach via secondary flat arrays or typed indices.
- **Rationale:** Decoupling topology from mutable payload permits zero-copy structural transformations without rewriting attribute tables.

### D4: Zero-Warning Compiler Verification & Precedence
- **Decision:** Every package compiles under `-Wall -Wcompat -Wredundant-constraints` and `-Werror`.
- **Precedence Rule:** Per `DOC_STRATEGY.md` §4, code wins at runtime; when code changes contradict this document, this document must be corrected in the same commit.

---

## 3. Grounded Notes Architecture

- **Note [Osteological Contiguous Memory Layout]** `[ref:note-osteology-memory-layout]`
  Defines flat memory layout invariants, alignment boundaries, and zero-allocation indexing.
- **Note [Chattering Lock-Free Atomic Synchronization]** `[ref:note-chattering-synchronization]`
  Details lock-free CAS mechanics, optimistic concurrency retry loops, and atomic state transitions.
