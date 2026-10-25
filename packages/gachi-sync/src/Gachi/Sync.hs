-- | Module: Gachi.Sync
-- Description: Root umbrella module for Gachi cross-repository standardization & synchronization
--
-- This is the primary entry point for the @gachi-sync@ library. It exposes
-- the 9-dimensional Standardization Matrix (~/src/PLAN.md §1.A), canonical
-- shared asset generators, non-destructive audit engine, and diagnostic reporting.
--
-- = Architectural Context & Invariants
--
-- In accordance with Note [Ecosystem Standardization Invariants]
-- [ref:note-ecosystem-standardization] and Note [Cross-Repository Standardization Matrix and Audit Semantics]
-- [ref:note-standardization-matrix], all repositories across ~/src/* share an
-- authoritative structural skeleton. This library provides the declarative
-- contracts and inspection machinery that guarantee structural consistency.
--
-- == The Four Standardization Subsystems
--
-- The Gachi synchronization subsystem is organized into four complementary layers:
--
-- 1.  __Core Types and Models ("Gachi.Sync.Types"):__
--     Formalizes the 9 dimensions as 'AssetCategory', individual asset models
--     as 'StandardAsset', composite matrices as 'StandardizationMatrix', and
--     inspection outcomes as 'AssetAuditStatus' and 'AuditReport'.
--
-- 2.  __Shared Asset Catalog ("Gachi.Sync.Catalog"):__
--     Pure, total template generators for Fourmolu, rustfmt, clang-format,
--     strict HLint rules, Cabal project pinning, Git commit-msg and pre-commit
--     hooks, forge-tiered CI workflows, and AI agent instructions.
--
-- 3.  __Canonical Standardization Matrix ("Gachi.Sync.Matrix"):__
--     The authoritative 'canonicalMatrix' registry aggregating all standardized
--     assets across the 9 dimensions, complete with category queries and filter
--     combinators ('assetsForCategory', 'requiredAssets', 'executableAssets').
--
-- 4.  __Non-Destructive Audit Engine ("Gachi.Sync.Audit"):__
--     Read-only filesystem analyzer ('auditRepository', 'auditRepositoryQuick')
--     evaluating checkouts against matrix contracts, detecting content and
--     permission drift, and rendering diagnostic ASCII tables ('formatAuditReport').
--
-- == Operational Invariants
--
-- All modules within @gachi-sync@ adhere to strict engineering guarantees:
-- * __Purity & Reproducibility:__ All generators evaluate from typed records
--   without reading environment variables or accessing the network.
-- * __Observational Non-Destruction:__ The audit engine evaluates disk checkouts
--   using read-only inspection primitives, guaranteeing zero accidental overwrites.
-- * __Toolchain Hermeticity:__ Pinned to GHC 9.14.1 and Cabal 3.18 under strict
--   compiler warnings (@-Wall -Wcompat -Wredundant-constraints@) and zero HLint hints.
--
-- = Worked Example: Auditing a Target Checkout
--
-- The following example demonstrates auditing an existing repository against
-- the canonical standardization matrix:
--
-- >>> import Gachi.Schema.Project (defaultProject, Author(..))
-- >>> import Gachi.Sync
-- >>> let auth = Author "Nadia Yvette Chambers" "nadia.yvette.chambers@ik.me"
-- >>> let proj = defaultProject "gachi" auth
-- >>> report <- auditRepository "/home/nyc/src/gachi" proj canonicalMatrix
-- >>> reportCompliantCount report > 0
-- True
-- >>> length (filterMissingResults report) == 0
-- True
--
-- = Worked Example: Quick Audit Without Explicit Project
--
-- When project specifications are not known upfront, 'auditRepositoryQuick'
-- automatically infers the project name from the checkout path or @project.dhall@:
--
-- >>> res <- auditRepositoryQuick "/home/nyc/src/gachi"
-- >>> case res of { Right rep -> reportCompliancePct rep >= 50.0; Left _ -> False }
-- True
module Gachi.Sync
  ( -- * Core Standardization Types
    module Gachi.Sync.Types

    -- * Canonical Standardization Matrix
  , module Gachi.Sync.Matrix

    -- * Shared Asset Catalog
  , module Gachi.Sync.Catalog

    -- * Non-Destructive Audit Engine
  , module Gachi.Sync.Audit
  ) where

import Gachi.Sync.Audit
import Gachi.Sync.Catalog
import Gachi.Sync.Matrix
import Gachi.Sync.Types
