{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Concurrent (forkIO, newEmptyMVar, putMVar, readMVar, takeMVar)
import Control.Monad (forM_, replicateM)
import Data.Monoid (Sum(..))
import Data.Text (Text)
import Data.Word (Word64, Word8)
import Test.Hspec

import Gachi.Core
import Gachi.Core.Traversal
import Gachi.Osteology

main :: IO ()
main = hspec do
  -- Tested against Note [Chattering Lock-Free Atomic Synchronization] [ref:note-chattering-synchronization]
  describe "Gachi.Core Skeletal Primitives" do
    it "constructs empty skeletal structure with zero bones and joints" do
      let skel = emptySkeleton :: Skeleton Text
      totalBones skel `shouldBe` 0
      totalJoints skel `shouldBe` 0
      lookupBone (BoneId 0) skel `shouldBe` Nothing
      lookupJoint (JointId 0) skel `shouldBe` Nothing

    -- Tested against Note [Monotonic Identifier Allocation and Contiguous Indexing] [ref:note-monotonic-id-allocation]
    it "inserts and retrieves bones with monotonically assigned identifiers in O(1)" do
      let skel0 = emptySkeleton :: Skeleton Text
          (b0, skel1) = insertBone "femur" skel0
          (b1, skel2) = insertBone "tibia" skel1
          (b2, skel3) = insertBone "cranium" skel2

      b0 `shouldBe` BoneId 0
      b1 `shouldBe` BoneId 1
      b2 `shouldBe` BoneId 2
      totalBones skel3 `shouldBe` 3

      lookupBone b0 skel3 `shouldBe` Just "femur"
      lookupBone b1 skel3 `shouldBe` Just "tibia"
      lookupBone b2 skel3 `shouldBe` Just "cranium"
      unsafeLookupBone b1 skel3 `shouldBe` "tibia"
      lookupBone (BoneId 99) skel3 `shouldBe` Nothing

    -- Tested against Note [Directional Joints and Incident Traversal] [ref:note-directional-joints-traversal]
    it "connects joints between bones and traverses incident connections" do
      let skel0 = emptySkeleton :: Skeleton Text
          (b0, skel1) = insertBone "femur" skel0
          (b1, skel2) = insertBone "patella" skel1
          (b2, skel3) = insertBone "tibia" skel2
          (j0, skel4) = connectJoint b0 b1 skel3
          (j1, skel5) = connectJoint b1 b2 skel4

      totalJoints skel5 `shouldBe` 2
      lookupJoint j0 skel5 `shouldBe` Just (Joint (JointId 0) b0 b1)
      lookupJoint j1 skel5 `shouldBe` Just (Joint (JointId 1) b1 b2)
      lookupJoint (JointId 99) skel5 `shouldBe` Nothing

      let incidents = incidentJoints b1 skel5
      length incidents `shouldBe` 2
      map jointId incidents `shouldBe` [JointId 0, JointId 1]

    -- Tested against Note [Zero-Copy Sub-Segment Slicing] [ref:note-zero-copy-slicing]
    it "extracts zero-copy bone slices from a skeleton" do
      let skel0 = emptySkeleton :: Skeleton Text
          (_, skel1) = insertBone "cervical" skel0
          (_, skel2) = insertBone "thoracic" skel1
          (_, skel3) = insertBone "lumbar" skel2
          (_, skel4) = insertBone "sacrum" skel3

      case sliceBones 1 2 skel4 of
        Nothing -> expectationFailure "sliceBones returned Nothing"
        Just sl -> do
          segmentLength sl `shouldBe` 2
          toListOsteo sl `shouldBe` ["thoracic", "lumbar"]

  -- Tested against Note [Osteological Contiguous Memory Layout] [ref:note-osteology-memory-layout]
  describe "Gachi.Osteology Contiguous Memory Layout" do
    it "constructs empty osteological segment" do
      let seg = emptySegment :: OsteoSegment Int
      segmentLength seg `shouldBe` 0
      segmentCapacity seg `shouldBe` 0
      indexOsteo 0 seg `shouldBe` Nothing

    -- Tested against Note [Geometric Capacity Expansion and Reallocation] [ref:note-geometric-capacity-expansion]
    it "appends elements sequentially and dynamically expands capacity" do
      let seg0 = emptySegment
          seg1 = appendOsteo (10 :: Int) seg0
          seg2 = appendOsteo 20 seg1
          seg3 = appendOsteo 30 seg2
          seg4 = appendOsteo 40 seg3
          seg5 = appendOsteo 50 seg4

      segmentLength seg5 `shouldBe` 5
      segmentCapacity seg5 `shouldSatisfy` (>= 5)

      indexOsteo 0 seg5 `shouldBe` Just 10
      indexOsteo 1 seg5 `shouldBe` Just 20
      indexOsteo 2 seg5 `shouldBe` Just 30
      indexOsteo 3 seg5 `shouldBe` Just 40
      indexOsteo 4 seg5 `shouldBe` Just 50
      unsafeIndexOsteo 2 seg5 `shouldBe` 30
      indexOsteo 5 seg5 `shouldBe` Nothing
      indexOsteo (-1) seg5 `shouldBe` Nothing

    -- Tested against Note [Zero-Copy Sub-Segment Slicing] [ref:note-zero-copy-slicing]
    it "performs zero-copy slicing within contiguous memory" do
      let seg = fromListOsteo [10, 20, 30, 40, 50 :: Int]
      case sliceOsteo 1 3 seg of
        Nothing -> expectationFailure "sliceOsteo returned Nothing"
        Just s1 -> do
          segmentLength s1 `shouldBe` 3
          toListOsteo s1 `shouldBe` [20, 30, 40]
          indexOsteo 0 s1 `shouldBe` Just 20
          indexOsteo 2 s1 `shouldBe` Just 40
          indexOsteo 3 s1 `shouldBe` Nothing

      sliceOsteo 0 6 seg `shouldBe` Nothing
      sliceOsteo (-1) 2 seg `shouldBe` Nothing
      sliceOsteo 2 (-1) seg `shouldBe` Nothing

    it "satisfies Semigroup concatenation into a single contiguous segment" do
      let segA = fromListOsteo [1, 2, 3 :: Int]
          segB = fromListOsteo [4, 5, 6 :: Int]
          combined = segA <> segB

      segmentLength combined `shouldBe` 6
      toListOsteo combined `shouldBe` [1, 2, 3, 4, 5, 6]

    it "implements Functor, Foldable, and Traversable lawfully" do
      let seg = fromListOsteo [1, 2, 3, 4, 5 :: Int]
          mapped = fmap (* 10) seg
      toListOsteo mapped `shouldBe` [10, 20, 30, 40, 50]
      sum seg `shouldBe` 15
      length seg `shouldBe` 5
      null seg `shouldBe` False
      null (emptySegment :: OsteoSegment Int) `shouldBe` True

  describe "Gachi.Osteology Unboxed Byte Storage" do
    it "constructs empty byte storage" do
      let bs = emptyBytes
      bytesLength bs `shouldBe` 0
      indexByte 0 bs `shouldBe` Nothing

    it "roundtrips fromByteList and toByteList faithfully" do
      let input = [0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0xFF] :: [Word8]
          bs = fromByteList input
      bytesLength bs `shouldBe` 6
      toByteList bs `shouldBe` input
      indexByte 0 bs `shouldBe` Just 0xDE
      indexByte 3 bs `shouldBe` Just 0xEF
      unsafeIndexByte 1 bs `shouldBe` 0xAD
      indexByte 6 bs `shouldBe` Nothing

    it "performs zero-copy slicing over unboxed byte arrays" do
      let input = [10, 20, 30, 40, 50 :: Word8]
          bs = fromByteList input
      case sliceBytes 1 3 bs of
        Nothing -> expectationFailure "sliceBytes returned Nothing"
        Just sl -> do
          bytesLength sl `shouldBe` 3
          toByteList sl `shouldBe` [20, 30, 40]
      sliceBytes 0 10 bs `shouldBe` Nothing

  -- Tested against Note [Chattering Lock-Free Atomic Synchronization] [ref:note-chattering-synchronization]
  describe "Gachi.Osteology.Atomic Tagged Word Layouts" do
    it "faithfully roundtrips all JointState constructors through 64-bit tagged words" do
      decodeJointState (encodeJointState JointInert) `shouldBe` JointInert
      decodeJointState (encodeJointState (JointChattering 0)) `shouldBe` JointChattering 0
      decodeJointState (encodeJointState (JointChattering 42)) `shouldBe` JointChattering 42
      decodeJointState (encodeJointState (JointChattering 0x1FFFFFFFFFFFFFFF))
        `shouldBe` JointChattering 0x1FFFFFFFFFFFFFFF
      decodeJointState (encodeJointState (JointSynchronized 0)) `shouldBe` JointSynchronized 0
      decodeJointState (encodeJointState (JointSynchronized 99999)) `shouldBe` JointSynchronized 99999
      decodeJointState (encodeJointState JointFused) `shouldBe` JointFused

    it "decodes zeroed memory naturally as JointInert (zero-initialization invariant)" do
      decodeJointState 0 `shouldBe` JointInert

    it "classifies joint lifecycle states with pure predicates" do
      isJointInert JointInert `shouldBe` True
      isJointInert (JointChattering 1) `shouldBe` False

      isJointChattering (JointChattering 10) `shouldBe` True
      isJointChattering JointInert `shouldBe` False

      isJointSynchronized (JointSynchronized 440) `shouldBe` True
      isJointSynchronized JointInert `shouldBe` False

      isJointFused JointFused `shouldBe` True
      isJointFused JointInert `shouldBe` False

  describe "Gachi.Core.Atomic Hardware Compare-And-Swap (Single-Threaded)" do
    it "initializes an unboxed joint reference to JointInert" do
      joint <- newAtomicJoint JointInert
      st <- readJointState joint
      st `shouldBe` JointInert

    it "succeeds on valid expected state and fails on mismatched expected state" do
      joint <- newAtomicJoint JointInert

      -- 1. Valid transition: JointInert -> JointChattering 1
      res1 <- casJointState joint JointInert (JointChattering 1)
      res1 `shouldBe` True
      readJointState joint `shouldReturn` JointChattering 1

      -- 2. Mismatched transition: expected JointInert but current is JointChattering 1
      res2 <- casJointState joint JointInert (JointChattering 2)
      res2 `shouldBe` False
      -- Memory must remain untouched
      readJointState joint `shouldReturn` JointChattering 1

      -- 3. Transition to JointSynchronized 440
      res3 <- casJointState joint (JointChattering 1) (JointSynchronized 440)
      res3 `shouldBe` True
      readJointState joint `shouldReturn` JointSynchronized 440

      -- 4. Transition to terminal JointFused
      res4 <- casJointState joint (JointSynchronized 440) JointFused
      res4 `shouldBe` True
      readJointState joint `shouldReturn` JointFused

    it "transitions joint with transitionJointWithBackoff" do
      joint <- newAtomicJoint JointInert
      res <- transitionJointWithBackoff joint (\s -> case s of
        JointInert -> Just (JointChattering 1)
        _          -> Nothing) 5
      res `shouldBe` Right (JointChattering 1)
      readJointState joint `shouldReturn` JointChattering 1

    it "fails with InvalidTransition when transition function disallows state" do
      joint <- newAtomicJoint JointFused
      res <- transitionJointWithBackoff joint (\s -> case s of
        JointChattering n -> Just (JointChattering (n + 1))
        _                 -> Nothing) 5
      res `shouldBe` Left (InvalidTransition JointFused)
      readJointState joint `shouldReturn` JointFused

  describe "Gachi.Core.Atomic Multi-Threaded High-Contention CAS Race" do
    it "resolves a 20-thread CAS race where exactly one thread succeeds and zero corrupt states emerge" do
      joint <- newAtomicJoint JointInert
      resultsMVar <- newEmptyMVar
      barrier <- newEmptyMVar
      let numThreads = 20 :: Int

      forM_ [1 .. numThreads] \tid -> forkIO do
        -- Synchronize starting line
        readMVar barrier
        success <- casJointState joint JointInert (JointChattering (fromIntegral tid))
        putMVar resultsMVar (tid, success)

      -- Release all threads simultaneously
      putMVar barrier ()

      results <- replicateM numThreads (takeMVar resultsMVar)
      let winners = [ tid | (tid, True) <- results ]

      -- Exactly one thread must win the race
      length winners `shouldBe` 1

      case winners of
        [winnerId] -> do
          finalState <- readJointState joint
          finalState `shouldBe` JointChattering (fromIntegral winnerId)
        _ -> expectationFailure ("Expected exactly 1 winner, but got: " ++ show winners)

    it "linearizes 500 concurrent transitions across 20 threads with bounded backoff" do
      joint <- newAtomicJoint JointInert
      let numThreads = 20 :: Int
          incrementsPerThread = 25 :: Int
      barrier <- newEmptyMVar
      doneMVar <- newEmptyMVar

      forM_ [1 .. numThreads] \_ -> forkIO do
        readMVar barrier
        forM_ [1 .. incrementsPerThread] \_ -> do
          res <- transitionJointWithBackoff joint (\case
            JointInert        -> Just (JointChattering 1)
            JointChattering n -> Just (JointChattering (n + 1))
            _                 -> Nothing) 100
          case res of
            Left err -> putMVar doneMVar (Just err)
            Right _  -> pure ()
        putMVar doneMVar Nothing

      -- Release all worker threads
      putMVar barrier ()

      errors <- replicateM numThreads (takeMVar doneMVar)
      -- Assert zero backoff errors occurred
      let failed = [ err | Just err <- errors ]
      failed `shouldBe` []

      -- Total increments = 20 * 25 = 500
      finalState <- readJointState joint
      finalState `shouldBe` JointChattering (fromIntegral (numThreads * incrementsPerThread))

  describe "Gachi.Core.Atomic Wait-Free Reads Under Write Saturation" do
    it "maintains wait-free monotonic read progression under heavy writer contention" do
      joint <- newAtomicJoint (JointChattering 0)
      let writeIterations = 2000 :: Word64
          numReaders = 4 :: Int
          readsPerReader = 500 :: Int
      startBarrier <- newEmptyMVar
      readerDone <- newEmptyMVar

      -- Spawn concurrent reader threads
      forM_ [1 .. numReaders] \_ -> forkIO do
        readMVar startBarrier
        let loop 0 !_prev = pure ()
            loop !k !prev = do
              st <- readJointState joint
              case st of
                JointChattering cur -> do
                  if cur >= prev
                    then loop (k - 1) cur
                    else putMVar readerDone (Just ("Non-monotonic read: observed " ++ show cur ++ " after " ++ show prev))
                _ -> putMVar readerDone (Just ("Unexpected state during saturation: " ++ show st))
        loop readsPerReader 0
        putMVar readerDone Nothing

      -- Spawn writer thread saturating the atomic joint with transitions
      writerDone <- newEmptyMVar
      _ <- forkIO do
        readMVar startBarrier
        forM_ [1 .. writeIterations] \i -> do
          writeJointState joint (JointChattering i)
        putMVar writerDone ()

      -- Trigger all threads simultaneously
      putMVar startBarrier ()

      -- Wait for writer and readers
      takeMVar writerDone
      readerErrors <- replicateM numReaders (takeMVar readerDone)

      let badReads = [ err | Just err <- readerErrors ]
      badReads `shouldBe` []

      finalState <- readJointState joint
      finalState `shouldBe` JointChattering writeIterations

  -- Tested against Note [Concurrent Skeletal Graph Traversal] [ref:note-concurrent-traversal]
  describe "Gachi.Core.Traversal Concurrent & Snapshot Primitives" do
    it "handles empty skeletons gracefully across all traversal routines" do
      let skel = emptySkeleton :: Skeleton Text
      bonesRes <- traverseSkeletonConcurrently skel (\b -> pure (bonePayload b))
      bonesRes `shouldBe` []

      fRes <- foldBonesConcurrently skel (\acc _ -> pure (acc + 1 :: Int)) 0
      fRes `shouldBe` 0

      mSum <- foldMapBonesConcurrently skel (\_ -> pure (Sum (1 :: Int)))
      mSum `shouldBe` Sum 0

      bPath <- findBonePathConcurrently skel (BoneId 0) (BoneId 1)
      bPath `shouldBe` Nothing

      jPath <- findJointPathConcurrently skel (JointId 0) (JointId 1)
      jPath `shouldBe` Nothing

      bfsRes <- traverseSkeletonBFS skel (BoneId 0)
      bfsRes `shouldBe` []

      dfsRes <- traverseSkeletonDFS skel (BoneId 0)
      dfsRes `shouldBe` []

      snap <- snapshotSkeleton skel
      snapshotBones snap `shouldBe` []
      snapshotJoints snap `shouldBe` []

    it "traverses bones concurrently preserving strict monotonic evaluation order" do
      let n = 100 :: Int
          buildSkel !s 0 = s
          buildSkel !s !k =
            let !i = n - k
                (_, !s') = insertBone i s
            in buildSkel s' (k - 1)
          skel = buildSkel emptySkeleton n

      traversed <- traverseSkeletonConcurrently skel (\b -> pure (bonePayload b))
      traversed `shouldBe` [0 .. n - 1]

    it "folds bones concurrently matching sequential evaluation" do
      let n = 50 :: Int
          buildSkel !s 0 = s
          buildSkel !s !k =
            let !i = n - k
                (_, !s') = insertBone i s
            in buildSkel s' (k - 1)
          skel = buildSkel emptySkeleton n

      foldedSum <- foldBonesConcurrently skel (\acc b -> pure (acc + bonePayload b)) 0
      foldedSum `shouldBe` sum [0 .. n - 1]

    it "foldMapBonesConcurrently combines monoidal payloads faithfully" do
      let n = 50 :: Int
          buildSkel !s 0 = s
          buildSkel !s !k =
            let !i = n - k
                (_, !s') = insertBone i s
            in buildSkel s' (k - 1)
          skel = buildSkel emptySkeleton n

      Sum total <- foldMapBonesConcurrently skel (\b -> pure (Sum (bonePayload b)))
      total `shouldBe` sum [0 .. n - 1]

    it "finds directed and bidirectional paths through bone and joint networks" do
      let skel0 = emptySkeleton :: Skeleton Text
          (b0, skel1) = insertBone "femur" skel0
          (b1, skel2) = insertBone "patella" skel1
          (b2, skel3) = insertBone "tibia" skel2
          (j0, skel4) = connectJoint b0 b1 skel3
          (j1, skel5) = connectJoint b1 b2 skel4

      -- Forward path: b0 -> b2
      mPathFwd <- findBonePathConcurrently skel5 b0 b2
      case mPathFwd of
        Nothing -> expectationFailure "Expected path between b0 and b2"
        Just p  -> map bonePayload p `shouldBe` ["femur", "patella", "tibia"]

      -- Reverse query with Forward config should fail:
      let fwdCfg = defaultTraversalConfig { traversalDirection = Forward }
      mPathRevFwd <- findBonePathConcurrentlyWith fwdCfg skel5 b2 b0
      mPathRevFwd `shouldBe` Nothing

      -- Reverse query with Reverse config should succeed:
      let revCfg = defaultTraversalConfig { traversalDirection = Reverse }
      mPathRev <- findBonePathConcurrentlyWith revCfg skel5 b2 b0
      case mPathRev of
        Nothing -> expectationFailure "Expected reverse path between b2 and b0"
        Just p  -> map bonePayload p `shouldBe` ["tibia", "patella", "femur"]

      -- Joint path: j0 -> j1
      mJointPath <- findJointPathConcurrently skel5 j0 j1
      case mJointPath of
        Nothing -> expectationFailure "Expected joint path between j0 and j1"
        Just jp -> map osteoJointId jp `shouldBe` [j0, j1]

      -- Root path when start == end
      mSelfPath <- findBonePathConcurrently skel5 b1 b1
      case mSelfPath of
        Nothing -> expectationFailure "Expected self path for b1"
        Just p  -> map bonePayload p `shouldBe` ["patella"]

    it "performs BFS and DFS graph walks over skeletal components" do
      let skel0 = emptySkeleton :: Skeleton Text
          (b0, skel1) = insertBone "root" skel0
          (b1, skel2) = insertBone "left" skel1
          (b2, skel3) = insertBone "right" skel2
          (_, skel4)  = connectJoint b0 b1 skel3
          (_, skel5)  = connectJoint b0 b2 skel4

      bfsNodes <- traverseSkeletonBFS skel5 b0
      map bonePayload bfsNodes `shouldMatchList` ["root", "left", "right"]

      dfsNodes <- traverseSkeletonDFS skel5 b0
      map bonePayload dfsNodes `shouldMatchList` ["root", "left", "right"]

    it "captures instantaneous atomic joint snapshots under state transitions" do
      let skel0 = emptySkeleton :: Skeleton Text
          (b0, skel1) = insertBone "pelvis" skel0
          (b1, skel2) = insertBone "spine" skel1
          (j0, skel3) = connectJoint b0 b1 skel2

      skel <- initAtomicJoints skel3
      snap0 <- snapshotSkeleton skel
      map osteoJointState (snapshotJoints snap0) `shouldBe` [JointInert]

      case getAtomicJoint j0 skel of
        Nothing -> expectationFailure "Atomic joint j0 not found"
        Just aj -> do
          _ <- casJointState aj JointInert (JointChattering 42)
          snap1 <- snapshotSkeleton skel
          map osteoJointState (snapshotJoints snap1) `shouldBe` [JointChattering 42]

  -- Tested against Note [Concurrent Skeletal Graph Traversal] [ref:note-concurrent-traversal]
  describe "Gachi.Core.Traversal Multi-Agent High-Concurrency Stress Test" do
    it "executes 50 concurrent agents traversing a 1,000-bone graph with continuous joint transitions" do
      let boneCount = 1000 :: Int
          buildBones !s 0 !acc = (reverse acc, s)
          buildBones !s !k !acc =
            let !i = boneCount - k
                (!bid, !s') = insertBone i s
            in buildBones s' (k - 1) (bid : acc)
          (_bids, skel1) = buildBones emptySkeleton boneCount []

          buildJoints !s 0 !acc = (reverse acc, s)
          buildJoints !s !k !acc =
            let !i = (boneCount - 1) - k
                !src = BoneId (fromIntegral i)
                !dst = BoneId (fromIntegral (i + 1))
                (!jid, !s') = connectJoint src dst s
            in buildJoints s' (k - 1) (jid : acc)
          (_jids, skel2) = buildJoints skel1 (boneCount - 1) []

      skel <- initAtomicJoints skel2
      let expectedSum = sum [0 .. boneCount - 1]
          numWorkers = 50 :: Int
          numWriters = 5 :: Int
          writerTransitions = 100 :: Int

      startBarrier <- newEmptyMVar
      workerDone <- newEmptyMVar
      writerDone <- newEmptyMVar

      -- Background writers continuously transitioning joints
      forM_ [0 .. numWriters - 1] \wIdx -> forkIO do
        readMVar startBarrier
        forM_ [0 .. writerTransitions - 1] \stepIdx -> do
          let targetJointIdx = (wIdx * 199 + stepIdx * 7) `rem` (boneCount - 1)
              jid = JointId (fromIntegral targetJointIdx)
          case getAtomicJoint jid skel of
            Nothing -> pure ()
            Just aj -> do
              _ <- transitionJointWithBackoff aj (\case
                JointInert          -> Just (JointChattering (fromIntegral stepIdx))
                JointChattering _   -> Just (JointSynchronized (fromIntegral stepIdx))
                JointSynchronized _ -> Just (JointChattering (fromIntegral (stepIdx + 1)))
                JointFused          -> Just JointInert
                ) 10
              pure ()
        putMVar writerDone ()

      -- 50 Concurrent Agent Workers performing mixed traversals
      forM_ [0 .. numWorkers - 1] \wId -> forkIO do
        readMVar startBarrier
        res <- case wId `rem` 4 of
          -- Worker class 0: Full concurrent traversal verifying exact baseline match
          0 -> do
            traversed <- traverseSkeletonConcurrently skel (\b -> pure (bonePayload b))
            if traversed == [0 .. boneCount - 1]
              then pure (Right ())
              else pure (Left ("Worker " ++ show wId ++ ": traversed mismatch"))

          -- Worker class 1: Concurrent fold computing sum
          1 -> do
            val <- foldBonesConcurrently skel (\acc b -> pure (acc + bonePayload b)) 0
            if val == expectedSum
              then pure (Right ())
              else pure (Left ("Worker " ++ show wId ++ ": fold sum mismatch " ++ show val))

          -- Worker class 2: Concurrent path finding along graph segments
          2 -> do
            let startIdx = (wId * 17) `rem` (boneCount - 20)
                endIdx   = startIdx + 15
                srcBid   = BoneId (fromIntegral startIdx)
                dstBid   = BoneId (fromIntegral endIdx)
            mPath <- findBonePathConcurrently skel srcBid dstBid
            case mPath of
              Nothing -> pure (Left ("Worker " ++ show wId ++ ": path not found"))
              Just p  ->
                if length p == 16
                  then pure (Right ())
                  else pure (Left ("Worker " ++ show wId ++ ": unexpected path length " ++ show (length p)))

          -- Worker class 3: Concurrent snapshot view under active writer chattering
          _ -> do
            snap <- snapshotSkeleton skel
            let bCount = length (snapshotBones snap)
                jCount = length (snapshotJoints snap)
            if bCount == boneCount && jCount == boneCount - 1
              then pure (Right ())
              else pure (Left ("Worker " ++ show wId ++ ": snapshot count mismatch"))

        putMVar workerDone res

      -- Release all workers and writers simultaneously
      putMVar startBarrier ()

      -- Wait for writers
      _ <- replicateM numWriters (takeMVar writerDone)

      -- Collect worker results
      workerResults <- replicateM numWorkers (takeMVar workerDone)
      let failures = [ err | Left err <- workerResults ]
      failures `shouldBe` []
