# gachi — Strategic Roadmap (`PLAN.md`)

**Status:** ACTIVE STRATEGIC ROADMAP · October 2026  
**Scope:** Ecosystem Skeleton Generation, Chattering Configuration Propagation, and Osteological Computing  
**Canonical Anchor:** Linked to and implementing [`../PLAN.md` §1](../PLAN.md#1-project-skeleton-&-configuration-propagation-infrastructure-gachi)  
**Implementation Plan:** [`docs/notes/IMPLEMENTATION_PLAN.md`](docs/notes/IMPLEMENTATION_PLAN.md)

---

## Phase 1: Foundational Skeleton & Osteological Memory (`gachi-core`) [COMPLETED]

- [x] **Milestone 1.1:** Canonical Repository Skeleton Grounding
  - Git repository initialization, `.githooks/` (`commit-msg`, `pre-commit`), `.gitmessage`.
  - Multi-forge CI configuration (`.github/workflows/ci.yml`, `.gitlab-ci.yml`).
  - Agent advisory layer (`AGENTS.md`, compatibility symlinks, modular rules in `.agents/rules/`).
  - 5-gate physical verification harness (`./bin/gachi-verify`).
- [x] **Milestone 1.2:** Unboxed Osteological Primitives
  - Contiguous primitive arrays (`SmallArray#`, `ByteArray#`) with compile-time bone indices (`BoneId`, `JointId`).
  - Constant-time $O(1)$ bone lookup and zero-allocation traversal (`indexOsteo`, `unsafeIndexOsteo`, `lookupBone`, `unsafeLookupBone`).
  - Zero-copy slicing (`sliceOsteo`, `sliceBytes`, `sliceBones`) without intermediate heap reallocation.
  - Comprehensive Hspec specification validating capacity growth, bounds safety, Semigroup concatenation, and roundtrip fidelity.
- [x] **Milestone 1.3:** Tagref & In-Code Notes Grounding
  - Canonical GHC Notes architecture grounded in code, tests, monographs, and maintainer guidance:
    - `Note [Osteological Contiguous Memory Layout]` (`[ref:note-osteology-memory-layout]`)
    - `Note [Zero-Copy Sub-Segment Slicing]` (`[ref:note-zero-copy-slicing]`)
    - `Note [Geometric Capacity Expansion and Reallocation]` (`[ref:note-geometric-capacity-expansion]`)
    - `Note [Chattering Lock-Free Atomic Synchronization]` (`[ref:note-chattering-synchronization]`)
    - `Note [Monotonic Identifier Allocation and Contiguous Indexing]` (`[ref:note-monotonic-id-allocation]`)
    - `Note [Directional Joints and Incident Traversal]` (`[ref:note-directional-joints-traversal]`)
    - `Note [Ecosystem Standardization Invariants]` (`[ref:note-ecosystem-standardization]`)
    - `Note [Dhall Parameterized Skeleton Templating]` (`[ref:note-dhall-skeleton-templating]`)
    - `Note [Plan Governance and Rollback Mechanics]` (`[ref:note-plan-governance-rollback]`)
    - `Note [Non-Destructive Skeleton Overlay]` (`[ref:note-nondestructive-retrofit]`)
  - 10 tags, 60 references, 0 dangling references, and 0 duplicate tags verified via `./bin/gachi-tagref`.

---

## Phase 2: Declarative Project Skeleton Generator (`gachi init`) [ACTIVE]

- [x] **Milestone 2.1:** Dhall-Parameterized Project Schema (`polytropos-dhall`)
  - Grounded declarative Dhall types for project metadata, modular package DAGs, Cabal 3.18 / GHC 9.14 stanzas, license terms (EUPL-1.2), and author information in `Gachi.Schema.Project` and `Gachi.Schema.Dhall`.
  - Implemented strongly-typed deserialization using `polytropos-dhall`'s `FromDhall` / `ToDhall` via `GenericDhall` and isomorphic open row representations (`ProjectRec`, `AuthorRec`, `PackageRec`, `RemoteRec`) backed by contiguous Polytropos `RowRep` storage.
  - Verified 12/12 passing Hspec tests validating nominal decoding, open row roundtripping, pretty-printing, and safe error handling.
- [x] **Milestone 2.2:** Multi-Package Workspace Scaffolding (`gachi-scaffold`)
  - Grounded declarative scaffolding engine `packages/gachi-scaffold` synthesizing complete canonical ecosystem workspaces: multi-package hierarchy (`packages/*/src`, `packages/*/test`, `.cabal`), toolchain configs (`cabal.project`, `cabal.project.local.example`, `.hlint.yaml`, `.gitmessage`, `.githooks/`), documentation corpus (`docs/notes/`, `docs/INDEX.md`, `docs/TUTORIAL.md`, `docs/NEWBIE_GUIDE.md`, `docs/MAINTAINER_GUIDE.md`, `docs/notes/DOC_STRATEGY.md`, `docs/notes/COMMIT_ATTRIBUTION.md`), and operational files (`PLAN.md`, `STATE.md`, `AGENTS.md`, `CLAUDE.md`, `.agents/rules/`).
  - Implemented turnkey 5-gate physical verification script generators (`bin/<name>-verify`, `bin/generate-tags`, `bin/<name>-tagref`, `bin/<name>-linkcheck`, `bin/<name>-cloc`).
  - Canonically grounded `Note [Ecosystem Standardization Invariants]` (`[ref:note-ecosystem-standardization]`) in `Gachi.Scaffold`.
  - Verified 15/15 passing Hspec tests validating pure generation, filesystem materialization, permission bits, error modes (`FailOnExisting`, `SkipExisting`, `OverwriteExisting`), and physical gate self-consistency on generated target projects.
- [ ] **Milestone 2.3:** CLI Tooling (`gachi init`)
  - Interactive and headless CLI modes to instantiate new projects or add satellite packages to existing workspaces.

---

## Phase 3: Chattering Configuration Propagation (`gachi sync`)

- [ ] **Milestone 3.1:** Cross-Repository Standardization Matrix (`~/src/PLAN.md` §1.A)
  - Standardization enforcement across directory layout, formatting profiles (Fourmolu/Ormolu/rustfmt), linter guardrails (`.hlint.yaml`), build conventions (`cabal.project` GHC 9.14 / Cabal 3.18), git hooks, and multi-mirror topologies.
- [ ] **Milestone 3.2:** Harmonic Chattering Synchronization (`gachi sync`)
  - Differential inspection of shared infrastructure assets across `~/src/*` (`polytropos`, `gargamelle`, `sarutahiko`).
  - Atomic, idempotent propagation of updated formatting rules, linter hints, git commit hooks, and agent guidance.
- [ ] **Milestone 3.3:** Forge-Tiered CI Matrix Generation
  - Synthesis of tailored CI configs: heavyweight physical verification for GitHub Actions vs lightweight static gates for resource-constrained community forges (GitLab, Framagit, Disroot).

---

## Phase 4: Project Retrofitting Engine (`gachi retrofit`)

- [ ] **Milestone 4.1:** Diagnostic Repository Inspector
  - Static analysis of arbitrary target checkouts: detects language stacks, build systems, existing tests, and missing ecosystem standards.
- [ ] **Milestone 4.2:** Non-Destructive Skeleton Overlay
  - Safely scaffolds missing documentation hierarchies, hooks, and verification harnesses without perturbing existing domain logic.
- [ ] **Milestone 4.3:** Progressive Quality Gate Realization
  - Incremental remediation pipelines: bringing builds under `-Wall -Werror`, purging HLint warnings, and grounding physical verification gates.

---

## Phase 5: Ecosystem Plan Governance & Rollback (`gachi plan` / `plan-ctl`)

- [ ] **Milestone 5.1:** Detached Git Store Architecture (`~/src/.plan.git`)
  - Initialize isolated Git repository tracking ecosystem governance files (`PLAN.md`, `STATE.md`, `INDEX.md`) across `~/src/` without interfering with child git checkouts.
- [ ] **Milestone 5.2:** Append-Only Snapshot Ledger (`~/src/plans/snapshots/`)
  - Automated pre-mutation snapshots with timestamped filenames and SHA256 integrity checksums.
- [ ] **Milestone 5.3:** CLI Plan Governance Subcommands
  - `gachi plan checkpoint [message]`: Atomic commit to detached store + snapshot.
  - `gachi plan diff [ref]`: Semantic delta display against prior checkpoints.
  - `gachi plan log`: Chronological history of ecosystem planning revisions.
  - `gachi plan rollback <checkpoint>`: Deterministic, atomic restoration of planning state.

---

## Phase 6: Lock-Free Chattering Synchronization & Graph Transformations

- [ ] **Milestone 6.1:** Atomic Bone State Machines
  - Non-blocking compare-and-swap (CAS) primitives on osteological joints.
  - Deterministic lock-free consensus and harmonic synchrony.
- [ ] **Milestone 6.2:** Multi-Agent Concurrent Traversal
  - Safe concurrent traversals without global locks; formal race-freedom guarantees.
- [ ] **Milestone 6.3:** Double-Pushout (DPO) Algebraic Graph Rewriting
  - Algebraic rewriting over osteological topologies; fusion with `gargamelle` rewriting engines.
- [ ] **Milestone 6.4:** Polytropos Zero-Cost Coercions
  - Zero-copy mapping between osteological arrays and `polytropos-core` flat `Rep` structures.
