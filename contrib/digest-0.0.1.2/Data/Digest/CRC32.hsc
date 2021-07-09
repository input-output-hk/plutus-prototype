{-# LANGUAGE ForeignFunctionInterface, FlexibleInstances #-}
------------------------------------------------------------
-- |
-- Copyright    :   (c) 2008 Eugene Kirpichov
-- License      :   BSD-style
--
-- Maintainer   :   ekirpichov@gmail.com
-- Stability    :   experimental
-- Portability  :   portable (H98 + FFI)
--
-- CRC32 wrapper
--
------------------------------------------------------------

module Data.Digest.CRC32 (
    CRC32, crc32, crc32Update
) where

import Data.ByteString.Unsafe (unsafeUseAsCStringLen)
import Foreign

import qualified Data.ByteString as S
import qualified Data.ByteString.Lazy as L
import qualified Data.ByteString.Lazy.Internal as LI
import qualified System.IO.Unsafe as U

#include "zlib.h"

-- | The class of values for which CRC32 may be computed
class CRC32 a where
    -- | Compute CRC32 checksum
    crc32 :: a -> Word32
    crc32 = crc32Update 0

    -- | Given the CRC32 checksum of a string, compute CRC32 of its
    -- concatenation with another string (t.i., incrementally update 
    -- the CRC32 hash value)
    crc32Update :: Word32 -> a -> Word32

instance CRC32 S.ByteString where
    crc32Update = crc32_s_update

instance CRC32 L.ByteString where
    crc32Update = crc32_l_update

instance CRC32 [Word8] where
    crc32Update n = (crc32Update n) . L.pack


crc32_s_update :: Word32 -> S.ByteString -> Word32
crc32_s_update seed str
    | S.null str = seed
    | otherwise =
        U.unsafePerformIO $
        unsafeUseAsCStringLen str $
        \(buf, len) -> fmap fromIntegral $
            crc32_c (fromIntegral seed) (castPtr buf) (fromIntegral len)

crc32_l_update :: Word32 -> L.ByteString -> Word32
crc32_l_update = LI.foldlChunks crc32_s_update


foreign import ccall unsafe "zlib.h crc32"
    crc32_c :: #{type uLong}
            -> Ptr #{type Bytef}
            -> #{type uInt}
            -> IO #{type uLong}

