<!--
SPDX-License-Identifier: EUPL-1.2
-->
# Gachi Maintainer Guide & Architectural Governance

**Status:** LIVING DOCUMENT · v1.1 · 2026-11-03  
**Audience:** Maintainers, Subsystem Leads, Ecosystem Contributors, AI Assistant Drivers  
**Canonical Strategy:** [`docs/notes/DOC_STRATEGY.md`](notes/DOC_STRATEGY.md) · [`docs/notes/GACHI_DESIGN.md`](notes/GACHI_DESIGN.md)  
**Corpus Inventory:** [`docs/INDEX.md`](INDEX.md)  
**Newbie Guide:** [`docs/NEWBIE_GUIDE.md`](NEWBIE_GUIDE.md) · **Tutorial:** [`docs/TUTORIAL.md`](TUTORIAL.md)  

---

## 1. Architectural Foundations & Invariants

Maintainers must protect ten core architectural invariants across all changes:

### Invariant 1: The Precedence Rule (`DOC_STRATEGY.md` §4)
- **Code wins at runtime:** When a note disagrees with code, the code defines runtime reality.
- **Notes are corrected regardless:** A stale note must be updated in the same change set. Never allow notes to rot silently.

### Invariant 2: Osteological Contiguous Memory Layout
Structural osteology data must maintain unboxed or flat contiguous arrays (`Data.Primitive.SmallArray#` / `ByteArray#`) without pointer indirection bloat. See Note [Osteological Contiguous Memory Layout] `[ref:note-osteology-memory-layout]`.

### Invariant 3: Zero-Copy Slicing
Sub-segment operations and regional extractions must share underlying arrays via pure pointer windows (`sliceOsteo`) without heap allocations or buffer duplication. See Note [Zero-Copy Sub-Segment Slicing] `[ref:note-zero-copy-slicing]`.

### Invariant 4: Monotonic Identifier Allocation
`BoneId` and `JointId` map directly to contiguous offsets with zero hashing or tree searching overhead. See Note [Monotonic Identifier Allocation and Contiguous Indexing] `[ref:note-monotonic-id-allocation]`.

### Invariant 5: Lock-Free Atomic State Transitions
Concurrent bone transitions must execute via Compare-And-Swap (CAS) primitives and atomic references without acquiring coarse-grained mutexes. See Note [Chattering Lock-Free Atomic Synchronization] `[ref:note-chattering-synchronization]`.

### Invariant 6: Double-Pushout (DPO) Algebraic Soundness
Every graph transformation must satisfy the categorical pushout complement existence conditions (Dangling Condition and Identification Condition) before materializing rewrites.

### Invariant 7: Polytropos Isomorphism Laws
Coercions between `OsteoSegment (f Any)` and Polytropos `Rep f a` must satisfy the bidirectional isomorphism:
$$\text{repToSegment} \circ \text{segmentToRep} = \text{id} \quad \text{and} \quad \text{segmentToRep} \circ \text{repToSegment} = \text{id}$$

### Invariant 8: Non-Destructive Skeleton Overlay
Retrofitting operations (`gachi retrofit`) must non-destructively overlay ecosystem scaffolding without altering, overwriting, or deleting existing domain source files in `src/`, `app/`, `lib/`, or `test/`.

### Invariant 9: Detached Plan Store Isolation
The detached Git metadata store (`~/src/.plan.git`) and snapshot ledger (`~/src/plans/snapshots/`) must remain strictly isolated from child repository `.git/` directories, preventing cross-repo commit pollution.

### Invariant 10: AI Commit Attribution Boundaries
AI coding assistants must be credited using RFC 2822 commit trailers (`Assisted-by: Antigravity (<Provider> / <Model>)`). AI assistants must NEVER be recorded as `Co-authored-by:` (implying joint copyright ownership) or `Signed-off-by:` (certifying the human Developer Certificate of Origin).

---

## 2. Multi-Remote Replication Topology & Provider Compliance

In accordance with Note [Multi-Remote Replication Topology and Provider Compliance] `[ref:note-remote-topology]`, all ecosystem repositories replicate across five canonical remotes:

1. **Sovereign Peer-to-Peer:** `rad` (`rad://<project-urn>`). Cryptographically verifiable DIDs without centralized server dependence.
2. **Commercial Mirrors:** `github` (`git@github.com:NadiaYvette/<project>.git`), `gitcode` (`git@gitcode.com:NadiaYvette/<project>.git`).
3. **Community Non-Profit Mirrors:** `framagit` (`git@framagit.org:NadiaYvette/<project>.git`), `disroot` (`git@git.disroot.org:NadiaYvette/<project>.git`).

Non-compliant providers (such as SourceHut / `git.sr.ht` due to AI pair programming restrictions and email-only workflows) and plaintext HTTP URLs (`http://`) are strictly prohibited and automatically audited and reconciled via `gachi sync --remotes`.

---

## 3. Cellular Sheaf Coherence & Obstruction Localization

In accordance with Note [Cellular Sheaf Coherence and Homological Obstruction Localization] `[ref:note-cellular-sheaf-coherence]`, cross-repository structural consensus is modeled as a 1-dimensional cellular sheaf $\mathcal{F}$ over a cell complex $G = (V, E)$ spanning all repositories across `~/src/*`.

The sheaf coboundary operator $\delta^0 : C^0 \to C^1$ evaluates ten standardization dimensions (GHC 9.14.1 pinning, Cabal 3.0/3.18, EUPL-1.2, git hooks, CI matrices, agent guidance):
- **$H^0$ Harmonic Equilibrium ($\ker \delta^0$):** Certifies that all checkouts agree across interface boundaries (0 drift).
- **$H^1$ Boundary Obstructions ($\operatorname{coker} \delta^0$):** Localizes exact drifting repositories, breached contract dimensions, and actionable remediation steps without requiring full ecosystem recompilation.

Audited interactively via `gachi doctor` and `gachi doctor --sheaf`.

---

## 4. Physical Verification Discipline

Before any commit is pushed to master, it must pass all 5 physical verification gates:

```bash
./bin/gachi-verify
```

### Gate Sequence:
1. **HLint Static Analysis:** Zero hints enforced (`0 hints` policy) across `packages/gachi-*/src`.
2. **Full Cabal Test Suite:** All test assertions pass cleanly with 0 failures across all 7 packages.
3. **Tagref Cross-Reference Gate:** Zero dangling references and zero duplicate tags across code, monographs, and documentation.
4. **Markdown Link & Anchor Integrity Gate:** Zero broken intra-corpus markdown links or relative file anchors.
5. **CLOC Comment Density Gate:** Tracks progress toward and maintains the **50%+ comment density target** on domain source code.

---

## 5. Triage Runbooks

### Problem: HLint Failure on New Language Pragmas or Lambdas
- **Symptoms:** `./bin/gachi-verify` fails at Gate 1 with `Warning: Unused LANGUAGE pragma` or `Warning: Eta reduce`.
- **Remediation:** Remove redundant pragmas, apply suggested eta-reductions, or use tuple sections. If a hint is intentionally invalid (e.g. primitive unboxed loops), add explicit exemptions to `.hlint.yaml` with rationale.

### Problem: Solver Failure with Transitive Dependencies
- **Symptoms:** Cabal reports constraint conflicts under GHC 9.14.1 (e.g. `beam-migrate` requiring `some < 1.1`).
- **Remediation:** Update `cabal.project` constraints stanza (`constraints: some < 1.1`). Ensure local checkouts in `cabal.project.local` match upstream versions.

### Problem: Dangling Tagref Cross-References
- **Symptoms:** `./bin/gachi-verify` fails at Gate 3 with `dangling references`.
- **Remediation:** Run `./bin/gachi-tagref` to identify broken tag labels. Verify if a tag was renamed or deleted in `docs/notes/GACHI_DESIGN.md` and update referencing source annotations.
