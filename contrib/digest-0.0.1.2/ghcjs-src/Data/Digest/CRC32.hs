module Data.Digest.CRC32 (
    CRC32, crc32, crc32Update
) where

import Data.Word

import qualified Data.ByteString as S
import qualified Data.ByteString.Lazy as L

-- | The class of values for which CRC32 may be computed
class CRC32 a where
    -- | Compute CRC32 checksum
    crc32 :: a -> Word32
    crc32 = error "no ghcjs impl"

    -- | Given the CRC32 checksum of a string, compute CRC32 of its
    -- concatenation with another string (t.i., incrementally update
    -- the CRC32 hash value)
    crc32Update :: Word32 -> a -> Word32

instance CRC32 S.ByteString where
    crc32Update = error "no ghcjs impl"

instance CRC32 L.ByteString where
    crc32Update = error "no ghcjs impl"

-- instance CRC32 [Word8] where
--     crc32Update n = error "no ghcjs impl"