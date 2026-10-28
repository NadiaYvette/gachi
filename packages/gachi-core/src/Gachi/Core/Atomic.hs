{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}

-- | Module: Gachi.Core.Atomic
-- Description: Lock-free atomic state machines and bounded backoff for skeletal joints
--
-- Implements compare-and-swap (CAS) transitions and contention-resilient exponential
-- backoff retry protocols for skeletal joints across concurrent multi-agent traversals.
--
-- Joint transitions operate strictly lock-free with zero mutex deadlocks, guaranteeing
-- wait-free progression for read traversals and livelock prevention under write saturation.
--
-- See Note [Chattering Lock-Free Atomic Synchronization] [ref:note-chattering-synchronization].
--
-- = Architectural Invariants
--
-- * **Zero Mutex Contention:** Transitions rely on native CPU compare-and-swap ('casJointState')
--   rather than OS mutexes or runtime MVars.
-- * **Wait-Free Snapshot Reads:** 'readJointState' performs a single atomic memory read
--   without spinning or waiting on writer threads.
-- * **Bounded Exponential Backoff:** 'transitionJointWithBackoff' desynchronizes contending
--   agents using jittered, bounded exponential delays to eliminate livelocks.
--
-- = Worked Example
--
-- >>> import Gachi.Core.Atomic
-- >>> joint <- newAtomicJoint JointInert
-- >>> readJointState joint
-- JointInert
-- >>> casJointState joint JointInert (JointChattering 1)
-- True
-- >>> readJointState joint
-- JointChattering 1
-- >>> transitionJointWithBackoff joint (\s -> case s of JointChattering n -> Just (JointChattering (n + 1)); _ -> Nothing) 10
-- Right (JointChattering 2)
module Gachi.Core.Atomic
  ( -- * Atomic Joint State Machine
    casJointState
  , transitionJointWithBackoff
  , readJointState
  , writeJointState

    -- * Error Conditions
  , AtomicError(..)

    -- * Re-exports from Osteology Substrate
  , JointState(..)
  , AtomicJoint(..)
  , newAtomicJoint
  , newAtomicJointRaw
  , readAtomicJointRaw
  , writeAtomicJointRaw
  , casAtomicJointRaw
  , encodeJointState
  , decodeJointState
  , isJointInert
  , isJointChattering
  , isJointSynchronized
  , isJointFused
  ) where

import Control.Concurrent (threadDelay)
import Control.Exception (Exception)
import Data.Bits (shiftL)
import GHC.Generics (Generic)
import Gachi.Osteology.Atomic
  ( AtomicJoint(..)
  , JointState(..)
  , casAtomicJointRaw
  , decodeJointState
  , encodeJointState
  , isJointChattering
  , isJointFused
  , isJointInert
  , isJointSynchronized
  , newAtomicJoint
  , newAtomicJointRaw
  , readAtomicJointRaw
  , writeAtomicJointRaw
  )

--------------------------------------------------------------------------------
-- Error Conditions
--------------------------------------------------------------------------------

-- | Error conditions encountered during lock-free atomic transitions.
--
-- Tested against Note [Chattering Lock-Free Atomic Synchronization] [ref:note-chattering-synchronization].
data AtomicError
  = InvalidTransition !JointState
    -- ^ The transition function returned 'Nothing' for the observed state,
    -- indicating an illegal or unsupported lifecycle transition.
  | MaxRetriesExceeded !Int
    -- ^ Bounded exponential backoff exhausted after the specified number of retries
    -- due to persistent contention from competing concurrent threads.
  deriving stock (Eq, Ord, Show, Generic)

instance Exception AtomicError

--------------------------------------------------------------------------------
-- Atomic Joint State Machine Primitives
--------------------------------------------------------------------------------

-- | Wait-free atomic memory read of the current 'JointState'.
--
-- Reads the unboxed 64-bit tagged word using a single atomic load instruction
-- and decodes it into a 'JointState'. Readers never block, allocate locks, or
-- stall writer threads.
--
-- See Note [Chattering Lock-Free Atomic Synchronization] [ref:note-chattering-synchronization].
readJointState :: AtomicJoint -> IO JointState
readJointState !joint = do
  !w <- readAtomicJointRaw joint
  pure $! decodeJointState w
{-# INLINE readJointState #-}

-- | Atomic memory write of a 'JointState'.
--
-- Encodes the given 'JointState' into an unboxed 64-bit tagged word and stores
-- it with release semantics.
writeJointState :: AtomicJoint -> JointState -> IO ()
writeJointState !joint !st =
  writeAtomicJointRaw joint (encodeJointState st)
{-# INLINE writeJointState #-}

-- | Atomic compare-and-swap (CAS) updating the joint state if and only if
-- the current state matches the expected state.
--
-- Returns 'True' if the transition succeeded; returns 'False' if the observed
-- state differed from 'expected', leaving the joint untouched.
--
-- See Note [Chattering Lock-Free Atomic Synchronization] [ref:note-chattering-synchronization].
casJointState :: AtomicJoint -> JointState -> JointState -> IO Bool
casJointState !joint !expected !target =
  casAtomicJointRaw joint (encodeJointState expected) (encodeJointState target)
{-# INLINE casJointState #-}

-- | Execute an optimistic atomic state transition with bounded exponential backoff.
--
-- Implements the lock-free retry loop:
--   1. Optimistic Read: Reads the current 'JointState' wait-free.
--   2. Target Evaluation: Applies the pure transition function @(JointState -> Maybe JointState)@.
--      If the function returns 'Nothing', fails immediately with 'InvalidTransition'.
--   3. Compare-And-Swap: Attempts 'casJointState' from the observed state to the target state.
--   4. Contention Backoff: If CAS fails, yields execution with bounded exponential delay
--      up to @maxRetries@ before returning 'MaxRetriesExceeded'.
--
-- See Note [Chattering Lock-Free Atomic Synchronization] [ref:note-chattering-synchronization].
transitionJointWithBackoff
  :: AtomicJoint
  -> (JointState -> Maybe JointState)
  -> Int
  -> IO (Either AtomicError JointState)
transitionJointWithBackoff !joint !stepFn !maxRetries = go 0
  where
    -- Base backoff delay in microseconds (10 µs)
    baseDelayMicros :: Int
    baseDelayMicros = 10

    -- Maximum ceiling backoff delay in microseconds (5,000 µs = 5 ms)
    maxDelayMicros :: Int
    maxDelayMicros = 5000

    go !attempt = do
      !curr <- readJointState joint
      case stepFn curr of
        Nothing -> pure (Left (InvalidTransition curr))
        Just !next -> do
          !succCAS <- casJointState joint curr next
          if succCAS
            then pure (Right next)
            else if attempt >= maxRetries
              then pure (Left (MaxRetriesExceeded maxRetries))
              else do
                -- Exponential backoff: baseDelay * 2^(min attempt 10)
                let !shiftAmount = min attempt 10
                    !delay = min maxDelayMicros (baseDelayMicros `shiftL` shiftAmount)
                threadDelay delay
                go (attempt + 1)
