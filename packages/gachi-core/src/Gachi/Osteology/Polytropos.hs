{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE MagicHash #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}

-- | Module: Gachi.Osteology.Polytropos
-- Description: Zero-cost coercions and algebraic isomorphisms between OsteoSegment and Polytropos Rep
--
-- Establishes zero-cost memory coercions and bidirectional algebraic isomorphisms
-- between 'gachi-core' contiguous osteological arrays ('OsteoSegment') and 'polytropos-core'
-- flat structural runtime representations ('Rep': constructor tag plus flat 'SA.SmallArray').
--
-- See Note [Zero-Cost Polytropos Rep Coercions] [ref:note-osteo-polytropos-coercion].
module Gachi.Osteology.Polytropos
  ( -- * Coercion Primitives
    segmentToRep
  , repToSegment
  , checkedSegmentToRep
  , checkedRepToSegment
  , validateSegment

    -- * Buffer Sharing Diagnostics
  , sameSmallArray
  , sharesArrayBuffer

    -- * Error Diagnostics
  , CoercionError(..)

    -- * Record & Bone Payload Codecs
  , bonePayloadToRecord
  , recordToBonePayload
  , recordToBonePayloadWithId
  , segmentToRecord
  , recordToSegment
  , BoneRecord
  , BoneRecordCodec(..)
  , boneToRecordVia
  , recordToBoneVia
  ) where

import Data.Functor.Identity (Identity(..))
import qualified Data.Primitive.SmallArray as SA
import GHC.Exts (Any, isTrue#, sameSmallArray#, unsafeCoerce#)

import Polytropos (Record)
import Polytropos.Core
  ( Rep(..)
  , Row
  , RowRep(..)
  )

import Gachi.Core (Bone(..), BoneId(..))
import Gachi.Osteology (OsteoSegment(..))

{- Note [Zero-Cost Polytropos Rep Coercions]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
[tag:note-osteo-polytropos-coercion]
In high-throughput osteological graph processing and generic transformation pipelines,
bridging data between domain representations (contiguous osteological arrays like
'OsteoSegment') and runtime row abstractions (such as Polytropos 'Rep' and 'Record')
must not incur pointer indirection overhead, auxiliary heap allocations, or
intermediate garbage collector pressure.

1. Memory Substrate Parity:
   Both 'OsteoSegment' and Polytropos 'Rep' share identical underlying primitive
   memory substrates backed by GHC's unlifted 'SmallArray#' primitive:
     - 'OsteoSegment a':
         osteoArray  :: !(SmallArray a)
         osteoOffset :: !Int
         osteoLength :: !Int
     - 'Rep f a':
         {-# UNPACK #-} !Word (constructor tag / discriminant)
         !(SmallArray (f Any)) (contiguous flat array of payload slots)

2. Zero Linked-List Detour:
   Traditional Haskell generic conversions (such as standard GHC.Generics or Scrap
   Your Boilerplate) map products and sums through intermediate heap-allocated lists
   ('[a]') or nested binary trees ('(:*:)'), inducing heavy nursery allocation churn
   and frequent cache misses. Polytropos zero-cost coercions bypass intermediate
   representations entirely, mapping between contiguous array slices directly via
   single-memcpy or O(1) array re-interpretation.

3. Fast-Path Zero-Allocation Re-Interpretation:
   When an 'OsteoSegment' spans the entirety of its underlying primitive buffer
   (i.e., 'osteoOffset == 0' and 'osteoLength == sizeofSmallArray osteoArray'),
   'segmentToRep' performs a zero-allocation coercion: the underlying 'SmallArray#'
   is passed through directly to 'Rep' without allocating any auxiliary array buffers.
   Conversely, when the segment represents a sliced sub-window (offset > 0 or
   length < capacity), 'segmentToRep' performs an optimal single slice clone via
   'cloneSmallArray', which compiles down to primitive GHC SIMD-accelerated memory
   copying without traversing intermediate pointers.

4. Formal Bidirectional Algebraic Isomorphism:
   For any canonically sized segment (offset 0, length equal to array capacity),
   the coercion primitives satisfy strict roundtrip algebraic isomorphisms:
     repToSegment . uncurry segmentToRep = id
     uncurry segmentToRep . repToSegment = id
   Similarly, extensible record wrappers satisfy:
     bonePayloadToRecord . recordToBonePayload = id
-}

-- | An error occurring during osteological segment or representation coercion.
data CoercionError
  = SegmentOutOfBounds !Int !Int
    -- ^ The segment offset or length exceeds the underlying array bounds.
    -- Carries (actual bound index requested, underlying array capacity).
  | TagMismatch !Word !Word
    -- ^ Constructor tag mismatch between expected discriminant and actual representation.
    -- Carries (expected tag, actual tag).
  deriving (Eq, Show)

-- | Check pointer identity between two primitive 'SA.SmallArray' allocations.
--
-- Returns 'True' if and only if both arrays reference the exact same memory buffer.
--
-- See Note [Zero-Cost Polytropos Rep Coercions] [ref:note-osteo-polytropos-coercion].
sameSmallArray :: SA.SmallArray a -> SA.SmallArray b -> Bool
sameSmallArray (SA.SmallArray a#) (SA.SmallArray b#) =
  isTrue# (sameSmallArray# a# (unsafeCoerce# b#))
{-# INLINE sameSmallArray #-}

-- | Check whether an 'OsteoSegment' and a Polytropos 'Rep' share the identical underlying array buffer.
--
-- Used to verify that zero-allocation fast-path coercions occurred without buffer reallocation.
--
-- See Note [Zero-Cost Polytropos Rep Coercions] [ref:note-osteo-polytropos-coercion].
sharesArrayBuffer :: OsteoSegment (f Any) -> Rep f a -> Bool
sharesArrayBuffer (OsteoSegment arr _ _) (Rep _ repArr) = sameSmallArray arr repArr
{-# INLINE sharesArrayBuffer #-}

-- | Validate that an 'OsteoSegment' adheres to the physical bounds of its underlying array.
--
-- See Note [Zero-Cost Polytropos Rep Coercions] [ref:note-osteo-polytropos-coercion].
validateSegment :: OsteoSegment a -> Either CoercionError ()
validateSegment (OsteoSegment arr off len)
  | off < 0 = Left (SegmentOutOfBounds off (SA.sizeofSmallArray arr))
  | len < 0 = Left (SegmentOutOfBounds len (SA.sizeofSmallArray arr))
  | off + len > SA.sizeofSmallArray arr =
      Left (SegmentOutOfBounds (off + len) (SA.sizeofSmallArray arr))
  | otherwise = Right ()
{-# INLINE validateSegment #-}

-- | Coerce an 'OsteoSegment' of dynamically typed field values into a Polytropos 'Rep'.
--
-- When the segment encompasses the entirety of the underlying array buffer
-- (@osteoOffset == 0@ and @osteoLength == sizeofSmallArray osteoArray@), this coercion
-- is strictly zero-cost: the underlying 'SA.SmallArray' is reused directly without
-- allocating a new array buffer.
--
-- When the segment is a sliced sub-segment (@osteoOffset > 0@ or @osteoLength < capacity@),
-- an optimal single-memcpy slice copy ('SA.cloneSmallArray') is performed to package the
-- slice into a tightly-sized contiguous array buffer without traversing intermediate
-- linked lists.
--
-- See Note [Zero-Cost Polytropos Rep Coercions] [ref:note-osteo-polytropos-coercion].
segmentToRep :: Word -> OsteoSegment (f Any) -> Rep f a
segmentToRep !tag (OsteoSegment arr off len)
  | off == 0 && len == SA.sizeofSmallArray arr =
      Rep tag arr
  | otherwise =
      Rep tag (SA.cloneSmallArray arr off len)
{-# INLINE segmentToRep #-}

-- | Coerce a Polytropos 'Rep' back into an 'OsteoSegment' paired with its constructor tag.
--
-- Wraps the underlying 'SA.SmallArray' directly into an 'OsteoSegment' with offset 0
-- and length equal to the array capacity, requiring zero element allocations.
--
-- See Note [Zero-Cost Polytropos Rep Coercions] [ref:note-osteo-polytropos-coercion].
repToSegment :: Rep f a -> (Word, OsteoSegment (f Any))
repToSegment (Rep tag arr) =
  (tag, OsteoSegment arr 0 (SA.sizeofSmallArray arr))
{-# INLINE repToSegment #-}

-- | Checked coercion from 'OsteoSegment' to Polytropos 'Rep' validating bounds.
--
-- See Note [Zero-Cost Polytropos Rep Coercions] [ref:note-osteo-polytropos-coercion].
checkedSegmentToRep :: Word -> OsteoSegment (f Any) -> Either CoercionError (Rep f a)
checkedSegmentToRep !tag !seg = do
  validateSegment seg
  Right (segmentToRep tag seg)
{-# INLINE checkedSegmentToRep #-}

-- | Checked extraction from Polytropos 'Rep' asserting an expected constructor tag.
--
-- See Note [Zero-Cost Polytropos Rep Coercions] [ref:note-osteo-polytropos-coercion].
checkedRepToSegment :: Word -> Rep f a -> Either CoercionError (OsteoSegment (f Any))
checkedRepToSegment !expectedTag rep@(Rep actualTag _)
  | expectedTag /= actualTag = Left (TagMismatch expectedTag actualTag)
  | otherwise = Right (snd (repToSegment rep))
{-# INLINE checkedRepToSegment #-}

--------------------------------------------------------------------------------
-- Record & Bone Payload Codecs
--------------------------------------------------------------------------------

-- | Disambiguating type synonym for an osteological 'Bone' bearing an extensible Polytropos 'Record'.
type BoneRecord r = Bone (Record r)

-- | Extract an extensible Polytropos 'Record' payload from an osteological 'Bone'.
--
-- Operates at \(O(1)\) with zero intermediate allocation.
--
-- See Note [Zero-Cost Polytropos Rep Coercions] [ref:note-osteo-polytropos-coercion].
bonePayloadToRecord :: Bone (Record r) -> Record r
bonePayloadToRecord = bonePayload
{-# INLINE bonePayloadToRecord #-}

-- | Wrap a Polytropos extensible 'Record' into an osteological 'Bone' with default identifier 0.
--
-- Operates at \(O(1)\).
--
-- See Note [Zero-Cost Polytropos Rep Coercions] [ref:note-osteo-polytropos-coercion].
recordToBonePayload :: Record r -> Bone (Record r)
recordToBonePayload = Bone (BoneId 0)
{-# INLINE recordToBonePayload #-}

-- | Wrap a Polytropos extensible 'Record' into an osteological 'Bone' with an explicit 'BoneId'.
--
-- Operates at \(O(1)\).
--
-- See Note [Zero-Cost Polytropos Rep Coercions] [ref:note-osteo-polytropos-coercion].
recordToBonePayloadWithId :: BoneId -> Record r -> Bone (Record r)
recordToBonePayloadWithId = Bone
{-# INLINE recordToBonePayloadWithId #-}

-- | Directly coerce an 'OsteoSegment' of 'Identity' values into an extensible Polytropos 'Record'.
--
-- Operates at \(O(1)\) when the segment is un-sliced, reusing the underlying array directly.
--
-- See Note [Zero-Cost Polytropos Rep Coercions] [ref:note-osteo-polytropos-coercion].
segmentToRecord :: OsteoSegment (Identity Any) -> Record (r :: Row)
segmentToRecord !seg = RowRep (segmentToRep 0 seg)
{-# INLINE segmentToRecord #-}

-- | Directly coerce an extensible Polytropos 'Record' into an 'OsteoSegment' of 'Identity' values.
--
-- Operates at \(O(1)\) with zero allocation.
--
-- See Note [Zero-Cost Polytropos Rep Coercions] [ref:note-osteo-polytropos-coercion].
recordToSegment :: Record (r :: Row) -> OsteoSegment (Identity Any)
recordToSegment (RowRep rep) = snd (repToSegment rep)
{-# INLINE recordToSegment #-}

-- | Bidirectional codec between an arbitrary osteological bone payload type @a@
-- and an extensible Polytropos record @Record r@.
class BoneRecordCodec a (r :: Row) | a -> r where
  -- | Encode an osteological bone payload into an open record.
  encodeBonePayload :: a -> Record r
  -- | Decode an open record back into an osteological bone payload.
  decodeBonePayload :: Record r -> a

-- | Encode a bone whose payload implements 'BoneRecordCodec' into an extensible record.
boneToRecordVia :: BoneRecordCodec a r => Bone a -> Record r
boneToRecordVia (Bone _ p) = encodeBonePayload p
{-# INLINE boneToRecordVia #-}

-- | Decode an extensible record into an osteological bone with an explicit 'BoneId'.
recordToBoneVia :: BoneRecordCodec a r => BoneId -> Record r -> Bone a
recordToBoneVia !bid !r = Bone bid (decodeBonePayload r)
{-# INLINE recordToBoneVia #-}
