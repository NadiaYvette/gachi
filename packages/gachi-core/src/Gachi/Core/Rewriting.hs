{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Module: Gachi.Core.Rewriting
-- Description: Double-Pushout (DPO) category-theoretic graph rewriting over osteological skeletal graphs
--
-- Provides a declarative, provably sound Double-Pushout (DPO) algebraic graph rewriting engine
-- operating over contiguous osteological skeletal graphs ('Skeleton a'). Implements monomorphic
-- subgraph matching, adhesive category gluing condition verification (dangling and identification
-- conditions), pushout complement derivation (deletion), and pushout construction (addition).
--
-- See Note [Double-Pushout Algebraic Graph Rewriting] [ref:note-dpo-graph-rewriting].
--
-- = Architectural Invariants
--
-- * **Adhesive Category Correctness:** Every production rule application strictly verifies
--   the gluing condition before mutating the graph topology.
-- * **Contiguous Memory Preservation:** Derived context and pushout skeletons preserve
--   contiguous bone indexing and zero-allocation \(O(1)\) lookup performance.
-- * **Monotonic Identifier Allocation:** Newly synthesized bones and joints receive monotonically
--   increasing handles without identifier recycling hazards.
-- * **Referential Transparency:** Graph transformations are purely functional; snapshots
--   and original skeletons remain completely immutable.
module Gachi.Core.Rewriting
  ( -- * Double-Pushout Data Types
    ProductionRule(..)
  , GraphMatch(..)
  , RewritingError(..)

    -- * Rule Construction & Validation
  , emptyMatch
  , validateRule
  , validateGluingCondition

    -- * Algebraic DPO Rewriting Engine
  , findMatches
  , derivePushoutComplement
  , constructPushout
  , applyRule
  , applyRuleFirstMatch
  ) where

import Control.Monad (foldM, forM, forM_, unless, when)
import Data.List (partition)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Text (Text, pack)
import GHC.Generics (Generic)

import Gachi.Core
  ( Bone(..)
  , BoneId(..)
  , Joint(..)
  , JointId(..)
  , Skeleton(..)
  , allBonesWithId
  , allJoints
  , connectJoint
  , emptySkeleton
  , insertBone
  , lookupBone
  , lookupJoint
  )

{- Note [Double-Pushout Algebraic Graph Rewriting]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
[tag:note-dpo-graph-rewriting]
Category-theoretic graph transformation provides declarative, provably sound topological
mutations over osteological skeletal graphs. In the Double-Pushout (DPO) algebraic approach,
a transformation rule is formalized as a span of monomorphisms in an adhesive category:

                        l          r
                 L <--------- K ---------> R
                 |            |            |
               m |            |            |
                 v     (1)    v     (2)    v
                 G <--------- D ---------> H

where:
  - 'L' is the left-hand pattern graph to match within host graph 'G'.
  - 'K' is the interface / gluing graph capturing the topological boundary preserved
    across the transformation.
  - 'R' is the right-hand replacement graph substituting 'L \ K' in derived graph 'H'.
  - 'l : K -> L' and 'r : K -> R' are monic graph embeddings.
  - 'm : L -> G' is a graph match identifying a candidate redex.

The transformation proceeds in two categorical pushout steps:
  1. First Pushout Complement (Deletion):
     Square (1) is a pushout complement, deriving the context graph 'D' by excising the
     deleted items: 'D = G \ m(L \ K)'.
     By the gluing condition in adhesive categories, this complement exists and is unique
     up to isomorphism if and only if two conditions hold:
       a. Dangling Condition: No edge in 'G \ m(L)' is incident to any vertex in 'm(L \ K)'.
          Deleting a vertex must never leave external host edges dangling without endpoints.
       b. Identification Condition: If 'm' identifies two distinct elements in 'L' (i.e.
          'm(x) = m(y)' with 'x /= y'), both elements must reside in 'l(K)'. Items scheduled
          for deletion cannot be conflated with preserved items or other deleted items.

  2. Second Pushout (Addition):
     Square (2) is a categorical pushout gluing replacement 'R' to context 'D' along interface 'K':
     'H = D \amalg_K R'. Preserved interface vertices and edges are identified, while newly
     synthesized vertices in 'R \ r(K)' and edges are adjoined.

Osteological Memory Layout Invariants:
In the Gachi osteological substrate, skeletons are represented as contiguous unboxed
primitive segments ('OsteoSegment a' for bones, 'OsteoSegment Joint' for edges).
Arbitrary node deletion in standard pointer-graph implementations creates heap fragmentation
and invalidates contiguous array indexing.

The Gachi DPO engine enforces strict contiguous memory compaction during rewriting:
  1. Monotonic Index Compaction:
     When constructing pushout complement 'D', retained bones from 'G' are compacted into
     a contiguous range [0 .. |V_D| - 1] via monotonic index compression:
     'newId(v) = oldId(v) - count(deleted vertices < oldId(v))'.
  2. Sequential ID Allocation:
     Newly added bones from 'R \ r(K)' are appended sequentially to 'D', receiving monotonic
     identifiers [|V_D| .. |V_D| + |V_new| - 1], preserving contiguous indexing and O(1)
     zero-allocation 'lookupBone' / 'unsafeLookupBone' access.
  3. Topological Soundness:
     Incident joint endpoints are remapped consistently to the new contiguous bone indices,
     guaranteeing that derived graph 'H' satisfies all invariants of 'Gachi.Core.Skeleton'.

Integration with Gargamelle:
DPO productions integrate directly into 'gargamelle' term and graph rewriting pipelines,
enabling declarative osteological transformations such as node fission, node fusion,
chain simplification, and bridge synthesis while maintaining categorical correctness.

See also:
  - Note [Directional Joints and Incident Traversal] [ref:note-directional-joints-traversal]
  - Note [Monotonic Identifier Allocation and Contiguous Indexing] [ref:note-monotonic-id-allocation]
  - Note [Osteological Contiguous Memory Layout] [ref:note-osteology-memory-layout]
-}

--------------------------------------------------------------------------------
-- Double-Pushout Data Types
--------------------------------------------------------------------------------

-- | A Double-Pushout (DPO) production rule @p = (L <--l-- K --r--> R)@.
--
-- A rule specifies a left pattern @L@ to match in host graph @G@, an interface @K@
-- representing preserved topological structure, and a right replacement @R@
-- to glue along @K@. The morphisms @morphismL@ and @morphismR@ map interface joints
-- and bones into @L@ and @R@ respectively.
data ProductionRule a = ProductionRule
  { ruleName      :: !Text
    -- ^ Human-readable descriptive name for this production rule.
  , ruleLeft      :: !(Skeleton a)
    -- ^ Left-hand pattern graph @L@ to search and match within the host skeleton.
  , ruleInterface :: !(Skeleton a)
    -- ^ Gluing interface @K@ preserved across deletion and pushout addition.
  , ruleRight     :: !(Skeleton a)
    -- ^ Right-hand replacement graph @R@ substituting @L \setminus K@ in result @H@.
  , morphismL     :: !(Map JointId JointId, Map BoneId BoneId)
    -- ^ Monic embedding @l : K -> L@ (mapping joints and bones of @K@ into @L@).
  , morphismR     :: !(Map JointId JointId, Map BoneId BoneId)
    -- ^ Monic embedding @r : K -> R@ (mapping joints and bones of @K@ into @R@).
  } deriving stock (Eq, Show, Generic)

-- | A match morphism @m : L -> G@ embedding pattern graph @L@ into host skeleton @G@.
data GraphMatch = GraphMatch
  { matchJoints :: !(Map JointId JointId)
    -- ^ Mapping from joint identifiers in @L@ to joint identifiers in host @G@.
  , matchBones  :: !(Map BoneId BoneId)
    -- ^ Mapping from bone identifiers in @L@ to bone identifiers in host @G@.
  } deriving stock (Eq, Ord, Show, Generic)

-- | Categorical and topological errors encountered during DPO rewriting passes.
data RewritingError
  = MatchNotFound !Text
    -- ^ Subgraph pattern matching failed to find a valid embedding.
  | DanglingConditionViolated !Text
    -- ^ Gluing condition failure: external edges in @G \setminus m(L)@ are incident to
    --   vertices scheduled for deletion in @m(L \setminus K)@.
  | IdentificationConditionViolated !Text
    -- ^ Gluing condition failure: match identifies distinct items in @L@ that are not
    --   both members of interface @l(K)@.
  | PushoutComplementFailed !Text
    -- ^ Pushout complement derivation failed due to structural inconsistency.
  | InvalidRuleMorphism !Text
    -- ^ Monic embedding @l : K -> L@ or @r : K -> R@ violates graph homomorphism constraints.
  deriving stock (Eq, Ord, Show, Generic)

-- | Construct an empty 'GraphMatch' with no mapped bones or joints.
emptyMatch :: GraphMatch
emptyMatch = GraphMatch
  { matchJoints = Map.empty
  , matchBones  = Map.empty
  }

--------------------------------------------------------------------------------
-- Rule Validation
--------------------------------------------------------------------------------

-- | Validate structural integrity of production rule embeddings @l : K -> L@ and @r : K -> R@.
-- Verifies that embeddings are total on @K@, preserve joint connectivity, and are monomorphic (injective).
validateRule :: ProductionRule a -> Either RewritingError ()
validateRule rule = do
  validateEmbedding "morphismL" (ruleInterface rule) (ruleLeft rule) (morphismL rule)
  validateEmbedding "morphismR" (ruleInterface rule) (ruleRight rule) (morphismR rule)
  where
    validateEmbedding name k target (jMap, bMap) = do
      let kBones = allBonesWithId k
          kJoints = allJoints k

      -- Check all bones of K are mapped to valid target bones
      forM_ kBones $ \b -> do
        case Map.lookup (boneId b) bMap of
          Nothing ->
            Left (InvalidRuleMorphism (name <> ": interface bone " <> showT (unBoneId (boneId b)) <> " not mapped"))
          Just tBid ->
            case lookupBone tBid target of
              Nothing ->
                Left (InvalidRuleMorphism (name <> ": interface bone mapped to non-existent bone " <> showT (unBoneId tBid)))
              Just _ -> Right ()

      -- Check all joints of K are mapped to valid target joints and preserve incidence
      forM_ kJoints $ \j -> do
        case Map.lookup (jointId j) jMap of
          Nothing ->
            Left (InvalidRuleMorphism (name <> ": interface joint " <> showT (unJointId (jointId j)) <> " not mapped"))
          Just tJid ->
            case lookupJoint tJid target of
              Nothing ->
                Left (InvalidRuleMorphism (name <> ": interface joint mapped to non-existent joint " <> showT (unJointId tJid)))
              Just tJoint -> do
                let expectedSrc = Map.lookup (jointSource j) bMap
                    expectedDst = Map.lookup (jointTarget j) bMap
                if Just (jointSource tJoint) == expectedSrc && Just (jointTarget tJoint) == expectedDst
                  then Right ()
                  else Left (InvalidRuleMorphism (name <> ": joint morphism does not preserve connectivity"))

      -- Check monomorphism (injectivity)
      let bVals = Map.elems bMap
          jVals = Map.elems jMap
      unless (Map.size bMap == Set.size (Set.fromList bVals)) $
        Left (InvalidRuleMorphism (name <> ": bone embedding is not injective"))
      unless (Map.size jMap == Set.size (Set.fromList jVals)) $
        Left (InvalidRuleMorphism (name <> ": joint embedding is not injective"))

--------------------------------------------------------------------------------
-- Gluing Condition Verification
--------------------------------------------------------------------------------

-- | Validate the adhesive category gluing conditions for match @m : L -> G@.
--
-- The gluing condition guarantees that the first pushout complement (deletion)
-- exists and produces a sound context graph:
--
-- 1. __Dangling Condition:__ No joint in @G \setminus m(L)@ is incident to a bone in @m(L \setminus K)@.
-- 2. __Identification Condition:__ For distinct items @x /= y@ in @L@, @m(x) == m(y)@ only if
--    both @x@ and @y@ are in @l(K)@.
validateGluingCondition :: ProductionRule a -> GraphMatch -> Skeleton a -> Either RewritingError ()
validateGluingCondition rule match host = do
  validateRule rule

  let lBones = allBonesWithId (ruleLeft rule)
      lJoints = allJoints (ruleLeft rule)
      bMatch = matchBones match
      jMatch = matchJoints match

  -- Check all bones in L are mapped to existing host bones
  forM_ lBones $ \b -> do
    case Map.lookup (boneId b) bMatch of
      Nothing ->
        Left (MatchNotFound ("Bone " <> showT (unBoneId (boneId b)) <> " of L not mapped in host match"))
      Just gBid ->
        case lookupBone gBid host of
          Nothing ->
            Left (MatchNotFound ("Bone " <> showT (unBoneId gBid) <> " out of bounds in host graph"))
          Just _ -> Right ()

  -- Check all joints in L are mapped to existing host joints and preserve connectivity
  forM_ lJoints $ \j -> do
    case Map.lookup (jointId j) jMatch of
      Nothing ->
        Left (MatchNotFound ("Joint " <> showT (unJointId (jointId j)) <> " of L not mapped in host match"))
      Just gJid ->
        case lookupJoint gJid host of
          Nothing ->
            Left (MatchNotFound ("Joint " <> showT (unJointId gJid) <> " out of bounds in host graph"))
          Just gJoint -> do
            let expectedSrc = Map.lookup (jointSource j) bMatch
                expectedDst = Map.lookup (jointTarget j) bMatch
            if Just (jointSource gJoint) == expectedSrc && Just (jointTarget gJoint) == expectedDst
              then Right ()
              else Left (InvalidRuleMorphism "Match joint does not preserve source/target bone connectivity")

  -- 1. Identification Condition Verification
  let (l_joints, l_bones) = morphismL rule
      kBoneImg = Set.fromList (Map.elems l_bones)
      kJointImg = Set.fromList (Map.elems l_joints)

  -- Identification on bones
  forM_ lBones $ \b1 -> do
    forM_ lBones $ \b2 -> do
      when (boneId b1 < boneId b2) $ do
        case (Map.lookup (boneId b1) bMatch, Map.lookup (boneId b2) bMatch) of
          (Just g1, Just g2) | g1 == g2 ->
            unless (Set.member (boneId b1) kBoneImg && Set.member (boneId b2) kBoneImg) $
              Left (IdentificationConditionViolated
                ("Match identifies distinct bones " <> showT (unBoneId (boneId b1)) <> " and " <>
                 showT (unBoneId (boneId b2)) <> " outside interface K"))
          _ -> Right ()

  -- Identification on joints
  forM_ lJoints $ \j1 -> do
    forM_ lJoints $ \j2 -> do
      when (jointId j1 < jointId j2) $ do
        case (Map.lookup (jointId j1) jMatch, Map.lookup (jointId j2) jMatch) of
          (Just g1, Just g2) | g1 == g2 ->
            unless (Set.member (jointId j1) kJointImg && Set.member (jointId j2) kJointImg) $
              Left (IdentificationConditionViolated
                ("Match identifies distinct joints " <> showT (unJointId (jointId j1)) <> " and " <>
                 showT (unJointId (jointId j2)) <> " outside interface K"))
          _ -> Right ()

  -- 2. Dangling Condition Verification
  let delBonesInL = [ boneId b | b <- lBones, not (Set.member (boneId b) kBoneImg) ]
      delBonesInG = Set.fromList [ gId | bId <- delBonesInL, Just gId <- [Map.lookup bId bMatch] ]
      matchedJointsG = Set.fromList (Map.elems jMatch)
      externalJoints = [ j | j <- allJoints host, not (Set.member (jointId j) matchedJointsG) ]

  forM_ externalJoints $ \j -> do
    if Set.member (jointSource j) delBonesInG || Set.member (jointTarget j) delBonesInG
      then Left (DanglingConditionViolated
        ("External joint " <> showT (unJointId (jointId j)) <>
         " connects to deleted bone (source: " <> showT (unBoneId (jointSource j)) <>
         ", target: " <> showT (unBoneId (jointTarget j)) <> ")"))
      else Right ()

--------------------------------------------------------------------------------
-- Matching
--------------------------------------------------------------------------------

-- | Search for all monomorphic (injective) subgraph embeddings @m : L -> G@.
--
-- Matches bone payloads via 'Eq' and ensures that all joint connections and
-- edge orientations in @L@ correspond to distinct joints in @G@.
findMatches :: forall a. (Eq a) => ProductionRule a -> Skeleton a -> [GraphMatch]
findMatches rule host =
  let lBones = allBonesWithId (ruleLeft rule)
      lJoints = allJoints (ruleLeft rule)
      gBones = allBonesWithId host
      gJoints = allJoints host

      -- Injective search over bone assignments
      matchBonesSearch :: [Bone a] -> Map BoneId BoneId -> Set BoneId -> [Map BoneId BoneId]
      matchBonesSearch [] !acc !_usedG = [acc]
      matchBonesSearch (Bone lBid lVal : rest) !acc !usedG =
        let candidates =
              [ boneId g
              | g <- gBones
              , not (Set.member (boneId g) usedG)
              , bonePayload g == lVal
              ]
        in [ res
           | c <- candidates
           , res <- matchBonesSearch rest (Map.insert lBid c acc) (Set.insert c usedG)
           ]

      -- Injective search over joint assignments given a valid bone assignment
      matchJointsSearch :: [Joint] -> Map BoneId BoneId -> Map JointId JointId -> Set JointId -> [Map JointId JointId]
      matchJointsSearch [] !_bMap !acc !_usedG = [acc]
      matchJointsSearch (Joint lJid lSrc lDst : rest) !bMap !acc !usedG =
        case (Map.lookup lSrc bMap, Map.lookup lDst bMap) of
          (Just gSrc, Just gDst) ->
            let candidates =
                  [ jointId j
                  | j <- gJoints
                  , not (Set.member (jointId j) usedG)
                  , jointSource j == gSrc
                  , jointTarget j == gDst
                  ]
            in [ res
               | c <- candidates
               , res <- matchJointsSearch rest bMap (Map.insert lJid c acc) (Set.insert c usedG)
               ]
          _ -> []

  in [ GraphMatch jMap bMap
     | bMap <- matchBonesSearch lBones Map.empty Set.empty
     , jMap <- matchJointsSearch lJoints bMap Map.empty Set.empty
     ]

--------------------------------------------------------------------------------
-- Pushout Complement & Pushout Construction
--------------------------------------------------------------------------------

-- | Derive the first pushout complement context skeleton @D = G \setminus m(L \setminus K)@.
--
-- Excises vertices and edges specified for deletion while validating the gluing condition.
-- Preserves contiguous bone indexing by monotonically re-indexing retained bones into
-- @[0 .. |V_D| - 1]@.
derivePushoutComplement :: ProductionRule a -> GraphMatch -> Skeleton a -> Either RewritingError (Skeleton a)
derivePushoutComplement rule match host = do
  validateGluingCondition rule match host

  let (_, l_bones) = morphismL rule
      (l_joints, _) = morphismL rule
      kBoneImg = Set.fromList (Map.elems l_bones)
      kJointImg = Set.fromList (Map.elems l_joints)
      bMatch = matchBones match
      jMatch = matchJoints match

      delBonesInL = [ boneId b | b <- allBonesWithId (ruleLeft rule), not (Set.member (boneId b) kBoneImg) ]
      delBonesInG = Set.fromList [ gId | bId <- delBonesInL, Just gId <- [Map.lookup bId bMatch] ]

      delJointsInL = [ jointId j | j <- allJoints (ruleLeft rule), not (Set.member (jointId j) kJointImg) ]
      delJointsInG = Set.fromList [ gId | jId <- delJointsInL, Just gId <- [Map.lookup jId jMatch] ]

      retainedBones = [ b | b <- allBonesWithId host, not (Set.member (boneId b) delBonesInG) ]
      retainedJoints = [ j | j <- allJoints host, not (Set.member (jointId j) delJointsInG) ]

      -- Old BoneId in G -> New contiguous BoneId in D (0 .. length retainedBones - 1)
      boneMapGtoD = Map.fromList (zipWith (\b i -> (boneId b, BoneId i)) retainedBones [0..])

  -- Build D with contiguous OsteoSegments
  let skel0 = emptySkeleton
      skelWithBones = foldl' (\s b -> snd (insertBone (bonePayload b) s)) skel0 retainedBones

  -- Add retained joints with re-indexed source and target
  foldM (\s j -> do
    case (Map.lookup (jointSource j) boneMapGtoD, Map.lookup (jointTarget j) boneMapGtoD) of
      (Just newSrc, Just newDst) ->
        pure (snd (connectJoint newSrc newDst s))
      _ ->
        Left (PushoutComplementFailed "Dangling edge endpoint encountered during complement derivation")
    ) skelWithBones retainedJoints

-- | Construct the second pushout skeleton @H = D \amalg_K R@.
--
-- Glues the replacement pattern @R@ to the pushout complement context skeleton @D@
-- along interface @K@. Appends newly synthesized bones and joints while maintaining
-- contiguous memory indexing and monotonic identifier allocation.
constructPushout :: ProductionRule a -> GraphMatch -> Skeleton a -> Either RewritingError (Skeleton a)
constructPushout rule match d = do
  validateRule rule

  let (_, l_bones) = morphismL rule
      kBoneImgL = Set.fromList (Map.elems l_bones)
      bMatch = matchBones match

      -- Deleted bones from G
      delBonesInL = [ boneId b | b <- allBonesWithId (ruleLeft rule), not (Set.member (boneId b) kBoneImgL) ]
      delBonesInG = Set.fromList [ gId | bId <- delBonesInL, Just gId <- [Map.lookup bId bMatch] ]

      (r_joints, r_bones) = morphismR rule

  -- For each bone k in K: resolve its corresponding BoneId in D.
  kToD_BoneList <- forM (allBonesWithId (ruleInterface rule)) $ \kB -> do
    let kBid = boneId kB
    case Map.lookup kBid l_bones of
      Nothing ->
        Left (InvalidRuleMorphism ("Interface bone " <> showT (unBoneId kBid) <> " not found in morphismL"))
      Just lBid ->
        case Map.lookup lBid bMatch of
          Nothing ->
            Left (InvalidRuleMorphism ("Pattern bone " <> showT (unBoneId lBid) <> " not found in match"))
          Just gBid -> do
            let deletedBefore = Set.size (Set.filter (< gBid) delBonesInG)
                dBid = BoneId (unBoneId gBid - fromIntegral deletedBefore)
            case lookupBone dBid d of
              Nothing ->
                Left (PushoutComplementFailed ("Interface bone mapped to out-of-bounds bone in D: " <> showT (unBoneId dBid)))
              Just _ -> pure (kBid, dBid)

  let kToD_BoneMap = Map.fromList kToD_BoneList

  -- Map from BoneId in R to BoneId in H:
  -- If rB is in range of r_bones: it corresponds to k in K, mapping to kToD_BoneMap(k).
  -- If rB is not in range of r_bones: it is newly synthesized, appended to D.
  let rBonesInK = Map.fromList [ (rBid, kBid) | (kBid, rBid) <- Map.toList r_bones ]
      rAllBones = allBonesWithId (ruleRight rule)
      (existingRBones, newRBones) = partition (\b -> Map.member (boneId b) rBonesInK) rAllBones

  existingMapList <- forM existingRBones $ \b -> do
    let rBid = boneId b
    case Map.lookup rBid rBonesInK of
      Nothing -> Left (InvalidRuleMorphism "Internal error: existing bone missing in rBonesInK")
      Just kBid ->
        case Map.lookup kBid kToD_BoneMap of
          Nothing -> Left (InvalidRuleMorphism "Interface bone missing in context mapping")
          Just dBid -> pure (rBid, dBid)

  let initRBoneToH = Map.fromList existingMapList

  -- Insert new bones into d sequentially
  let insertNewRBones (!currSkel, !currMap) [] = pure (currSkel, currMap)
      insertNewRBones (!currSkel, !currMap) (b : rest) = do
        let (newBid, nextSkel) = insertBone (bonePayload b) currSkel
            nextMap = Map.insert (boneId b) newBid currMap
        insertNewRBones (nextSkel, nextMap) rest

  (skelWithBones, rBoneToH) <- insertNewRBones (d, initRBoneToH) newRBones

  -- Now connect joints:
  -- Joints in R that are in image of r_joints already exist in D.
  -- Joints in R NOT in image of r_joints are newly synthesized in H!
  let rJointImg = Set.fromList (Map.elems r_joints)
      newRJoints = [ j | j <- allJoints (ruleRight rule), not (Set.member (jointId j) rJointImg) ]

  foldM (\s j -> do
    case (Map.lookup (jointSource j) rBoneToH, Map.lookup (jointTarget j) rBoneToH) of
      (Just srcH, Just dstH) ->
        pure (snd (connectJoint srcH dstH s))
      _ ->
        Left (PushoutComplementFailed "New joint in R connects to unmapped bone in H")
    ) skelWithBones newRJoints

--------------------------------------------------------------------------------
-- End-to-End Rewriting
--------------------------------------------------------------------------------

-- | Execute an atomic Double-Pushout rewrite given an explicit match @m : L -> G@.
--
-- Validates the gluing condition, derives the pushout complement @D@, and glues
-- the replacement @R@ to produce derived graph @H@.
applyRule :: ProductionRule a -> GraphMatch -> Skeleton a -> Either RewritingError (Skeleton a)
applyRule rule match host = do
  validateGluingCondition rule match host
  d <- derivePushoutComplement rule match host
  constructPushout rule match d

-- | Find the first monomorphic match in host graph @G@ and apply the production rule.
applyRuleFirstMatch :: (Eq a) => ProductionRule a -> Skeleton a -> Either RewritingError (Skeleton a)
applyRuleFirstMatch rule host =
  case findMatches rule host of
    [] -> Left (MatchNotFound ("No monomorphic match found for rule: " <> ruleName rule))
    (m : _) -> applyRule rule m host

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

showT :: (Show a) => a -> Text
showT = pack . show
