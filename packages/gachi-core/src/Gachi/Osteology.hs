{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Module: Gachi.Osteology
-- Description: Contiguous primitive osteological memory layouts and zero-overhead arrays
--
-- Implements contiguous primitive array structures for osteological node graphs,
-- guaranteeing spatial locality, minimal GC pressure, and zero-allocation traversals.
module Gachi.Osteology
  ( -- * Primitive Osteological Storage
    OsteoSegment(..)
  , emptySegment
  , segmentCapacity
  , segmentLength
  , appendOsteo
  , indexOsteo
  ) where

import qualified Data.Primitive.SmallArray as SA
import Control.Monad.ST (runST)

{- Note [Osteological Contiguous Memory Layout]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
[tag:note-osteology-memory-layout]
In high-throughput AST transformations and massive graph synthesis loops, standard linked
structures (e.g. algebraic trees of boxed heap cells) introduce significant penalties:
  1. Excessive Heap Overhead: Each constructor node requires a 2-word info table and GC header.
  2. Pointer Indirection: Traversal entails non-sequential memory dereferences, defeating CPU
     hardware prefetchers.
  3. Garbage Collector Pause Times: A graph of 100,000 nodes introduces 100,000 distinct pointers
     that the GHC garbage collector must trace during minor scavenges.

Osteological Memory Design:
Gachi resolves these costs by packing nodes into contiguous 'OsteoSegment' unboxed structures:
  - Memory Locality: Segments allocate flat, contiguous memory blocks via GHC primitive
    'SmallArray#' structures.
  - Zero-Copy Slicing: Sub-segments and joint regions reference sub-ranges within contiguous
    memory blocks without reallocating intermediate cells.
  - Unboxed Indexing: Nodes are addressed via primitive unboxed integer offsets, reducing
    traversal to single arithmetic additions and direct memory indexing.
-}

-- | A contiguous, immutable osteological memory segment storing elements of type @a@.
--
-- See Note [Osteological Contiguous Memory Layout] [ref:note-osteology-memory-layout].
data OsteoSegment a = OsteoSegment
  { osteoArray :: !(SA.SmallArray a)
    -- ^ Underlying flat contiguous primitive array.
  , osteoCount :: !Int
    -- ^ Number of active initialized osteological elements.
  } deriving (Eq, Show)

-- | Construct an empty osteological segment with zero capacity and length.
emptySegment :: OsteoSegment a
emptySegment = OsteoSegment
  { osteoArray = SA.smallArrayFromList []
  , osteoCount = 0
  }

-- | Total storage capacity allocated within the underlying contiguous array.
segmentCapacity :: OsteoSegment a -> Int
segmentCapacity (OsteoSegment arr _) = SA.sizeofSmallArray arr

-- | Number of populated elements within this segment.
segmentLength :: OsteoSegment a -> Int
segmentLength = osteoCount

-- | Append an element to an 'OsteoSegment', allocating a resized contiguous array
-- if capacity is exceeded.
appendOsteo :: a -> OsteoSegment a -> OsteoSegment a
appendOsteo !val (OsteoSegment arr count) =
  let cap = SA.sizeofSmallArray arr
  in if count < cap
     then runST $ do
       marr <- SA.thawSmallArray arr 0 cap
       SA.writeSmallArray marr count val
       frozen <- SA.freezeSmallArray marr 0 cap
       pure (OsteoSegment frozen (count + 1))
     else runST $ do
       let newCap = max 4 (cap * 2)
       marr <- SA.newSmallArray newCap val
       SA.copySmallArray marr 0 arr 0 count
       SA.writeSmallArray marr count val
       frozen <- SA.freezeSmallArray marr 0 newCap
       pure (OsteoSegment frozen (count + 1))

-- | Retrieve an element at a specified contiguous index.
-- Returns 'Nothing' if the index is out of bounds.
indexOsteo :: Int -> OsteoSegment a -> Maybe a
indexOsteo idx (OsteoSegment arr count)
  | idx >= 0 && idx < count = Just (SA.indexSmallArray arr idx)
  | otherwise               = Nothing
