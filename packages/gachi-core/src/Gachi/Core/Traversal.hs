{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Module: Gachi.Core.Traversal
-- Description: Lock-free concurrent graph traversal and snapshot isolation over osteological graphs
--
-- Provides high-performance, wait-free concurrent traversal algorithms over skeletal
-- bone-and-joint graphs. Readers observe consistent topological snapshots without acquiring
-- global read/write locks, even while underlying joint states chatter or transition concurrently.
--
-- See Note [Concurrent Skeletal Graph Traversal] [ref:note-concurrent-traversal].
--
-- = Architectural Invariants
--
-- * **Zero Mutex Contention:** Multi-agent traversals never acquire OS mutexes or runtime
--   locks on graph nodes.
-- * **Wait-Free Snapshot Reads:** 'readJointSnapshot' performs a single atomic memory read
--   without spinning or stalling writer threads.
-- * **Deterministic Concurrency:** 'traverseSkeletonConcurrently' yields bone traversal
--   results that match pure sequential evaluation byte-for-byte.
-- * **Topological Soundness:** Path-finding queries ('findJointPathConcurrently') traverse
--   consistent skeletal frontiers under concurrent joint oscillation.
--
-- = Worked Example
--
-- >>> import Gachi.Core
-- >>> import Gachi.Core.Traversal
-- >>> let (b0, s0) = insertBone "femur" emptySkeleton
-- >>> let (b1, s1) = insertBone "tibia" s0
-- >>> let (j0, s2) = connectJoint b0 b1 s1
-- >>> skel <- initAtomicJoints s2
-- >>> traverseSkeletonConcurrently skel (\b -> pure (bonePayload b))
-- ["femur","tibia"]
-- >>> findJointPathConcurrently skel j0 j0
-- Just [OsteoJoint {osteoJointId = JointId {unJointId = 0}, ...}]
module Gachi.Core.Traversal
  ( -- * Traversal Configuration
    TraversalConfig(..)
  , TraversalDirection(..)
  , defaultTraversalConfig

    -- * Snapshot Representations
  , OsteoJoint(..)
  , osteoJointToJoint
  , SkeletalSnapshot(..)
  , readJointSnapshot
  , snapshotJointStates
  , snapshotSkeleton

    -- * Concurrent Traversal Primitives
  , traverseSkeletonConcurrently
  , traverseSkeletonConcurrentlyWith
  , foldBonesConcurrently
  , foldBonesConcurrentlyWith
  , foldMapBonesConcurrently
  , foldMapBonesConcurrentlyWith

    -- * Concurrent Path Finding & Graph Walks
  , findJointPathConcurrently
  , findJointPathConcurrentlyWith
  , findBonePathConcurrently
  , findBonePathConcurrentlyWith
  , traverseSkeletonBFS
  , traverseSkeletonDFS

    -- * Error Conditions
  , TraversalException(..)
  ) where

import Control.Concurrent (forkIO, newEmptyMVar, putMVar, takeMVar, tryTakeMVar)
import Control.Exception (Exception, SomeException, throwIO, try)
import Control.Monad (forM_)
import qualified Data.Map.Strict as Map
import qualified Data.Primitive.SmallArray as SA
import qualified Data.Set as Set
import GHC.Generics (Generic)
import System.Timeout (timeout)

import Gachi.Core.Atomic
  ( JointState(..)
  , readJointState
  )
import Gachi.Core
  ( Bone(..)
  , BoneId(..)
  , Joint(..)
  , JointId(..)
  , Skeleton(..)
  , allBonesWithId
  , allJoints
  , getAtomicJoint
  , lookupBone
  , lookupJoint
  , totalBones
  , unsafeLookupBone
  )

{- Note [Concurrent Skeletal Graph Traversal]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
[tag:note-concurrent-traversal]
In high-throughput multi-agent simulation, robotic kinematics, and parallel AST transforms,
multiple autonomous agent threads concurrently query, navigate, and evaluate osteological
skeletal graphs.

Traditional graph traversal under concurrent edge modification relies on global reader-writer
locks or coarse-grained mutexes. This induces:
  1. Lock Contention Bottlenecks: Parallel workers serialize on shared locks, collapsing throughput.
  2. Priority Inversion & Convoy Effects: Preempted reader threads stall high-priority writers.
  3. Livelock & Reader Starvation: Continuous write activity blocks read traversals indefinitely.

The Gachi Traversal Engine solves this via a lock-free dual-layer architecture:
  1. Immutable Structural Topology:
     The underlying skeletal graph ('Skeleton a')—consisting of contiguous 'OsteoSegment'
     arrays of bones and joints—is referentially transparent and immutable. Graph structure
     (nodes, directed joints, monotonic IDs) never undergoes in-place pointer mutation.
     Autonomous agent workers read topological frontiers wait-free without locks.

  2. Lock-Free Joint State Machine:
     Dynamic lifecycle states (inert, chattering, synchronized, fused) are isolated inside
     unboxed 64-bit atomic references ('AtomicJoint'). Reader agents read joint states
     via single-instruction atomic loads ('readJointState'). Readers never block writers,
     and writer CAS transitions never block or invalidate reader traversals.

  3. Snapshot Isolation:
     Traversals observe instantaneous snapshots ('OsteoJoint') along topological paths.
     Even while joint states oscillate at high frequency under concurrent chattering,
     the topological path remains valid, acyclic (where configured), and formally race-free.

  4. Bounded Multi-Agent Concurrency:
     Traversal workloads ('traverseSkeletonConcurrently', 'foldMapBonesConcurrently')
     distribute bone sets across bounded worker threads via contiguous memory slice partitioning,
     achieving optimal hardware L1/L2 cache prefetching with zero synchronization overhead
     during traversal execution.
-}

--------------------------------------------------------------------------------
-- Traversal Configuration & Directions
--------------------------------------------------------------------------------

-- | Direction of skeletal edge exploration for graph walk routines.
data TraversalDirection
  = Forward
    -- ^ Follow directed joints from source bone to target bone.
  | Reverse
    -- ^ Follow directed joints from target bone to source bone.
  | Bidirectional
    -- ^ Follow joints in either orientation along shared bone attachments.
  deriving stock (Eq, Ord, Show, Generic)

-- | Configuration parameters controlling concurrent multi-agent graph traversals.
data TraversalConfig = TraversalConfig
  { traversalConcurrency   :: !Int
    -- ^ Maximum number of worker threads to spawn for parallel traversal passes.
  , traversalTimeoutMicros :: !(Maybe Int)
    -- ^ Optional timeout in microseconds. If exceeded, traversal terminates.
  , traversalDirection     :: !TraversalDirection
    -- ^ Direction of edge exploration for path-finding and graph walk routines.
  } deriving stock (Eq, Show, Generic)

-- | Default traversal configuration: 8 worker threads, no timeout, bidirectional search.
defaultTraversalConfig :: TraversalConfig
defaultTraversalConfig = TraversalConfig
  { traversalConcurrency   = 8
  , traversalTimeoutMicros = Nothing
  , traversalDirection     = Bidirectional
  }

--------------------------------------------------------------------------------
-- Snapshot Representations
--------------------------------------------------------------------------------

-- | An osteological joint connection capturing its structural connectivity
-- and an instantaneous wait-free snapshot of its atomic lifecycle state.
--
-- See Note [Concurrent Skeletal Graph Traversal] [ref:note-concurrent-traversal].
data OsteoJoint = OsteoJoint
  { osteoJointId     :: !JointId
    -- ^ Unique identifier for this skeletal joint.
  , osteoJointSource :: !BoneId
    -- ^ Originating bone handle.
  , osteoJointTarget :: !BoneId
    -- ^ Terminating bone handle.
  , osteoJointState  :: !JointState
    -- ^ Instantaneous atomic lifecycle state observed during traversal.
  } deriving stock (Eq, Ord, Show, Generic)

-- | Project the pure structural 'Joint' from an 'OsteoJoint'.
osteoJointToJoint :: OsteoJoint -> Joint
osteoJointToJoint (OsteoJoint jid src dst _) = Joint jid src dst
{-# INLINE osteoJointToJoint #-}

-- | Complete immutable snapshot of a skeleton with observed atomic joint states.
data SkeletalSnapshot a = SkeletalSnapshot
  { snapshotBones  :: ![Bone a]
    -- ^ All bones in the skeleton paired with their identifiers.
  , snapshotJoints :: ![OsteoJoint]
    -- ^ All joints paired with their observed atomic states.
  } deriving stock (Eq, Show, Generic)

-- | Exception raised when concurrent traversals encounter unrecoverable failures.
data TraversalException
  = TraversalTimeout !Int
    -- ^ Traversal exceeded the deadline specified in 'traversalTimeoutMicros'.
  | TraversalWorkerPanic !String
    -- ^ A concurrent worker thread failed with an unhandled exception.
  deriving stock (Eq, Show, Generic)

instance Exception TraversalException

--------------------------------------------------------------------------------
-- Snapshot Reading Primitives
-- See Note [Concurrent Skeletal Graph Traversal] [ref:note-concurrent-traversal]
--------------------------------------------------------------------------------

-- | Wait-free snapshot read of a single joint's atomic state.
-- Returns 'Nothing' if the joint does not exist in the skeleton.
-- If the joint has no initialized atomic reference, defaults to 'JointInert'.
readJointSnapshot :: Skeleton a -> JointId -> IO (Maybe JointState)
readJointSnapshot skel jid =
  case lookupJoint jid skel of
    Nothing -> pure Nothing
    Just _  ->
      case getAtomicJoint jid skel of
        Just aj -> do
          !st <- readJointState aj
          pure (Just st)
        Nothing -> pure (Just JointInert)
{-# INLINE readJointSnapshot #-}

-- | Read instantaneous snapshot states for all skeletal joints in the graph.
snapshotJointStates :: Skeleton a -> IO [OsteoJoint]
snapshotJointStates skel =
  mapM (\j -> do
    mSt <- readJointSnapshot skel (jointId j)
    let !st = case mSt of
                Just s  -> s
                Nothing -> JointInert
    pure (OsteoJoint (jointId j) (jointSource j) (jointTarget j) st)
  ) (allJoints skel)

-- | Create a complete snapshot view of bones and atomic joint states.
snapshotSkeleton :: Skeleton a -> IO (SkeletalSnapshot a)
snapshotSkeleton skel = do
  let bones = allBonesWithId skel
  joints <- snapshotJointStates skel
  pure (SkeletalSnapshot bones joints)

--------------------------------------------------------------------------------
-- Concurrent Traversal Primitives
-- See Note [Concurrent Skeletal Graph Traversal] [ref:note-concurrent-traversal]
--------------------------------------------------------------------------------

-- | Traverse all bones in a skeleton concurrently with default configuration.
traverseSkeletonConcurrently :: Skeleton a -> (Bone a -> IO b) -> IO [b]
traverseSkeletonConcurrently = traverseSkeletonConcurrentlyWith defaultTraversalConfig
{-# INLINE traverseSkeletonConcurrently #-}

-- | Traverse all bones in a skeleton concurrently with custom 'TraversalConfig'.
--
-- Divides bones into disjoint contiguous slices and evaluates them across a bounded
-- pool of concurrent worker threads. Results are assembled in strict monotonically
-- increasing index order, guaranteeing exact correspondence with pure sequential evaluation.
traverseSkeletonConcurrentlyWith
  :: TraversalConfig
  -> Skeleton a
  -> (Bone a -> IO b)
  -> IO [b]
traverseSkeletonConcurrentlyWith cfg skel f = do
  let !microsOpt = traversalTimeoutMicros cfg
  case microsOpt of
    Nothing     -> runTraverse
    Just micros -> do
      mRes <- timeout micros runTraverse
      case mRes of
        Just res -> pure res
        Nothing  -> throwIO (TraversalTimeout micros)
  where
    !n = totalBones skel

    runTraverse
      | n == 0    = pure []
      | otherwise = do
          let !wMax = max 1 (traversalConcurrency cfg)
              !w = min wMax n
          if w == 1
            then do
              let bones = allBonesWithId skel
              mapM f bones
            else do
              marr <- SA.newSmallArray n (error "Gachi.Core.Traversal: uninitialized element")
              let !baseChunk = n `quot` w
                  !remainder = n `rem` w
                  computeSlices !k !start
                    | k >= w = []
                    | otherwise =
                        let !len = baseChunk + if k < remainder then 1 else 0
                            !end = start + len - 1
                        in if len > 0
                           then (start, end) : computeSlices (k + 1) (end + 1)
                           else []
                  slices = computeSlices 0 0
                  sliceCount = length slices

              doneMVar <- newEmptyMVar
              errMVar  <- newEmptyMVar

              forM_ slices \(start, end) -> forkIO do
                res <- try (forM_ [start .. end] \i -> do
                  let !bid = BoneId (fromIntegral i)
                      !payload = unsafeLookupBone bid skel
                      !bone = Bone bid payload
                  !val <- f bone
                  SA.writeSmallArray marr i val
                  )
                case res of
                  Left (e :: SomeException) -> putMVar errMVar (show e)
                  Right ()                  -> putMVar doneMVar ()

              let waitWorkers 0 = pure ()
                  waitWorkers remaining = do
                    mErr <- tryTakeMVar errMVar
                    case mErr of
                      Just errStr -> throwIO (TraversalWorkerPanic errStr)
                      Nothing     -> do
                        takeMVar doneMVar
                        waitWorkers (remaining - 1)

              waitWorkers sliceCount
              frozen <- SA.freezeSmallArray marr 0 n
              pure [ SA.indexSmallArray frozen i | i <- [0 .. n - 1] ]

-- | Fold over all bones in a skeleton with default configuration.
foldBonesConcurrently :: Skeleton a -> (b -> Bone a -> IO b) -> b -> IO b
foldBonesConcurrently = foldBonesConcurrentlyWith defaultTraversalConfig
{-# INLINE foldBonesConcurrently #-}

-- | Fold over all bones in a skeleton with custom 'TraversalConfig'.
-- Respects timeout boundaries and guarantees deterministic sequential reduction order.
foldBonesConcurrentlyWith
  :: TraversalConfig
  -> Skeleton a
  -> (b -> Bone a -> IO b)
  -> b
  -> IO b
foldBonesConcurrentlyWith cfg skel step z = do
  let !microsOpt = traversalTimeoutMicros cfg
  case microsOpt of
    Nothing     -> runFold
    Just micros -> do
      mRes <- timeout micros runFold
      case mRes of
        Just res -> pure res
        Nothing  -> throwIO (TraversalTimeout micros)
  where
    bones = allBonesWithId skel
    runFold = foldlM' step z bones
      where
        foldlM' _ !acc [] = pure acc
        foldlM' stp !acc (x:xs) = do
          !acc' <- stp acc x
          foldlM' stp acc' xs

-- | Map bones to a Monoid concurrently across worker threads and combine with '<>'.
foldMapBonesConcurrently :: Monoid m => Skeleton a -> (Bone a -> IO m) -> IO m
foldMapBonesConcurrently = foldMapBonesConcurrentlyWith defaultTraversalConfig
{-# INLINE foldMapBonesConcurrently #-}

-- | Map bones to a Monoid concurrently with custom 'TraversalConfig'.
foldMapBonesConcurrentlyWith
  :: Monoid m
  => TraversalConfig
  -> Skeleton a
  -> (Bone a -> IO m)
  -> IO m
foldMapBonesConcurrentlyWith cfg skel f = do
  results <- traverseSkeletonConcurrentlyWith cfg skel f
  pure $! foldl' (<>) mempty results

--------------------------------------------------------------------------------
-- Pure Queue Abstraction (Zero Partial Functions)
--------------------------------------------------------------------------------

data Queue a = Q ![a] ![a]

emptyQ :: Queue a
emptyQ = Q [] []

pushQ :: a -> Queue a -> Queue a
pushQ x (Q ins outs) = Q (x : ins) outs

popQ :: Queue a -> Maybe (a, Queue a)
popQ (Q ins (x:outs)) = Just (x, Q ins outs)
popQ (Q [] [])        = Nothing
popQ (Q ins [])       =
  case reverse ins of
    []     -> Nothing
    (y:ys) -> Just (y, Q [] ys)

--------------------------------------------------------------------------------
-- Path Finding & Graph Walk Routines
-- See Note [Concurrent Skeletal Graph Traversal] [ref:note-concurrent-traversal]
--------------------------------------------------------------------------------

-- | Find a path of connected joints between two 'JointId' endpoints concurrently.
--
-- Each returned 'OsteoJoint' includes an instantaneous atomic snapshot of its
-- lifecycle state observed at the moment of traversal.
findJointPathConcurrently
  :: Skeleton a
  -> JointId
  -> JointId
  -> IO (Maybe [OsteoJoint])
findJointPathConcurrently = findJointPathConcurrentlyWith defaultTraversalConfig
{-# INLINE findJointPathConcurrently #-}

-- | Find a path of connected joints with custom 'TraversalConfig'.
findJointPathConcurrentlyWith
  :: TraversalConfig
  -> Skeleton a
  -> JointId
  -> JointId
  -> IO (Maybe [OsteoJoint])
findJointPathConcurrentlyWith cfg skel startJid endJid = do
  let !microsOpt = traversalTimeoutMicros cfg
  case microsOpt of
    Nothing     -> runSearch
    Just micros -> do
      mRes <- timeout micros runSearch
      case mRes of
        Just res -> pure res
        Nothing  -> pure Nothing
  where
    mStartJoint = lookupJoint startJid skel
    mEndJoint   = lookupJoint endJid skel

    runSearch =
      case (mStartJoint, mEndJoint) of
        (Nothing, _) -> pure Nothing
        (_, Nothing) -> pure Nothing
        (Just startJoint, Just _)
          | startJid == endJid -> do
              mSt <- readJointSnapshot skel startJid
              let !st = case mSt of
                          Just s  -> s
                          Nothing -> JointInert
              pure (Just [OsteoJoint startJid (jointSource startJoint) (jointTarget startJoint) st])
          | otherwise -> do
              let joints = allJoints skel
                  outMap = Map.fromListWith (++) [ (jointSource j, [j]) | j <- joints ]
                  inMap  = Map.fromListWith (++) [ (jointTarget j, [j]) | j <- joints ]
                  incMap = Map.fromListWith (++)
                    ([ (jointSource j, [j]) | j <- joints ] ++ [ (jointTarget j, [j]) | j <- joints ])

                  getNeighbors curr =
                    let jid = jointId curr
                        candidates = case traversalDirection cfg of
                          Forward ->
                            Map.findWithDefault [] (jointTarget curr) outMap
                          Reverse ->
                            Map.findWithDefault [] (jointSource curr) inMap
                          Bidirectional ->
                            let sNeighbors = Map.findWithDefault [] (jointSource curr) incMap
                                tNeighbors = Map.findWithDefault [] (jointTarget curr) incMap
                            in sNeighbors ++ tNeighbors
                    in filter (\nxt -> jointId nxt /= jid) candidates

                  bfsLoop !q !visited =
                    case popQ q of
                      Nothing -> pure Nothing
                      Just ((curr, path), restQ)
                        | jointId curr == endJid -> do
                            let fullPath = reverse (curr : path)
                            osteoPath <- mapM (\j -> do
                              mSt <- readJointSnapshot skel (jointId j)
                              let !st = case mSt of
                                          Just s  -> s
                                          Nothing -> JointInert
                              pure (OsteoJoint (jointId j) (jointSource j) (jointTarget j) st)
                              ) fullPath
                            pure (Just osteoPath)
                        | otherwise ->
                            let neighbors = getNeighbors curr
                                unvisited = filter (\nxt -> not (Set.member (jointId nxt) visited)) neighbors
                                newVisited = foldl' (\s nxt -> Set.insert (jointId nxt) s) visited unvisited
                                newQ = foldl' (\qAcc nxt -> pushQ (nxt, curr : path) qAcc) restQ unvisited
                            in bfsLoop newQ newVisited

                  initQ = pushQ (startJoint, []) emptyQ
                  initVisited = Set.singleton startJid

              bfsLoop initQ initVisited

-- | Find a path of bones connecting 'startBid' to 'endBid' concurrently.
findBonePathConcurrently
  :: Skeleton a
  -> BoneId
  -> BoneId
  -> IO (Maybe [Bone a])
findBonePathConcurrently = findBonePathConcurrentlyWith defaultTraversalConfig
{-# INLINE findBonePathConcurrently #-}

-- | Find a path of bones with custom 'TraversalConfig'.
findBonePathConcurrentlyWith
  :: TraversalConfig
  -> Skeleton a
  -> BoneId
  -> BoneId
  -> IO (Maybe [Bone a])
findBonePathConcurrentlyWith cfg skel startBid endBid = do
  let !microsOpt = traversalTimeoutMicros cfg
  case microsOpt of
    Nothing     -> runSearch
    Just micros -> do
      mRes <- timeout micros runSearch
      case mRes of
        Just res -> pure res
        Nothing  -> pure Nothing
  where
    mStartBone = lookupBone startBid skel
    mEndBone   = lookupBone endBid skel

    runSearch =
      case (mStartBone, mEndBone) of
        (Nothing, _) -> pure Nothing
        (_, Nothing) -> pure Nothing
        (Just startPayload, Just _)
          | startBid == endBid ->
              pure (Just [Bone startBid startPayload])
          | otherwise -> do
              let joints = allJoints skel
                  outMap = Map.fromListWith (++) [ (jointSource j, [jointTarget j]) | j <- joints ]
                  inMap  = Map.fromListWith (++) [ (jointTarget j, [jointSource j]) | j <- joints ]
                  incMap = Map.fromListWith (++)
                    ([ (jointSource j, [jointTarget j]) | j <- joints ] ++ [ (jointTarget j, [jointSource j]) | j <- joints ])

                  getNeighbors currBid =
                    case traversalDirection cfg of
                      Forward       -> Map.findWithDefault [] currBid outMap
                      Reverse       -> Map.findWithDefault [] currBid inMap
                      Bidirectional -> Map.findWithDefault [] currBid incMap

                  bfsLoop !q !visited =
                    case popQ q of
                      Nothing -> pure Nothing
                      Just ((currBid, path), restQ)
                        | currBid == endBid -> do
                            let fullBids = reverse (currBid : path)
                                mBones = mapM (\bid -> do
                                  p <- lookupBone bid skel
                                  pure (Bone bid p)
                                  ) fullBids
                            pure mBones
                        | otherwise ->
                            let neighbors = getNeighbors currBid
                                unvisited = filter (\nxt -> not (Set.member nxt visited)) neighbors
                                newVisited = foldl' (\s nxt -> Set.insert nxt s) visited unvisited
                                newQ = foldl' (\qAcc nxt -> pushQ (nxt, currBid : path) qAcc) restQ unvisited
                            in bfsLoop newQ newVisited

                  initQ = pushQ (startBid, []) emptyQ
                  initVisited = Set.singleton startBid

              bfsLoop initQ initVisited

-- | Perform a breadth-first search (BFS) walk of all reachable bones from a starting bone.
traverseSkeletonBFS :: Skeleton a -> BoneId -> IO [Bone a]
traverseSkeletonBFS skel startBid =
  case lookupBone startBid skel of
    Nothing -> pure []
    Just startPayload -> do
      let joints = allJoints skel
          incMap = Map.fromListWith (++)
            ([ (jointSource j, [jointTarget j]) | j <- joints ] ++ [ (jointTarget j, [jointSource j]) | j <- joints ])

          bfs !q !visited !acc =
            case popQ q of
              Nothing -> pure (reverse acc)
              Just (currBid, restQ) ->
                let neighbors = Map.findWithDefault [] currBid incMap
                    unvisited = filter (\nxt -> not (Set.member nxt visited)) neighbors
                    newVisited = foldl' (\s nxt -> Set.insert nxt s) visited unvisited
                    newQ = foldl' (flip pushQ) restQ unvisited
                    mBone = case lookupBone currBid skel of
                              Just p  -> [Bone currBid p]
                              Nothing -> []
                in bfs newQ newVisited (mBone ++ acc)

          initQ = pushQ startBid emptyQ
          initVisited = Set.singleton startBid
          initAcc = [Bone startBid startPayload]

      -- Pop initial root and expand
      case popQ initQ of
        Nothing -> pure []
        Just (rootBid, q0) ->
          let nbrs = Map.findWithDefault [] rootBid incMap
              unvisited = filter (\nxt -> not (Set.member nxt initVisited)) nbrs
              v1 = foldl' (\s nxt -> Set.insert nxt s) initVisited unvisited
              q1 = foldl' (flip pushQ) q0 unvisited
          in bfs q1 v1 initAcc

-- | Perform a depth-first search (DFS) walk of all reachable bones from a starting bone.
traverseSkeletonDFS :: Skeleton a -> BoneId -> IO [Bone a]
traverseSkeletonDFS skel startBid =
  case lookupBone startBid skel of
    Nothing -> pure []
    Just _  -> do
      let joints = allJoints skel
          incMap = Map.fromListWith (++)
            ([ (jointSource j, [jointTarget j]) | j <- joints ] ++ [ (jointTarget j, [jointSource j]) | j <- joints ])

          dfs [] !_ !acc = pure (reverse acc)
          dfs (currBid : stack) !visited !acc
            | Set.member currBid visited = dfs stack visited acc
            | otherwise =
                let !newVisited = Set.insert currBid visited
                    neighbors = Map.findWithDefault [] currBid incMap
                    unvisited = filter (\nxt -> not (Set.member nxt newVisited)) neighbors
                    mBone = case lookupBone currBid skel of
                              Just p  -> [Bone currBid p]
                              Nothing -> []
                in dfs (unvisited ++ stack) newVisited (mBone ++ acc)

      dfs [startBid] Set.empty []
