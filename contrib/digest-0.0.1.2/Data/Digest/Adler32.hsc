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
-- Adler32 wrapper
--
------------------------------------------------------------

module Data.Digest.Adler32 (
    Adler32, adler32, adler32Update
) where

import Data.ByteString.Unsafe (unsafeUseAsCStringLen)
import Foreign

import qualified Data.ByteString as S
import qualified Data.ByteString.Lazy as L
import qualified Data.ByteString.Lazy.Internal as LI
import qualified System.IO.Unsafe as U

#include "zlib.h"

-- | The class of values for which Adler32 may be computed
class Adler32 a where
    -- | Compute Adler32 checksum
    adler32 :: a -> Word32
    adler32 = adler32Update 1

    -- | Given the Adler32 checksum of a string, compute Adler32 of its
    -- concatenation with another string (t.i., incrementally update the 
    -- Adler32 hash value).
    adler32Update :: Word32 -> a -> Word32

instance Adler32 S.ByteString where
    adler32Update = adler32_s_update

instance Adler32 L.ByteString where
    adler32Update = adler32_l_update

instance Adler32 [Word8] where
    adler32Update n = (adler32Update n) . L.pack


adler32_s_update :: Word32 -> S.ByteString -> Word32
adler32_s_update seed str
    | S.null str = seed
    | otherwise =
        U.unsafePerformIO $
        unsafeUseAsCStringLen str $
        \(buf, len) -> fmap fromIntegral $
            adler32_c (fromIntegral seed) (castPtr buf) (fromIntegral len)

adler32_l_update :: Word32 -> L.ByteString -> Word32
adler32_l_update = LI.foldlChunks adler32_s_update


foreign import ccall unsafe "zlib.h adler32"
    adler32_c :: #{type uLong}
              -> Ptr #{type Bytef}
              -> #{type uInt}
              -> IO #{type uLong}
