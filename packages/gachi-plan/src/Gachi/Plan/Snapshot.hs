{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Module: Gachi.Plan.Snapshot
-- Description: Append-only snapshot ledger engine with SHA-256 integrity verification
--
-- This module implements Milestone 5.2 of Phase 5 (Ecosystem Plan Governance & Rollback
-- per ~/src/PLAN.md §1.A). It provides an append-only snapshot ledger engine writing
-- immutable pre-mutation backups to @~/src/plans/snapshots/@ (configurable via
-- @PLAN_SNAPSHOT_DIR@).
--
-- = Architectural Context & Invariants
--
-- Note [Append-Only Plan Snapshot Invariants]
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- [tag:note-plan-snapshots]
-- The plan snapshot ledger operates as an immutable, append-only repository of
-- pre-mutation state backups and milestone checkpoints located in
-- @~/src/plans/snapshots/@ (configurable via @PLAN_SNAPSHOT_DIR@).
--
-- Core Invariants:
-- 1. __Append-Only Immutability Invariant:__
--    Snapshots are strictly write-once. Once written, snapshot files and their
--    associated sidecars are marked read-only on the filesystem (owner write permission
--    revoked). Pre-existing snapshot files are never overwritten in-place under any
--    circumstances.
--
-- 2. __Cryptographic Sidecar Verification:__
--    Every snapshot file is accompanied by a companion @.sha256@ digest sidecar
--    (e.g. @2026-10-28-174500-PLAN.md.sha256@) containing the NIST FIPS 180-2
--    SHA-256 checksum calculated over the immutable snapshot bytes. Tamper detection
--    verifies bitwise equivalence between the sidecar digest and recomputed file hash.
--
-- 3. __Deterministic Timestamped Naming:__
--    Snapshot files follow the canonical timestamp format:
--    @YYYY-MM-DD-HHMMSS-<filename>@ for standard pre-mutation safety backups, and
--    @YYYY-MM-DD-HHMMSS-checkpoint-<filename>@ (with companion @.checkpoint@ sidecar)
--    for milestone checkpoints.
--
-- 4. __Milestone Checkpoint Preservation:__
--    Automated snapshot pruning enforces a retention window for ephemeral pre-mutation
--    snapshots while permanently preserving milestone checkpoints. Checkpoints marked
--    with semantic labels are strictly exempt from pruning regardless of age or
--    retention counts.
--
-- 5. __Zero Partial Functions:__
--    All filesystem discovery, path slicing, sidecar parsing, and timestamp extraction
--    routines are implemented using total pattern matching and safe combinators.
--    No unsafe partial functions or partial list indexing operations are permitted.
module Gachi.Plan.Snapshot
  ( -- * Snapshot Creation & Verification
    createSnapshot
  , createSnapshotAt
  , verifySnapshotIntegrity

    -- * Ledger Querying & Pruning
  , listSnapshots
  , pruneSnapshots

    -- * Path & Environment Resolution
  , resolvePlanSnapshotDir

    -- * Low-Level Hashing & Sidecars
  , computeFileSha256
  , writeSha256Sidecar
  ) where

import Control.Exception (SomeException, catch)
import Control.Monad (forM_, when)
import qualified Data.ByteString as BS
import Data.Char (isHexDigit, toLower)
import Data.List (isPrefixOf, isSuffixOf, sortOn)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Time
  ( UTCTime
  , defaultTimeLocale
  , formatTime
  , getCurrentTime
  , parseTimeM
  )
import System.Directory
  ( createDirectoryIfMissing
  , doesDirectoryExist
  , doesFileExist
  , getHomeDirectory
  , getPermissions
  , listDirectory
  , makeAbsolute
  , removeFile
  , setOwnerWritable
  , setPermissions
  )
import System.Environment (lookupEnv)
import System.FilePath ((<.>), (</>), takeFileName)

import Gachi.Plan.Types
  ( PlanError(..)
  , SnapshotMeta(..)
  , defaultSnapshotDirName
  , planSnapshotDirEnvVar
  )
import Gachi.Sync.Hash (sha256ByteString)

-- | Resolves the target snapshot ledger directory.
--
-- Precedence:
-- 1. Explicitly provided 'FilePath' argument (if 'Just').
-- 2. Environment variable @PLAN_SNAPSHOT_DIR@ (if set and non-empty).
-- 3. Canonical default at @~/src/plans/snapshots@ relative to the user's home directory.
resolvePlanSnapshotDir :: Maybe FilePath -> IO FilePath
resolvePlanSnapshotDir (Just p) = makeAbsolute p
resolvePlanSnapshotDir Nothing = do
  mEnv <- lookupEnv planSnapshotDirEnvVar
  case mEnv of
    Just envPath | not (null envPath) -> makeAbsolute envPath
    _ -> do
      home <- getHomeDirectory
      let srcPlansDir = home </> "src" </> defaultSnapshotDirName
      srcPlansExists <- doesDirectoryExist (home </> "src")
      if srcPlansExists
        then makeAbsolute srcPlansDir
        else makeAbsolute (home </> defaultSnapshotDirName)

-- | Computes the hexadecimal SHA-256 digest of a target file.
computeFileSha256 :: FilePath -> IO (Either PlanError Text)
computeFileSha256 path = do
  exists <- doesFileExist path
  if not exists
    then pure (Left (PlanIOError ("Cannot compute hash: file does not exist: " <> T.pack path)))
    else catch
      (do bytes <- BS.readFile path
          pure (Right (sha256ByteString bytes)))
      (\(err :: SomeException) ->
         pure (Left (PlanIOError ("Error reading file for hash: " <> T.pack (show err)))))

-- | Writes a companion @.sha256@ sidecar file adjacent to the target snapshot file.
--
-- Sets the resulting sidecar to read-only mode to enforce immutability.
writeSha256Sidecar :: FilePath -> Text -> IO (Either PlanError FilePath)
writeSha256Sidecar snapshotFile digest = do
  let sidecarFile = snapshotFile <.> "sha256"
      sidecarContent = digest <> "\n"
  catch
    (do BS.writeFile sidecarFile (TE.encodeUtf8 sidecarContent)
        perms <- getPermissions sidecarFile
        setPermissions sidecarFile (setOwnerWritable False perms)
        pure (Right sidecarFile))
    (\(err :: SomeException) ->
       pure (Left (PlanIOError ("Failed to write sha256 sidecar: " <> T.pack (show err)))))

-- | Creates an immutable, timestamped snapshot of a target file in the snapshot directory.
--
-- In accordance with Note [Append-Only Plan Snapshot Invariants] [ref:note-plan-snapshots],
-- this operation:
-- 1. Copies target governance file into snapshot directory with a @YYYY-MM-DD-HHMMSS-@ prefix.
-- 2. If 'isCheckpoint' is 'True', inserts a @-checkpoint-@ infix and writes a @.checkpoint@ marker.
-- 3. Computes the cryptographic SHA-256 digest and writes a companion @.sha256@ sidecar.
-- 4. Revokes owner write permissions on both files, enforcing the append-only invariant.
--
-- Accepts parameters in either order: @(snapshotDir, targetFile)@ or @(targetFile, snapshotDir)@.
createSnapshot :: FilePath -> FilePath -> Bool -> IO (Either PlanError SnapshotMeta)
createSnapshot p1 p2 isCheckpoint = do
  now <- getCurrentTime
  createSnapshotAt now p1 p2 isCheckpoint

-- | Deterministic snapshot creation at a designated 'UTCTime' timestamp.
createSnapshotAt :: UTCTime -> FilePath -> FilePath -> Bool -> IO (Either PlanError SnapshotMeta)
createSnapshotAt timestamp p1 p2 isCheckpoint = do
  -- Resolve arguments: detect if caller passed (targetFile, snapshotDir) or (snapshotDir, targetFile)
  p1IsFile <- doesFileExist p1
  p2IsFile <- doesFileExist p2
  let (snapshotDir, targetFile) =
        if p1IsFile && not p2IsFile
          then (p2, p1)
          else (p1, p2)

  targetExists <- doesFileExist targetFile
  if not targetExists
    then pure (Left (PlanIOError ("Target file does not exist: " <> T.pack targetFile)))
    else do
      createDirectoryIfMissing True snapshotDir
      let timePrefix = formatTime defaultTimeLocale "%Y-%m-%d-%H%M%S" timestamp
          baseName = takeFileName targetFile
          snapshotFileName =
            if isCheckpoint
              then timePrefix ++ "-checkpoint-" ++ baseName
              else timePrefix ++ "-" ++ baseName
          targetSnapshotPath = snapshotDir </> snapshotFileName
          sidecarPath = targetSnapshotPath <.> "sha256"
          checkpointMarkerPath = targetSnapshotPath <.> "checkpoint"

      alreadyExists <- doesFileExist targetSnapshotPath
      if alreadyExists
        then pure (Left (PlanIOError ("Snapshot file already exists (append-only invariant): " <> T.pack targetSnapshotPath)))
        else catch
          (do -- 1. Read source bytes
              contentBytes <- BS.readFile targetFile
              let digest = sha256ByteString contentBytes

              -- 2. Write snapshot file
              BS.writeFile targetSnapshotPath contentBytes

              -- 3. Write sidecar file
              BS.writeFile sidecarPath (TE.encodeUtf8 (digest <> "\n"))

              -- 4. Write checkpoint marker if checkpoint
              when isCheckpoint $
                BS.writeFile checkpointMarkerPath (TE.encodeUtf8 "checkpoint\n")

              -- 5. Revoke write permissions to ensure immutability
              perms1 <- getPermissions targetSnapshotPath
              setPermissions targetSnapshotPath (setOwnerWritable False perms1)

              perms2 <- getPermissions sidecarPath
              setPermissions sidecarPath (setOwnerWritable False perms2)

              when isCheckpoint $ do
                perms3 <- getPermissions checkpointMarkerPath
                setPermissions checkpointMarkerPath (setOwnerWritable False perms3)

              absSnapshotPath <- makeAbsolute targetSnapshotPath
              let meta = SnapshotMeta
                    { snapshotId           = T.pack snapshotFileName
                    , snapshotPath         = absSnapshotPath
                    , snapshotTimestamp    = timestamp
                    , snapshotSha256       = digest
                    , snapshotSourceFile   = baseName
                    , snapshotIsCheckpoint = isCheckpoint
                    }
              pure (Right meta))
          (\(err :: SomeException) ->
             pure (Left (PlanIOError ("Failed to create snapshot: " <> T.pack (show err)))))

-- | Verifies the cryptographic integrity of a snapshot against its @.sha256@ sidecar.
--
-- Recomputes the SHA-256 digest of the snapshot file and verifies equality with the
-- digest recorded in the companion sidecar file. Returns 'True' if matching, 'False'
-- if corrupted or tampered with.
verifySnapshotIntegrity :: FilePath -> IO (Either PlanError Bool)
verifySnapshotIntegrity snapshotPath = do
  snapshotExists <- doesFileExist snapshotPath
  if not snapshotExists
    then pure (Left (PlanIOError ("Snapshot file missing: " <> T.pack snapshotPath)))
    else do
      let sidecarPath = snapshotPath <.> "sha256"
      sidecarExists <- doesFileExist sidecarPath
      if not sidecarExists
        then pure (Left (PlanIOError ("Sidecar checksum file missing: " <> T.pack sidecarPath)))
        else catch
          (do snapshotBytes <- BS.readFile snapshotPath
              sidecarBytes <- BS.readFile sidecarPath
              let computedDigest = sha256ByteString snapshotBytes
                  rawSidecarText = TE.decodeUtf8Lenient sidecarBytes
                  expectedDigest = extractDigestText rawSidecarText
              pure (Right (computedDigest == expectedDigest)))
          (\(err :: SomeException) ->
             pure (Left (PlanIOError ("Error reading files for integrity verification: " <> T.pack (show err)))))
  where
    -- Extracts first 64-character hex sequence from sidecar content
    extractDigestText :: Text -> Text
    extractDigestText t =
      let candidateWords = T.words t
      in case candidateWords of
           [] -> ""
           (w:_) ->
             let hexChars = filter isHexDigit (map toLower (T.unpack w))
             in T.pack (take 64 hexChars)

-- | Lists all snapshots recorded in the snapshot ledger in ordered chronological sequence.
--
-- Discovers all timestamped snapshot files in @snapshotDir@, excluding @.sha256@ and
-- @.checkpoint@ sidecars, and parses their metadata.
listSnapshots :: FilePath -> IO [SnapshotMeta]
listSnapshots snapshotDir = do
  dirExists <- doesDirectoryExist snapshotDir
  if not dirExists
    then pure []
    else do
      entries <- listDirectory snapshotDir
      absDir <- makeAbsolute snapshotDir
      let candidateFiles = filter isSnapshotFile entries
      metas <- mapMaybeM (parseSnapshotEntry absDir) candidateFiles
      pure (sortOn snapshotTimestamp metas)
  where
    isSnapshotFile :: FilePath -> Bool
    isSnapshotFile name =
      not ("." `isPrefixOf` name)
        && not (".sha256" `isSuffixOf` name)
        && not (".checkpoint" `isSuffixOf` name)
        && not (".tmp" `isSuffixOf` name)

    mapMaybeM :: (a -> IO (Maybe b)) -> [a] -> IO [b]
    mapMaybeM _ [] = pure []
    mapMaybeM f (x:xs) = do
      mRes <- f x
      rest <- mapMaybeM f xs
      case mRes of
        Nothing  -> pure rest
        Just val -> pure (val : rest)

    parseSnapshotEntry :: FilePath -> FilePath -> IO (Maybe SnapshotMeta)
    parseSnapshotEntry dir name = do
      let fullPath = dir </> name
      isFile <- doesFileExist fullPath
      if not isFile
        then pure Nothing
        else do
          -- Filename format: YYYY-MM-DD-HHMMSS-[checkpoint-]<filename>
          -- Prefix length: 17 chars (e.g. "2026-10-28-174500")
          let prefixStr = take 17 name
          case parseTimeM True defaultTimeLocale "%Y-%m-%d-%H%M%S" prefixStr of
            Nothing -> pure Nothing
            Just (parsedTime :: UTCTime) -> do
              let remaining = drop 18 name -- skip prefix and hyphen
                  (isCpByName, sourceName) =
                    if "checkpoint-" `isPrefixOf` remaining
                      then (True, drop 11 remaining)
                      else (False, remaining)

              cpMarkerExists <- doesFileExist (fullPath <.> "checkpoint")
              let isCheckpoint = isCpByName || cpMarkerExists

              -- Read sha256 from sidecar if present, otherwise compute
              let sidecarFile = fullPath <.> "sha256"
              hasSidecar <- doesFileExist sidecarFile
              shaText <-
                if hasSidecar
                  then catch
                    (do raw <- BS.readFile sidecarFile
                        let rawText = TE.decodeUtf8Lenient raw
                            wordsList = T.words rawText
                        case wordsList of
                          [] -> pure ""
                          (w:_) -> pure (T.pack (take 64 (filter isHexDigit (map toLower (T.unpack w))))))
                    (\(_ :: SomeException) -> pure "")
                  else catch
                    (do bytes <- BS.readFile fullPath
                        pure (sha256ByteString bytes))
                    (\(_ :: SomeException) -> pure "")

              pure (Just (SnapshotMeta
                { snapshotId           = T.pack name
                , snapshotPath         = fullPath
                , snapshotTimestamp    = parsedTime
                , snapshotSha256       = shaText
                , snapshotSourceFile   = sourceName
                , snapshotIsCheckpoint = isCheckpoint
                }))

-- | Prunes older non-checkpoint snapshots beyond the designated retention count threshold.
--
-- In accordance with Note [Append-Only Plan Snapshot Invariants] [ref:note-plan-snapshots],
-- milestone checkpoints are permanently preserved and never pruned. Only non-checkpoint
-- snapshots exceeding the retention limit are removed.
--
-- Returns the count of pruned snapshots.
pruneSnapshots :: FilePath -> Int -> IO Int
pruneSnapshots snapshotDir retentionCount = do
  allSnaps <- listSnapshots snapshotDir
  let nonCheckpoints = filter (not . snapshotIsCheckpoint) allSnaps
      retention = max 0 retentionCount
      totalNonCp = length nonCheckpoints

  if totalNonCp <= retention
    then pure 0
    else do
      let pruneCount = totalNonCp - retention
          toPrune = take pruneCount nonCheckpoints
      forM_ toPrune $ \s -> deleteSnapshotFiles (snapshotPath s)
      pure pruneCount
  where
    deleteSnapshotFiles :: FilePath -> IO ()
    deleteSnapshotFiles path = do
      let shaPath = path <.> "sha256"
          cpPath  = path <.> "checkpoint"
      forM_ [path, shaPath, cpPath] $ \p -> do
        exists <- doesFileExist p
        when exists $
          catch
            (do perms <- getPermissions p
                setPermissions p (setOwnerWritable True perms)
                removeFile p)
            (\(_ :: SomeException) ->
               catch (removeFile p) (\(_ :: SomeException) -> pure ()))
