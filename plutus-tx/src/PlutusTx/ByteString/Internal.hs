{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DerivingVia    #-}
{-# LANGUAGE TypeOperators  #-}
-- This ensures that we don't put *anything* about these functions into the interface
-- file, otherwise GHC can be clever about the ones that are always error, even though
-- they're NOINLINE!
{-# OPTIONS_GHC -O0 #-}
module PlutusTx.ByteString.Internal
  ( ByteString
  , fromHaskellByteString
  , toHaskellByteString
  , concatenate
  , takeByteString
  , dropByteString
  , emptyByteString
  , sha2_256
  , sha3_256
  , verifySignature
  , equalsByteString
  , lessThanByteString
  , greaterThanByteString
  , decodeUtf8
  , encodeUtf8
  ) where

import           Codec.Serialise
import           Control.DeepSeq          (NFData)
import qualified Crypto
import qualified Data.ByteArray           as BA
import qualified Data.ByteString          as BS
import qualified Data.ByteString.Hash     as Hash
import           Data.Hashable            (Hashable)
import           Data.Maybe               (fromMaybe)
import           GHC.Generics             (Generic)
import           PlutusTx.String.Internal as String
import           PlutusTx.Utils           (mustBeReplaced)
import           Prelude                  as Haskell

-- | An opaque type representing Plutus Core ByteStrings.
newtype ByteString = ByteString { unByteString :: BS.ByteString }
  deriving stock (Generic)
  deriving newtype (Haskell.Show, Haskell.Eq, Haskell.Ord, Haskell.Semigroup, Haskell.Monoid)
  deriving newtype (Hashable, Serialise, NFData, BA.ByteArrayAccess, BA.ByteArray)

{-# INLINABLE fromHaskellByteString #-}
fromHaskellByteString :: BS.ByteString -> ByteString
fromHaskellByteString = ByteString

{-# INLINABLE toHaskellByteString #-}
toHaskellByteString :: ByteString -> BS.ByteString
toHaskellByteString = unByteString

{-# NOINLINE concatenate #-}
-- | Concatenates two 'ByteString's.
concatenate :: ByteString -> ByteString -> ByteString
concatenate (ByteString b1) (ByteString b2) = ByteString $ BS.append b1 b2

{-# NOINLINE takeByteString #-}
-- | Returns the n length prefix of a 'ByteString'.
takeByteString :: Integer -> ByteString -> ByteString
takeByteString n (ByteString b) = ByteString $ BS.take (fromIntegral n) b

{-# NOINLINE dropByteString #-}
-- | Returns the suffix of a 'ByteString' after n elements.
dropByteString :: Integer -> ByteString -> ByteString
dropByteString n (ByteString b) = ByteString $ BS.drop (fromIntegral n) b

{-# NOINLINE emptyByteString #-}
-- | An empty 'ByteString'.
emptyByteString :: ByteString
emptyByteString = ByteString $ BS.empty

{-# NOINLINE sha2_256 #-}
-- | The SHA2-256 hash of a 'ByteString'
sha2_256 :: ByteString -> ByteString
sha2_256 (ByteString b) = ByteString $ Hash.sha2 b

{-# NOINLINE sha3_256 #-}
-- | The SHA3-256 hash of a 'ByteString'
sha3_256 :: ByteString -> ByteString
sha3_256 (ByteString b) = ByteString $ Hash.sha3 b

{-# NOINLINE verifySignature #-}
-- | Verify that the signature is a signature of the message by the public key.
verifySignature :: ByteString -> ByteString -> ByteString -> Bool
verifySignature (ByteString pubKey) (ByteString message) (ByteString signature) =
  fromMaybe False (Crypto.verifySignature pubKey message signature)

{-# NOINLINE equalsByteString #-}
-- | Check if two 'ByteString's are equal.
equalsByteString :: ByteString -> ByteString -> Bool
equalsByteString = (==)

{-# NOINLINE lessThanByteString #-}
-- | Check if one 'ByteString' is less than another.
lessThanByteString :: ByteString -> ByteString -> Bool
lessThanByteString = (<)

{-# NOINLINE greaterThanByteString #-}
-- | Check if one 'ByteString' is greater than another.
greaterThanByteString :: ByteString -> ByteString -> Bool
greaterThanByteString = (>)

{-# NOINLINE decodeUtf8 #-}
-- | Converts a ByteString to a String.
decodeUtf8 :: ByteString -> String.String
decodeUtf8 = mustBeReplaced "decodeUtf8"

{-# NOINLINE encodeUtf8 #-}
-- | Convert a String into a ByteString.
encodeUtf8 :: String.String -> ByteString
encodeUtf8 = mustBeReplaced "encodeUtf8"
