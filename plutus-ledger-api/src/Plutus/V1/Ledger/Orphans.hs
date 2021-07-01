{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE TypeApplications  #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}

module Plutus.V1.Ledger.Orphans where

import           Codec.Serialise.Class (Serialise, decode, encode)
import           Crypto.Hash           (Digest, SHA256, digestFromByteString)
import           Data.Aeson            (FromJSON (parseJSON), ToJSON (toJSON))
import qualified Data.Aeson            as JSON
import qualified Data.Aeson.Extras     as JSON
import qualified Data.ByteArray        as BA
import qualified Data.ByteString       as BSS
import qualified PlutusTx.ByteString   as PlutusTx


{- Note [Serialising Digests from Crypto.Hash]
This is more complicated than you might expect.  If you say
`encode = encode . BA.unpack` then the contents of the digest are
unpacked into a `Word8` list with 32 entries.  However, when cborg
serialises a list, every element in the output is preceded by a type
tag (in this case, 24), and this means that the serialised version is
about 64 bytes long, twice the length of the original data.  Packing
the `Word8` list into a `ByteString` first fixes this because cborg
just serialises it as a sequence of contiguous bytes. -}

instance Serialise (Digest SHA256) where
    encode = encode . BSS.pack . BA.unpack
    decode = do
      d :: BSS.ByteString <- decode
      let bs :: BA.Bytes = BA.pack . BSS.unpack $ d
      case digestFromByteString bs of
        Nothing -> fail $ "Couldn't decode SHA256 Digest: " ++ show d
        Just v  -> pure v

instance ToJSON (Digest SHA256) where
    toJSON = JSON.String . JSON.encodeSerialise

instance FromJSON (Digest SHA256) where
    parseJSON = JSON.decodeSerialise

instance ToJSON BSS.ByteString where
    toJSON = JSON.String . JSON.encodeByteString

instance FromJSON BSS.ByteString where
    parseJSON v = JSON.decodeByteString v

instance ToJSON PlutusTx.ByteString where
    toJSON = JSON.String . JSON.encodeByteString . PlutusTx.toHaskellByteString

instance FromJSON PlutusTx.ByteString where
    parseJSON v = PlutusTx.fromHaskellByteString <$> JSON.decodeByteString v
