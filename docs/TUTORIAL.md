# Hands-on Tutorial: Mastering Gachi

**Status:** LIVING DOCUMENT · v1.1 · 2026-11-03  
**Audience:** Developers, Systems Engineers, Ecosystem Maintainers  
**Parent Strategy:** [`docs/notes/DOC_STRATEGY.md`](notes/DOC_STRATEGY.md)  
**Corpus Inventory:** [`docs/INDEX.md`](INDEX.md)  
**Newbie Guide:** [`docs/NEWBIE_GUIDE.md`](NEWBIE_GUIDE.md) · **Maintainer Guide:** [`docs/MAINTAINER_GUIDE.md`](MAINTAINER_GUIDE.md)  

Welcome to the comprehensive, hands-on tutorial for `gachi`. This tutorial guides you through the dual nature of `gachi`:
1. **The Osteological Computation Substrate:** Contiguous unboxed memory, lock-free chattering concurrency, DPO algebraic graph rewriting, and Polytropos zero-cost coercions.
2. **The Sovereign Ecosystem Infrastructure:** Dhall project schemas, workspace scaffolding, configuration synchronization, non-destructive retrofitting via Penelope polycategorical arrow pipelines, and detached plan governance.

---

## Lesson 1: Contiguous Osteology & Memory Physics

Standard Haskell tree representations incur severe pointer chasing and GC fragmentation. `gachi-core` models structural data as an osseous scaffold: flat, contiguous arrays with zero heap indirection.

### 1.1 Core Concepts
- **`OsteoSegment a`:** A contiguous slice of elements backed by GHC primitive `SmallArray#`.
- **`BoneId`:** A lightweight, unboxed integer handle mapping directly to an array offset without hash collisions or tree traversal.
- **`sliceOsteo`:** Extracts a sub-segment in strictly $O(1)$ time by adjusting pointer offset windows without allocating new array memory.
- **`appendOsteo`:** Appends new elements with amortized $O(1)$ cost using geometric capacity expansion.

### 1.2 Interactive Code Example

```haskell
module Lesson1 where

import Gachi.Osteology
import Data.Text (Text)

-- | Constructing an osteological segment of bones
buildRig :: OsteoSegment Text
buildRig =
  let s0 = emptyOsteo 4                      -- Allocate capacity for 4 elements
      s1 = appendOsteo "manifest.cabal" s0   -- BoneId 0
      s2 = appendOsteo "README.md" s1        -- BoneId 1
      s3 = appendOsteo "bin/verify" s2       -- BoneId 2
      s4 = appendOsteo "docs/INDEX.md" s3    -- BoneId 3
  in s4

-- | O(1) zero-copy sub-segment extraction
extractSubRig :: OsteoSegment Text -> OsteoSegment Text
extractSubRig rig =
  -- Slices elements from index 1 of length 2 ("README.md", "bin/verify")
  -- Shares the underlying SmallArray#; zero heap copies.
  sliceOsteo 1 2 rig

main :: IO ()
main = do
  let rig = buildRig
  putStrLn $ "Total bones in rig: " ++ show (osteoLength rig)
  let sub = extractSubRig rig
  putStrLn $ "Sub-rig length: " ++ show (osteoLength sub)
```

---

## Lesson 2: Lock-Free Chattering Concurrency

Just as the teeth of the mythical *gashadokuro* chatter in harmonic resonance, `Gachi.Core.Atomic` enables multiple concurrent worker threads to update and traverse bone state machines without global lock contention.

### 2.1 The CAS State Loop

```haskell
module Lesson2 where

import Gachi.Core.Atomic
import Control.Concurrent.Async (mapConcurrently_)

-- | State machine transitions for an individual bone
data BoneStatus = Uninspected | Verifying | Verified | Breached
  deriving (Eq, Show)

-- | Executes atomic state transition using a Compare-And-Swap (CAS) loop
advanceBone :: BoneMachine BoneStatus -> IO ()
advanceBone machine = do
  -- Atomically updates status from Uninspected to Verifying
  success <- casBoneStatus machine Uninspected Verifying
  if success
    then putStrLn "Acquired lock-free reservation on bone."
    else putStrLn "Bone was already acquired by another worker."

main :: IO ()
main = do
  machine <- newBoneMachine Uninspected
  -- Run 10 concurrent threads attempting to claim the bone
  mapConcurrently_ (\_ -> advanceBone machine) [1..10]
  finalStatus <- readBoneStatus machine
  putStrLn $ "Final bone status: " ++ show finalStatus
```

---

## Lesson 3: Double-Pushout (DPO) Algebraic Graph Rewriting

Structural modifications to osteological graphs are defined categorically via Double-Pushout (DPO) rewriting in the adhesive category $\mathbf{Graph}_{\text{osteo}}$.

### 3.1 The DPO Span
A production rule $p = (L \stackrel{l}{\hookleftarrow} K \stackrel{r}{\hookrightarrow} R)$ consists of:
- $L$ (Left-hand side): The subgraph pattern to detect.
- $K$ (Interface / Glue): The subgraph elements to preserve.
- $R$ (Right-hand side): The replacement elements to materialize.

```
       l           r
  L  <────  K  ─────>  R       (Production Rule)
  │         │          │
m │ (PO 1)  │  (PO 2)  │
  ▼         ▼          ▼
  G  <────  D  ─────>  H       (Host Graph Rewrite)
```

### 3.2 Executing a DPO Transformation

```haskell
module Lesson3 where

import Gachi.Core.Rewriting

-- | Define an algebraic rewrite replacing an obsolete verification hook
-- with a modernized turnkey harness.
replaceHookProduction :: ProductionRule String
replaceHookProduction =
  let l = patternGraph [legacyHookBone] [hookJoint]
      k = glueGraph [] []                    -- The boundary interface
      r = replacementGraph [modernVerifyBone] [harnessJoint]
  in makeProduction l k r

applyRewrite :: HostGraph -> Maybe HostGraph
applyRewrite hostGraph = do
  -- Step 1: Find valid match morphism m: L -> G
  match <- findMatch (productionL replaceHookProduction) hostGraph
  -- Step 2: Verify Dangling & Identification conditions; compute pushout complement D (PO 1)
  d <- pushoutComplement replaceHookProduction match hostGraph
  -- Step 3: Compute pushout H = D +_K R (PO 2)
  pure (pushout replaceHookProduction d)
```

---

## Lesson 4: Polytropos Zero-Cost Isomorphisms

`gachi-core` and `polytropos-core` share contiguous array memory physics. `Gachi.Core` provides bidirectional algebraic isomorphisms converting between `OsteoSegment (f Any)` and Polytropos `Rep f a` with zero linked-list traversals.

```haskell
module Lesson4 where

import Gachi.Core
import Polytropos.Core (Record, emptyRecord, insertField, getField)

-- | 1. Memory Substrate Parity
-- Both representations are backed by contiguous GHC SmallArray# primitives.
-- segmentToRep: Word tag -> OsteoSegment (f Any) -> Rep f a
-- repToSegment: Rep f a -> (Word, OsteoSegment (f Any))

-- | 2. Formal Isomorphism Law:
-- repToSegment . segmentToRep == id
-- segmentToRep . repToSegment == id

demoCoercion :: Record '["name" ':= String, "bones" ':= Int] -> IO ()
demoCoercion rec = do
  -- Coerce open record into osteological bone payload in O(1) time
  let bone = recordToBonePayload rec
  putStrLn "Coerced record to osteological bone payload with zero intermediate list allocations."
```

---

## Lesson 5: Declarative Dhall Project Schemas

`gachi-schema` leverages `polytropos-dhall` to specify project layouts, dependency configurations, and metadata declaratively in Dhall.

### 5.1 Project Manifest (`project.dhall`)
```dhall
let Gachi = https://raw.githubusercontent.com/NadiaYvette/polytropos/master/packages/polytropos-dhall/package.dhall
in { name = "hyperion"
   , synopsis = "Ultra-fast distributed osteological graph coordinator"
   , license = "EUPL-1.2"
   , ghcVersion = "9.14.1"
   , packages =
       [ { name = "hyperion-core", path = "packages/hyperion-core" }
       , { name = "hyperion-server", path = "packages/hyperion-server" }
       ]
   , authors = [ { name = "Nadia Yvette Chambers", email = "nadia.yvette.chambers@ik.me" } ]
   , forge = { github = True, gitlab = True }
   }
```

---

## Lesson 6: Workspace Scaffolding (`gachi init`)

To materialize the complete repository skeleton on disk:

```bash
gachi init project.dhall
```

`gachi-scaffold` synthesizes:
1. Multi-package layout with Cabal 3.0+ manifests.
2. Complete documentation corpus: `README.md`, `PLAN.md`, `STATE.md`, `docs/INDEX.md`, `docs/TUTORIAL.md`, `docs/NEWBIE_GUIDE.md`, `docs/MAINTAINER_GUIDE.md`, `docs/notes/DOC_STRATEGY.md`, `docs/notes/COMMIT_ATTRIBUTION.md`.
3. AI agent governance: `AGENTS.md`, `CLAUDE.md`, `.agents/rules/`.
4. Git governance: `.gitmessage`, `.githooks/commit-msg` (validating Sarutahiko RFC 2822 trailers), `.githooks/pre-commit`.
5. Turnkey 5-gate verification suite: `bin/<project>-verify`, `bin/<project>-tagref`, `bin/<project>-linkcheck`, `bin/<project>-cloc`, `bin/generate-tags`.
6. Multi-forge CI workflows: `.github/workflows/ci.yml` and `.gitlab-ci.yml`.

---

## Lesson 7: Configuration Propagation (`gachi sync`)

When static linters, git hooks, or AI agent advisories improve in `polytropos` or `sarutahiko`, propagate improvements across all checkouts in lockstep:

```bash
# Check configuration drift across ~/src/*
gachi sync --check

# Propagate improvements across all repositories in lockstep
gachi sync --all

# Audit and reconcile remote URLs against the 5-remote replication topology
gachi sync --remotes
```

`gachi sync` is deterministic and idempotent: it preserves repository-specific domain code while synchronizing shared infrastructure assets.

---

## Lesson 8: Non-Destructive Retrofitting & Penelope Arrow Pipeline (`gachi retrofit`)

When adopting legacy, single-package, or foreign repositories into the ecosystem, `gachi retrofit` inspects the target across 6 orthogonal dimensions and overlays the canonical skeleton non-destructively.

### 8.1 The Penelope Polycategorical Pipeline
The retrofitting engine models analysis, planning, sandboxing, and execution as an extensible Penelope binary arrow pipeline (`PenelopeRope '[] '[]` / `P.Rope`):

```haskell
-- | Discrete arrow strands composed cleanly via Category (>>>)
buildRetrofitSimulationPipeline :: RetrofitPipeline RetrofitContext OverlayResult
buildRetrofitSimulationPipeline =
  simulationStrand >>> arr (undefined,) >>> sandboxValidationStrand
```

### 8.2 CLI Usage & Progressive Quality Gates
```bash
# 1. Run diagnostic scan and preview overlay actions in dry-run mode
gachi retrofit --target /path/to/legacy-repo --dry-run

# 2. Apply non-destructive skeleton overlay
gachi retrofit --target /path/to/legacy-repo
```

The progressive quality gates track compliance across four incremental levels:
- **Level 0 (Foundation):** Git repository initialized, `.githooks/`, `README.md`, `PLAN.md`, `tagref.yml`, `.hlint.yaml`.
- **Level 1 (Structural Integrity):** Tagref cross-references validated, zero broken Markdown links.
- **Level 2 (Compiler Discipline):** Clean compilation under `-Wall -Wcompat -Wredundant-constraints`.
- **Level 3 (Static Analysis Purity):** Zero HLint hints, $\ge 50\%$ comment density, full test suite pass.

---

## Lesson 9: Ecosystem Plan Governance & Rollback (`gachi plan`)

Top-level strategic planning documents (`~/src/PLAN.md`, `~/src/STATE.md`) govern the active development frontier across all checkouts. `gachi-plan` isolates plan versioning from child repositories:

```bash
# Record an immutable strategic planning checkpoint
gachi plan checkpoint "Complete Milestone 4.3 and Phase 6"

# View structural diff against prior checkpoint
gachi plan diff HEAD~1

# List historical checkpoints with SHA256 checksums
gachi plan list

# Roll back to an earlier strategic state atomically
gachi plan rollback 84ba668f
```

The plan repository lives in a detached Git store (`~/src/.plan.git`) paired with an append-only snapshot ledger (`~/src/plans/snapshots/`), preventing cross-repository git collision.

---

## Conclusion & Next Steps

You now possess the foundational knowledge required to design osteological rigs and govern ecosystem workspaces with `gachi`.
- Review [`docs/MAINTAINER_GUIDE.md`](MAINTAINER_GUIDE.md) for architectural invariants and triage runbooks.
- Review [`docs/notes/GACHI_DESIGN.md`](notes/GACHI_DESIGN.md) for formal decision records D1–D10.
- Execute `./bin/gachi-verify` to ensure all 5 verification gates pass cleanly.
