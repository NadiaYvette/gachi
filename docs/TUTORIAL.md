# Getting Started with gachi

A foundational tutorial for working with `gachi` — both as an unboxed osteological computation substrate and as the ecosystem's project skeleton and chattering configuration engine.

---

## 1. Concepts: Bones, Joints, and Skeletons

In `gachi`, systems and codebases are modeled as an osteological framework:
- **`Bone`**: An immutable structural node identified by a typed handle (`BoneId`). In repository architectures, this corresponds to an essential structural component (e.g. package manifest, verification script, design note).
- **`Joint`**: A connection point linking bones with atomic transition semantics (`JointId`).
- **`Skeleton`**: A flat, contiguous unboxed array containing bone topologies, joint mappings, and project schemas.

```haskell
module Tutorial where

import Gachi.Core

-- | Create an empty skeletal structure
emptyRig :: Skeleton ()
emptyRig = emptySkeleton

-- | Inspect bone count
boneCount :: Int
boneCount = totalBones emptyRig
```

---

## 2. Ecosystem Skeleton Generation (`gachi init`)

To scaffold a new repository adhering to the ecosystem standardization matrix:

1. Define a declarative project manifest in Dhall (leveraging `polytropos-dhall`):
   ```dhall
   let Gachi = https://raw.githubusercontent.com/NadiaYvette/polytropos/master/packages/polytropos-dhall/package.dhall
   in { name = "my-service"
      , license = "EUPL-1.2"
      , packages = [ "my-service-core", "my-service-server" ]
      , ghcVersion = "9.14.1"
      }
   ```

2. Invoke the skeleton builder:
   ```bash
   gachi init project.dhall
   ```
   This generates the standardized workspace skeleton: modular multi-package layout, `.githooks/`, `.gitmessage`, `.hlint.yaml`, `cabal.project`, `docs/notes/`, and `bin/<name>-verify`.

---

## 3. Chattering Configuration Synchronization (`gachi sync`)

When upstream improvements are made to linter rules, commit hooks, or agent advisory contexts in `polytropos` or `sarutahiko`:

```bash
# Propagate improvements across all repositories in lockstep
gachi sync --all
```

The bones chatter in harmonic resonance across `~/src/*`, updating shared infrastructure assets without overwriting repository-specific code.

---

## 4. Ecosystem Plan Governance (`gachi plan`)

To checkpoint or review strategic planning deltas in `~/src/PLAN.md`:

```bash
# Record an immutable planning checkpoint
gachi plan checkpoint "Refine §1 infrastructure specifications"

# View diff against prior checkpoint
gachi plan diff HEAD~1

# Restore an earlier strategic state if needed
gachi plan rollback <checkpoint-sha>
```

---

## 5. Invariant Verification

All osteological graphs and repository skeletons satisfy structural integrity laws verified via physical verification gates:

```bash
./bin/gachi-verify
```
