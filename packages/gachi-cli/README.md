# gachi-cli

Unified command-line interface and ecosystem automation binary for `gachi`.

## Architectural Overview

`gachi-cli` provides the turnkey CLI executable `gachi`, delivering:
- **`gachi init`**: Declarative multi-package workspace generation from Dhall schemas or interactive prompts ([Note [CLI Ergonomics and Non-Destructive Initialization]](docs/notes/GACHI_DESIGN.md)).
- **`gachi sync`**: Cross-repository harmonic synchronization (Phase 3).
- **`gachi retrofit`**: Non-destructive codebase retrofitting and overlay (Phase 4).
- **`gachi plan`**: Detached Git governance and snapshot ledger rollback (Phase 5).

## Installation & Quick Start

```bash
# Build the CLI executable
cabal build gachi-cli

# Run gachi init to scaffold a new project
cabal run gachi -- init my-project --desc "High-performance substrate"

# Or initialize from a declarative Dhall schema
cabal run gachi -- init --config packages/gachi-schema/dhall/example-project.dhall --target-dir ./tmp-proj
```

## CLI Commands & Subcommand Hierarchy

| Subcommand | Flag Options | Description | Status |
| :--- | :--- | :--- | :--- |
| `gachi init` | `[NAME] [-c FILE] [-d DIR] [-m MODE] [--no-git] [--dry-run]` | Scaffolds turn-key standardized repository workspace | **ACTIVE** |
| `gachi sync` | `[--target DIR] [--dry-run]` | Harmonically syncs formatting, linters, and hooks | Phase 3 |
| `gachi retrofit` | `[--target DIR] [--dry-run]` | Non-destructively overlays canonical hierarchy | Phase 4 |
| `gachi plan` | `[checkpoint\|diff\|log\|rollback]` | Detached Git plan store and snapshot rollback | Phase 5 |
| `gachi version` | | Displays toolchain metadata and version stanzas | **ACTIVE** |

## Invariants & Guarantees

1. **Non-Destructive Safety:** By default, files are written under `FailOnExisting` mode to prevent overwriting existing assets. Dry-run mode (`--dry-run`) previews actions without touching disk.
2. **Turnkey Git Governance:** Automatically executes `git init` and pins `core.hooksPath` to `.githooks` and `commit.template` to `.gitmessage`.
3. **Five-Gate Physical Verification:** Skeletons immediately pass all 5 verification gates (`./bin/<project>-verify`).

## Documentation

- [`AGENTS.md`](../../AGENTS.md) — Advisory rules for AI coding assistants.
- [`PLAN.md`](../../PLAN.md) — Strategic roadmap (Milestone 2.3).
- [`docs/notes/GACHI_DESIGN.md`](../../docs/notes/GACHI_DESIGN.md) — Canonical design monograph and notes.

## License

EUPL-1.2 OR Apache-2.0. Author: Nadia Yvette Chambers <nadia.yvette.chambers@ik.me>.
