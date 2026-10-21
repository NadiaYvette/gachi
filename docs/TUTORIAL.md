# Getting Started with gachi

A foundational tutorial for working with osteological data structures and lock-free chattering synchronization.

---

## 1. Concepts: Bones, Joints, and Skeletons

In `gachi`, computational structures are organized like an osteological skeleton:
- **`Bone`**: An immutable structural node identified by a typed handle.
- **`Joint`**: A connection point linking two or more bones.
- **`Skeleton`**: A flat, contiguous unboxed array containing bone topologies and joint mappings.

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

## 2. Invariant Verification

All osteological graphs satisfy structural integrity laws verified via physical verification gates.
To verify your environment:

```bash
./bin/gachi-verify
```
