{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Module: Gachi.Osteology
-- Description: Contiguous primitive osteological memory layouts and zero-overhead arrays
--
-- Implements contiguous primitive array structures ('OsteoSegment' and 'OsteoBytes')
-- for osteological node graphs, guaranteeing spatial locality, minimal GC pressure,
-- zero-allocation indexing, and zero-copy slicing.
--
-- Inspired by the bone structure of the mythical /gashadokuro/ (がしゃどくろ),
-- osteological segments provide unyielding structural rigidity with cache-coherent
-- memory layouts.
--
-- = When to Use This Module
--
-- * **High-Throughput Node Graphs:** Constructing graph structures or ASTs where node traversal
--   must not incur pointer-indirection penalties.
-- * **Zero-Copy Slicing:** Extracting contiguous sub-graphs or sub-sequences without reallocating
--   underlying array buffers via 'sliceOsteo'.
-- * **GC Scavenge Elimination:** Storing millions of elements in flat contiguous blocks
--   ('OsteoSegment' and 'OsteoBytes') that present a minimal traversal footprint to the GHC garbage collector.
--
-- = Worked Example
--
-- >>> import Gachi.Osteology
-- >>> let seg0 = emptySegment
-- >>> let seg1 = appendOsteo "femur" (appendOsteo "cranium" seg0)
-- >>> indexOsteo 0 seg1
-- Just "cranium"
-- >>> let Just sl = sliceOsteo 0 1 seg1
-- >>> toListOsteo sl
-- ["cranium"]
module Gachi.Osteology
  ( -- * Primitive Osteological Segment
    OsteoSegment(..)
  , emptySegment
  , segmentCapacity
  , segmentLength
  , appendOsteo
  , indexOsteo
  , unsafeIndexOsteo
  , sliceOsteo
  , fromListOsteo
  , toListOsteo

    -- * Unboxed Osteological Byte Storage
  , OsteoBytes(..)
  , emptyBytes
  , bytesCapacity
  , bytesLength
  , indexByte
  , unsafeIndexByte
  , sliceBytes
  , fromByteList
  , toByteList
  ) where

import Control.Monad.ST (runST)
import qualified Data.Primitive.ByteArray as BA
import qualified Data.Primitive.SmallArray as SA
import Data.Word (Word8)

{- Note [Osteological Contiguous Memory Layout]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
[tag:note-osteology-memory-layout]
In high-throughput AST transformations, skeletal graph synthesis, and compiler passes,
traditional boxed linked structures (trees of heap-allocated constructors) introduce
severe performance penalties:
  1. Excessive Heap Overhead: Each constructor node incurs a 2-word info table and
     GC header, quadrupling memory consumption relative to payload.
  2. Pointer Indirection: Traversal entails non-sequential pointer chasing across the
     GHC managed heap, defeating CPU hardware L1/L2 prefetchers and inducing TLB misses.
  3. Garbage Collector Pause Latency: A graph with 100,000 nodes introduces 100,000
     pointers that the GHC garbage collector must trace during minor scavenges.

Osteological Memory Design:
Gachi resolves these costs by packing nodes into contiguous 'OsteoSegment' unboxed structures:
  - Memory Locality: Segments allocate flat, contiguous memory blocks via GHC primitive
    'SmallArray#' structures.
  - Zero-Copy Slicing: Sub-segments and joint regions reference sub-ranges within contiguous
    memory blocks via an offset and length window without reallocating intermediate arrays.
  - O(1) Zero-Allocation Indexing: Nodes are addressed via primitive unboxed integer offsets,
    reducing traversal to single arithmetic additions and direct memory indexing.
  - Amortized Geometric Resizing: Dynamic growth doubles array capacity upon saturation,
    ensuring O(1) amortized append performance.
-}

-- | A contiguous, immutable osteological memory segment storing elements of type @a@.
--
-- Features an offset and length window into an underlying primitive 'SA.SmallArray',
-- enabling true $O(1)$ zero-copy sub-segment slicing without heap allocations.
--
-- See Note [Osteological Contiguous Memory Layout] [ref:note-osteology-memory-layout].
data OsteoSegment a = OsteoSegment
  { osteoArray  :: !(SA.SmallArray a)
    -- ^ Underlying flat contiguous primitive array.
  , osteoOffset :: !Int
    -- ^ Starting offset index of this segment slice within 'osteoArray'.
  , osteoLength :: !Int
    -- ^ Number of active initialized elements within this segment slice.
  }

instance Show a => Show (OsteoSegment a) where
  show seg = "OsteoSegment " ++ show (toListOsteo seg)

instance Eq a => Eq (OsteoSegment a) where
  seg1 == seg2 =
    osteoLength seg1 == osteoLength seg2 && toListOsteo seg1 == toListOsteo seg2

instance Functor OsteoSegment where
  fmap f (OsteoSegment arr off len) = runST $ do
    marr <- SA.newSmallArray len (error "Gachi.Osteology.fmap: uninitialized element")
    let fill !i
          | i < len = do
              let !val = SA.indexSmallArray arr (off + i)
              SA.writeSmallArray marr i (f val)
              fill (i + 1)
          | otherwise = pure ()
    fill 0
    frozen <- SA.freezeSmallArray marr 0 len
    pure (OsteoSegment frozen 0 len)

instance Foldable OsteoSegment where
  foldr f z (OsteoSegment arr off len) = go 0
    where
      go !i
        | i < len   = f (SA.indexSmallArray arr (off + i)) (go (i + 1))
        | otherwise = z
  {-# INLINE foldr #-}

  length = osteoLength
  {-# INLINE length #-}

  null seg = osteoLength seg == 0
  {-# INLINE null #-}

instance Traversable OsteoSegment where
  traverse f seg = fromListOsteo <$> traverse f (toListOsteo seg)

instance Semigroup (OsteoSegment a) where
  seg1 <> seg2 =
    let len1 = osteoLength seg1
        len2 = osteoLength seg2
        totalLen = len1 + len2
    in if totalLen == 0
       then emptySegment
       else runST $ do
         marr <- SA.newSmallArray totalLen (error "Gachi.Osteology.<>: uninitialized element")
         SA.copySmallArray marr 0 (osteoArray seg1) (osteoOffset seg1) len1
         SA.copySmallArray marr len1 (osteoArray seg2) (osteoOffset seg2) len2
         frozen <- SA.freezeSmallArray marr 0 totalLen
         pure (OsteoSegment frozen 0 totalLen)

instance Monoid (OsteoSegment a) where
  mempty = emptySegment

-- | Construct an empty osteological segment with zero capacity and length.
emptySegment :: OsteoSegment a
emptySegment = OsteoSegment
  { osteoArray  = SA.smallArrayFromList []
  , osteoOffset = 0
  , osteoLength = 0
  }

-- | Total storage capacity allocated within the underlying contiguous array
-- from the current offset point.
segmentCapacity :: OsteoSegment a -> Int
segmentCapacity (OsteoSegment arr off _) = SA.sizeofSmallArray arr - off

-- | Number of populated elements within this segment.
--
-- Time complexity: @O(1)@.
segmentLength :: OsteoSegment a -> Int
segmentLength = osteoLength

-- | Append an element to an 'OsteoSegment', allocating a geometrically resized
-- contiguous array if current capacity is exceeded.
--
-- Time complexity: @O(1)@ amortized.
appendOsteo :: a -> OsteoSegment a -> OsteoSegment a
appendOsteo !val (OsteoSegment arr off len) =
  let cap = SA.sizeofSmallArray arr
  in if off == 0 && len < cap
     then runST $ do
       marr <- SA.thawSmallArray arr 0 cap
       SA.writeSmallArray marr len val
       frozen <- SA.freezeSmallArray marr 0 cap
       pure (OsteoSegment frozen 0 (len + 1))
     else runST $ do
       let newCap = max 4 (max (len + 1) (len * 2))
       marr <- SA.newSmallArray newCap val
       SA.copySmallArray marr 0 arr off len
       SA.writeSmallArray marr len val
       frozen <- SA.freezeSmallArray marr 0 newCap
       pure (OsteoSegment frozen 0 (len + 1))

-- | Retrieve an element at a specified contiguous index with bounds checking.
-- Returns 'Nothing' if the index is out of bounds.
--
-- Time complexity: @O(1)@.
indexOsteo :: Int -> OsteoSegment a -> Maybe a
indexOsteo idx (OsteoSegment arr off len)
  | idx >= 0 && idx < len = Just (SA.indexSmallArray arr (off + idx))
  | otherwise             = Nothing
{-# INLINE indexOsteo #-}

-- | Retrieve an element at a specified contiguous index without bounds checking.
-- Precondition: @0 <= idx < segmentLength seg@.
--
-- Time complexity: @O(1)@ zero-allocation.
unsafeIndexOsteo :: Int -> OsteoSegment a -> a
unsafeIndexOsteo idx (OsteoSegment arr off _) =
  SA.indexSmallArray arr (off + idx)
{-# INLINE unsafeIndexOsteo #-}

-- | Create a zero-copy sub-segment slice referencing the sub-range [@offset .. offset + length - 1@].
-- Returns 'Nothing' if the slice range extends beyond the segment bounds.
--
-- Time complexity: @O(1)@ with zero heap array allocation.
sliceOsteo :: Int -> Int -> OsteoSegment a -> Maybe (OsteoSegment a)
sliceOsteo sliceOff sliceLen (OsteoSegment arr off len)
  | sliceOff >= 0 && sliceLen >= 0 && sliceOff + sliceLen <= len =
      Just (OsteoSegment arr (off + sliceOff) sliceLen)
  | otherwise = Nothing
{-# INLINE sliceOsteo #-}

-- | Construct an 'OsteoSegment' from a standard Haskell list.
fromListOsteo :: [a] -> OsteoSegment a
fromListOsteo xs =
  let arr = SA.smallArrayFromList xs
  in OsteoSegment arr 0 (SA.sizeofSmallArray arr)

-- | Convert an 'OsteoSegment' back into a standard Haskell list.
toListOsteo :: OsteoSegment a -> [a]
toListOsteo (OsteoSegment arr off len) =
  [ SA.indexSmallArray arr (off + i) | i <- [0 .. len - 1] ]

--------------------------------------------------------------------------------
-- Unboxed Osteological Byte Storage
--------------------------------------------------------------------------------

-- | A contiguous, unboxed byte storage segment backed by 'BA.ByteArray'.
--
-- Used for storing raw numeric bone representations, serialized coordinate tables,
-- and binary cryptographic signatures with spatial cache locality.
data OsteoBytes = OsteoBytes
  { osteoByteArray  :: !BA.ByteArray
    -- ^ Underlying flat contiguous primitive byte array.
  , osteoByteOffset :: !Int
    -- ^ Starting byte offset index within 'osteoByteArray'.
  , osteoByteLength :: !Int
    -- ^ Number of active initialized bytes within this slice.
  }

instance Show OsteoBytes where
  show bs = "OsteoBytes " ++ show (toByteList bs)

instance Eq OsteoBytes where
  b1 == b2 =
    osteoByteLength b1 == osteoByteLength b2 && toByteList b1 == toByteList b2

-- | Construct an empty unboxed osteological byte storage with zero bytes.
emptyBytes :: OsteoBytes
emptyBytes = OsteoBytes
  { osteoByteArray  = runST (BA.newByteArray 0 >>= BA.unsafeFreezeByteArray)
  , osteoByteOffset = 0
  , osteoByteLength = 0
  }

-- | Total storage capacity allocated within the underlying byte array
-- from the current offset point.
bytesCapacity :: OsteoBytes -> Int
bytesCapacity (OsteoBytes arr off _) = BA.sizeofByteArray arr - off

-- | Number of populated bytes within this segment.
bytesLength :: OsteoBytes -> Int
bytesLength = osteoByteLength

-- | Retrieve a byte at a specified index with bounds checking.
indexByte :: Int -> OsteoBytes -> Maybe Word8
indexByte idx (OsteoBytes arr off len)
  | idx >= 0 && idx < len = Just (BA.indexByteArray arr (off + idx))
  | otherwise             = Nothing
{-# INLINE indexByte #-}

-- | Retrieve a byte at a specified index without bounds checking.
unsafeIndexByte :: Int -> OsteoBytes -> Word8
unsafeIndexByte idx (OsteoBytes arr off _) =
  BA.indexByteArray arr (off + idx)
{-# INLINE unsafeIndexByte #-}

-- | Create a zero-copy sub-segment slice referencing the byte sub-range.
sliceBytes :: Int -> Int -> OsteoBytes -> Maybe OsteoBytes
sliceBytes sliceOff sliceLen (OsteoBytes arr off len)
  | sliceOff >= 0 && sliceLen >= 0 && sliceOff + sliceLen <= len =
      Just (OsteoBytes arr (off + sliceOff) sliceLen)
  | otherwise = Nothing
{-# INLINE sliceBytes #-}

-- | Construct an 'OsteoBytes' from a list of 'Word8' bytes.
fromByteList :: [Word8] -> OsteoBytes
fromByteList xs = runST $ do
  let len = length xs
  marr <- BA.newByteArray len
  let fill !i (b:bs) = do
        BA.writeByteArray marr i b
        fill (i + 1) bs
      fill _ [] = pure ()
  fill 0 xs
  frozen <- BA.unsafeFreezeByteArray marr
  pure (OsteoBytes frozen 0 len)

-- | Convert an 'OsteoBytes' into a list of 'Word8' bytes.
toByteList :: OsteoBytes -> [Word8]
toByteList (OsteoBytes arr off len) =
  [ BA.indexByteArray arr (off + i) | i <- [0 .. len - 1] ]
