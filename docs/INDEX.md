# gachi Documentation Index & Reading Map

Welcome to the `gachi` technical documentation corpus.

This index maps the documentation of `gachi` per the policy established in [`docs/notes/DOC_STRATEGY.md`](notes/DOC_STRATEGY.md). Documents are segregated into distinct genres serving specific audiences with well-defined authority.

---

## 1. Corpus Inventory Matrix

| Document / Asset | Genre | Primary Audience | Authority | Status |
| :--- | :--- | :--- | :--- | :--- |
| [`README.md`](../README.md) | Orientation | Arrivals, Evaluators, All | Canonical (Orientation) | Living |
| [`docs/INDEX.md`](INDEX.md) | Inventory | All Audiences | Canonical (Reading Map) | Living |
| [`docs/TUTORIAL.md`](TUTORIAL.md) | Tutorial | API Consumers, Developers | Practical Primer | Living |
| [`docs/NEWBIE_GUIDE.md`](NEWBIE_GUIDE.md) | Onboarding | New Contributors, AI Drivers | Progressive Funnel | Living |
| [`docs/MAINTAINER_GUIDE.md`](MAINTAINER_GUIDE.md) | Operational | Maintainers, Subsystem Leads | Invariants & Runbooks | Living |
| [`PLAN.md`](../PLAN.md) | Governance | Maintainers, Contributors | Strategic Roadmap | Living |
| [`STATE.md`](../STATE.md) | Governance | Maintainers, AI Drivers | Active Session Frontier | Living |
| [`AGENTS.md`](../AGENTS.md) | Advisory | AI Coding Assistants | Advisory Boundaries | Living |
| [`.agents/rules/commit-attribution.md`](../.agents/rules/commit-attribution.md) | Advisory | AI Coding Assistants | Operational Rule | Living |
| [`.agents/rules/code-navigation.md`](../.agents/rules/code-navigation.md) | Advisory | AI Coding Assistants | Operational Rule | Living |
| [`.agents/rules/compiler-verification.md`](../.agents/rules/compiler-verification.md) | Advisory | AI Coding Assistants | Operational Rule | Living |
| [`.agents/rules/documentation-precedence.md`](../.agents/rules/documentation-precedence.md) | Advisory | AI Coding Assistants | Operational Rule | Living |
| [`docs/notes/GACHI_DESIGN.md`](notes/GACHI_DESIGN.md) | Design Note | Systems Architects, Maintainers | Canonical Decisions D1–D10 | Living |
| [`docs/notes/IMPLEMENTATION_PLAN.md`](notes/IMPLEMENTATION_PLAN.md) | Implementation | Developers, Contributors | Phase Roadmap (1–6) | Living |
| [`docs/notes/DOC_STRATEGY.md`](notes/DOC_STRATEGY.md) | Strategy | Authors, Maintainers | Corpus Policy & Rules | Living |
| [`docs/notes/COMMIT_ATTRIBUTION.md`](notes/COMMIT_ATTRIBUTION.md) | Policy | Contributors, Git Authors | RFC 2822 Trailer Standard | Living |

---

## 2. Active Package Catalog

| Package | Purpose & Capabilities | Primary Modules |
| :--- | :--- | :--- |
| [`packages/gachi-core/`](../packages/gachi-core/) | Contiguous osteology (`OsteoSegment`, `OsteoBytes`), lock-free atomic state machines (`Gachi.Core.Atomic`), Double-Pushout (DPO) algebraic graph rewriting, and Polytropos zero-cost coercions. | `Gachi.Core`, `Gachi.Osteology`, `Gachi.Core.Atomic`, `Gachi.Core.Rewriting` |
| [`packages/gachi-schema/`](../packages/gachi-schema/) | Declarative Dhall schemas, project model encoders/decoders, and Polytropos open record isomorphisms. | `Gachi.Schema.Project`, `Gachi.Schema.Package` |
| [`packages/gachi-scaffold/`](../packages/gachi-scaffold/) | Multi-package workspace scaffolding engine, canonical template synthesis, forge-tiered CI matrix generators (GitHub/GitLab), and turnkey verification harnesses. | `Gachi.Scaffold.Templates`, `Gachi.Scaffold.Engine` |
| [`packages/gachi-sync/`](../packages/gachi-sync/) | Cross-repository standardization matrix, shared asset catalog, repository audit engine, and differential configuration propagation (`gachi sync`). | `Gachi.Sync.Catalog`, `Gachi.Sync.Audit`, `Gachi.Sync.Engine` |
| [`packages/gachi-retrofit/`](../packages/gachi-retrofit/) | 6-pillar diagnostic repository inspection, quantitative retrofit scoring, non-destructive skeleton overlay, progressive quality gate realization (L0–L3), and Penelope arrow pipeline (`RetrofitPipeline`). | `Gachi.Retrofit`, `Gachi.Retrofit.Diagnostic`, `Gachi.Retrofit.Overlay`, `Gachi.Retrofit.Pipeline`, `Gachi.Retrofit.QualityGate` |
| [`packages/gachi-plan/`](../packages/gachi-plan/) | Deterministic versioning and rollback architecture for top-level strategic planning documents (`~/src/PLAN.md`, `~/src/STATE.md`) with detached Git store (`~/.plan.git`) and append-only snapshot ledger. | `Gachi.Plan.Store`, `Gachi.Plan.Snapshot`, `Gachi.Plan.Rollback` |
| [`packages/gachi-cli/`](../packages/gachi-cli/) | Unified command-line interface driver (`gachi init`, `gachi sync`, `gachi retrofit`, `gachi plan`, `gachi doctor`, `gachi verify`). | `Gachi.CLI`, `Gachi.CLI.Retrofit`, `Gachi.CLI.Plan` |

---

## 3. Curated Audience Reading Paths

### Path 1: The First 15 Minutes (Arrivals & Newcomers)
1. Read [`README.md`](../README.md) for the high-level onomatopoeic vision (*gachi-gachi* chattering), architectural pillars, and memory physics.
2. Read [`docs/NEWBIE_GUIDE.md`](NEWBIE_GUIDE.md) to adopt the 3-level token-conservation navigation funnel.
3. Walk through [`docs/TUTORIAL.md`](TUTORIAL.md) Lessons 1 and 2 to build an osteological rig and run `gachi init`.
4. Run `./bin/gachi-verify` to observe the 5-gate physical verification discipline.

### Path 2: The Systems & Osteology Engineer
1. Read [`docs/notes/GACHI_DESIGN.md`](notes/GACHI_DESIGN.md) for architectural decisions D1–D4 on contiguous memory layouts, amortized reallocation, and monotonic identifier allocation.
2. Inspect [`packages/gachi-core/src/Gachi/Osteology.hs`](../packages/gachi-core/src/Gachi/Osteology.hs) for `SmallArray#` contiguous layouts and $O(1)$ zero-copy slicing.
3. Inspect [`packages/gachi-core/src/Gachi/Core/Atomic.hs`](../packages/gachi-core/src/Gachi/Core/Atomic.hs) for lock-free CAS chattering concurrency.
4. Inspect [`packages/gachi-core/src/Gachi/Core/Rewriting.hs`](../packages/gachi-core/src/Gachi/Core/Rewriting.hs) for adhesive Double-Pushout algebraic graph transformations.
5. Study [`docs/TUTORIAL.md`](TUTORIAL.md) Lessons 1–4.

### Path 3: The Toolchain & Scaffolding Consumer
1. Read [`docs/notes/GACHI_DESIGN.md`](notes/GACHI_DESIGN.md) §3 (Ecosystem Skeleton Generation) and §4 (Chattering Configuration Synchronization).
2. Inspect [`packages/gachi-schema/src/Gachi/Schema/Project.hs`](../packages/gachi-schema/src/Gachi/Schema/Project.hs) for declarative Dhall project specifications.
3. Study [`packages/gachi-scaffold/src/Gachi/Scaffold/Templates.hs`](../packages/gachi-scaffold/src/Gachi/Scaffold/Templates.hs) for canonical template synthesis and forge-tiered CI matrix generators.
4. Follow [`docs/TUTORIAL.md`](TUTORIAL.md) Lessons 5–7.

### Path 4: The Ecosystem Administrator & Plan Maintainer
1. Read [`docs/notes/GACHI_DESIGN.md`](notes/GACHI_DESIGN.md) §5 (Ecosystem Plan Governance & Rollback) and [`docs/MAINTAINER_GUIDE.md`](MAINTAINER_GUIDE.md) §1.4 (5-Remote Replication Topology).
2. Inspect [`packages/gachi-plan/src/Gachi/Plan/Store.hs`](../packages/gachi-plan/src/Gachi/Plan/Store.hs) for detached Git metadata store mechanics (`~/.plan.git`).
3. Follow [`docs/TUTORIAL.md`](TUTORIAL.md) Lesson 9 (`gachi plan checkpoint`, `gachi plan diff`, `gachi plan rollback`).
4. Read [`docs/notes/COMMIT_ATTRIBUTION.md`](notes/COMMIT_ATTRIBUTION.md) for Linux kernel RFC 2822 trailer standards.

### Path 5: The Effect Pipeline & Retrofit Architect
1. Read [`packages/gachi-retrofit/src/Gachi/Retrofit/Diagnostic.hs`](../packages/gachi-retrofit/src/Gachi/Retrofit/Diagnostic.hs) for 6-pillar static repository analysis.
2. Read [`packages/gachi-retrofit/src/Gachi/Retrofit/Pipeline.hs`](../packages/gachi-retrofit/src/Gachi/Retrofit/Pipeline.hs) for Penelope polycategorical arrow pipeline integration (`PenelopeRope '[] '[]`).
3. Read [`packages/gachi-retrofit/src/Gachi/Retrofit/QualityGate.hs`](../packages/gachi-retrofit/src/Gachi/Retrofit/QualityGate.hs) for progressive compliance gate realization (L0–L3).
4. Follow [`docs/TUTORIAL.md`](TUTORIAL.md) Lesson 8.

### Path 6: The AI Coding Assistant
1. Read [`AGENTS.md`](../AGENTS.md) for non-negotiable operational guidelines.
2. Read [`PLAN.md`](../PLAN.md) and [`STATE.md`](../STATE.md) for current roadmap frontiers.
3. Read [`.agents/rules/documentation-precedence.md`](../.agents/rules/documentation-precedence.md) for the Section 4 precedence rule ("code wins at runtime; notes corrected regardless").
4. Read [`.agents/rules/commit-attribution.md`](../.agents/rules/commit-attribution.md) for `Assisted-by:` trailers.
5. Use [`.agents/rules/code-navigation.md`](../.agents/rules/code-navigation.md) for token-saving symbol navigation.

---

## 4. Autonomous Task Packets (`docs/task_packets/`)

| Packet | Subsystem | Purpose | Status |
| :--- | :--- | :--- | :--- |
| [`phase5-01-detached-git-store.yaml`](task_packets/phase5-01-detached-git-store.yaml) | `gachi-plan` | Detached Git metadata store architecture (`~/.plan.git`) | Complete |
| [`phase5-02-snapshot-ledger.yaml`](task_packets/phase5-02-snapshot-ledger.yaml) | `gachi-plan` | Append-only snapshot ledger with SHA256 verification | Complete |
| [`phase5-03-cli-plan-governance.yaml`](task_packets/phase5-03-cli-plan-governance.yaml) | `gachi-plan` / `gachi-cli` | CLI plan governance subcommands (`gachi plan`) | Complete |
| [`phase6-01-atomic-bone-machines.yaml`](task_packets/phase6-01-atomic-bone-machines.yaml) | `gachi-core` | Lock-free atomic bone state machines (`Gachi.Core.Atomic`) | Complete |
| [`phase6-02-multi-agent-traversal.yaml`](task_packets/phase6-02-multi-agent-traversal.yaml) | `gachi-core` | Concurrent multi-agent lock-free graph traversal | Complete |
| [`phase6-03-dpo-graph-rewriting.yaml`](task_packets/phase6-03-dpo-graph-rewriting.yaml) | `gachi-core` | Double-Pushout (DPO) algebraic graph transformations | Complete |
| [`phase6-04-polytropos-coercions.yaml`](task_packets/phase6-04-polytropos-coercions.yaml) | `gachi-core` | Polytropos zero-cost memory coercions (`Rep` $\leftrightarrow$ `OsteoSegment`) | Complete |

---

## 5. Physical Verification Harnesses (`bin/`)

- [`bin/gachi-verify`](../bin/gachi-verify) — Turnkey 5-gate physical verification runner.
- [`bin/generate-tags`](../bin/generate-tags) — Fast symbol tag generator for token-efficient navigation.
- [`bin/gachi-tagref`](../bin/gachi-tagref) — Cross-reference integrity validator.
- [`bin/gachi-linkcheck`](../bin/gachi-linkcheck) — Markdown link and anchor validator.
- [`bin/gachi-cloc`](../bin/gachi-cloc) — Comment density audit enforcing the 50%+ comment policy.
