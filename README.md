# gachi — がちがち

> **gachi** (*onomatopoeia*): The sharp, rhythmic clicking and chattering sound of the teeth of a *gashadokuro* (がしゃどくろ) — the colossal mythical skeleton formed from the spirits of those fallen in famine and battle.

`gachi` is a high-performance skeletal computation and bone-crunching structural Haskell substrate. It provides flat, contiguous, unboxed osteological memory representations, zero-copy graph transformations, and deterministic lock-free state synchronization.

---

## Architecture & Design Pillars

1. **Osteological Layouts (`Gachi.Osteology`):**
   Flat contiguous memory representations combining unboxed primitive arrays (`SmallArray#`, `ByteArray#`) with compile-time bone indices, avoiding pointer chasing and eliminating garbage collection pressure.
2. **Deterministic Chattering Synchronization (`Gachi.Core`):**
   Lock-free, atomic synchronization primitives designed for harmonic multi-agent consensus and high-throughput concurrent evaluation.
3. **Rigid Invariant Enforcement:**
   Every structural transformation satisfies strict formal preservation laws verified via Hspec property tests and in-code GHC Notes.
4. **Canonical Ecosystem Standards:**
   Engineered to align seamlessly with `~/src/polytropos/`, `~/src/gargamelle/`, and `~/src/sarutahiko/`.

---

## Repository Layout

```text
packages/
  gachi-core/             -- Foundational osteological types, memory layouts, and primitives
docs/
  INDEX.md                -- Corpus reading map and documentation inventory
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
