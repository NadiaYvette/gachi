# AGENTS.md — Advisory Context for AI Coding Assistants

Pointer file. Canonical sources win on any disagreement.

## What this repository is

`gachi` (from the onomatopoeia for gashadokuro teeth chattering, がちがち) — the ecosystem project skeleton generator and configuration propagation infrastructure (`~/src/PLAN.md` §1), paired with a high-performance osteological computation and structural Haskell substrate. Flat contiguous memory layouts, unboxed representations, and deterministic lock-free state synchronization.

## Read first, in this order

1. `README.md` — what this is, and its status.
2. `PLAN.md` & `STATE.md` — operational roadmap and active session frontier.
3. `docs/notes/GACHI_DESIGN.md` — canonical design notes: architectural decisions, memory layout invariants, and open questions.
4. `docs/notes/DOC_STRATEGY.md` — documentation policy: genres, lifecycle, canonicity, tone. §4's precedence rule fires most.
5. `docs/INDEX.md` — corpus inventory and reading map.

## Subdivided operational rules (`.agents/rules/`)

To conserve context tokens and prevent attention degradation, operational guidance is subdivided into modular rules loaded on demand:

- [`.agents/rules/commit-attribution.md`](.agents/rules/commit-attribution.md) —
  Linux kernel RFC 2822 trailer format (`Assisted-by:`), DCO boundaries, and hook enforcement.
- [`.agents/rules/code-navigation.md`](.agents/rules/code-navigation.md) —
  Token-saving funnel (`./tags` symbol jump, `ast-grep`, targeted slice viewing).
- [`.agents/rules/compiler-verification.md`](.agents/rules/compiler-verification.md) —
  Zero-log compiler verification (`tricorder status --json`), tests, and zero-contamination.
- [`.agents/rules/documentation-precedence.md`](.agents/rules/documentation-precedence.md) —
  Precedence rule ("code wins at runtime; notes corrected regardless") and the two-file loop.
- [`.agents/rules/hls-housekeeping.md`](.agents/rules/hls-housekeeping.md) —
  Zero-token mechanical code repairs via `hls-autoheal`.
- [`.agents/rules/kioku-context.md`](.agents/rules/kioku-context.md) —
  Durable memory offloading (`kioku-remember`) and `/compact` cadence.
- [`.agents/rules/plugin-invariants.md`](.agents/rules/plugin-invariants.md) —
  TcPlugin literal index evidence and Core AST dictionary synthesis.
- [`.agents/rules/task-execution.md`](.agents/rules/task-execution.md) —
  Yamaarashi runner invariants, `executor: auto` preference, and zero-polling discipline.

## Subdivided operational skills (`.agents/skills/`)

- [`.agents/skills/code-navigation/SKILL.md`](.agents/skills/code-navigation/SKILL.md) — Fast, token-efficient code navigation using tags, ripgrep, and ast-grep.
- [`.agents/skills/contextful/SKILL.md`](.agents/skills/contextful/SKILL.md) — Query project context packs, local FTS5 BM25 search.
- [`.agents/skills/kioku/SKILL.md`](.agents/skills/kioku/SKILL.md) — Durable agent memory and hybrid recall via shinzui kioku.
- [`.agents/skills/ponytail/SKILL.md`](.agents/skills/ponytail/SKILL.md) — Minimalist / YAGNI / lazy-mode coding.
- [`.agents/skills/shikumi/SKILL.md`](.agents/skills/shikumi/SKILL.md) — Typed language-model programs & hierarchical tracing.
- [`.agents/skills/tricorder/SKILL.md`](.agents/skills/tricorder/SKILL.md) — Check continuous GHCi build status and zero-log compiler diagnostics.
- [`.agents/skills/yamaarashi/SKILL.md`](.agents/skills/yamaarashi/SKILL.md) — Autonomous task packet runner and ASCII Kanban board projection.

## Operational advisories

1. **Design docs are load-bearing.** A change that makes the design note stale must correct the note in the same change set. Code wins at runtime; the note must still be fixed, not ignored. (`DOC_STRATEGY.md` §4.)
2. **Commits:** descriptive-imperative subject under 72 chars, body explains why, HEREDOC style. AI attribution uses git trailers per `sarutahiko`:
   `Assisted-by: <Tool> (<Provider> / <Model>)` (or `<Tool>`) and optional `Orchestrated-by: <Engine>`. Never `Co-authored-by:` or `Signed-off-by:` for AI tools (only humans certify the DCO). Enforced by `.githooks/commit-msg`; template in `.gitmessage`.
3. **Toolchain:** GHC 9.14 / Cabal 3.18; features opt in via cabal commons only. Tests: Hspec / Tasty.
4. **This file has a ~4 KB budget.** Add links, not content.
5. **Two-file loop.** Update `STATE.md` before ending or resetting a session; fresh sessions initialise from `PLAN.md` and `STATE.md`.
