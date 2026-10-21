# gachi — Strategic Roadmap (`PLAN.md`)

**Status:** ACTIVE SPECIFICATION · October 2026  
**Scope:** Core Architecture, Osteological Primitives, and Verification Milestones

---

## Phase 1: Foundational Skeleton & Osteological Memory (`gachi-core`) [IN PROGRESS]

- [x] **Milestone 1.1:** Canonical Repository Skeleton Setup
  - Git repository initialization, `.githooks/` (`commit-msg`, `pre-commit`), `.gitmessage`.
  - Multi-forge CI configuration (`.github/workflows/ci.yml`, `.gitlab-ci.yml`).
  - Agent advisory context (`AGENTS.md`, modular rules in `.agents/rules/`).
  - Physical verification harness (`./bin/gachi-verify`).
- [ ] **Milestone 1.2:** Unboxed Osteological Primitives
  - Contiguous primitive arrays (`SmallArray#`, `ByteArray#`) with compile-time bone indices.
  - Constant-time O(1) bone lookup and zero-allocation traversal.
  - Property-based roundtrip testing under Hspec/Tasty.
- [ ] **Milestone 1.3:** Tagref & In-Code Notes Grounding
  - Establish canonical GHC Notes architecture:
    - `Note [Osteological Contiguous Memory Layout]`
    - `Note [Chattering Lock-Free Atomic Synchronization]`
  - Zero dangling references verified via `./bin/gachi-tagref`.

---

## Phase 2: Lock-Free Chattering Synchronization

- [ ] **Milestone 2.1:** Atomic Bone State Machines
  - Non-blocking compare-and-swap (CAS) primitives on osteological joints.
  - Deterministic lock-free consensus and harmonic synchrony.
- [ ] **Milestone 2.2:** Multi-Agent Concurrent Traversal
  - Safe concurrent traversals without global locks.
  - Formal race-freedom and progress guarantees.

---

## Phase 3: Skeletal Transformations & Ecosystem Integration

- [ ] **Milestone 3.1:** Double-Pushout (DPO) Graph Rewriting on Skeletal Graphs
  - Algebraic rewriting over osteological topologies.
  - Fusion with `gargamelle` algebraic rewriting engines.
- [ ] **Milestone 3.2:** Polytropos Row-Polymorphic Integration
  - Unboxed row layouts mapping into `polytropos-core` representations.
