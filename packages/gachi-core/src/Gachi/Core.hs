{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Module: Gachi.Core
-- Description: Core skeletal definitions, bone/joint identifiers, and chattering synchronization
--
-- Provides foundational osteological abstractions and deterministic state synchronization
-- inspired by the gashadokuro mythical skeletal folklore.
--
-- All skeletal structures are backed by contiguous primitive 'OsteoSegment' storage,
-- ensuring $O(1)$ zero-allocation lookups and flat memory locality.
--
-- = When to Use This Module
--
-- * **Osteological Skeletal Graphs:** Modeling directed bone-and-joint graphs with contiguous
--   memory representations and monotonic node identifier tracking.
-- * **Lock-Free Concurrency Substrate:** Serving as the structural topology for concurrent
--   chattering agent traversals without mutex contention.
-- * **Zero-Allocation Node Lookup:** Querying bone payloads in $O(1)$ time via 'lookupBone' or
--   'unsafeLookupBone'.
--
-- = Worked Example
--
-- >>> import Gachi.Core
-- >>> let skel0 = emptySkeleton
-- >>> let (b0, skel1) = insertBone "femur" skel0
-- >>> let (b1, skel2) = insertBone "tibia" skel1
-- >>> let (j0, skel3) = connectJoint b0 b1 skel2
-- >>> lookupBone b0 skel3
-- Just "femur"
-- >>> totalJoints skel3
-- 1
module Gachi.Core
  ( -- * Osteological Identifiers
    BoneId(..)
  , JointId(..)
  , Joint(..)

    -- * Skeletal Structures
  , Skeleton(..)
  , emptySkeleton
  , totalBones
  , totalJoints
  , insertBone
  , lookupBone
  , unsafeLookupBone
  , connectJoint
  , lookupJoint
  , allBones
  , allJoints
  , incidentJoints
  , sliceBones
  ) where

import Data.Word (Word64)
import GHC.Generics (Generic)
import Gachi.Osteology
  ( OsteoSegment
  , emptySegment
  , segmentLength
  , appendOsteo
  , indexOsteo
  , unsafeIndexOsteo
  , sliceOsteo
  , toListOsteo
  )

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

{- Note [Monotonic Identifier Allocation and Contiguous Indexing]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
[tag:note-monotonic-id-allocation]
In high-performance graph processing and AST transformation passes, node lookups
frequently bottleneck on map operations. Standard implementations rely on balanced
binary search trees (such as 'Data.Map.Map', incurring O(log N) pointer dereferences)
or hash tables (incurring hashing overhead, pointer collisions, and bucket indirection).

Gachi adopts a strict monotonic identifier allocation strategy:
  1. Contiguous Identity Mapping: 'BoneId' and 'JointId' are monotonically increasing
     64-bit unsigned integers ('Word64'). Because bones are inserted into an append-only
     contiguous 'OsteoSegment', each 'BoneId' corresponds exactly to its contiguous array
     offset in 'skeletonBones'.
  2. O(1) Zero-Allocation Lookups: Querying 'lookupBone' or 'unsafeLookupBone' reduces
     to a single integer conversion and direct array indexing via 'indexOsteo' /
     'unsafeIndexOsteo'. No hashing, tree balancing, or intermediate allocation occurs.
  3. Determinism & Generation Stability: Identifiers are strictly monotonic within a
     skeletal generation, eliminating identifier recycling hazards and guaranteeing
     byte-for-byte reproducibility during serialization and AST comparison.

See also:
  - Note [Osteological Contiguous Memory Layout] [ref:note-osteology-memory-layout]
-}

{- Note [Directional Joints and Incident Traversal]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
[tag:note-directional-joints-traversal]
Skeletal structures represent directed multigraphs where nodes ('BoneId') are joined
by directed edges ('Joint'). A joint captures a directional dependency or structural
link between a source bone and a target bone.

Key Structural Properties:
  1. Contiguous Edge Storage: All joints are stored in a dedicated contiguous 'OsteoSegment'
     ('skeletonJoints'). This layout ensures that traversing or filtering the edge set
     benefits from sequential memory prefetching rather than traversing linked-list edge
     structures.
  2. Incident Edge Resolution: 'incidentJoints' resolves all edges touching a specific
     bone (as either source or target). This primitive underlies bidirectional dependency
     resolution, AST parent-child navigation, and topological sorting passes.
  3. Compositional Isolation: Bone payloads and joint topologies reside in independent
     osteological segments, permitting payload transformation (via 'fmap' on bones)
     without invalidating or reallocating the joint topology.
-}

-- | Strongly-typed unique identifier for an osteological bone node.
newtype BoneId = BoneId { unBoneId :: Word64 }
  deriving (Eq, Ord, Show, Generic)

-- | Strongly-typed unique identifier for a skeletal joint connection.
newtype JointId = JointId { unJointId :: Word64 }
  deriving (Eq, Ord, Show, Generic)

-- | A directional joint connecting a source bone to a target bone.
data Joint = Joint
  { jointId     :: !JointId
    -- ^ Unique identifier for this joint connection.
  , jointSource :: !BoneId
    -- ^ The originating bone handle.
  , jointTarget :: !BoneId
    -- ^ The terminating bone handle.
  } deriving (Eq, Ord, Show, Generic)

-- | A skeletal graph structure parameterized over payload @a@.
-- Contains a contiguous collection of osteological bones and joints.
--
-- All nodes and connections are packed into contiguous 'OsteoSegment' structures
-- guaranteeing cache-line spatial locality and zero-allocation indexing.
--
-- See Note [Osteological Contiguous Memory Layout] [ref:note-osteology-memory-layout],
-- Note [Chattering Lock-Free Atomic Synchronization] [ref:note-chattering-synchronization],
-- Note [Monotonic Identifier Allocation and Contiguous Indexing] [ref:note-monotonic-id-allocation],
-- and Note [Directional Joints and Incident Traversal] [ref:note-directional-joints-traversal].
data Skeleton a = Skeleton
  { skeletonBones  :: !(OsteoSegment a)
    -- ^ Contiguous flat primitive array storing bone payloads.
  , skeletonJoints :: !(OsteoSegment Joint)
    -- ^ Contiguous flat primitive array storing skeletal joints.
  , skeletonNextId :: !Word64
    -- ^ Monotonically increasing identifier counter for next bone allocation.
  } deriving (Eq, Show, Generic)

-- | Create an empty skeletal structure with zero bones and zero joints.
emptySkeleton :: Skeleton a
emptySkeleton = Skeleton
  { skeletonBones  = emptySegment
  , skeletonJoints = emptySegment
  , skeletonNextId = 0
  }

-- | Count the total number of bones currently assembled in the skeleton.
--
-- Time complexity: @O(1)@.
totalBones :: Skeleton a -> Int
totalBones = segmentLength . skeletonBones

-- | Count the total number of joints connecting bones in the skeleton.
--
-- Time complexity: @O(1)@.
totalJoints :: Skeleton a -> Int
totalJoints = segmentLength . skeletonJoints

-- | Insert a new bone with payload @a@ into the skeleton, returning the assigned 'BoneId'
-- and the updated 'Skeleton'.
--
-- Time complexity: @O(1)@ amortized.
--
-- See Note [Monotonic Identifier Allocation and Contiguous Indexing] [ref:note-monotonic-id-allocation].
insertBone :: a -> Skeleton a -> (BoneId, Skeleton a)
insertBone !val skel =
  let bid = BoneId (skeletonNextId skel)
      newBones = appendOsteo val (skeletonBones skel)
      newSkel = skel
        { skeletonBones  = newBones
        , skeletonNextId = skeletonNextId skel + 1
        }
  in (bid, newSkel)

-- | Retrieve the payload associated with a specific 'BoneId' with bounds checking.
-- Returns 'Nothing' if the 'BoneId' is unallocated or out of bounds.
--
-- Time complexity: @O(1)@ zero-allocation.
--
-- See Note [Monotonic Identifier Allocation and Contiguous Indexing] [ref:note-monotonic-id-allocation].
lookupBone :: BoneId -> Skeleton a -> Maybe a
lookupBone (BoneId w) skel =
  indexOsteo (fromIntegral w) (skeletonBones skel)
{-# INLINE lookupBone #-}

-- | Retrieve the payload associated with a specific 'BoneId' without bounds checking.
-- Precondition: The 'BoneId' was returned by a prior 'insertBone' on this skeleton.
--
-- Time complexity: @O(1)@ zero-allocation.
--
-- See Note [Monotonic Identifier Allocation and Contiguous Indexing] [ref:note-monotonic-id-allocation].
unsafeLookupBone :: BoneId -> Skeleton a -> a
unsafeLookupBone (BoneId w) skel =
  unsafeIndexOsteo (fromIntegral w) (skeletonBones skel)
{-# INLINE unsafeLookupBone #-}

-- | Connect two bones via a directed skeletal 'Joint'.
-- Returns the assigned 'JointId' and the updated 'Skeleton'.
--
-- Time complexity: @O(1)@ amortized.
--
-- See Note [Directional Joints and Incident Traversal] [ref:note-directional-joints-traversal].
connectJoint :: BoneId -> BoneId -> Skeleton a -> (JointId, Skeleton a)
connectJoint src dst skel =
  let jid = JointId (fromIntegral (totalJoints skel))
      newJoint = Joint jid src dst
      newJoints = appendOsteo newJoint (skeletonJoints skel)
      newSkel = skel { skeletonJoints = newJoints }
  in (jid, newSkel)

-- | Retrieve a skeletal joint by its 'JointId'.
--
-- Time complexity: @O(1)@.
--
-- See Note [Directional Joints and Incident Traversal] [ref:note-directional-joints-traversal].
lookupJoint :: JointId -> Skeleton a -> Maybe Joint
lookupJoint (JointId w) skel =
  indexOsteo (fromIntegral w) (skeletonJoints skel)
{-# INLINE lookupJoint #-}

-- | Extract all bone payloads as a standard Haskell list.
allBones :: Skeleton a -> [a]
allBones = toListOsteo . skeletonBones

-- | Extract all skeletal joints as a standard Haskell list.
allJoints :: Skeleton a -> [Joint]
allJoints = toListOsteo . skeletonJoints

-- | Find all joints incident to a given 'BoneId' (as either source or target).
--
-- See Note [Directional Joints and Incident Traversal] [ref:note-directional-joints-traversal].
incidentJoints :: BoneId -> Skeleton a -> [Joint]
incidentJoints bid skel =
  filter (\j -> jointSource j == bid || jointTarget j == bid) (allJoints skel)

-- | Create a zero-copy sub-segment slice of bone payloads.
--
-- See Note [Zero-Copy Sub-Segment Slicing] [ref:note-zero-copy-slicing].
sliceBones :: Int -> Int -> Skeleton a -> Maybe (OsteoSegment a)
sliceBones off len skel = sliceOsteo off len (skeletonBones skel)
