# Credits and Intellectual Acknowledgments — Gachi

This document honors the researchers, engineers, and open-source maintainers whose
work, designs, and architectural principles informed the creation of Gachi.
Per `docs/notes/DOC_STRATEGY.md` §9, credit in this repository is granted **by choice,
not mere legal obligation** — celebrating the conceptual debts we owe across the
ecosystem.

---

## 1. Key Individuals and Ecosystems

### Simon Peyton Jones, Simon Marlow & The GHC Team
- **Contribution:** Engineered the Glasgow Haskell Compiler runtime system, primitive
  memory operations (`SmallArray#`, `MutableArray#`), and atomic synchronization primitives
  that power Gachi's lock-free skeletal osteology.

### Roman Leshchinskiy & The Primitive Maintainers
- **Projects:** *primitive*, *vector*
- **Contribution:** Standardized low-level memory abstractions (`Data.Primitive.SmallArray`)
  enabling unboxed and contiguous array manipulation in pure Haskell with zero GC overhead.

### Andrey Mokhov & The Newcastle / Jane Street Research Group
- **Projects:** *Algebraic Graphs* (`alga`), *Selective Applicative Functors*
- **Contribution:** Formulated algebraic representations of graph structures, directly
  informing Gachi's skeletal joint-and-bone topological relationship models.

### Edward Kmett
- **Projects:** *lens*, *ad*, *thc*
- **Contribution:** Advanced zero-cost combinators, high-performance category-theoretic
  data structures, and impeccable documentation and provenance verification practices.

### Edsko de Vries & Well-Typed
- **Projects:** *large-records*, *large-anon*
- **Contribution:** Pioneered $O(1)$ compile-time flat memory record layouts that inspired
  Gachi's single-indirection osteological payload slots.

---

## 2. Institutional and Academic Lineage

- **Non-blocking Data Structures & Lock-Free Synchronization** (Maurice Herlihy, Nir Shavit):
  Monotonic version stamps and lock-free atomic graph mutations.
- **Cache-Conscious Contiguous Memory Layouts** (Ulrich Drepper, *What Every Programmer Should Know About Memory*):
  Contiguous osteological memory segments eliminating pointer chasing and CPU L1/L2 cache misses.
