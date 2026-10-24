<!--
SPDX-License-Identifier: EUPL-1.2
-->
# Gachi Maintainer Guide & Architectural Governance

**Status:** LIVING DOCUMENT · v1.0 · 2026-10-21  
**Audience:** Maintainers, Subsystem Leads, Ecosystem Contributors, AI Assistant Drivers  
**Canonical Strategy:** [`docs/notes/DOC_STRATEGY.md`](notes/DOC_STRATEGY.md) · [`docs/notes/GACHI_DESIGN.md`](notes/GACHI_DESIGN.md)  
**Corpus Inventory:** [`docs/INDEX.md`](INDEX.md)  
**Newbie Guide:** [`docs/NEWBIE_GUIDE.md`](NEWBIE_GUIDE.md) · **Tutorial:** [`docs/TUTORIAL.md`](TUTORIAL.md)  

---

## 1. Architectural Foundations & Invariants

### 1.1 The Precedence Rule (`DOC_STRATEGY.md` §4)
- **Code wins at runtime:** When a note disagrees with code, the code defines runtime reality.
- **Notes are corrected regardless:** A stale note must be updated in the same change set.

### 1.2 The Osteological Memory Discipline
- **Contiguous Layouts:** Structural osteology data must maintain unboxed or flat contiguous arrays (`Data.Primitive.SmallArray`) without pointer indirection bloat. See Note [Osteological Contiguous Memory Layout] [ref:note-osteology-memory-layout].
- **Zero-Copy Slicing:** Sub-segment operations and regional extractions must share underlying arrays via pure pointer windows without heap copies. See Note [Zero-Copy Sub-Segment Slicing] [ref:note-zero-copy-slicing].
- **Amortized Growth:** Dynamic bone appending follows geometric array capacity expansion. See Note [Geometric Capacity Expansion and Reallocation] [ref:note-geometric-capacity-expansion].
- **Monotonic Indexing:** Bone and joint IDs map directly to contiguous offsets with zero hashing or tree searching. See Note [Monotonic Identifier Allocation and Contiguous Indexing] [ref:note-monotonic-id-allocation].
- **Directional Joints:** Multigraph connectivity is modeled via contiguous directed joint segments. See Note [Directional Joints and Incident Traversal] [ref:note-directional-joints-traversal].
- **Lock-Free Atomic Synchronization:** Chattering state transitions use atomic memory references and monotonic ID counters. See Note [Chattering Lock-Free Atomic Synchronization] [ref:note-chattering-synchronization].

### 1.3 Ecosystem Infrastructure Governance ([`~/src/PLAN.md` §1](../../PLAN.md#1-project-skeleton-&-configuration-propagation-infrastructure-gachi))
- **Skeleton Conformity:** Generated project templates (`gachi init`) must strictly adhere to the ecosystem standardization matrix (multi-package layout, `.githooks/`, `.hlint.yaml`, `docs/`, `bin/`).
- **Chattering Sync Idempotency:** Configuration propagation (`gachi sync`) must be deterministic, atomic, and idempotent, never clobbering project-specific customizations.
- **Non-Destructive Retrofitting:** Retrofitting operations (`gachi retrofit`) must non-destructively overlay ecosystem scaffolding without altering existing domain code.
- **Plan Rollback Isolation:** The detached Git metadata store (`~/src/.plan.git`) and snapshot ledger (`~/src/plans/snapshots/`) must remain strictly isolated from child repository `.git/` directories.

---

## 2. Verification Gates & Quality Control

Before any change is committed to master, it must pass all 5 physical verification gates:

```bash
./bin/gachi-verify
```

Checks executed in sequence:
1. **HLint Static Analysis:** Zero hints enforced across `packages/gachi-*/src`.
2. **Full Test Suite Assertions:** All test suite assertions pass with 0 failures across active packages.
3. **Tagref Cross-Reference Gate:** Zero dangling references and zero duplicate tags across code, monographs, and docs.
4. **Markdown Link & Anchor Integrity Gate:** Zero broken intra-corpus markdown links or anchors.
5. **CLOC Comment Density Gate:** Tracks progress toward and maintains the **50%+ comment density target**.
