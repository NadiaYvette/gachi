-- | Module: Gachi.Plan
-- Description: Unified facade for ecosystem plan governance and detached Git store operations
--
-- This module serves as the primary entry point for @gachi-plan@, re-exporting
-- the detached Git store lifecycle operations and algebraic data models.
--
-- = Architectural Context & Invariants
--
-- In accordance with Note [Plan Governance and Rollback Mechanics]
-- [ref:note-plan-governance-rollback] and Note [Append-Only Plan Snapshot Invariants]
-- [ref:note-plan-snapshots], the detached Git store architecture and snapshot
-- ledger manage strategic ecosystem governance documents (@PLAN.md@, @STATE.md@,
-- @INDEX.md@, and @docs/INDEX.md@) in an isolated Git repository and append-only
-- directory without creating nested @.git@ roots or interfering with child repository checkouts.
module Gachi.Plan
  ( -- * Core Store Lifecycle & Operations
    module Gachi.Plan.Store

    -- * Append-Only Snapshot Ledger Engine
  , module Gachi.Plan.Snapshot

    -- * Atomic Rollback & Differential History Engine
  , module Gachi.Plan.Rollback

    -- * Algebraic Data Models & Types
  , module Gachi.Plan.Types
  ) where

import Gachi.Plan.Rollback
import Gachi.Plan.Snapshot
import Gachi.Plan.Store
import Gachi.Plan.Types
