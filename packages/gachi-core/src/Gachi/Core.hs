{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Module: Gachi.Core
-- Description: Core skeletal definitions, bone/joint identifiers, and chattering synchronization
--
-- Provides foundational osteological abstractions and deterministic state synchronization
-- inspired by the gashadokuro mythical skeletal folklore.
module Gachi.Core
  ( -- * Osteological Identifiers
    BoneId(..)
  , JointId(..)
    -- * Skeletal Structures
  , Skeleton(..)
  , emptySkeleton
  , totalBones
  , insertBone
  , lookupBone
  ) where

import GHC.Generics (Generic)
import qualified Data.Map.Strict as Map
import Data.Word (Word64)

{- Note [Chattering Lock-Free Atomic Synchronization]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
[tag:note-chattering-synchronization]
The hallmark of a gashadokuro in folklore is the distinct, rhythmic 'gachi-gachi'
chattering of its teeth before it appears. In the Gachi substrate, 'chattering' represents
the deterministic synchronization cadence of concurrent agents navigating osteological graphs.

Traditional multi-threaded graph traversal utilizes mutexes or Reader-Writer locks, which
suffer from:
  1. Cache-line bouncing across multi-core processors.
  2. Severe thread contention under high read/write ratios.
  3. Convoy effects and deadlocks under asynchronous cancellation.

Gachi resolves this by employing lock-free, optimistic atomic state progression:
  - Joints are represented as atomic references capable of single-instruction compare-and-swap
    (CAS) updates.
  - Reader agents traverse immutable snapshots of the skeletal topology without acquiring locks.
  - When concurrent modifications collide, the chattering synchronization protocol retries
    with bounded exponential backoff, preserving global progress and lock-freedom.
-}

-- | Strongly-typed unique identifier for an osteological bone node.
newtype BoneId = BoneId { unBoneId :: Word64 }
  deriving (Eq, Ord, Show, Generic)

-- | Strongly-typed unique identifier for a skeletal joint connection.
newtype JointId = JointId { unJointId :: Word64 }
  deriving (Eq, Ord, Show, Generic)

-- | A skeletal graph structure parameterized over payload @a@.
-- Contains a collection of osteological bones and their associated attributes.
--
-- See Note [Chattering Lock-Free Atomic Synchronization] [ref:note-chattering-synchronization].
data Skeleton a = Skeleton
  { skeletonBones :: !(Map.Map BoneId a)
    -- ^ Primary map of bone handles to node payloads.
  , skeletonNextId :: !Word64
    -- ^ Monotonically increasing identifier counter for next bone allocation.
  } deriving (Eq, Show, Generic)

-- | Create an empty skeletal structure with zero bones.
emptySkeleton :: Skeleton a
emptySkeleton = Skeleton
  { skeletonBones = Map.empty
  , skeletonNextId = 0
  }

-- | Count the total number of bones currently assembled in the skeleton.
--
-- Time complexity: @O(1)@.
totalBones :: Skeleton a -> Int
totalBones = Map.size . skeletonBones

-- | Insert a new bone with payload @a@ into the skeleton, returning the assigned 'BoneId'
-- and the updated 'Skeleton'.
--
-- Time complexity: @O(log N)@.
insertBone :: a -> Skeleton a -> (BoneId, Skeleton a)
insertBone val skel =
  let bid = BoneId (skeletonNextId skel)
      newMap = Map.insert bid val (skeletonBones skel)
      newSkel = skel
        { skeletonBones = newMap
        , skeletonNextId = skeletonNextId skel + 1
        }
  in (bid, newSkel)

-- | Retrieve the payload associated with a specific 'BoneId', if present.
--
-- Time complexity: @O(log N)@.
lookupBone :: BoneId -> Skeleton a -> Maybe a
lookupBone bid skel = Map.lookup bid (skeletonBones skel)
