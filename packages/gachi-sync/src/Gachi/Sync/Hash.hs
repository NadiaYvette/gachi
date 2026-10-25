{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Module: Gachi.Sync.Hash
-- Description: Pure, self-contained SHA-256 differential hashing engine
--
-- This module implements FIPS 180-2 compliant Secure Hash Algorithm (SHA-256)
-- in pure Haskell with zero external cryptographic dependencies.
--
-- = Architectural Context & Invariants
--
-- In accordance with Note [Harmonic Chattering Synchronization and Differential Propagation]
-- [ref:note-harmonic-sync], the synchronization engine must rapidly verify
-- content identity across dozens of workspace files without triggering unnecessary
-- disk writes or external process invocations.
--
-- == Invariant: Pure Referential Transparency
--
-- * __Totality:__ Hashing functions are pure and total across all inputs.
-- * __Zero-Dependency:__ Implemented using standard @base@ and @bytestring@ primitives.
-- * __FIPS 180-2 Compliance:__ Satisfies standard NIST test vectors, including the empty string
--   digest (@e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855@).
--
-- == Algorithmic Overview (FIPS 180-2 SHA-256)
--
-- SHA-256 operates on 512-bit message blocks through a sequence of mathematical
-- transformations structured across four stages:
--
-- 1. __Preprocessing and Padding:__
--    The arbitrary-length input bitstream \( M \) of length \( L \) bits is padded
--    by appending a single '1' bit, followed by \( k \) '0' bits, where \( k \)
--    is the smallest non-negative integer satisfying:
--    \[
--      L + 1 + k \equiv 448 \pmod{512}
--    \]
--    Finally, the 64-bit big-endian representation of \( L \) is appended, yielding
--    an exact multiple of 512 bits (16 32-bit words).
--
-- 2. __Message Schedule Expansion:__
--    Each 16-word block \( W_{0..15} \) is expanded into a 64-word schedule \( W_{0..63} \):
--    \[
--      W_t = \sigma_1(W_{t-2}) + W_{t-7} + \sigma_0(W_{t-15}) + W_{t-16}
--    \]
--    where the lower-case sigma functions apply rotational and right-shift mixing:
--    \[
--      \sigma_0(x) = \text{RotR}(x, 7) \oplus \text{RotR}(x, 18) \oplus \text{ShR}(x, 3)
--    \]
--    \[
--      \sigma_1(x) = \text{RotR}(x, 17) \oplus \text{RotR}(x, 19) \oplus \text{ShR}(x, 10)
--    \]
--
-- 3. __64-Round Compression Loop:__
--    Eight 32-bit working state variables (\( a, b, c, d, e, f, g, h \)) are initialized
--    from the intermediate hash values \( H^{(i-1)} \). In each step \( t \in [0, 63] \):
--    \[
--      T_1 = h + \Sigma_1(e) + \text{Ch}(e, f, g) + K_t + W_t
--    \]
--    \[
--      T_2 = \Sigma_0(a) + \text{Maj}(a, b, c)
--    \]
--    \[
--      h \leftarrow g, \quad g \leftarrow f, \quad f \leftarrow e, \quad e \leftarrow d + T_1
--    \]
--    \[
--      d \leftarrow c, \quad c \leftarrow b, \quad b \leftarrow a, \quad a \leftarrow T_1 + T_2
--    \]
--    where the non-linear bitwise choice and majority combinators are defined as:
--    \[
--      \text{Ch}(x, y, z) = (x \wedge y) \oplus (\neg x \wedge z)
--    \]
--    \[
--      \text{Maj}(x, y, z) = (x \wedge y) \oplus (x \wedge z) \oplus (y \wedge z)
--    \]
--
-- 4. __Intermediate State Accumulation:__
--    The updated working variables are summed modulo \( 2^{32} \) into the running state:
--    \[
--      H_j^{(i)} = H_j^{(i-1)} + \text{Var}_j \quad \forall j \in \{0..7\}
--    \]
--
-- = Worked Example
--
-- >>> import Gachi.Sync.Hash
-- >>> sha256Text ""
-- "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
-- >>> sha256Text "gachi"
-- "e43b177d6118bfa6b6f7097eb586ef291f5a5a92cf6d62ea09c0fa168e312521"
module Gachi.Sync.Hash
  ( -- * Pure SHA-256 Digest Functions
    sha256Text
  , sha256ByteString
  , sha256File
  ) where

import Data.Bits (complement, rotateR, shiftL, shiftR, xor, (.&.), (.|.))
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as BL
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Word (Word32, Word64)
import Numeric (showHex)

--------------------------------------------------------------------------------
-- 1. Initial State & Round Constants (FIPS 180-2)
--------------------------------------------------------------------------------

-- | Initial 256-bit hash values representing first 32 bits of fractional parts
-- of the square roots of the first 8 prime numbers (2..19).
initialHash :: (Word32, Word32, Word32, Word32, Word32, Word32, Word32, Word32)
initialHash =
  ( 0x6a09e667
  , 0xbb67ae85
  , 0x3c6ef372
  , 0xa54ff53a
  , 0x510e527f
  , 0x9b05688c
  , 0x1f83d9ab
  , 0x5be0cd19
  )

-- | Sixty-four 32-bit round constants representing the first 32 bits of the
-- fractional parts of the cube roots of the first 64 prime numbers (2..311).
roundConstants :: [Word32]
roundConstants =
  [ 0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5
  , 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5
  , 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3
  , 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174
  , 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc
  , 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da
  , 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7
  , 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967
  , 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13
  , 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85
  , 0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3
  , 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070
  , 0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5
  , 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3
  , 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208
  , 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
  ]

--------------------------------------------------------------------------------
-- 2. Bitwise Logical Functions
--------------------------------------------------------------------------------

-- | Bitwise choice: (x AND y) XOR (NOT x AND z).
ch :: Word32 -> Word32 -> Word32 -> Word32
ch !x !y !z = (x .&. y) `xor` (complement x .&. z)
{-# INLINE ch #-}

-- | Bitwise majority: (x AND y) XOR (x AND z) XOR (y AND z).
maj :: Word32 -> Word32 -> Word32 -> Word32
maj !x !y !z = (x .&. y) `xor` (x .&. z) `xor` (y .&. z)
{-# INLINE maj #-}

-- | Upper-case Sigma 0: RotR(x, 2) XOR RotR(x, 13) XOR RotR(x, 22).
sigmaUpper0 :: Word32 -> Word32
sigmaUpper0 !x = rotateR x 2 `xor` rotateR x 13 `xor` rotateR x 22
{-# INLINE sigmaUpper0 #-}

-- | Upper-case Sigma 1: RotR(x, 6) XOR RotR(x, 11) XOR RotR(x, 25).
sigmaUpper1 :: Word32 -> Word32
sigmaUpper1 !x = rotateR x 6 `xor` rotateR x 11 `xor` rotateR x 25
{-# INLINE sigmaUpper1 #-}

-- | Lower-case Sigma 0: RotR(x, 7) XOR RotR(x, 18) XOR ShiftR(x, 3).
sigmaLower0 :: Word32 -> Word32
sigmaLower0 !x = rotateR x 7 `xor` rotateR x 18 `xor` shiftR x 3
{-# INLINE sigmaLower0 #-}

-- | Lower-case Sigma 1: RotR(x, 17) XOR RotR(x, 19) XOR ShiftR(x, 10).
sigmaLower1 :: Word32 -> Word32
sigmaLower1 !x = rotateR x 17 `xor` rotateR x 19 `xor` shiftR x 10
{-# INLINE sigmaLower1 #-}

--------------------------------------------------------------------------------
-- 3. Message Padding & Block Preparation
--------------------------------------------------------------------------------

-- | Pads message bytes according to FIPS 180-2:
-- 1. Appends bit 1 (single byte 0x80).
-- 2. Appends k zero bytes such that (length + 1 + k) == 56 mod 64.
-- 3. Appends 64-bit big-endian representation of original bit length.
padMessage :: BS.ByteString -> BL.ByteString
padMessage input =
  let lenBytes = fromIntegral (BS.length input) :: Word64
      lenBits = lenBytes * 8
      padLen = (55 - fromIntegral (lenBytes `mod` 64)) `mod` 64
      zeros = BS.replicate padLen 0
      lenEncoding = BS.pack
        [ fromIntegral (shiftR lenBits 56 .&. 0xFF)
        , fromIntegral (shiftR lenBits 48 .&. 0xFF)
        , fromIntegral (shiftR lenBits 40 .&. 0xFF)
        , fromIntegral (shiftR lenBits 32 .&. 0xFF)
        , fromIntegral (shiftR lenBits 24 .&. 0xFF)
        , fromIntegral (shiftR lenBits 16 .&. 0xFF)
        , fromIntegral (shiftR lenBits 8  .&. 0xFF)
        , fromIntegral (lenBits .&. 0xFF)
        ]
  in BL.fromChunks [input, BS.singleton 0x80, zeros, lenEncoding]

-- | Parses a 64-byte block into 16 32-bit big-endian words.
parseBlock :: BS.ByteString -> [Word32]
parseBlock bs = go (BS.unpack bs)
  where
    go [] = []
    go (b0:b1:b2:b3:rest) =
      let !w0 = fromIntegral b0 `shiftL` 24
          !w1 = fromIntegral b1 `shiftL` 16
          !w2 = fromIntegral b2 `shiftL` 8
          !w3 = fromIntegral b3
          !w  = w0 .|. w1 .|. w2 .|. w3
      in w : go rest
    go _ = []

-- | Expands the 16 words of a block into a full 64-word message schedule.
expandSchedule :: [Word32] -> [Word32]
expandSchedule w16 = go 16 (w16 ++ replicate 48 0)
  where
    go !t !ws
      | t == 64   = ws
      | otherwise =
          let s0 = sigmaLower0 (ws !! (t - 15))
              s1 = sigmaLower1 (ws !! (t - 2))
              newW = (ws !! (t - 16)) + s0 + (ws !! (t - 7)) + s1
              updated = take t ws ++ [newW] ++ drop (t + 1) ws
          in go (t + 1) updated

--------------------------------------------------------------------------------
-- 4. Compression Function & Main Loop
--------------------------------------------------------------------------------

-- | Processes a single 64-byte block, updating the internal 8-word hash state.
compressBlock
  :: (Word32, Word32, Word32, Word32, Word32, Word32, Word32, Word32)
  -> BS.ByteString
  -> (Word32, Word32, Word32, Word32, Word32, Word32, Word32, Word32)
compressBlock (!h0, !h1, !h2, !h3, !h4, !h5, !h6, !h7) blockBytes =
  let wSchedule = expandSchedule (parseBlock blockBytes)
      (!a, !b, !c, !d, !e, !f, !g, !h) =
        foldl step (h0, h1, h2, h3, h4, h5, h6, h7) (zip roundConstants wSchedule)
  in (h0 + a, h1 + b, h2 + c, h3 + d, h4 + e, h5 + f, h6 + g, h7 + h)
  where
    step (!a, !b, !c, !d, !e, !f, !g, !h) (!k, !w) =
      let !t1 = h + sigmaUpper1 e + ch e f g + k + w
          !t2 = sigmaUpper0 a + maj a b c
      in (t1 + t2, a, b, c, d + t1, e, f, g)

-- | Computes the raw 8-word SHA-256 state from lazy byte stream.
hashByteString :: BL.ByteString -> (Word32, Word32, Word32, Word32, Word32, Word32, Word32, Word32)
hashByteString lazyBytes =
  let chunks = splitBlocks (BL.toStrict lazyBytes)
  in foldl compressBlock initialHash chunks
  where
    splitBlocks bs
      | BS.null bs = []
      | otherwise  = BS.take 64 bs : splitBlocks (BS.drop 64 bs)

-- | Formats an 8-word hash state into a 64-character lowercase hexadecimal string.
formatDigest :: (Word32, Word32, Word32, Word32, Word32, Word32, Word32, Word32) -> Text
formatDigest (h0, h1, h2, h3, h4, h5, h6, h7) =
  T.pack $ concatMap padHex [h0, h1, h2, h3, h4, h5, h6, h7]
  where
    padHex w =
      let s = showHex w ""
      in replicate (8 - length s) '0' ++ s

--------------------------------------------------------------------------------
-- 5. Public API
--------------------------------------------------------------------------------

-- | Computes the SHA-256 hex digest of a UTF-8 'Text' string.
--
-- === Worked Example
--
-- >>> sha256Text ""
-- "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
sha256Text :: Text -> Text
sha256Text = sha256ByteString . TE.encodeUtf8

-- | Computes the SHA-256 hex digest of a strict 'BS.ByteString'.
--
-- === Worked Example
--
-- >>> sha256ByteString "hello"
-- "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
sha256ByteString :: BS.ByteString -> Text
sha256ByteString bs = formatDigest (hashByteString (padMessage bs))

-- | Computes the SHA-256 hex digest of a file on disk.
--
-- Reads the file contents strictly as binary and computes the digest.
sha256File :: FilePath -> IO Text
sha256File path = do
  content <- BS.readFile path
  pure (sha256ByteString content)
