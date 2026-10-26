# gachi-scaffold

**Declarative Multi-Package Workspace Scaffolding Engine for Gachi**

`gachi-scaffold` generates complete, turn-key Haskell workspaces adhering strictly to the canonical ecosystem standardization matrix (`~/src/PLAN.md` §1 and `Note [Ecosystem Standardization Invariants]` `[ref:note-ecosystem-standardization]`).

## Overview

Given a declarative `Project` specification from `gachi-schema` (loaded from Dhall or instantiated in Haskell), `gachi-scaffold` synthesizes the entire canonical repository skeleton:

1. **Multi-Package Hierarchy:**
   - Modular package directories (`packages/<name>/src`, `packages/<name>/test`)
   - Fully configured Cabal 3.0 package manifests (`packages/<name>/<name>.cabal`)
   - Initial Haskell modules with comprehensive Haddock documentation, passing the $\ge 50\%$ comment density gate out of the box
   - Standard Hspec test suites (`packages/<name>/test/Main.hs`)

2. **Root Toolchain & Build Assets:**
   - Multi-package `cabal.project` pinning GHC (9.14.1) and Cabal (3.18)
   - Developer configuration template `cabal.project.local.example`
   - Strict HLint configuration `.hlint.yaml` enforcing zero-hint cleanliness
   - Git commit message template `.gitmessage` with Sarutahiko AI attribution rules
   - Git hooks `.githooks/commit-msg` (RFC 2822 trailer validation) and `.githooks/pre-commit` (tagref and linkcheck validation)

3. **Canonical Documentation Corpus:**
   - System design note `docs/notes/<PROJECT>_DESIGN.md`
   - Corpus inventory `docs/INDEX.md`
   - Interactive getting started guide `docs/TUTORIAL.md`
   - Token-conservation guide `docs/NEWBIE_GUIDE.md`
   - Architectural governance guide `docs/MAINTAINER_GUIDE.md`
   - Documentation policy `docs/notes/DOC_STRATEGY.md`
   - Commit attribution guidelines `docs/notes/COMMIT_ATTRIBUTION.md`

4. **Turnkey Verification Suite (`bin/`):**
   - 5-gate physical verification script `bin/<project>-verify`
   - Mechanical Tagref cross-reference validator `bin/<project>-tagref`
   - Markdown relative link & anchor validator `bin/<project>-linkcheck`
   - In-code comment density audit harness `bin/<project>-cloc`
   - Symbol tag indexer `bin/generate-tags`

5. **Operational Governance & Agent Guidance:**
   - Strategic roadmap `PLAN.md` and active frontier `STATE.md`
   - Agent advisory context `AGENTS.md` and `CLAUDE.md` pointer
   - Subdivided operational rules under `.agents/rules/`

## Invariants & Notes

- **Note [Ecosystem Standardization Invariants]** `[ref:note-ecosystem-standardization]`:
  Every generated repository skeleton must satisfy all 5 physical verification gates immediately upon creation without human intervention.
- **Note [Dhall Parameterized Skeleton Templating]** `[ref:note-dhall-skeleton-templating]`:
  All template rendering functions are pure, deterministic functions of the underlying `Project` schema.

## License

EUPL-1.2 (European Union Public Licence 1.2).
