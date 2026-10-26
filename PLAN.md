# gachi — Strategic Roadmap (`PLAN.md`)

**Status:** ACTIVE STRATEGIC ROADMAP · October 2026  
**Scope:** Ecosystem Skeleton Generation, Chattering Configuration Propagation, and Osteological Computing  
**Canonical Anchor:** Linked to and implementing [`../PLAN.md` §1](../PLAN.md#1-project-skeleton-&-configuration-propagation-infrastructure-gachi)  
**Implementation Plan:** [`docs/notes/IMPLEMENTATION_PLAN.md`](docs/notes/IMPLEMENTATION_PLAN.md)

---

## Phase 1: Foundational Skeleton & Osteological Memory (`gachi-core`) [COMPLETED]

- [x] **Milestone 1.1:** Canonical Repository Skeleton Grounding
  - Git repository initialization, `.githooks/` (`commit-msg`, `pre-commit`), `.gitmessage`.
  - Multi-forge CI configuration (`.github/workflows/ci.yml`, `.gitlab-ci.yml`).
  - Agent advisory layer (`AGENTS.md`, compatibility symlinks, modular rules in `.agents/rules/`).
  - 5-gate physical verification harness (`./bin/gachi-verify`).
- [x] **Milestone 1.2:** Unboxed Osteological Primitives
  - Contiguous primitive arrays (`SmallArray#`, `ByteArray#`) with compile-time bone indices (`BoneId`, `JointId`).
  - Constant-time $O(1)$ bone lookup and zero-allocation traversal (`indexOsteo`, `unsafeIndexOsteo`, `lookupBone`, `unsafeLookupBone`).
  - Zero-copy slicing (`sliceOsteo`, `sliceBytes`, `sliceBones`) without intermediate heap reallocation.
  - Comprehensive Hspec specification validating capacity growth, bounds safety, Semigroup concatenation, and roundtrip fidelity.
- [x] **Milestone 1.3:** Tagref & In-Code Notes Grounding
  - Canonical GHC Notes architecture grounded in code, tests, monographs, and maintainer guidance:
    - `Note [Osteological Contiguous Memory Layout]` (`[ref:note-osteology-memory-layout]`)
    - `Note [Zero-Copy Sub-Segment Slicing]` (`[ref:note-zero-copy-slicing]`)
    - `Note [Geometric Capacity Expansion and Reallocation]` (`[ref:note-geometric-capacity-expansion]`)
    - `Note [Chattering Lock-Free Atomic Synchronization]` (`[ref:note-chattering-synchronization]`)
    - `Note [Monotonic Identifier Allocation and Contiguous Indexing]` (`[ref:note-monotonic-id-allocation]`)
    - `Note [Directional Joints and Incident Traversal]` (`[ref:note-directional-joints-traversal]`)
    - `Note [Ecosystem Standardization Invariants]` (`[ref:note-ecosystem-standardization]`)
    - `Note [Dhall Parameterized Skeleton Templating]` (`[ref:note-dhall-skeleton-templating]`)
    - `Note [Plan Governance and Rollback Mechanics]` (`[ref:note-plan-governance-rollback]`)
    - `Note [Non-Destructive Skeleton Overlay]` (`[ref:note-nondestructive-retrofit]`)
  - 10 tags, 60 references, 0 dangling references, and 0 duplicate tags verified via `./bin/gachi-tagref`.

---

## Phase 2: Declarative Project Skeleton Generator (`gachi init`) [ACTIVE]

- [x] **Milestone 2.1:** Dhall-Parameterized Project Schema (`polytropos-dhall`)
  - Grounded declarative Dhall types for project metadata, modular package DAGs, Cabal 3.18 / GHC 9.14 stanzas, license terms (EUPL-1.2), and author information in `Gachi.Schema.Project` and `Gachi.Schema.Dhall`.
  - Implemented strongly-typed deserialization using `polytropos-dhall`'s `FromDhall` / `ToDhall` via `GenericDhall` and isomorphic open row representations (`ProjectRec`, `AuthorRec`, `PackageRec`, `RemoteRec`) backed by contiguous Polytropos `RowRep` storage.
  - Verified 12/12 passing Hspec tests validating nominal decoding, open row roundtripping, pretty-printing, and safe error handling.
- [x] **Milestone 2.2:** Multi-Package Workspace Scaffolding & Structured Markdown AST (`gachi-scaffold`)
  - Grounded declarative scaffolding engine `packages/gachi-scaffold` synthesizing complete canonical ecosystem workspaces: multi-package hierarchy (`packages/*/src`, `packages/*/test`, `.cabal`), toolchain configs (`cabal.project`, `cabal.project.local.example`, `.hlint.yaml`, `.gitmessage`, `.githooks/`), documentation corpus (`docs/notes/`, `docs/INDEX.md`, `docs/TUTORIAL.md`, `docs/NEWBIE_GUIDE.md`, `docs/MAINTAINER_GUIDE.md`, `docs/notes/DOC_STRATEGY.md`, `docs/notes/COMMIT_ATTRIBUTION.md`), and operational files (`PLAN.md`, `STATE.md`, `AGENTS.md`, `CLAUDE.md`, `.agents/rules/`).
  - Implemented lean, pure-Haskell GitHub-Flavored Markdown (GFM) / CommonMark AST and deterministic pretty-printer in `Gachi.Scaffold.Markdown` with typed blocks (`Heading`, `Paragraph`, `FencedCode`, `BulletList`, `OrderedList`, `Table`, `ThematicBreak`, `RawBlock`), inlines (`Plain`, `Bold`, `Italic`, `Code`, `Link`, `TagRef`, `TagDef`, `Inlines`), and dynamic table column measurement and alignment.
  - Refactored all repository documentation and operational governance templates in `Gachi.Scaffold.Templates` to construct structured `[Block]` AST representations and render via `renderMarkdown` rather than raw string concatenation.
  - Implemented turnkey 5-gate physical verification script generators (`bin/<name>-verify`, `bin/generate-tags`, `bin/<name>-tagref`, `bin/<name>-linkcheck`, `bin/<name>-cloc`).
  - Canonically grounded `Note [Ecosystem Standardization Invariants]` (`[ref:note-ecosystem-standardization]`) in `Gachi.Scaffold`.
  - Verified 20/20 passing Hspec tests validating GFM AST pretty-printing, dynamic table layout, pure generation, filesystem materialization modes (`FailOnExisting`, `SkipExisting`, `OverwriteExisting`), and physical gate self-consistency on generated target projects.
- [x] **Milestone 2.3:** CLI Tooling (`gachi init`)
  - Implemented turnkey unified CLI binary in `packages/gachi-cli/` (`Gachi.CLI`, `Gachi.CLI.Init`, `Gachi.CLI.Options`, `app/Main.hs`).
  - Added support for `--config <file.dhall>`, `--target-dir <path>`, `--mode <fail|skip|overwrite>`, `--no-git`, `--dry-run`, and `--interactive`.
  - Implemented hermetic Git repository initialization (`git init`), commit template pinning (`commit.template = .gitmessage`), and hook activation (`core.hooksPath = .githooks`).
  - Verified 10/10 passing Hspec test suite covering option parsing, Dhall decoding, headless workspace generation, and write modes.
  - Passed all 5 physical verification gates in `./bin/gachi-verify` with 0 HLint hints, 0 broken links, 0 dangling tags, and >= 50% comment density in production code.

---

## Phase 3: Chattering Configuration Propagation (`gachi sync`)

- [x] **Milestone 3.1:** Cross-Repository Standardization Matrix (`~/src/PLAN.md` §1.A)
  - Established `packages/gachi-sync` library implementing the 9-dimensional Standardization Matrix data models (`Gachi.Sync.Types`), canonical shared asset catalog (`Gachi.Sync.Catalog`), authoritative matrix registry (`Gachi.Sync.Matrix`), and read-only repository audit engine (`Gachi.Sync.Audit`).
  - Grounded `Note [Cross-Repository Standardization Matrix and Audit Semantics]` (`[ref:note-standardization-matrix]`) with 14 tags and 101 cross-references validated by Tagref.
  - Verified 21/21 passing Hspec tests validating canonical matrix completeness, category queries, path token substitution, audit compliance, content drift detection, missing file reporting, and ASCII diagnostic table formatting.
- [x] **Milestone 3.2:** Harmonic Chattering Synchronization (`gachi sync`)
  - Built pure, self-contained FIPS 180-2 SHA-256 differential cryptographic hashing engine (`Gachi.Sync.Hash`) with zero external crypto dependencies.
  - Implemented harmonic chattering synchronization engine (`Gachi.Sync.Engine`) providing `SyncMode` (`DryRun`, `ApplySync`), atomic action planning (`ActionCreate`, `ActionUpdate`, `ActionChmod`, `ActionNoOp`), `SyncPlan`, `SyncResult`, `computeSyncPlan`, `executeSyncPlan`, `syncRepository`, `syncRepositoryQuick`, `discoverEcosystemRepositories`, and `syncEcosystem`.
  - Enforced and mathematically verified the strict idempotency property: \(f(f(x)) = f(x)\), ensuring that applying synchronization a second time produces an empty modification set.
  - Grounded CLI integration in `packages/gachi-cli` (`Gachi.CLI.Sync`) supporting `gachi sync [--target DIR] [--dry-run] [--all]`, with rich diagnostic ASCII summary tables.
  - Grounded `Note [Harmonic Chattering Synchronization and Differential Propagation]` (`[ref:note-harmonic-sync]`).
  - Verified 30/30 passing `gachi-sync` tests and 14/14 passing `gachi-cli` tests covering SHA-256 NIST vectors, plan evaluation, dry-run simulation, live repair, ecosystem discovery, and mathematical idempotency.
  - Passed all 5 physical verification gates in `./bin/gachi-verify`: 0 HLint hints, all test suites passed, 15 tags and 110 references validated, 0 broken markdown links, and 50.0% production source comment density.
- [x] **Milestone 3.3:** Forge-Tiered CI Matrix Generation
  - Established dedicated CI synthesis module `packages/gachi-sync/src/Gachi/Sync/CI.hs` modeling `ForgeType` (`ForgeGitHub`, `ForgeGitLab`, `ForgeWoodpecker`, `ForgeForgejo`, `ForgeRadicle`), `CITier` (`TierHighResource`, `TierLightweightStatic`), and `CISpec`.
  - Implemented pure deterministic workflow generators for high-resource commercial runners (`generateGitHubWorkflow`) featuring GHC 9.14.1, Cabal 3.18.1.0, Cabal store caching (`actions/cache@v4`), AppArmor unprivileged user namespace configuration, and turnkey physical verification (`./bin/<project>-verify`).
  - Implemented lightweight static gate generators for community runners (`generateGitLabWorkflow`, `generateWoodpeckerWorkflow`, `generateRadicleWorkflow`) executing Tagref (0 dangling references), linkcheck (0 broken links), and comment density audits (`./bin/<project>-cloc --check`) inside minimal `debian:bookworm-slim` containers in < 15 seconds without GHC compilation overhead.
  - Provided standard defaults (`defaultGitHubSpec`, `defaultGitLabSpec`, `defaultWoodpeckerSpec`, `canonicalForgeSpecs`), classification predicates (`classifyForge`, `classifyTier`, `isHighResource`, `isLightweight`), and matrix synthesis combinators (`synthesizeCIAssets`, `canonicalCIAssets`, `ciWorkflowAssets`).
  - Integrated CI generators into `Gachi.Sync.Catalog` (`githubCiTemplate`, `gitlabCiTemplate`, `woodpeckerCiTemplate`) and `Gachi.Sync.Matrix` (`ciWorkflowAssets`).
  - Canonically grounded `Note [Forge-Tiered CI Resource Allocation and Static Gate Partitioning]` (`[ref:note-forge-tiered-ci]`) with 16 tags and 128 references validated across 82 files.
  - Verified 39/39 passing Hspec tests in `packages/gachi-sync/test/Main.hs` (97/97 total tests across all 5 packages) and passed all 5 physical verification gates in `./bin/gachi-verify` with 50.7% production comment density.
- [x] **Milestone 3.4:** Multi-Remote Topology Management
  - Grounded canonical 5-mirror remote topology across all ecosystem checkouts in `packages/gachi-sync/src/Gachi/Sync/Remote.hs`: sovereign peer-to-peer storage `rad` (`rad://...`), commercial cloud mirrors `github` (`git@github.com:...`) and `gitcode` (`git@gitcode.com:...`), community mirrors `framagit` (`git@framagit.org:...`) and `disroot` (`git@git.disroot.org:...`), and aggregate multi-push remote `all`.
  - Implemented provider compliance auditing (`isProviderCompliant`, `classifyProvider`) enforcing exclusion of non-compliant forges (e.g., SourceHut / `git.sr.ht` due to AI pair programming tool prohibitions and email-only workflows) and insecure plaintext transports.
  - Implemented pure topology analysis combinators (`evaluateRemoteTopology`, `computeRemoteSyncPlan`, `normalizeRemoteUrl`, `urlsMatch`) and live Git remote mutation routines (`queryGitRemotes`, `executeRemoteSyncPlan`, `syncRemoteTopology`, `syncRemoteTopologyQuick`).
  - Extended CLI options in `packages/gachi-cli` with `--remotes` / `-r` flag for `gachi sync` to audit and reconcile remote configurations in standalone or batch modes.
  - Canonically grounded `Note [Multi-Remote Replication Topology and Provider Compliance]` (`[ref:note-remote-topology]`).
  - Verified 47/47 passing tests in `packages/gachi-sync/test/Main.hs` and 16/16 in `packages/gachi-cli/test/Main.hs` (107/107 total tests across all workspace packages) and passed all 5 physical verification gates in `./bin/gachi-verify` with 50.1% production comment density.

---

## Phase 4: Project Retrofitting Engine (`gachi retrofit`)

- [ ] **Milestone 4.1:** Diagnostic Repository Inspector
  - Static analysis of arbitrary target checkouts: detects language stacks, build systems, existing tests, and missing ecosystem standards.
- [ ] **Milestone 4.2:** Non-Destructive Skeleton Overlay
  - Safely scaffolds missing documentation hierarchies, hooks, and verification harnesses without perturbing existing domain logic.
- [ ] **Milestone 4.3:** Progressive Quality Gate Realization
  - Incremental remediation pipelines: bringing builds under `-Wall -Werror`, purging HLint warnings, and grounding physical verification gates.

---

## Phase 5: Ecosystem Plan Governance & Rollback (`gachi plan` / `plan-ctl`)

- [ ] **Milestone 5.1:** Detached Git Store Architecture (`~/src/.plan.git`)
  - Initialize isolated Git repository tracking ecosystem governance files (`PLAN.md`, `STATE.md`, `INDEX.md`) across `~/src/` without interfering with child git checkouts.
- [ ] **Milestone 5.2:** Append-Only Snapshot Ledger (`~/src/plans/snapshots/`)
  - Automated pre-mutation snapshots with timestamped filenames and SHA256 integrity checksums.
- [ ] **Milestone 5.3:** CLI Plan Governance Subcommands
  - `gachi plan checkpoint [message]`: Atomic commit to detached store + snapshot.
  - `gachi plan diff [ref]`: Semantic delta display against prior checkpoints.
  - `gachi plan log`: Chronological history of ecosystem planning revisions.
  - `gachi plan rollback <checkpoint>`: Deterministic, atomic restoration of planning state.

---

## Phase 6: Lock-Free Chattering Synchronization & Graph Transformations

- [ ] **Milestone 6.1:** Atomic Bone State Machines
  - Non-blocking compare-and-swap (CAS) primitives on osteological joints.
  - Deterministic lock-free consensus and harmonic synchrony.
- [ ] **Milestone 6.2:** Multi-Agent Concurrent Traversal
  - Safe concurrent traversals without global locks; formal race-freedom guarantees.
- [ ] **Milestone 6.3:** Double-Pushout (DPO) Algebraic Graph Rewriting
  - Algebraic rewriting over osteological topologies; fusion with `gargamelle` rewriting engines.
- [ ] **Milestone 6.4:** Polytropos Zero-Cost Coercions
  - Zero-copy mapping between osteological arrays and `polytropos-core` flat `Rep` structures.
