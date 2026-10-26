# gachi-sync — Cross-Repository Standardization Matrix & Harmonic Configuration Synchronization

[![License: EUPL-1.2](https://img.shields.io/badge/License-EUPL--1.2-blue.svg)](LICENSE)
[![GHC: 9.14.1](https://img.shields.io/badge/GHC-9.14.1-purple.svg)](cabal.project)
[![Verification: 5 Gates](https://img.shields.io/badge/Verification-5%20Gates%20Passed-brightgreen.svg)](bin/gachi-verify)

`gachi-sync` is the core standardization and propagation engine of the Gachi ecosystem framework. It establishes the canonical 9-dimensional Standardization Matrix (`~/src/PLAN.md` §1.A), canonical asset catalog, repository audit engine, and differential configuration propagation mechanisms (`gachi sync`).

---

## The 9 Standardization Dimensions

In accordance with Note [Ecosystem Standardization Invariants] ([`ref:note-ecosystem-standardization`](../../docs/notes/GACHI_DESIGN.md#3-grounded-notes-architecture)) and Note [Cross-Repository Standardization Matrix and Audit Semantics] ([`ref:note-standardization-matrix`](src/Gachi/Sync/Matrix.hs)), every repository in the ecosystem conforms to nine non-negotiable dimensions:

| Dimension | Description | Canonical Assets |
|---|---|---|
| **1. Layout** | Workspace hierarchy & documentation | `packages/*/`, `docs/INDEX.md`, `PLAN.md`, `STATE.md` |
| **2. Formatters** | Declarative style profiles | `fourmolu.yaml`, `rustfmt.toml`, `.clang-format` |
| **3. Linters** | Zero-hint static analysis rules | `.hlint.yaml` |
| **4. Build System** | Pinning GHC 9.14 / Cabal 3.18 | `cabal.project`, `cabal.project.local.example` |
| **5. Git Governance** | RFC 2822 trailer & pre-commit hooks | `.gitmessage`, `.githooks/commit-msg`, `.githooks/pre-commit` |
| **6. Remote Topology** | Multi-forge replication remotes | `rad` (Radicle p2p), `github`, `gitcode`, `framagit`, `disroot` |
| **7. Tiered CI** | Asymmetric resource allocation | `.github/workflows/ci.yml`, `.gitlab-ci.yml` |
| **8. Polyglot** | Multi-language FFI & boundaries | FFI ABI stability, polyglot test runners |
| **9. Agent Context** | AI pair programming & token budget | `AGENTS.md` (~4 KB), `CLAUDE.md`, `.agents/rules/` |

---

## Architectural Principles

1. **Non-Destructive Safety:**
   Audit operations are strictly read-only and pure. Synchronization operations inspect differential changes and report discrepancies before mutating files.
2. **Deterministic Catalog:**
   All shared configurations derive from pure Haskell generators with zero ambient filesystem or network side-effects.
3. **Five-Gate Readiness:**
   Any repository conforming to the standardization matrix immediately satisfies all five physical verification gates (`./bin/<project>-verify`).

---

## Module Overview

- **[`Gachi.Sync.Types`](src/Gachi/Sync/Types.hs):** Structural data types for asset categories, standard assets, standardization matrices, audit statuses, and diagnostic reports.
- **[`Gachi.Sync.Matrix`](src/Gachi/Sync/Matrix.hs):** Canonical 9-dimensional Standardization Matrix definition and category lookup.
- **[`Gachi.Sync.Catalog`](src/Gachi/Sync/Catalog.hs):** Pure content generators for shared formatters, linters, Git hooks, CI workflows, and agent rules.
- **[`Gachi.Sync.Audit`](src/Gachi/Sync/Audit.hs):** Non-destructive audit engine inspecting physical workspaces against matrix contracts and formatting diagnostic reports.
- **[`Gachi.Sync.CI`](src/Gachi/Sync/CI.hs):** Forge-tiered CI matrix synthesizer and asymmetric runner allocation engine.
- **[`Gachi.Sync.Hash`](src/Gachi/Sync/Hash.hs):** Pure FIPS 180-2 SHA-256 differential cryptographic hashing engine.
- **[`Gachi.Sync.Engine`](src/Gachi/Sync/Engine.hs):** Harmonic chattering synchronization engine enforcing mathematical idempotency \(f(f(x)) = f(x)\).
- **[`Gachi.Sync`](src/Gachi/Sync.hs):** Root umbrella module re-exporting the complete synchronization API.

---

## Quick Example

```haskell
import Gachi.Schema.Project (defaultProject, Author(..))
import Gachi.Sync

-- Audit a target repository against the canonical matrix
main :: IO ()
main = do
  let auth = Author "Nadia Yvette Chambers" "nadia.yvette.chambers@ik.me"
      proj = defaultProject "gongju" auth
  report <- auditRepository "/home/nyc/src/gongju" proj canonicalMatrix
  putStrLn (formatAuditReport report)
```
