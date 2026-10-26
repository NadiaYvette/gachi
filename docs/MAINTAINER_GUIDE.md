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

### 1.3 Ecosystem Infrastructure Governance (`~/src/PLAN.md` §1)
- **Skeleton Conformity:** Generated project templates (`gachi init`) must strictly adhere to the ecosystem standardization matrix (multi-package layout, `.githooks/`, `.hlint.yaml`, `docs/`, `bin/`).
- **Chattering Sync Idempotency:** Configuration propagation (`gachi sync`) must be deterministic, atomic, and idempotent, never clobbering project-specific customizations.
- **Non-Destructive Retrofitting:** Retrofitting operations (`gachi retrofit`) must non-destructively overlay ecosystem scaffolding without altering existing domain code.
- **Plan Rollback Isolation:** The detached Git metadata store (`~/src/.plan.git`) and snapshot ledger (`~/src/plans/snapshots/`) must remain strictly isolated from child repository `.git/` directories.

### 1.4 Multi-Remote Replication Topology & Provider Compliance
In accordance with Note [Multi-Remote Replication Topology and Provider Compliance] [ref:note-remote-topology], all ecosystem repositories replicate across five canonical remotes:
- **Sovereign Peer-to-Peer:** `rad` (`rad://<project-urn>`). Cryptographically verifiable DIDs without centralized server dependence.
- **Commercial Mirrors:** `github` (`git@github.com:NadiaYvette/<project>.git`), `gitcode` (`git@gitcode.com:NadiaYvette/<project>.git`).
- **Community Non-Profit Mirrors:** `framagit` (`git@framagit.org:NadiaYvette/<project>.git`), `disroot` (`git@git.disroot.org:NadiaYvette/<project>.git`).

Non-compliant providers (such as SourceHut / `git.sr.ht` due to AI pair programming restrictions and email-only workflows) and plaintext HTTP URLs (`http://`) are strictly prohibited and automatically audited and reconciled via `gachi sync --remotes`.

### 1.5 Cellular Sheaf Coherence & Obstruction Localization
In accordance with Note [Cellular Sheaf Coherence and Homological Obstruction Localization] [ref:note-cellular-sheaf-coherence], cross-repository structural consensus is modeled as a 1-dimensional cellular sheaf \(\mathcal{F}\) over cell complex \(G = (V, E)\) spanning all repositories across `~/src/*`.
The sheaf coboundary operator \(\delta^0 : C^0 \to C^1\) evaluates ten standardization dimensions (GHC 9.14.1 pinning, Cabal 3.0/3.18, EUPL-1.2, git hooks, CI matrices, agent guidance):
- **\(H^0\) Harmonic Equilibrium (\(\ker \delta^0\)):** Certifies that all checkouts agree across interface boundaries (0 drift).
- **\(H^1\) Boundary Obstructions (\(\operatorname{coker} \delta^0\)):** Localizes exact drifting repositories, breached contract dimensions, and actionable remediation steps without full ecosystem compilation.
Audited interactively via `gachi doctor` and `gachi doctor --sheaf`.

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
