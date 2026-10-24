{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Test.Hspec
import Data.Text (Text)
import Data.Word (Word8)

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
      foldr (+) 0 seg `shouldBe` 15
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
