{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}

-- | Module: Gachi.Plan.Types
-- Description: Core types, models, and data structures for ecosystem plan governance
--
-- This module defines the foundational algebraic data models for the isolated
-- detached Git store architecture (~/src/PLAN.md §1.A, Phase 5, Milestone 5.1).
--
-- = Architectural Context & Invariants
--
-- In accordance with Note [Plan Governance and Rollback Mechanics]
-- [ref:note-plan-governance-rollback], planning files across @~/src/@ are
-- tracked in an isolated detached Git repository without interfering with
-- child repository checkouts. This module formalizes the data models representing
-- the detached store configuration, execution errors, status queries, snapshot
-- ledger metadata, and governed document invariants.
--
-- See also Note [Append-Only Plan Snapshot Invariants] [ref:note-plan-snapshots].
module Gachi.Plan.Types
  ( -- * Store Configuration
    PlanStore(..)
  , defaultGovernedFiles
  , defaultStoreName
  , planGitDirEnvVar

    -- * Snapshot Ledger Configuration & Metadata
  , SnapshotMeta(..)
  , planSnapshotDirEnvVar
  , defaultSnapshotDirName

    -- * Store Status & Metadata
  , PlanStoreStatus(..)
  , isPlanStoreClean

    -- * Failure Conditions
  , PlanError(..)
  ) where

import Data.Text (Text)
import Data.Time (UTCTime)
import GHC.Generics (Generic)

-- | Configuration and runtime handle for a detached Git plan store.
--
-- The detached store separates the repository metadata directory (@--git-dir@)
-- from the working directory root (@--work-tree@). This architecture guarantees
-- that no nested @.git@ directory is created in @~/src/@, completely avoiding
-- collisions with child repository checkouts.
data PlanStore = PlanStore
  { planGitDir        :: !FilePath
    -- ^ Absolute path to the detached bare Git repository directory
    -- (e.g. @/home/nyc/.plan.git@ or @/home/nyc/src/.plan.git@).
  , planWorkTree      :: !FilePath
    -- ^ Absolute path to the governed working tree root directory
    -- (e.g. @/home/nyc/src@).
  , planGovernedFiles :: ![FilePath]
    -- ^ Canonical relative paths of governance documents tracked by the store.
  }
  deriving stock (Eq, Show, Generic)

-- | Canonical ecosystem planning and governance files tracked by the detached store.
--
-- Per Note [Plan Governance and Rollback Mechanics] [ref:note-plan-governance-rollback],
-- the detached Git store exclusively tracks top-level planning documents and roadmap
-- indexes across @~/src/@.
defaultGovernedFiles :: [FilePath]
defaultGovernedFiles =
  [ "PLAN.md"
  , "STATE.md"
  , "INDEX.md"
  , "docs/INDEX.md"
  ]

-- | Default name of the bare Git store directory relative to the home directory.
defaultStoreName :: FilePath
defaultStoreName = ".plan.git"

-- | Standard environment variable name for overriding the detached Git store path.
planGitDirEnvVar :: String
planGitDirEnvVar = "PLAN_GIT_DIR"

-- | Standard environment variable name for overriding the snapshot ledger directory.
planSnapshotDirEnvVar :: String
planSnapshotDirEnvVar = "PLAN_SNAPSHOT_DIR"

-- | Default snapshot ledger directory relative to workspace root or home directory.
defaultSnapshotDirName :: FilePath
defaultSnapshotDirName = "plans/snapshots"

-- | Metadata record describing an immutable snapshot within the snapshot ledger.
--
-- In accordance with Note [Append-Only Plan Snapshot Invariants] [ref:note-plan-snapshots],
-- each snapshot preserves a byte-for-byte replica of a governed planning document
-- prior to mutation or at an explicit milestone checkpoint.
data SnapshotMeta = SnapshotMeta
  { snapshotId           :: !Text
    -- ^ Unique snapshot identifier (typically matching the snapshot file name).
  , snapshotPath         :: !FilePath
    -- ^ Absolute filesystem path to the immutable snapshot file.
  , snapshotTimestamp    :: !UTCTime
    -- ^ Timestamp when the snapshot was recorded in UTC.
  , snapshotSha256       :: !Text
    -- ^ Cryptographic SHA-256 digest of the snapshot file contents.
  , snapshotSourceFile   :: !FilePath
    -- ^ Original governed file name or relative path that was snapshotted (e.g. @"PLAN.md"@).
  , snapshotIsCheckpoint :: !Bool
    -- ^ Whether this snapshot marks an immutable milestone checkpoint exempt from automated pruning.
  }
  deriving stock (Eq, Show, Generic)

-- | Observed runtime status, commit metadata, and dirty state of a detached Git plan store.
--
-- Captures the current HEAD commit hash, dirty tracking state of governed files,
-- commit timestamp, and tracked file inventory.
data PlanStoreStatus = PlanStoreStatus
  { statusStorePath      :: !FilePath
    -- ^ Absolute path to the detached Git store directory.
  , statusWorkTree       :: !FilePath
    -- ^ Absolute path to the governed working tree root directory.
  , statusHeadCommit     :: !(Maybe Text)
    -- ^ Full 40-character SHA-1 commit hash of the current HEAD revision,
    -- or 'Nothing' if the repository is newly initialized without commits (unborn HEAD).
  , statusIsDirty        :: !Bool
    -- ^ 'True' if any governed document has unstaged modifications, staged changes,
    -- or exists untracked in the worktree.
  , statusLastCommitTime :: !(Maybe UTCTime)
    -- ^ Timestamp of the most recent commit in UTC, or 'Nothing' if unborn.
  , statusDirtyFiles     :: ![FilePath]
    -- ^ Canonical relative paths of governed files that have uncommitted or untracked changes.
  , statusTrackedFiles   :: ![FilePath]
    -- ^ Canonical relative paths of governed files currently tracked in the Git index.
  }
  deriving stock (Eq, Show, Generic)

-- | Predicate checking whether a plan store has zero uncommitted or untracked changes.
isPlanStoreClean :: PlanStoreStatus -> Bool
isPlanStoreClean status = not (statusIsDirty status)

-- | Error conditions encountered during detached Git store lifecycle or operations.
data PlanError
  = PlanGitError !Text
    -- ^ An underlying git command exited with a non-zero exit code.
    -- Contains the captured standard error output.
  | PlanStoreMissing !FilePath
    -- ^ The specified detached Git store directory does not exist or is not a valid bare Git repository.
  | PlanWorkTreeMissing !FilePath
    -- ^ The specified working tree root directory does not exist.
  | PlanIOError !Text
    -- ^ A filesystem or I/O failure occurred during store operations.
  | PlanInvalidPath !FilePath
    -- ^ A provided filesystem path is malformed or invalid.
  deriving stock (Eq, Show, Generic)
