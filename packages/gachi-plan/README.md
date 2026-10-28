<!--
SPDX-License-Identifier: EUPL-1.2 OR Apache-2.0
-->
# gachi-plan — Detached Git Store Architecture & Ecosystem Plan Governance

`gachi-plan` provides isolated version-control and snapshot ledger infrastructure for ecosystem-wide planning documents (`~/src/PLAN.md` §1.A, Phase 5). It manages a detached Git repository tracking strategic governance documents without creating or writing nested `.git` directories in child repository workspaces.

## 1. Architectural Overview

Per Note [Plan Governance and Rollback Mechanics] [ref:note-plan-governance-rollback], the detached Git store operates under three strict invariants:

1. **Non-Interference Invariant:** The store is maintained in an external bare repository (`~/.plan.git` or `~/src/.plan.git`), completely avoiding nested `.git` directory collisions inside child repository checkouts (`~/src/gachi/.git`, `~/src/polytropos/.git`, etc.).
2. **Governed Documents Invariant:** Exclusively tracks top-level planning documents (`PLAN.md`, `STATE.md`, `INDEX.md`, and `docs/INDEX.md`), ignoring child repository source files through explicit pathspec scoping.
3. **Hermetic Store Execution:** All git invocations pass explicit `--git-dir` and `--work-tree` arguments, guaranteeing total independence from ambient working directory state or parent discovery.

```
~/src/ (Work Tree Root)
  ├── PLAN.md          ◄── Tracked by detached store
  ├── STATE.md         ◄── Tracked by detached store
  ├── INDEX.md         ◄── Tracked by detached store
  ├── docs/INDEX.md    ◄── Tracked by detached store
  │
  ├── gachi/           ─── Child Repo (.git intact, untouched)
  ├── polytropos/      ─── Child Repo (.git intact, untouched)
  └── ...
        ▲
        │ git --git-dir=~/.plan.git --work-tree=~/src
        ▼
~/.plan.git/ (Bare Detached Git Store)
  ├── HEAD
  ├── config (core.bare = true)
  ├── objects/
  └── refs/
```

## 2. Core Modules

- **`Gachi.Plan`**: Unified library facade re-exporting store and type abstractions.
- **`Gachi.Plan.Types`**: Algebraic data models (`PlanStore`, `PlanError`, `PlanStoreStatus`, `defaultGovernedFiles`).
- **`Gachi.Plan.Store`**: Detached bare Git repository initialization, status querying, file tracking, and commit operations.
