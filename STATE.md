# gachi — State

Operational frontier. Read with `PLAN.md`; update before ending a session.

## Where we are

The repository skeleton for `gachi` is fully grounded and verified under GHC 9.14.1 / Cabal 3.18.
The foundational package `packages/gachi-core` is scaffolded with pure osteological memory abstractions, zero-hint HLint compliance, and passing Hspec test suites.

### Package Architecture
- **`gachi-core`**: Core osteological primitives, contiguous unboxed memory representations, atomic chattering synchronization, and invariant validation.
- **`gachi-schema`**: Declarative Dhall schemas, `polytropos-dhall` codecs, isomorphic Polytropos open row representations (`ProjectRec`), and turnkey project templates.
- **`gachi-scaffold`**: Declarative multi-package workspace scaffolding engine, canonical asset tree synthesis, execution modes, and turnkey physical verification harnesses.
- **`gachi-cli`**: Turnkey command-line interface executable (`gachi`), optparse-applicative option parsing hierarchy, declarative Dhall resolution, interactive wizard, and hermetic Git governance automation.
- **`gachi-sync`**: Cross-repository standardization matrix, canonical shared asset catalog, repository audit engine, and differential configuration propagation (`gachi sync`).

### Code Quality & Static Analysis Gates [COMPLETED]
- **Toolchain**: GHC 9.14.1 / Cabal 3.18.1.0 targeting `-Wall -Wcompat -Wredundant-constraints`.
- **HLint Cleanliness**: 0 hints across production source files under `.hlint.yaml`.
- **Physical Verification**: `./bin/gachi-verify` active with 5 verification gates (HLint, Cabal Test Suite across 5 packages, Tagref Cross-References, Markdown Link Integrity, CLOC Comment Density).
- **Git Governance**: `.githooks/commit-msg` enforcing Sarutahiko RFC 2822 commit trailer rules; `.githooks/pre-commit` guarding Tagref and link consistency.

### Active Frontier
- **Ecosystem Infrastructure Governance (`~/src/PLAN.md` §1):** Formally designated as the engine for ecosystem skeleton generation (`gachi init`), cross-repo chattering configuration propagation (`gachi sync`), non-destructive project retrofitting (`gachi retrofit`), and strategic plan versioning/rollback (`gachi plan` / `plan-ctl`).
- **Implementation Plan:** Canonical implementation plan established at [`docs/notes/IMPLEMENTATION_PLAN.md`](docs/notes/IMPLEMENTATION_PLAN.md) detailing Phases 1–6, multi-package architecture, verification gates, and risk mitigations.
- **Phase 1 Completed (`gachi-core`):**
  - **Milestone 1.1:** Canonical multi-forge repository skeleton grounded with strict git hooks and 5 verification gates.
  - **Milestone 1.2:** Grounded contiguous unboxed osteological primitives (`OsteoSegment a` and `OsteoBytes`), zero-allocation $O(1)$ indexing, zero-copy slicing, and contiguous `Skeleton` bone-and-joint graphs with 12/12 passing Hspec tests.
  - **Milestone 1.3:** Canonical GHC Notes architecture grounded across `Gachi.Osteology`, `Gachi.Core`, tests, maintainer guide, and design monographs with 10 tags, 60 references, 0 dangling references, and 0 duplicate tags verified via `./bin/gachi-tagref`.
- **Phase 2 Completed (`gachi init`):**
  - **Milestone 2.1 Completed:** Grounded declarative Dhall project schemas in `packages/gachi-schema` with `FromDhall` / `ToDhall` via `GenericDhall`, Polytropos open row isomorphisms (`ProjectRec` / `RowRep`), turnkey Dhall templates, and 12/12 passing Hspec tests.
  - **Milestone 2.2 Completed:** Grounded declarative scaffolding engine `packages/gachi-scaffold`, lean GFM AST and deterministic pretty-printer (`Gachi.Scaffold.Markdown`), auto-aligned table layout engine, and full template generator refactoring across all repository documentation and operational governance assets. Verified 20/20 passing Hspec tests validating GFM AST pretty-printing, dynamic table layout, pure generation, and physical gate self-consistency on generated target projects. Grounded `Note [Ecosystem Standardization Invariants]` (`[ref:note-ecosystem-standardization]`) in `Gachi.Scaffold`.
  - **Milestone 2.3 Completed:** Grounded turnkey CLI binary `packages/gachi-cli/` (`Gachi.CLI`, `Gachi.CLI.Init`, `Gachi.CLI.Options`, `app/Main.hs`) and launcher script `bin/gachi`. Added dual-path project resolution (typed Dhall vs CLI flags / interactive prompt), non-destructive write modes (`FailOnExisting`, `SkipExisting`, `OverwriteExisting`), dry-run preview, and automated Git governance pinning (`core.hooksPath = .githooks`, `commit.template = .gitmessage`). Grounded `Note [CLI Ergonomics and Non-Destructive Initialization]` (`[ref:note-cli-init-ergonomics]`). Verified 10/10 passing Hspec tests in `packages/gachi-cli/test/Main.hs`.
- **Phase 3 Active (Chattering Configuration Propagation - `gachi sync`):**
  - **Milestone 3.1 Completed:** Established `packages/gachi-sync` library implementing the 9-dimensional Standardization Matrix data models (`Gachi.Sync.Types`), canonical shared asset catalog (`Gachi.Sync.Catalog`), authoritative matrix registry (`Gachi.Sync.Matrix`), and read-only repository audit engine (`Gachi.Sync.Audit`). Grounded `Note [Cross-Repository Standardization Matrix and Audit Semantics]` (`[ref:note-standardization-matrix]`) with 14 tags and 101 cross-references validated by Tagref. Verified 21/21 passing Hspec tests validating matrix completeness, category queries, path token substitution, audit compliance, content drift detection, missing file reporting, and ASCII diagnostic table formatting.
- **Next Frontier:** Milestone 3.2: Harmonic Chattering Synchronization (`gachi sync`).
- **Verification Status:** All 5 physical verification gates (`bin/gachi-verify`) passing cleanly with 0 warnings, 0 hints, 0 dangling tagref references, 0 broken markdown links, and 50.1% comment density in production code across 5 packages (75/75 total Hspec tests passing).
