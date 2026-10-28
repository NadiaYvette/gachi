{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Module: Gachi.Plan.Rollback
-- Description: Atomic rollback engine, pre-mutation safety snapshots, and differential history
--
-- This module implements Milestone 5.3 of Phase 5 (Ecosystem Plan Governance & Rollback
-- per ~/src/PLAN.md §1.A). It delivers atomic rollback mechanics, pre-mutation safety
-- snapshots, unified diff computation, structured git log queries, and checkpoint commits.
--
-- = Architectural Context & Invariants
--
-- Note [Deterministic Plan Rollback Invariants]
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- [tag:note-plan-rollback-invariants]
-- The plan rollback engine guarantees deterministic, reversible state transitions
-- across ecosystem planning and governance documents (PLAN.md, STATE.md, INDEX.md,
-- and docs/INDEX.md).
--
-- Core Invariants:
-- 1. __Pre-Mutation Safety Invariant:__
--    Prior to executing any destructive mutation or checkout of working tree files,
--    the rollback engine MUST record immutable pre-mutation safety snapshots of all
--    governed files currently on disk in the snapshot ledger (~/src/plans/snapshots/).
--    This ensures that uncommitted progress or interim state is never permanently lost.
--
-- 2. __Hermetic Object Store Restoration:__
--    Restoration checks out objects exclusively from the detached Git store
--    using explicit tree pathspecs (@git checkout <ref> -- <governed-files>@).
--    No ambient child repository checkouts or working files outside the governed
--    set are inspected or modified.
--
-- 3. __Byte-Level Verification Invariant:__
--    Every restored file is verified post-checkout by comparing its raw disk bytes
--    against the cryptographic blob stored in the Git object database at the target
--    revision (@git cat-file -p <ref>:<file>@). Any mismatch immediately reports
--    an integrity verification failure.
--
-- 4. __Audit Trail & Attribution Preservation:__
--    Checkpoints recorded during plan governance preserve Sarutahiko RFC 2822
--    attribution trailers (@Assisted-by:@, @Orchestrated-by:@). Rollback queries
--    expose structured log history and semantic diffs without losing provenance.
--
-- 5. __Zero Partial Functions Invariant:__
--    All parsing, string splitting, path manipulation, and tree queries are
--    strictly total. No partial functions (such as unsafe indexing or extraction)
--    are permitted in the rollback or CLI governance pipelines.
module Gachi.Plan.Rollback
  ( -- * Atomic Rollback & Verification
    rollbackToCheckpoint
  , verifyFilesIntegrity
  , verifySingleFile

    -- * Differential Analysis & Log Queries
  , computePlanDiff
  , queryPlanLog

    -- * Checkpoint Creation & Attribution
  , createPlanCheckpoint
  , formatSarutahikoCommitMessage
  , extractTrailers

    -- * Path & Snapshot Resolution
  , resolveSnapshotDirForStore
  ) where

import Control.Exception (SomeException, catch)
import Control.Monad (filterM)
import qualified Data.ByteString as BS
import Data.Char (isAsciiLower, isAsciiUpper)
import Data.Foldable (for_)
import Data.Maybe (fromMaybe, mapMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time.Clock.POSIX (posixSecondsToUTCTime)
import GHC.IO.Exception (ExitCode(..))
import System.Directory
  ( createDirectoryIfMissing
  , doesDirectoryExist
  , doesFileExist
  , makeAbsolute
  )
import System.Environment (lookupEnv)
import System.FilePath ((</>))
import System.IO (hClose, hGetContents)
import System.Process
  ( CreateProcess(..)
  , StdStream(..)
  , createProcess
  , proc
  , waitForProcess
  )
import Text.Read (readMaybe)

import Gachi.Plan.Snapshot
  ( createSnapshot
  , resolvePlanSnapshotDir
  )
import Gachi.Plan.Store
  ( commitStore
  , runGitInStore
  , trackGovernedFiles
  )
import Gachi.Plan.Types
  ( CheckpointResult(..)
  , PlanCommit(..)
  , PlanDiff(..)
  , PlanError(..)
  , PlanStore(..)
  , RollbackResult(..)
  , SnapshotMeta(..)
  , defaultSnapshotDirName
  , planSnapshotDirEnvVar
  )

-- | Resolves the snapshot ledger directory for a given 'PlanStore'.
--
-- Precedence:
-- 1. Environment variable @PLAN_SNAPSHOT_DIR@ (if set and non-empty).
-- 2. @plans/snapshots@ relative to 'planWorkTree' (if exists or if @plans@ dir exists).
-- 3. Canonical default snapshot directory via 'resolvePlanSnapshotDir'.
resolveSnapshotDirForStore :: PlanStore -> IO FilePath
resolveSnapshotDirForStore store = do
  mEnv <- lookupEnv planSnapshotDirEnvVar
  case mEnv of
    Just envPath | not (null envPath) -> makeAbsolute envPath
    _ -> do
      let workSnapDir = planWorkTree store </> defaultSnapshotDirName
      workSnapExists <- doesDirectoryExist workSnapDir
      if workSnapExists
        then makeAbsolute workSnapDir
        else do
          let workPlansDir = planWorkTree store </> "plans"
          workPlansExists <- doesDirectoryExist workPlansDir
          if workPlansExists
            then makeAbsolute workSnapDir
            else resolvePlanSnapshotDir Nothing

-- | Executes low-level git invocation hermetically inside detached store, capturing raw bytes.
runGitInStoreBytes :: PlanStore -> [String] -> IO (ExitCode, BS.ByteString, Text)
runGitInStoreBytes store args = do
  let storeArgs =
        [ "--git-dir=" ++ planGitDir store
        , "--work-tree=" ++ planWorkTree store
        ] ++ args
  let p = (proc "git" storeArgs)
        { std_out = CreatePipe
        , std_err = CreatePipe
        }
  catch
    (do (mIn, mOut, mErr, ph) <- createProcess p
        for_ mIn hClose
        outBytes <- case mOut of
          Just outh -> BS.hGetContents outh
          Nothing   -> pure BS.empty
        errStr <- case mErr of
          Just errh -> hGetContents errh
          Nothing   -> pure ""
        exitCode <- waitForProcess ph
        pure (exitCode, outBytes, T.pack errStr)
    )
    (\(err :: SomeException) -> pure (ExitFailure 127, BS.empty, T.pack (show err)))

-- | Verifies a single restored file on disk against the raw blob stored in the detached Git store.
verifySingleFile :: PlanStore -> Text -> FilePath -> IO (Either PlanError Bool)
verifySingleFile store commitSha relPath = do
  let fullPath = planWorkTree store </> relPath
  diskExists <- doesFileExist fullPath
  if not diskExists
    then pure (Right False)
    else do
      diskBytes <- BS.readFile fullPath
      let gitObjSpec = T.unpack commitSha ++ ":" ++ relPath
      (code, blobBytes, _) <- runGitInStoreBytes store ["cat-file", "-p", gitObjSpec]
      case code of
        ExitSuccess   -> pure (Right (diskBytes == blobBytes))
        ExitFailure _ -> pure (Right False)

-- | Verifies bitwise integrity for a collection of restored files against the target commit.
verifyFilesIntegrity :: PlanStore -> Text -> [FilePath] -> IO (Either PlanError Bool)
verifyFilesIntegrity _ _ [] = pure (Right True)
verifyFilesIntegrity store commitSha files = do
  results <- mapM (verifySingleFile store commitSha) files
  case sequence results of
    Left err    -> pure (Left err)
    Right bools -> pure (Right (and bools))

-- | Deterministically rolls back ecosystem planning state to a specified checkpoint reference.
--
-- In accordance with Note [Deterministic Plan Rollback Invariants]
-- [ref:note-plan-rollback-invariants]:
-- 1. Validates that the target revision exists in the detached Git repository.
-- 2. Records pre-mutation safety snapshots of all governed files currently existing on disk.
-- 3. Restores governed files from the Git object store (@git checkout <ref> -- <files>@).
-- 4. Verifies byte-level integrity by comparing restored disk contents with Git blob objects.
rollbackToCheckpoint :: PlanStore -> Text -> IO (Either PlanError RollbackResult)
rollbackToCheckpoint store targetRef = do
  -- 1. Validate target ref in store
  (revCode, revOut, revErr) <- runGitInStore store ["rev-parse", "--verify", T.unpack targetRef ++ "^{commit}"]
  case revCode of
    ExitFailure _ -> pure (Left (PlanGitError ("Target ref does not exist: " <> targetRef <> " (" <> revErr <> ")")))
    ExitSuccess -> do
      let resolvedSha = T.strip revOut

      -- 2. Identify governed files present in target revision
      (treeCode, treeOut, _) <- runGitInStore store ["ls-tree", "-r", "--name-only", T.unpack resolvedSha]
      let filesInCommit =
            case treeCode of
              ExitSuccess ->
                let treeLines = map T.unpack (T.lines treeOut)
                in filter (`elem` planGovernedFiles store) treeLines
              ExitFailure _ -> []
          filesToCheckout =
            if null filesInCommit
              then planGovernedFiles store
              else filesInCommit

      -- 3. Take pre-mutation safety snapshots of all existing governed files on disk
      snapDir <- resolveSnapshotDirForStore store
      createDirectoryIfMissing True snapDir
      let workRoot = planWorkTree store
      existingWorkFiles <- filterM (\f -> doesFileExist (workRoot </> f)) (planGovernedFiles store)
      safetySnapsEither <- mapM (\f -> createSnapshot snapDir (workRoot </> f) False) existingWorkFiles
      case sequence safetySnapsEither of
        Left err -> pure (Left err)
        Right safetySnaps -> do
          -- 4. Restore target files via git checkout
          (checkoutCode, _, checkoutErr) <-
            runGitInStore store (["checkout", T.unpack resolvedSha, "--"] ++ filesToCheckout)
          case checkoutCode of
            ExitFailure _ -> pure (Left (PlanGitError ("Git checkout failed: " <> checkoutErr)))
            ExitSuccess -> do
              -- 5. Verify byte-level integrity
              verifyRes <- verifyFilesIntegrity store resolvedSha filesToCheckout
              case verifyRes of
                Left err -> pure (Left err)
                Right verified ->
                  pure (Right RollbackResult
                    { rollbackTargetRef       = resolvedSha
                    , rollbackSafetySnapshots = safetySnaps
                    , rollbackRestoredFiles   = filesToCheckout
                    , rollbackVerified        = verified
                    })

-- | Computes unified diff of governed documents between working tree and a Git revision.
computePlanDiff :: PlanStore -> Maybe Text -> IO (Either PlanError PlanDiff)
computePlanDiff store mTargetRevision = do
  let baseDiffArgs =
        case mTargetRevision of
          Just rev -> ["diff", T.unpack rev, "--"]
          Nothing  -> ["diff", "HEAD", "--"]
      diffArgs = baseDiffArgs ++ planGovernedFiles store
  (code, stdoutTxt, stderrTxt) <- runGitInStore store diffArgs
  case code of
    ExitFailure _ -> pure (Left (PlanGitError stderrTxt))
    ExitSuccess -> do
      let nameArgs =
            (case mTargetRevision of
               Just rev -> ["diff", "--name-only", T.unpack rev, "--"]
               Nothing  -> ["diff", "--name-only", "HEAD", "--"])
            ++ planGovernedFiles store
      (nameCode, nameOut, _) <- runGitInStore store nameArgs
      let changed =
            case nameCode of
              ExitSuccess   -> filter (not . null) (map T.unpack (T.lines nameOut))
              ExitFailure _ -> []

          diffLines = T.lines stdoutTxt
          isAdd l = "+" `T.isPrefixOf` l && not ("+++" `T.isPrefixOf` l)
          isDel l = "-" `T.isPrefixOf` l && not ("---" `T.isPrefixOf` l)
          addCount = length (filter isAdd diffLines)
          delCount = length (filter isDel diffLines)

      pure (Right PlanDiff
        { diffTargetRef    = mTargetRevision
        , diffRawContent   = stdoutTxt
        , diffChangedFiles = changed
        , diffAdditions    = addCount
        , diffDeletions    = delCount
        })

-- | Parses a single commit record emitted with delimiter bytes.
parseCommitRecord :: Text -> PlanCommit
parseCommitRecord rawRecord =
  let fields = T.splitOn "\x1f" rawRecord
      getFld idx = case drop idx fields of
        (val:_) -> val
        []      -> ""
      cHash      = T.strip (getFld 0)
      cShortHash = T.strip (getFld 1)
      cAuthor    = T.strip (getFld 2)
      cTimeSec   = T.strip (getFld 3)
      cSubject   = T.strip (getFld 4)
      cBody      = T.strip (getFld 5)
      cTimestamp =
        case (readMaybe (T.unpack cTimeSec) :: Maybe Integer) of
          Just s  -> posixSecondsToUTCTime (fromIntegral s)
          Nothing -> posixSecondsToUTCTime 0
      trailers   = extractTrailers cBody
  in PlanCommit
       { commitHash      = cHash
       , commitShortHash = cShortHash
       , commitAuthor    = cAuthor
       , commitTimestamp = cTimestamp
       , commitSubject   = cSubject
       , commitBody      = cBody
       , commitTrailers  = trailers
       }

-- | Extracts RFC 2822 git trailers from a commit body.
extractTrailers :: Text -> [(Text, Text)]
extractTrailers bodyText =
  let bodyLines = map T.strip (T.lines bodyText)
      parseTrailerLine line =
        case T.breakOn ":" line of
          (k, rest)
            | not (T.null rest) && isTrailerKey k ->
                let val = T.strip (T.drop 1 rest)
                in Just (k, val)
          _ -> Nothing
      isTrailerKey k =
        not (T.null k) && T.all (\c -> c == '-' || isAsciiLower c || isAsciiUpper c) k
  in mapMaybe parseTrailerLine bodyLines

-- | Queries the chronological commit log of plan governance history.
queryPlanLog :: PlanStore -> Int -> IO (Either PlanError [PlanCommit])
queryPlanLog store limit = do
  let n = if limit <= 0 then 20 else limit
      logFormat = "--format=%H%x1f%h%x1f%an <%ae>%x1f%ct%x1f%s%x1f%b%x1e"
      args = ["log", "-n", show n, logFormat, "--"] ++ planGovernedFiles store
  (code, stdoutTxt, stderrTxt) <- runGitInStore store args
  case code of
    ExitFailure _ ->
      if "does not have any commits yet" `T.isInfixOf` stderrTxt
         || "fatal: your current branch 'master' does not have any commits yet" `T.isInfixOf` stderrTxt
         || "fatal: your current branch 'main' does not have any commits yet" `T.isInfixOf` stderrTxt
        then pure (Right [])
        else pure (Left (PlanGitError stderrTxt))
    ExitSuccess -> do
      let rawRecords = T.splitOn "\x1e" stdoutTxt
          nonEmptyRecords = filter (not . T.null . T.strip) rawRecords
          parsedCommits = map parseCommitRecord nonEmptyRecords
      pure (Right parsedCommits)

-- | Formats a commit message with canonical Sarutahiko RFC 2822 commit attribution trailers.
formatSarutahikoCommitMessage :: Text -> Text
formatSarutahikoCommitMessage rawMsg =
  let msg = T.strip rawMsg
      effectiveMsg = if T.null msg then "Ecosystem plan governance checkpoint" else msg
      hasAssisted = "Assisted-by:" `T.isInfixOf` effectiveMsg
      hasOrchestrated = "Orchestrated-by:" `T.isInfixOf` effectiveMsg
      trailers = case (hasAssisted, hasOrchestrated) of
        (True, True)   -> ""
        (True, False)  -> "\nOrchestrated-by: Sarutahiko"
        (False, True)  -> "\nAssisted-by: Antigravity"
        (False, False) -> "\nAssisted-by: Antigravity\nOrchestrated-by: Sarutahiko"
  in if T.null trailers
       then effectiveMsg
       else effectiveMsg <> "\n" <> trailers

-- | Creates an atomic plan milestone checkpoint.
--
-- 1. Takes pre-mutation snapshots marked as milestone checkpoints for all existing governed files.
-- 2. Stages all existing governed files in the detached Git store.
-- 3. Atomically commits them with Sarutahiko RFC 2822 commit attribution trailers.
createPlanCheckpoint :: PlanStore -> Maybe Text -> IO (Either PlanError CheckpointResult)
createPlanCheckpoint store mUserMsg = do
  let workRoot = planWorkTree store
  existingFiles <- filterM (\f -> doesFileExist (workRoot </> f)) (planGovernedFiles store)
  if null existingFiles
    then pure (Left (PlanIOError "No governed files found on disk to checkpoint"))
    else do
      snapDir <- resolveSnapshotDirForStore store
      createDirectoryIfMissing True snapDir
      snapsEither <- mapM (\f -> createSnapshot snapDir (workRoot </> f) True) existingFiles
      case sequence snapsEither of
        Left err -> pure (Left err)
        Right snapshots -> do
          stageRes <- trackGovernedFiles store
          case stageRes of
            Left err -> pure (Left err)
            Right stagedPaths -> do
              let rawMsg = fromMaybe "Ecosystem plan governance checkpoint" mUserMsg
                  formattedMsg = formatSarutahikoCommitMessage rawMsg
              commitRes <- commitStore store formattedMsg
              case commitRes of
                Left err -> pure (Left err)
                Right commitSha ->
                  pure (Right CheckpointResult
                    { checkpointCommitSha   = commitSha
                    , checkpointSnapshots   = snapshots
                    , checkpointStagedFiles = stagedPaths
                    , checkpointMessage     = formattedMsg
                    })
