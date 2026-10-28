{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Module: Gachi.Plan.Store
-- Description: Detached Git store lifecycle, probing, status, and tracking operations
--
-- This module implements the detached Git store architecture for ecosystem plan
-- governance (~/src/PLAN.md §1.A, Phase 5, Milestone 5.1).
--
-- = Architectural Context & Invariants
--
-- Note [Plan Governance and Rollback Mechanics]
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- [tag:note-plan-governance-rollback]
-- Ecosystem planning and operational frontier documents (@PLAN.md@, @STATE.md@,
-- @INDEX.md@, and @docs/INDEX.md@) across @~/src/@ are version-controlled via an
-- isolated, detached Git repository (@--git-dir=<path> --work-tree=<root>@)
-- and an append-only pre-mutation snapshot ledger per ~/src/PLAN.md §1.A.
--
-- Core Invariants:
-- 1. __Non-Interference Invariant:__ Strictly avoids nested @.git@ collisions by
--    never writing @.git@ directories or metadata into child repository workspaces
--    (@~/src/gachi/.git@, @~/src/polytropos/.git@, etc.). The store is maintained
--    as a bare repository in an external directory (default @~/.plan.git@ or
--    @~/src/.plan.git@).
-- 2. __Governed Documents Invariant:__ Exclusively tracks top-level ecosystem
--    planning files and roadmap indexes, ignoring child directory workspaces
--    via explicit pathspec scoping (@-- <governed-files>@). Child project repositories
--    remain completely autonomous.
-- 3. __Hermetic Store Execution:__ All git operations are executed with explicit
--    @--git-dir@ and @--work-tree@ arguments, guaranteeing total independence
--    from ambient directory state or parent repository discovery.
-- 4. __Zero Partial Functions:__ Invariant enforcement and parsing strictly use
--    total pattern matching, eliminating any risk of runtime partial function crashes.
module Gachi.Plan.Store
  ( -- * Store Lifecycle
    initPlanStore
  , isStoreInitialized
  , resolvePlanStorePath

    -- * Status & Tracking Operations
  , queryPlanStore
  , listTrackedFiles
  , trackGovernedFiles
  , stageFiles
  , commitStore
  , getPlanStoreDiff
  , governedFilesExist

    -- * Low-Level Execution
  , runGitInStore
  , runGitRaw
  ) where

import Control.Exception (SomeException, catch)
import Control.Monad (filterM)
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time.Clock.POSIX (posixSecondsToUTCTime)
import GHC.IO.Exception (ExitCode(..))
import System.Directory
  ( createDirectoryIfMissing
  , doesDirectoryExist
  , doesFileExist
  , getHomeDirectory
  , makeAbsolute
  )
import System.Environment (lookupEnv)
import System.FilePath ((</>))
import System.Process (proc, readCreateProcessWithExitCode)
import Text.Read (readMaybe)

import Gachi.Plan.Types
  ( PlanError(..)
  , PlanStore(..)
  , PlanStoreStatus(..)
  , defaultGovernedFiles
  , defaultStoreName
  , planGitDirEnvVar
  )

-- | Resolves the target detached Git store directory.
--
-- Precedence:
-- 1. Explicitly provided 'FilePath' argument (if 'Just').
-- 2. Environment variable @PLAN_GIT_DIR@ (if set and non-empty).
-- 3. Canonical default at @~/.plan.git@ relative to the user's home directory.
resolvePlanStorePath :: Maybe FilePath -> IO FilePath
resolvePlanStorePath (Just p) = makeAbsolute p
resolvePlanStorePath Nothing = do
  mEnv <- lookupEnv planGitDirEnvVar
  case mEnv of
    Just envPath | not (null envPath) -> makeAbsolute envPath
    _ -> do
      home <- getHomeDirectory
      makeAbsolute (home </> defaultStoreName)

-- | Low-level executor invoking git with specified arguments.
-- Safely catches execution exceptions (such as missing git binary).
runGitRaw :: [String] -> IO (ExitCode, Text, Text)
runGitRaw args = do
  let processSpec = proc "git" args
  (code, stdoutStr, stderrStr) <-
    catch
      (readCreateProcessWithExitCode processSpec "")
      (\(err :: SomeException) -> pure (ExitFailure 127, "", show err))
  pure (code, T.pack stdoutStr, T.pack stderrStr)

-- | Executes a git command hermetically inside the detached store context.
-- Explicitly prepends @--git-dir=<path>@ and @--work-tree=<root>@ to all invocations.
runGitInStore :: PlanStore -> [String] -> IO (ExitCode, Text, Text)
runGitInStore store args = do
  let storeArgs =
        [ "--git-dir=" ++ planGitDir store
        , "--work-tree=" ++ planWorkTree store
        ] ++ args
  runGitRaw storeArgs

-- | Checks whether a directory exists and constitutes a valid bare Git repository.
isStoreInitialized :: FilePath -> IO Bool
isStoreInitialized storePath = do
  absPath <- makeAbsolute storePath
  exists <- doesDirectoryExist absPath
  if not exists
    then pure False
    else do
      (code, _, _) <- runGitRaw ["--git-dir=" ++ absPath, "rev-parse", "--git-dir"]
      pure (code == ExitSuccess)

-- | Initializes or opens an isolated detached Git store.
--
-- If the bare git repository at the given store directory does not yet exist,
-- this function creates the directory and executes @git init --bare@.
-- Ensures that the governed work tree root directory also exists.
--
-- Returns a configured 'PlanStore' handle or a 'PlanError' upon initialization failure.
initPlanStore :: FilePath -> FilePath -> IO (Either PlanError PlanStore)
initPlanStore rawStorePath rawWorkTree = do
  absStore <- makeAbsolute rawStorePath
  absWork  <- makeAbsolute rawWorkTree
  createDirectoryIfMissing True absWork

  storeExists <- doesDirectoryExist absStore
  if not storeExists
    then do
      createDirectoryIfMissing True absStore
      (code, _, stderrTxt) <- runGitRaw ["init", "--bare", absStore]
      case code of
        ExitSuccess -> pure (Right (PlanStore absStore absWork defaultGovernedFiles))
        ExitFailure _ -> pure (Left (PlanGitError stderrTxt))
    else do
      alreadyInit <- isStoreInitialized absStore
      if alreadyInit
        then pure (Right (PlanStore absStore absWork defaultGovernedFiles))
        else do
          (code, _, stderrTxt) <- runGitRaw ["init", "--bare", absStore]
          case code of
            ExitSuccess -> pure (Right (PlanStore absStore absWork defaultGovernedFiles))
            ExitFailure _ -> pure (Left (PlanGitError stderrTxt))

-- | Lists all governed files currently tracked in the detached Git store index.
-- Runs @git ls-files@ against the detached store.
listTrackedFiles :: PlanStore -> IO [FilePath]
listTrackedFiles store = do
  (code, stdoutTxt, _) <- runGitInStore store ["ls-files"]
  case code of
    ExitSuccess ->
      let nonBlank = filter (not . null) (map T.unpack (T.lines stdoutTxt))
      in pure nonBlank
    ExitFailure _ -> pure []

-- | Queries the status of the detached Git plan store.
--
-- Inspects:
-- 1. Current HEAD commit SHA hash (or 'Nothing' if the repository is newly initialized).
-- 2. Last commit timestamp parsed from POSIX commit seconds.
-- 3. Currently tracked files via 'listTrackedFiles'.
-- 4. Dirty tracking status exclusively across governed files using pathspec scoping.
queryPlanStore :: PlanStore -> IO PlanStoreStatus
queryPlanStore store = do
  -- 1. Query current HEAD commit SHA
  (revCode, revOut, _) <- runGitInStore store ["rev-parse", "--verify", "HEAD"]
  let currentHeadSha =
        case revCode of
          ExitSuccess ->
            let stripped = T.strip revOut
            in if T.null stripped then Nothing else Just stripped
          ExitFailure _ -> Nothing

  -- 2. Query last commit timestamp (POSIX timestamp format via %ct)
  commitTime <-
    case currentHeadSha of
      Nothing -> pure Nothing
      Just _ -> do
        (timeCode, timeOut, _) <- runGitInStore store ["log", "-1", "--format=%ct"]
        case timeCode of
          ExitSuccess ->
            let s = T.unpack (T.strip timeOut)
            in case (readMaybe s :: Maybe Integer) of
                 Just sec -> pure (Just (posixSecondsToUTCTime (fromIntegral sec)))
                 Nothing  -> pure Nothing
          ExitFailure _ -> pure Nothing

  -- 3. Query tracked files
  trackedList <- listTrackedFiles store

  -- 4. Query dirty state restricted exclusively to governed files
  let governed = planGovernedFiles store
  (statusCode, statusOut, _) <-
    if null governed
      then runGitInStore store ["status", "--porcelain"]
      else runGitInStore store (["status", "--porcelain", "--"] ++ governed)

  let porcelainLines =
        case statusCode of
          ExitSuccess -> map T.unpack (T.lines statusOut)
          ExitFailure _ -> []

      -- Extract path from porcelain status output "XY <path>"
      extractDirtyPath :: String -> Maybe FilePath
      extractDirtyPath lineStr
        | length lineStr > 3 = Just (drop 3 lineStr)
        | otherwise          = Nothing

      dirtyPaths = mapMaybe extractDirtyPath porcelainLines
      dirtyFlag = not (null dirtyPaths)

  pure PlanStoreStatus
    { statusStorePath      = planGitDir store
    , statusWorkTree       = planWorkTree store
    , statusHeadCommit     = currentHeadSha
    , statusIsDirty        = dirtyFlag
    , statusLastCommitTime = commitTime
    , statusDirtyFiles     = dirtyPaths
    , statusTrackedFiles   = trackedList
    }

-- | Stages specified relative file paths into the detached Git store index.
stageFiles :: PlanStore -> [FilePath] -> IO (Either PlanError ())
stageFiles _ [] = pure (Right ())
stageFiles store paths = do
  (code, _, stderrTxt) <- runGitInStore store (["add", "--"] ++ paths)
  case code of
    ExitSuccess -> pure (Right ())
    ExitFailure _ -> pure (Left (PlanGitError stderrTxt))

-- | Automatically stages all canonical governed planning files that exist on disk in the worktree.
trackGovernedFiles :: PlanStore -> IO (Either PlanError [FilePath])
trackGovernedFiles store = do
  let workRoot = planWorkTree store
  existingFiles <- filterM (\f -> doesFileExist (workRoot </> f)) (planGovernedFiles store)
  case existingFiles of
    [] -> pure (Right [])
    filesToStage -> do
      stageResult <- stageFiles store filesToStage
      case stageResult of
        Right () -> pure (Right filesToStage)
        Left err -> pure (Left err)

-- | Commits staged changes to the detached Git store with a given commit message.
-- Injects hermetic user identity configuration to prevent failures in unconfigured environments.
commitStore :: PlanStore -> Text -> IO (Either PlanError Text)
commitStore store message = do
  let commitArgs =
        [ "-c", "user.name=Gachi Plan Governance"
        , "-c", "user.email=gachi-plan@ecosystem.local"
        , "commit"
        , "-m", T.unpack message
        ]
  (code, _, stderrTxt) <- runGitInStore store commitArgs
  case code of
    ExitSuccess -> do
      (revCode, revOut, revErr) <- runGitInStore store ["rev-parse", "HEAD"]
      case revCode of
        ExitSuccess -> pure (Right (T.strip revOut))
        ExitFailure _ -> pure (Left (PlanGitError revErr))
    ExitFailure _ -> pure (Left (PlanGitError stderrTxt))

-- | Retrieves the Git diff of governed planning documents against HEAD or a specified revision.
getPlanStoreDiff :: PlanStore -> Maybe Text -> IO (Either PlanError Text)
getPlanStoreDiff store mTargetRevision = do
  let baseArgs =
        case mTargetRevision of
          Just rev -> ["diff", T.unpack rev, "--"]
          Nothing  -> ["diff", "HEAD", "--"]
      diffArgs = baseArgs ++ planGovernedFiles store
  (code, stdoutTxt, stderrTxt) <- runGitInStore store diffArgs
  case code of
    ExitSuccess -> pure (Right stdoutTxt)
    ExitFailure _ -> pure (Left (PlanGitError stderrTxt))

-- | Checks which governed planning files physically exist in the worktree directory on disk.
governedFilesExist :: PlanStore -> IO [(FilePath, Bool)]
governedFilesExist store = do
  let root = planWorkTree store
  mapM (\relPath -> do
    exists <- doesFileExist (root </> relPath)
    pure (relPath, exists)
    ) (planGovernedFiles store)
