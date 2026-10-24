{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}

-- | Module: Gachi.Scaffold.Types
-- Description: Core types and configuration models for workspace scaffolding
--
-- This module establishes the structural types and configuration options
-- governing project scaffolding, file generation, error handling, and
-- filesystem materialization.
--
-- = Architectural Context & Invariants
--
-- In Gachi's infrastructure model (per Note [Ecosystem Standardization Invariants]
-- [ref:note-ecosystem-standardization]), all repository skeletons are materialized
-- from an immutable, deterministic list of 'FileEntry' records.
--
-- == Two-Phase Scaffolding Architecture
--
-- Generation proceeds in two strictly decoupled phases:
--
-- 1. __Pure Synthesis (Phase A):__
--    The template engine transforms a declarative 'Gachi.Schema.Project.Project'
--    specification into an in-memory list of 'FileEntry' values. This phase is
--    referentially transparent, pure, and total, with zero filesystem or network
--    side-effects.
--
-- 2. __Materialization (Phase B):__
--    The execution engine writes the in-memory 'FileEntry' list to the physical
--    filesystem according to the active 'ScaffoldMode', creating directories as
--    needed and setting POSIX executable bits (+x) for shell and Python scripts.
--
-- = When to Use This Module
--
-- Import this module when configuring scaffolding executions, processing
-- in-memory generated files, or handling scaffolding results and errors.
module Gachi.Scaffold.Types
  ( -- * Core File Representation
    FileEntry(..)

    -- * Operational Modes
  , ScaffoldMode(..)

    -- * Results and Errors
  , ScaffoldResult(..)
  , ScaffoldError(..)
  ) where

import Control.Exception (Exception)
import Data.Text (Text)
import GHC.Generics (Generic)

-- | Represents a single file to be generated or materialized in a project skeleton.
--
-- Each 'FileEntry' holds a relative path, textual content, and a flag indicating
-- whether the file requires POSIX executable permissions (such as verification scripts
-- in @bin/@ or Git hooks in @.githooks/@).
data FileEntry = FileEntry
  { entryPath       :: !FilePath
    -- ^ Relative file path from the repository root (e.g. @"docs/INDEX.md"@).
  , entryContent    :: !Text
    -- ^ Complete textual content of the file to be written.
  , entryExecutable :: !Bool
    -- ^ Whether POSIX executable permissions (@+x@) must be applied upon creation.
  } deriving stock (Eq, Show, Generic)

-- | Operational policy governing how the scaffolding engine behaves when a
-- target file already exists on the destination filesystem.
--
-- Used to differentiate between initial repository creation, non-destructive
-- retrofitting, and dry-run synchronization.
data ScaffoldMode
  = OverwriteExisting
    -- ^ Overwrite any existing files unconditionally.
  | SkipExisting
    -- ^ Preserve existing files intact, recording them as skipped in 'ScaffoldResult'.
  | FailOnExisting
    -- ^ Abort immediately with a 'DestinationExists' error if any file already exists.
  deriving stock (Eq, Show, Generic)

-- | Summary outcome of a completed scaffolding operation across a filesystem tree.
--
-- Tracks both newly written files and skipped files to provide transparent
-- diagnostic reporting to CLI users and calling code.
data ScaffoldResult = ScaffoldResult
  { writtenFiles :: ![FilePath]
    -- ^ List of file paths successfully materialized on disk.
  , skippedFiles :: ![FilePath]
    -- ^ List of file paths preserved untouched because they already existed.
  } deriving stock (Eq, Show, Generic)

-- | Scaffolding execution errors encountered during filesystem materialization.
--
-- Instances of 'Exception' allowing safe capture and propagation via 'Control.Exception.throwIO'.
data ScaffoldError
  = DestinationExists !FilePath
    -- ^ A destination file already exists and 'ScaffoldMode' was set to 'FailOnExisting'.
  | FileWriteFailure !FilePath !String
    -- ^ An unhandled I/O error occurred while writing to disk.
  deriving stock (Eq, Show, Generic)

instance Exception ScaffoldError
