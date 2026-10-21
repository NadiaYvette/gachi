# Gachi Newbie Quickstart & Token-Conservation Guide

**Audience:** New human contributors and AI coding assistant drivers (Antigravity, Claude Code, Cursor, Aider).  
**Parent Strategy:** [`docs/notes/DOC_STRATEGY.md`](notes/DOC_STRATEGY.md)  
**Corpus Inventory:** [`docs/INDEX.md`](INDEX.md)  
**Interactive Tutorial:** [`docs/TUTORIAL.md`](TUTORIAL.md)  
**Maintainer Guide:** [`docs/MAINTAINER_GUIDE.md`](MAINTAINER_GUIDE.md)  

---

## 1. The Core Invariant: Never Dump Whole Modules

In high-performance systems code dealing with unboxed arrays, primitive state, and lock-free synchronization, dumping full source modules into the conversation context wastes tokens and causes attention degradation.

Always follow the **Progressive Disclosure Funnel**:

```
Level 0: Global Navigation  (docs/INDEX.md, packages/ overview)   →   ~10–50 tokens
Level 1: Structural Outline (module export lists, type headers)   →   ~100–250 tokens
Level 2: Targeted Slice     (view_file StartLine / EndLine)       →   ~200–500 tokens
```

---

## 2. Fast Package & Symbol Navigation (Level 0 — <20 tokens)

Before opening any file, identify the module owning the concept:

| If you are looking for... | Look in module | Source Location |
| :--- | :--- | :--- |
| `BoneId`, `JointId`, `Skeleton`, lock-free sync | `Gachi.Core` | `packages/gachi-core/src/Gachi/Core.hs` |
| `OsteoSegment`, `appendOsteo`, unboxed arrays | `Gachi.Osteology` | `packages/gachi-core/src/Gachi/Osteology.hs` |
| Verification tests and property suites | `Main` (Test) | `packages/gachi-core/test/Main.hs` |
| Repository skeleton generator & templating | `gachi init` | `docs/TUTORIAL.md` §2 / `~/src/PLAN.md` §1.B |
| Chattering configuration propagation | `gachi sync` | `docs/TUTORIAL.md` §3 / `~/src/PLAN.md` §1.C |
| Plan checkpointing & rollback governance | `gachi plan` | `docs/TUTORIAL.md` §4 / `~/src/PLAN.md` §1.E |

View targeted slices using `view_file` (typically 40–80 lines) around target symbols.
