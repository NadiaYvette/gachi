{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Test.Hspec
import Data.Text (Text)

import Gachi.Core
import Gachi.Osteology

main :: IO ()
main = hspec do
  -- Tested against Note [Chattering Lock-Free Atomic Synchronization] [ref:note-chattering-synchronization]
  describe "Gachi.Core Skeletal Primitives" do
    it "constructs empty skeletal structure with zero bones" do
      let skel = emptySkeleton :: Skeleton Text
      totalBones skel `shouldBe` 0
      lookupBone (BoneId 0) skel `shouldBe` Nothing

    it "inserts and retrieves bones with monotonically assigned identifiers" do
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
      lookupBone (BoneId 99) skel3 `shouldBe` Nothing

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
      indexOsteo 5 seg5 `shouldBe` Nothing
      indexOsteo (-1) seg5 `shouldBe` Nothing
