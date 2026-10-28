{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE MagicHash #-}
{-# LANGUAGE UnboxedTuples #-}

-- | Module: Gachi.Osteology.Atomic
-- Description: Unboxed atomic state references and tagged word layouts for skeletal joints
--
-- Provides low-level, high-performance unboxed atomic memory primitives for representing
-- skeletal joint lifecycles without heap overhead or global locks.
--
-- Each joint is backed by an unboxed 64-bit tagged word stored inside a contiguous primitive
-- byte array ('AtomicJoint'), enabling native CPU compare-and-swap (CAS) instructions.
--
-- = Joint Lifecycle
--
-- Joint lifecycles progress through four canonical phases:
--
--   1. 'JointInert' (Tag @00_2@): Stationary joint awaiting excitation. Zero-initialized memory
--      (@0x0000000000000000@) naturally decodes to this state.
--   2. 'JointChattering' (Tag @01_2@): High-frequency lock-free oscillation carrying a 62-bit
--      chattering generation or sequence counter.
--   3. 'JointSynchronized' (Tag @10_2@): Harmonically locked joint carrying a 62-bit phase
--      or frequency identifier.
--   4. 'JointFused' (Tag @11_2@): Immutable terminal joint state resisting further mutation.
--
-- = Memory Layout (64-bit Tagged Word)
--
-- @
--  63 62 61                                                            0
-- +-----+---------------------------------------------------------------+
-- | Tag | Payload (62-bit generation / frequency / phase word)         |
-- +-----+---------------------------------------------------------------+
--  00: JointInert
--  01: JointChattering
--  10: JointSynchronized
--  11: JointFused
-- @
module Gachi.Osteology.Atomic
  ( -- * Joint Lifecycle State
    JointState(..)
  , isJointInert
  , isJointChattering
  , isJointSynchronized
  , isJointFused

    -- * Tagged Word Codecs
  , encodeJointState
  , decodeJointState
  , tagMask
  , payloadMask

    -- * Unboxed Atomic Joint Reference
  , AtomicJoint(..)
  , newAtomicJoint
  , newAtomicJointRaw
  , readAtomicJointRaw
  , writeAtomicJointRaw
  , casAtomicJointRaw
  , casAtomicJointRawOld
  ) where

import Control.Monad.Primitive (RealWorld)
import Data.Bits (shiftL, shiftR, (.&.), (.|.))
import qualified Data.Primitive.ByteArray as BA
import Data.Word (Word64)
import GHC.Exts
  ( Int(..)
  , atomicReadIntArray#
  , atomicWriteIntArray#
  , casIntArray#
  , isTrue#
  , (==#)
  )
import GHC.Generics (Generic)
import GHC.IO (IO(..))

--------------------------------------------------------------------------------
-- Joint Lifecycle State
--------------------------------------------------------------------------------

-- | Algebraic data type representing the lifecycle state of a skeletal joint.
--
-- Encoded compactly into a single 64-bit word using the top 2 bits as discriminator tag
-- and the bottom 62 bits as the numeric payload.
data JointState
  = JointInert
    -- ^ Stationary joint awaiting signal excitation (Tag @00_2@).
  | JointChattering !Word64
    -- ^ High-frequency lock-free oscillation under multi-agent signal propagation (Tag @01_2@).
  | JointSynchronized !Word64
    -- ^ Harmonically locked joint in phase equilibrium (Tag @10_2@).
  | JointFused
    -- ^ Immutable terminal joint state (Tag @11_2@).
  deriving stock (Eq, Ord, Show, Generic)

-- | Query whether a 'JointState' is 'JointInert'.
isJointInert :: JointState -> Bool
isJointInert JointInert = True
isJointInert _          = False
{-# INLINE isJointInert #-}

-- | Query whether a 'JointState' is 'JointChattering'.
isJointChattering :: JointState -> Bool
isJointChattering (JointChattering _) = True
isJointChattering _                   = False
{-# INLINE isJointChattering #-}

-- | Query whether a 'JointState' is 'JointSynchronized'.
isJointSynchronized :: JointState -> Bool
isJointSynchronized (JointSynchronized _) = True
isJointSynchronized _                     = False
{-# INLINE isJointSynchronized #-}

-- | Query whether a 'JointState' is 'JointFused'.
isJointFused :: JointState -> Bool
isJointFused JointFused = True
isJointFused _          = False
{-# INLINE isJointFused #-}

--------------------------------------------------------------------------------
-- Tagged Word Codecs
--------------------------------------------------------------------------------

-- | Bitmask selecting the upper 2 tag bits of a 64-bit word (@0xC000000000000000@).
tagMask :: Word64
tagMask = 0xC000000000000000
{-# INLINE tagMask #-}

-- | Bitmask selecting the lower 62 payload bits of a 64-bit word (@0x3FFFFFFFFFFFFFFF@).
payloadMask :: Word64
payloadMask = 0x3FFFFFFFFFFFFFFF
{-# INLINE payloadMask #-}

-- | Encode a 'JointState' into an unboxed 64-bit tagged word.
--
-- * 'JointInert': Encoded as @0x0000000000000000@.
-- * 'JointChattering': Encoded with tag @01_2@ in bits 63..62 and masked payload in bits 61..0.
-- * 'JointSynchronized': Encoded with tag @10_2@ in bits 63..62 and masked payload in bits 61..0.
-- * 'JointFused': Encoded with tag @11_2@ in bits 63..62 (@0xC000000000000000@).
encodeJointState :: JointState -> Word64
encodeJointState JointInert = 0
encodeJointState (JointChattering !payload) =
  (1 `shiftL` 62) .|. (payload .&. payloadMask)
encodeJointState (JointSynchronized !payload) =
  (2 `shiftL` 62) .|. (payload .&. payloadMask)
encodeJointState JointFused = 3 `shiftL` 62
{-# INLINE encodeJointState #-}

-- | Decode an unboxed 64-bit tagged word back into its corresponding 'JointState'.
--
-- Discriminates on the high 2 bits (63..62):
-- * @00_2@ -> 'JointInert'
-- * @01_2@ -> 'JointChattering' with masked 62-bit payload
-- * @10_2@ -> 'JointSynchronized' with masked 62-bit payload
-- * @11_2@ -> 'JointFused'
decodeJointState :: Word64 -> JointState
decodeJointState !w =
  let !tag = w `shiftR` 62
      !payload = w .&. payloadMask
  in case tag of
    0 -> JointInert
    1 -> JointChattering payload
    2 -> JointSynchronized payload
    3 -> JointFused
    _ -> JointInert
{-# INLINE decodeJointState #-}

--------------------------------------------------------------------------------
-- Unboxed Atomic Joint Reference
--------------------------------------------------------------------------------

-- | An unboxed atomic reference storing a tagged joint state word.
--
-- Backed by an 8-byte contiguous 'BA.MutableByteArray' to permit direct hardware-level
-- atomic compare-and-swap ('casIntArray#') instructions and wait-free memory reads
-- without acquiring OS mutexes or runtime reader-writer locks.
newtype AtomicJoint = AtomicJoint (BA.MutableByteArray RealWorld)

instance Eq AtomicJoint where
  AtomicJoint mba1 == AtomicJoint mba2 = BA.sameMutableByteArray mba1 mba2

instance Show AtomicJoint where
  show _ = "<AtomicJoint>"

-- | Allocate a new 'AtomicJoint' initialized to the given raw 64-bit word.
newAtomicJointRaw :: Word64 -> IO AtomicJoint
newAtomicJointRaw !val = do
  mba <- BA.newByteArray 8
  let !joint = AtomicJoint mba
  writeAtomicJointRaw joint val
  pure joint

-- | Allocate a new 'AtomicJoint' initialized to the given 'JointState'.
newAtomicJoint :: JointState -> IO AtomicJoint
newAtomicJoint !st = newAtomicJointRaw (encodeJointState st)

-- | Wait-free atomic memory read of the raw 64-bit tagged word.
readAtomicJointRaw :: AtomicJoint -> IO Word64
readAtomicJointRaw (AtomicJoint mba) = IO $ \s0# ->
  let !(BA.MutableByteArray mba#) = mba
  in case atomicReadIntArray# mba# 0# s0# of
    (# s1#, val# #) ->
      (# s1#, fromIntegral (I# val#) #)
{-# INLINE readAtomicJointRaw #-}

-- | Atomic memory write of the raw 64-bit tagged word.
writeAtomicJointRaw :: AtomicJoint -> Word64 -> IO ()
writeAtomicJointRaw (AtomicJoint mba) !val = IO $ \s0# ->
  let !(I# v#) = fromIntegral val
      !(BA.MutableByteArray mba#) = mba
  in case atomicWriteIntArray# mba# 0# v# s0# of
    s1# -> (# s1#, () #)
{-# INLINE writeAtomicJointRaw #-}

-- | Hardware compare-and-swap (CAS) operation on the raw 64-bit tagged word.
--
-- Atomically compares the current word at slot 0 with @expected@. If they match,
-- writes @newVal@ and returns 'True'. If they do not match, leaves memory untouched
-- and returns 'False'.
casAtomicJointRaw :: AtomicJoint -> Word64 -> Word64 -> IO Bool
casAtomicJointRaw (AtomicJoint mba) !expected !newVal = IO $ \s0# ->
  let !(I# exp#) = fromIntegral expected
      !(I# new#) = fromIntegral newVal
      !(BA.MutableByteArray mba#) = mba
  in case casIntArray# mba# 0# exp# new# s0# of
    (# s1#, old# #) ->
      (# s1#, isTrue# (old# ==# exp#) #)
{-# INLINE casAtomicJointRaw #-}

-- | Hardware compare-and-swap returning both success status and the observed previous word.
casAtomicJointRawOld :: AtomicJoint -> Word64 -> Word64 -> IO (Bool, Word64)
casAtomicJointRawOld (AtomicJoint mba) !expected !newVal = IO $ \s0# ->
  let !(I# exp#) = fromIntegral expected
      !(I# new#) = fromIntegral newVal
      !(BA.MutableByteArray mba#) = mba
  in case casIntArray# mba# 0# exp# new# s0# of
    (# s1#, old# #) ->
      let !oldW = fromIntegral (I# old#)
          !succCAS = isTrue# (old# ==# exp#)
      in (# s1#, (succCAS, oldW) #)
{-# INLINE casAtomicJointRawOld #-}
