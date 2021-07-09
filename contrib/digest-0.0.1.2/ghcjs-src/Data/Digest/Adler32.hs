module Data.Digest.Adler32 (
    Adler32, adler32, adler32Update
) where

import Data.Word

import qualified Data.ByteString as S
import qualified Data.ByteString.Lazy as L
-- import qualified Data.ByteString.Lazy.Internal as LI
-- import qualified System.IO.Unsafe as U

class Adler32 a where
    -- | Compute Adler32 checksum
    adler32 :: a -> Word32
    adler32 = error "no ghcjs impl"

    -- | Given the Adler32 checksum of a string, compute Adler32 of its
    -- concatenation with another string (t.i., incrementally update the
    -- Adler32 hash value).
    adler32Update :: Word32 -> a -> Word32

instance Adler32 S.ByteString where
    adler32Update = error "no ghcjs impl"

instance Adler32 L.ByteString where
    adler32Update = error "no ghcjs impl"

-- instance Adler32 [Word8] where
--     adler32Update n = error "no ghcjs impl"