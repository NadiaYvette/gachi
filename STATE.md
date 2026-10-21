# gachi — State

Operational frontier. Read with `PLAN.md`; update before ending a session.

## Where we are

The repository skeleton for `gachi` is fully grounded and verified under GHC 9.14.1 / Cabal 3.18.
The foundational package `packages/gachi-core` is scaffolded with pure osteological memory abstractions, zero-hint HLint compliance, and passing Hspec test suites.

### Package Architecture
- **`gachi-core`**: Core osteological primitives, contiguous unboxed memory representations, atomic chattering synchronization, and invariant validation.

### Code Quality & Static Analysis Gates [COMPLETED]
- **Toolchain**: GHC 9.14.1 / Cabal 3.18.1.0 targeting `-Wall -Wcompat -Wredundant-constraints`.
- **HLint Cleanliness**: 0 hints across production source files under `.hlint.yaml`.
- **Physical Verification**: `./bin/gachi-verify` active with 5 verification gates (HLint, Cabal Test Suite, Tagref Cross-References, Markdown Link Integrity, CLOC Comment Density).
- **Git Governance**: `.githooks/commit-msg` enforcing Sarutahiko RFC 2822 commit trailer rules; `.githooks/pre-commit` guarding Tagref and link consistency.

### Active Frontier
- Advancing Milestone 1.2: Unboxed primitive osteological arrays and flat contiguous node graphs.
