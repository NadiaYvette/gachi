{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Concurrent (forkIO, newEmptyMVar, putMVar, readMVar, takeMVar)
import Control.Monad (forM_, replicateM)
import Data.Text (Text)
import Data.Word (Word64, Word8)
import Test.Hspec

import Gachi.Core
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
