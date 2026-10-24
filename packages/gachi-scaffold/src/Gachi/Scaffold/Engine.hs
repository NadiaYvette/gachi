-- | Module: Gachi.Scaffold.Engine
-- Description: Execution engine for materializing workspace file trees
--
-- This module coordinates the physical instantiation of project skeletons
-- on the filesystem, managing directory creation, overwrite policies, and
-- POSIX permission bits.
--
-- = Architectural Context & Invariants
--
-- In accordance with Note [Ecosystem Standardization Invariants]
-- [ref:note-ecosystem-standardization], the scaffolding engine guarantees that
-- generated file trees are structurally identical, total, and deterministic.
--
-- == Two-Stage Execution Pipeline
--
-- 1. __Pure Generation:__ Invokes 'generateProjectScaffold' to produce the complete
--    set of 'FileEntry' records from a declarative 'Project' specification.
-- 2. __Materialization:__ Evaluates 'writeScaffold' across target paths, enforcing
--    the selected 'ScaffoldMode' ('FailOnExisting', 'SkipExisting', or 'OverwriteExisting').
--
-- = Error Safety
--
-- When configured with 'FailOnExisting', any collision on disk immediately
-- halts execution and raises 'DestinationExists', preventing partial or accidental
-- clobbering of pre-existing user code.
module Gachi.Scaffold.Engine
  ( -- * High-Level Scaffolding API
    generateAndWriteScaffold
  , generateProjectScaffold
  , writeScaffold
  ) where

import Control.Exception (throwIO)
import Control.Monad (forM, when)
import Data.Either (lefts, rights)
import qualified Data.Text.IO as TIO
import System.Directory
  ( createDirectoryIfMissing
  , doesFileExist
  , getPermissions
  , setOwnerExecutable
  , setPermissions
  )
import System.FilePath (takeDirectory, (</>))

import Gachi.Schema.Project (Project)
import Gachi.Scaffold.Templates (allProjectEntries)
import Gachi.Scaffold.Types
  ( FileEntry(..)
  , ScaffoldError(..)
  , ScaffoldMode(..)
  , ScaffoldResult(..)
  )

-- | Pure generation of all canonical project files and directories from a
-- declarative 'Project' specification.
--
-- Returns a complete list of 'FileEntry' values representing every configuration,
-- hook, verification script, document, and source module in the workspace.
--
-- Time complexity: @O(F)@ proportional to the number of generated files.
generateProjectScaffold :: Project -> [FileEntry]
generateProjectScaffold = allProjectEntries

-- | Writes an in-memory list of 'FileEntry' records to a destination root directory
-- on the physical filesystem.
--
-- Creates parent directories as needed and applies POSIX executable bits (@+x@)
-- to files flagged with 'entryExecutable'.
--
-- Behaviors by 'ScaffoldMode':
--
-- * 'FailOnExisting': Throws 'DestinationExists' if any target file already exists.
-- * 'SkipExisting': Preserves existing files unchanged and records them in 'skippedFiles'.
-- * 'OverwriteExisting': Replaces existing files unconditionally.
writeScaffold :: FilePath -> ScaffoldMode -> [FileEntry] -> IO ScaffoldResult
writeScaffold targetDir mode entries = do
  results <- forM entries $ \entry -> do
    let dest = targetDir </> entryPath entry
    exists <- doesFileExist dest
    case (exists, mode) of
      (True, FailOnExisting) ->
        throwIO (DestinationExists dest)
      (True, SkipExisting) ->
        pure (Left (entryPath entry))
      _ -> do
        createDirectoryIfMissing True (takeDirectory dest)
        TIO.writeFile dest (entryContent entry)
        when (entryExecutable entry) $ do
          p <- getPermissions dest
          setPermissions dest (setOwnerExecutable True p)
        pure (Right (entryPath entry))

  let written = rights results
      skipped = lefts results
  pure ScaffoldResult
    { writtenFiles = written
    , skippedFiles = skipped
    }

-- | Combined generation and filesystem materialization.
--
-- Purely generates the project file tree and writes all files to 'targetDir'
-- according to the supplied 'ScaffoldMode'.
generateAndWriteScaffold :: FilePath -> ScaffoldMode -> Project -> IO ScaffoldResult
generateAndWriteScaffold targetDir mode proj =
  writeScaffold targetDir mode (generateProjectScaffold proj)
