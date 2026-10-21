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
- **Contiguous Layouts:** Structural osteology data must maintain unboxed or flat contiguous arrays (`Data.Primitive.SmallArray`) without pointer indirection bloat.
- **Lock-Free Atomic Synchronization:** Chattering state transitions use atomic memory references and monotonic ID counters.

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
