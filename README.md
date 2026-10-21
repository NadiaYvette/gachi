# gachi — がちがち

> **gachi** (*onomatopoeia* がちがち): The sharp, rhythmic clicking and chattering of the teeth of a *gashadokuro* (がしゃどくろ) — the colossal mythical skeleton formed from the spirits of those fallen in famine and battle.
>
> When the gashadokuro approaches, its towering bones vibrate in ominous unison, emitting the rhythmic *gachi-gachi* cadence that warns all in its shadow of an unyielding, unified presence.

In our software engineering ecosystem, `gachi` is the **Project Skeleton & Configuration Propagation Infrastructure** across `~/src/*` (governed by [`../PLAN.md` §1](../PLAN.md#1-project-skeleton-&-configuration-propagation-infrastructure-gachi)), paired with an unboxed, high-performance osteological computation substrate.

Just as a biological skeleton forms the rigid, immutable osseous scaffold that preserves anatomical integrity, `gachi` establishes and guarantees the canonical structural skeletons of our repositories. And just as the teeth of the gashadokuro chatter in rapid harmonic resonance, `gachi` propagates formatting standards, linter rules, git hooks, CI matrices, and agent advisory contexts across all ecosystem repositories in lockstep.

---

## Architecture & Core Subsystems

1. **Osteological Repository Skeletons (`gachi init`):**
   Declarative, Dhall-parameterized project skeleton generator (leveraging `polytropos-dhall` and `gachi-core`). Generates modular multi-package DAGs (`packages/<name>/<name>.cabal`), canonical design monographs (`docs/notes/<NAME>_DESIGN.md`), centralized indices (`docs/INDEX.md`), test suites, and 5-gate physical verification harnesses (`bin/<name>-verify`).
2. **Chattering Configuration Propagation (`gachi sync`):**
   High-speed configuration and policy synchronizer. Propagates upstream improvements to code formatting (Fourmolu/Ormolu), static analysis guardrails (`.hlint.yaml`), git governance (`.gitmessage`, `.githooks/`), and agent advisory contexts (`AGENTS.md`, `.agents/rules/`, `.agents/skills/`) across `polytropos`, `gargamelle`, `sarutahiko`, and satellite checkouts.
3. **Non-Destructive Project Retrofitting (`gachi retrofit`):**
   Diagnostic analyzer and non-destructive skeleton overlay engine that brings adopted codebases, legacy repositories, and single-package checkouts into full compliance with ecosystem standards without overwriting project-specific logic.
4. **Ecosystem Plan Governance & Rollback (`gachi plan` / `plan-ctl`):**
   Deterministic versioning and rollback architecture for top-level strategic planning documents (`~/src/PLAN.md`, `~/src/STATE.md`). Backed by an isolated detached Git metadata store (`~/src/.plan.git`) and an append-only snapshot ledger (`~/src/plans/snapshots/`) with SHA256 integrity checksums.
5. **High-Performance Osteological Computing (`gachi-core`):**
   Flat, contiguous, unboxed osteological memory representations (`SmallArray#`, `ByteArray#`) with compile-time bone indices, lock-free chattering state machines, and zero-copy topological transformations.

---

## Repository Layout

```text
packages/
  gachi-core/             -- Core osteological primitives, contiguous memory layouts, and atomic sync
docs/
  INDEX.md                -- Corpus reading map and documentation inventory
  TUTORIAL.md             -- Hands-on primer on osteological rigs and skeleton templating
  NEWBIE_GUIDE.md         -- Token-conservation funnel and fast symbol navigation
  MAINTAINER_GUIDE.md     -- Architectural governance, memory invariants, and verification gates
  notes/
    GACHI_DESIGN.md       -- Canonical design monograph: architectural decisions & invariants
    DOC_STRATEGY.md       -- Documentation lifecycle, genres, and precedence rules
    COMMIT_ATTRIBUTION.md -- Linux kernel RFC 2822 trailer standards
bin/
  gachi-verify            -- Deterministic physical verification harness (5 gates)
  generate-tags           -- Fast symbol tag generation for code navigation
  gachi-tagref            -- Tagref cross-reference integrity checker
  gachi-linkcheck         -- Markdown link and anchor validator
  gachi-cloc              -- CLOC comment density audit
```

---

## Quick Start

### Toolchain Requirements
- GHC 9.14.1
- Cabal 3.18.1.0+

### Building & Testing
```bash
# Build all packages
cabal build all

# Run test suite
cabal test all

# Run physical verification harness
./bin/gachi-verify
```

---

## Contributing & AI Pair Programming

All commits adhere to the Linux kernel RFC 2822 trailer format with `Assisted-by:` trailers.
See [`AGENTS.md`](AGENTS.md) and [`docs/notes/COMMIT_ATTRIBUTION.md`](docs/notes/COMMIT_ATTRIBUTION.md).

## License

European Union Public Licence (EUPL-1.2). See [`LICENSE`](LICENSE).
