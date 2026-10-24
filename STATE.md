# gachi — State

Operational frontier. Read with `PLAN.md`; update before ending a session.

## Where we are

The repository skeleton for `gachi` is fully grounded and verified under GHC 9.14.1 / Cabal 3.18.
The foundational package `packages/gachi-core` is scaffolded with pure osteological memory abstractions, zero-hint HLint compliance, and passing Hspec test suites.

### Package Architecture
- **`gachi-core`**: Core osteological primitives, contiguous unboxed memory representations, atomic chattering synchronization, and invariant validation.
- **`gachi-schema`**: Declarative Dhall schemas, `polytropos-dhall` codecs, isomorphic Polytropos open row representations (`ProjectRec`), and turnkey project templates.

### Code Quality & Static Analysis Gates [COMPLETED]
- **Toolchain**: GHC 9.14.1 / Cabal 3.18.1.0 targeting `-Wall -Wcompat -Wredundant-constraints`.
- **HLint Cleanliness**: 0 hints across production source files under `.hlint.yaml`.
- **Physical Verification**: `./bin/gachi-verify` active with 5 verification gates (HLint, Cabal Test Suite, Tagref Cross-References, Markdown Link Integrity, CLOC Comment Density).
- **Git Governance**: `.githooks/commit-msg` enforcing Sarutahiko RFC 2822 commit trailer rules; `.githooks/pre-commit` guarding Tagref and link consistency.

### Active Frontier
- **Ecosystem Infrastructure Governance (`~/src/PLAN.md` §1):** Formally designated as the engine for ecosystem skeleton generation (`gachi init`), cross-repo chattering configuration propagation (`gachi sync`), non-destructive project retrofitting (`gachi retrofit`), and strategic plan versioning/rollback (`gachi plan` / `plan-ctl`).
- **Implementation Plan:** Canonical implementation plan established at [`docs/notes/IMPLEMENTATION_PLAN.md`](docs/notes/IMPLEMENTATION_PLAN.md) detailing Phases 1–6, multi-package architecture, verification gates, and risk mitigations.
- **Phase 1 Completed (`gachi-core`):**
  - **Milestone 1.1:** Canonical multi-forge repository skeleton grounded with strict git hooks and 5 verification gates.
  - **Milestone 1.2:** Grounded contiguous unboxed osteological primitives (`OsteoSegment a` and `OsteoBytes`), zero-allocation $O(1)$ indexing, zero-copy slicing, and contiguous `Skeleton` bone-and-joint graphs with 12/12 passing Hspec tests.
  - **Milestone 1.3:** Canonical GHC Notes architecture grounded across `Gachi.Osteology`, `Gachi.Core`, tests, maintainer guide, and design monographs with 10 tags, 60 references, 0 dangling references, and 0 duplicate tags verified via `./bin/gachi-tagref`.
- **Phase 2 In Progress (`gachi init`):**
  - **Milestone 2.1 Completed:** Grounded declarative Dhall project schemas in `packages/gachi-schema` with `FromDhall` / `ToDhall` via `GenericDhall`, Polytropos open row isomorphisms (`ProjectRec` / `RowRep`), turnkey Dhall templates, and 12/12 passing Hspec tests.
  - **Advancing Milestone 2.2:** Multi-package workspace scaffolding engine (`packages/gachi-scaffold`).
- **Verification Status:** All 5 physical verification gates (`bin/gachi-verify`) passing cleanly with 0 warnings, 0 hints, and 0 dangling tagref references across 2 packages.
