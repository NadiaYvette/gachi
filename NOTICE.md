# Licensing and Reuse Provenance — Gachi Ecosystem

Gachi is licensed under the **European Union Public Licence v. 1.2 (EUPL-1.2)**. Original contributions
and osteological graph architectures are Copyright (c) 2026, Nadia Yvette Chambers.
See [LICENSE](LICENSE) and [LICENSES/EUPL-1.2.txt](LICENSES/EUPL-1.2.txt).

---

## 1. The Derivation & Attribution Principle

Gachi (from the Japanese onomatopoeia for teeth chattering, がちがち) embodies a foundational
design philosophy: **flat contiguous osteological memory layouts, zero-overhead unboxed
representations, and deterministic lock-free state synchronization.**

Per `docs/notes/DOC_STRATEGY.md` §9 and maintainer doctrine:
**intellectual derivation credit is granted by deliberate choice, not merely where statutory
copyright laws or license obligations compel it.**

Even where clean-room re-implementation or absence of direct patch deltas removes legal copyleft
requirements, this repository treats the synthesis, adaptation, and re-expression of low-level
data structures and lock-free algorithms as genuine intellectual derivations.

Third-party ancestral projects, conceptual donors, and component licenses are detailed below.
Retained upstream licenses are cataloged in the `LICENSES/` directory.

---

## 2. Genealogy & Ancestral Attribution by Subsystem

### 2.1 Low-Level Primitive Arrays & Contiguous Memory (`packages/gachi-core`)

- **GHC Primitives & `primitive` library** (BSD-3-Clause)
  - *Ancestral Role:* Gachi's osteological contiguous segment storage relies on
    unboxed memory operations (`Data.Primitive.SmallArray`) derived from GHC primops.
  - *Terms:* [LICENSES/BSD-3-Clause.txt](LICENSES/BSD-3-Clause.txt).
- **Haskell `containers`** (BSD-3-Clause)
  - *Ancestral Role:* Skeletal topological indexing structures utilize `Data.IntMap.Strict`
    for $O(\min(n, W))$ joint indexing.
  - *Terms:* [LICENSES/BSD-3-Clause.txt](LICENSES/BSD-3-Clause.txt).
- **Hspec Test Framework** (MIT)
  - *Ancestral Role:* Specification and property verification harness in `test/Main.hs`.
  - *Terms:* [LICENSES/MIT.txt](LICENSES/MIT.txt).
