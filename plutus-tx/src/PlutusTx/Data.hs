{-# LANGUAGE BangPatterns       #-}
{-# LANGUAGE DeriveAnyClass     #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE LambdaCase         #-}
{-# LANGUAGE MultiWayIf         #-}
{-# LANGUAGE OverloadedStrings  #-}
{-# LANGUAGE ViewPatterns       #-}

module PlutusTx.Data (Data (..)) where

import           Codec.CBOR.Decoding          (Decoder)
import qualified Codec.CBOR.Decoding          as CBOR
import qualified Codec.CBOR.Term              as CBOR
import           Codec.Serialise              (Serialise (decode, encode))
import           Codec.Serialise.Decoding     (decodeSequenceLenIndef, decodeSequenceLenN)
import           Control.DeepSeq              (NFData)
import           Control.Monad.Except
import           Data.Bifunctor               (bimap)
import qualified Data.ByteString              as BS
import           Data.Text.Prettyprint.Doc
import           GHC.Generics
import qualified PlutusTx.ByteString.Internal as PlutusTx
import           Prelude

-- | A generic "data" type.
--
-- The main constructor 'Constr' represents a datatype value in sum-of-products
-- form: @Constr i args@ represents a use of the @i@th constructor along with its arguments.
--
-- The other constructors are various primitives.
data Data =
      Constr Integer [Data]
    | Map [(Data, Data)]
    | List [Data]
    | I Integer
    | B PlutusTx.ByteString
    deriving stock (Show, Eq, Ord, Generic)
    deriving anyclass (NFData)

instance Pretty Data where
    pretty = \case
        Constr _ ds -> angles (sep (punctuate comma (fmap pretty ds)))
        Map entries -> braces (sep (punctuate comma (fmap (\(k, v) -> pretty k <> ":" <+> pretty v) entries)))
        List ds     -> brackets (sep (punctuate comma (fmap pretty ds)))
        I i         -> pretty i
        B b         -> viaShow b

{- Note [Encoding via Term]
We want to write a custom encoder/decoder for Data (i.e. not use the Generic version), but actually
doing this is a pain. So instead we go via the CBOR 'Term' representation, which lets us process a
more structured representation, which is a lot easier.
-}

instance Serialise Data where
    -- See Note [Encoding via Term]
    encode = CBOR.encodeTerm . toTerm
    decode = decodeData

{- Note [CBOR alternative tags]
We've proposed to add additional tags to the CBOR standard to cover (essentially) sum types.
This is exactly what we need to encode the 'Constr' constructor of 'Data' in an unambiguous way.

The tags aren't *quite* accepted yet, but they're clearly going to accept so we might as well
start using them.

The scheme is:
- Alternatives 0-6 -> tags 121-127
- Alternatives 7-127 -> tags 1280-1400
- Any alternatives, including those that don't fit in the above -> tag 102 followed by an integer for the actual alternative.
-}

-- | Turn Data into a CBOR Term.
toTerm :: Data -> CBOR.Term
toTerm = \case
    -- See Note [CBOR alternative tags]
    Constr i ds | 0 <= i && i < 7   -> CBOR.TTagged (fromIntegral (121 + i)) (CBOR.TList $ fmap toTerm ds)
    Constr i ds | 7 <= i && i < 128 -> CBOR.TTagged (fromIntegral (1280 + (i - 7))) (CBOR.TList $ fmap toTerm ds)
    Constr i ds | otherwise         -> CBOR.TTagged 102 (CBOR.TList $ CBOR.TInteger i : fmap toTerm ds)
    Map es                          -> CBOR.TMap (fmap (bimap toTerm toTerm) es)
    List ds                         -> CBOR.TList $ fmap toTerm ds
    I i                             -> CBOR.TInteger i
    B b                             -> CBOR.TBytes $ PlutusTx.toHaskellByteString b

{- Note [Definite and indefinite forms of CBOR]
CBOR is annoying and you can have both definite (with a fixed length) and indefinite lists, maps, etc.

So we have to be careful to handle both cases when decoding. When encoding we simply don't make
the indefinite kinds.
-}

-- | Turn a CBOR Term into Data if possible.
decodeData :: forall s. Decoder s Data
decodeData = CBOR.peekTokenType >>= \case
  CBOR.TypeUInt         -> I <$> CBOR.decodeInteger
  CBOR.TypeUInt64       -> I <$> CBOR.decodeInteger
  CBOR.TypeNInt         -> I <$> CBOR.decodeInteger
  CBOR.TypeNInt64       -> I <$> CBOR.decodeInteger
  CBOR.TypeInteger      -> decodeBoundedInteger

  CBOR.TypeBytes        -> decodeBoundedBytes
  CBOR.TypeBytesIndef   -> decodeBoundedBytes

  CBOR.TypeListLen      -> decodeList
  CBOR.TypeListLen64    -> decodeList
  CBOR.TypeListLenIndef -> decodeList

  CBOR.TypeMapLen       -> decodeMap
  CBOR.TypeMapLen64     -> decodeMap
  CBOR.TypeMapLenIndef  -> decodeMap

  CBOR.TypeTag          -> decodeConstr
  CBOR.TypeTag64        -> decodeConstr

  t                     -> fail ("Unrecognized value of type " ++ show t)

decodeBoundedInteger :: Decoder s Data
decodeBoundedInteger = do
  i <- CBOR.decodeInteger
  unless (inBounds i) $ fail "Integer exceeds 64 bytes"
  pure $ I i
  where
  bound :: Integer
  -- The maximum value of a 64 byte unsigned integer
  bound = 2 ^ (64 * 8 :: Integer) - 1
  inBounds x = (x <= bound) && (x >= -1 - bound)

decodeBoundedBytes :: Decoder s Data
decodeBoundedBytes =  do
  b <- CBOR.decodeBytes
  if BS.length b <= 64
    then pure $ B $ PlutusTx.fromHaskellByteString b
    else fail $ "ByteString exceeds 64 bytes"

decodeList :: Decoder s Data
decodeList = List <$> decodeListOf decodeData

decodeListOf :: Decoder s x -> Decoder s [x]
decodeListOf decoder = CBOR.decodeListLenOrIndef >>= \case
  Nothing -> decodeSequenceLenIndef (flip (:)) [] reverse   decoder
  Just n  -> decodeSequenceLenN     (flip (:)) [] reverse n decoder

decodeMap :: Decoder s Data
decodeMap = CBOR.decodeMapLenOrIndef >>= \case
  Nothing -> Map <$> decodeSequenceLenIndef (flip (:)) [] reverse   decodePair
  Just n  -> Map <$> decodeSequenceLenN     (flip (:)) [] reverse n decodePair
  where
  decodePair = (,) <$> decodeData <*> decodeData

-- See note [CBOR alternative tags] for the encoding scheme.
decodeConstr :: Decoder s Data
decodeConstr = CBOR.decodeTag64 >>= \case
  102 -> decodeConstrExtended
  t | 121 <= t && t < 128 ->
         Constr (fromIntegral t - 121) <$> decodeListOf decodeData
  t | 1280 <= t && t < 1401 ->
         Constr ((fromIntegral t - 1280) + 7) <$> decodeListOf decodeData
  t -> fail ("Unrecognized tag " ++ show t)
  where
  decodeConstrExtended = do
    lenOrIndef <- CBOR.decodeListLenOrIndef
    i <- CBOR.decodeWord64
    xs <- case lenOrIndef of
      Nothing -> decodeSequenceLenIndef (flip (:)) [] reverse       decodeData
      Just n  -> decodeSequenceLenN     (flip (:)) [] reverse (n-1) decodeData
    pure $ Constr (fromIntegral i) xs
