{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE DeriveAnyClass        #-}
{-# LANGUAGE DeriveGeneric         #-}
{-# LANGUAGE DerivingVia           #-}
{-# LANGUAGE LambdaCase            #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE NoImplicitPrelude     #-}
{-# LANGUAGE OverloadedLists       #-}
{-# LANGUAGE OverloadedStrings     #-}
{-# LANGUAGE TemplateHaskell       #-}
{-# LANGUAGE TypeApplications      #-}
{-# OPTIONS_GHC -Wno-orphans #-}
-- Prevent unboxing, which the plugin can't deal with
{-# OPTIONS_GHC -fno-strictness #-}
{-# OPTIONS_GHC -fno-omit-interface-pragmas #-}
{-# OPTIONS_GHC -fno-spec-constr #-}
{-# OPTIONS_GHC -fno-specialise #-}

-- | Functions for working with 'Value'.
module Plutus.V1.Ledger.Value(
    -- ** Currency symbols
      CurrencySymbol(..)
    , currencySymbol
    , mpsSymbol
    , currencyMPSHash
    -- ** Token names
    , TokenName(..)
    , tokenName
    , toString
    -- * Asset classes
    , AssetClass(..)
    , assetClass
    , assetClassValue
    , assetClassValueOf
    -- ** Value
    , Value(..)
    , singleton
    , valueOf
    , scale
    , symbols
      -- * Partial order operations
    , geq
    , gt
    , leq
    , lt
      -- * Etc.
    , isZero
    , split
    , unionWith
    , flattenValue
    ) where

import qualified Prelude                          as Haskell

import           Codec.Serialise.Class            (Serialise)
import           Control.DeepSeq                  (NFData)
import           Control.Monad                    (guard)
import           Data.Aeson                       (FromJSON, FromJSONKey, ToJSON, ToJSONKey, (.:))
import qualified Data.Aeson                       as JSON
import qualified Data.Aeson.Extras                as JSON
import qualified Data.ByteString                  as BS
import           Data.Hashable                    (Hashable)
import qualified Data.List                        (sortBy)
import           Data.String                      (IsString (fromString))
import           Data.Text                        (Text)
import qualified Data.Text                        as Text
import qualified Data.Text.Encoding               as E
import           Data.Text.Prettyprint.Doc
import           Data.Text.Prettyprint.Doc.Extras
import           GHC.Generics                     (Generic)
import           GHC.Show                         (showList__)
import           Plutus.V1.Ledger.Bytes           (LedgerBytes (LedgerBytes))
import           Plutus.V1.Ledger.Orphans         ()
import           Plutus.V1.Ledger.Scripts
import qualified PlutusTx                         as PlutusTx
import qualified PlutusTx.AssocMap                as Map
import           PlutusTx.Lift                    (makeLift)
import qualified PlutusTx.Ord                     as Ord
import           PlutusTx.Prelude                 as PlutusTx
import           PlutusTx.These

newtype CurrencySymbol = CurrencySymbol { unCurrencySymbol :: PlutusTx.ByteString }
    deriving (IsString, Haskell.Show, Serialise, Pretty) via LedgerBytes
    deriving stock (Generic)
    deriving newtype (Haskell.Eq, Haskell.Ord, Eq, Ord, PlutusTx.IsData)
    deriving anyclass (Hashable, ToJSONKey, FromJSONKey,  NFData)

instance ToJSON CurrencySymbol where
  toJSON currencySymbol =
    JSON.object
      [ ( "unCurrencySymbol"
        , JSON.String .
          JSON.encodeByteString .
          PlutusTx.toHaskellByteString .
          unCurrencySymbol $
          currencySymbol)
      ]

instance FromJSON CurrencySymbol where
  parseJSON =
    JSON.withObject "CurrencySymbol" $ \object -> do
      raw <- object .: "unCurrencySymbol"
      bytes <- JSON.decodeByteString raw
      Haskell.pure $ CurrencySymbol $ PlutusTx.fromHaskellByteString bytes

makeLift ''CurrencySymbol

{-# INLINABLE mpsSymbol #-}
-- | The currency symbol of a monetay policy hash
mpsSymbol :: MintingPolicyHash -> CurrencySymbol
mpsSymbol (MintingPolicyHash h) = CurrencySymbol h

{-# INLINABLE currencyMPSHash #-}
-- | The minting policy hash of a currency symbol
currencyMPSHash :: CurrencySymbol -> MintingPolicyHash
currencyMPSHash (CurrencySymbol h) = MintingPolicyHash h

{-# INLINABLE currencySymbol #-}
-- | Creates `CurrencySymbol` from raw `ByteString`. Shouldn't be used with literals.
currencySymbol :: BS.ByteString -> CurrencySymbol
currencySymbol = CurrencySymbol . PlutusTx.fromHaskellByteString

-- | ByteString of a name of a token, shown as UTF-8 string when possible
newtype TokenName = TokenName { unTokenName :: PlutusTx.ByteString }
    deriving (Serialise) via LedgerBytes
    deriving stock (Generic)
    deriving newtype (Haskell.Eq, Haskell.Ord, Eq, Ord, PlutusTx.IsData)
    deriving anyclass (Hashable, NFData)
    deriving Pretty via (PrettyShow TokenName)

instance IsString TokenName where
    fromString = fromText . Text.pack

{-# INLINABLE tokenName #-}
-- | Creates `TokenName` from raw `ByteString`. Shouldn't be used with literals.
tokenName :: BS.ByteString -> TokenName
tokenName = TokenName . PlutusTx.fromHaskellByteString

fromText :: Text -> TokenName
fromText = TokenName . PlutusTx.fromHaskellByteString . E.encodeUtf8

fromTokenName :: (BS.ByteString -> r) -> (Text -> r) -> TokenName -> r
fromTokenName handleBytestring handleText (TokenName bs) = either (\_ -> handleBytestring $ PlutusTx.toHaskellByteString bs) handleText $ E.decodeUtf8' (PlutusTx.toHaskellByteString bs)

asBase16 :: BS.ByteString -> Text
asBase16 bs = Text.concat ["0x", JSON.encodeByteString bs]

quoted :: Text -> Text
quoted s = Text.concat ["\"", s, "\""]

toString :: TokenName -> Haskell.String
toString = Text.unpack . fromTokenName asBase16 id

instance Haskell.Show TokenName where
    show = Text.unpack . fromTokenName asBase16 quoted

{- note [Roundtripping token names]

How to properly roundtrip a token name that is not valid UTF-8 through PureScript
without a big rewrite of the API?
We prefix it with a zero byte so we can recognize it when we get a bytestring value back,
and we serialize it base16 encoded, with 0x in front so it will look as a hex string.
(Browsers don't render the zero byte.)
-}

instance ToJSON TokenName where
    toJSON = JSON.object . Haskell.pure . (,) "unTokenName" . JSON.toJSON .
        fromTokenName
            (\bs -> Text.cons '\NUL' (asBase16 bs))
            (\t -> case Text.take 1 t of "\NUL" -> Text.concat ["\NUL\NUL", t]; _ -> t)

instance FromJSON TokenName where
    parseJSON =
        JSON.withObject "TokenName" $ \object -> do
        raw <- object .: "unTokenName"
        fromJSONText raw
        where
            fromJSONText t = case Text.take 3 t of
                "\NUL0x"       -> either Haskell.fail (Haskell.pure . TokenName . PlutusTx.fromHaskellByteString) . JSON.tryDecode . Text.drop 3 $ t
                "\NUL\NUL\NUL" -> Haskell.pure . fromText . Text.drop 2 $ t
                _              -> Haskell.pure . fromText $ t

makeLift ''TokenName

-- | An asset class, identified by currency symbol and token name.
newtype AssetClass = AssetClass { unAssetClass :: (CurrencySymbol, TokenName) }
    deriving stock (Generic)
    deriving newtype (Haskell.Eq, Haskell.Ord, Haskell.Show, Eq, Ord, PlutusTx.IsData, Serialise)
    deriving anyclass (Hashable, NFData, ToJSON, FromJSON)
    deriving Pretty via (PrettyShow (CurrencySymbol, TokenName))

{-# INLINABLE assetClass #-}
assetClass :: CurrencySymbol -> TokenName -> AssetClass
assetClass s t = AssetClass (s, t)

makeLift ''AssetClass

-- | A cryptocurrency value. This is a map from 'CurrencySymbol's to a
-- quantity of that currency.
--
-- Operations on currencies are usually implemented /pointwise/. That is,
-- we apply the operation to the quantities for each currency in turn. So
-- when we add two 'Value's the resulting 'Value' has, for each currency,
-- the sum of the quantities of /that particular/ currency in the argument
-- 'Value'. The effect of this is that the currencies in the 'Value' are "independent",
-- and are operated on separately.
--
-- Whenever we need to get the quantity of a currency in a 'Value' where there
-- is no explicit quantity of that currency in the 'Value', then the quantity is
-- taken to be zero.
--
-- See note [Currencies] for more details.
newtype Value = Value { getValue :: Map.Map CurrencySymbol (Map.Map TokenName Integer) }
    deriving stock (Generic)
    deriving anyclass (ToJSON, FromJSON, Hashable, NFData)
    deriving newtype (Serialise, PlutusTx.IsData)
    deriving Pretty via (PrettyShow Value)

instance Haskell.Show Value where
    showsPrec d v =
        Haskell.showParen (d Haskell.== 11) $
            Haskell.showString "Value " . (Haskell.showParen True (showsMap (showPair (showsMap Haskell.shows)) rep))
        where Value rep = normalizeValue v
              showsMap sh m = Haskell.showString "Map " . showList__ sh (Map.toList m)
              showPair s (x,y) = Haskell.showParen True $ Haskell.shows x . Haskell.showString "," . s y

normalizeValue :: Value -> Value
normalizeValue = Value . Map.fromList . sort . filterRange (/=Map.empty)
               . mapRange normalizeTokenMap . Map.toList . getValue
  where normalizeTokenMap = Map.fromList . sort . filterRange (/=0) . Map.toList
        filterRange p kvs = [(k,v) | (k,v) <- kvs, p v]
        mapRange f xys = [(x,f y) | (x,y) <- xys]
        sort xs = Data.List.sortBy compare xs

-- Orphan instances for 'Map' to make this work
instance (ToJSON v, ToJSON k) => ToJSON (Map.Map k v) where
    toJSON = JSON.toJSON . Map.toList

instance (FromJSON v, FromJSON k) => FromJSON (Map.Map k v) where
    parseJSON v = Map.fromList Haskell.<$> JSON.parseJSON v

deriving anyclass instance (Hashable k, Hashable v) => Hashable (Map.Map k v)
deriving anyclass instance (Serialise k, Serialise v) => Serialise (Map.Map k v)

makeLift ''Value

instance Haskell.Eq Value where
    (==) = eq

instance Eq Value where
    {-# INLINABLE (==) #-}
    (==) = eq

-- No 'Ord Value' instance since 'Value' is only a partial order, so 'compare' can't
-- do the right thing in some cases.

instance Haskell.Semigroup Value where
    (<>) = unionWith (+)

instance Semigroup Value where
    {-# INLINABLE (<>) #-}
    (<>) = unionWith (+)

instance Haskell.Monoid Value where
    mempty = Value Map.empty

instance Monoid Value where
    {-# INLINABLE mempty #-}
    mempty = Value Map.empty

instance Group Value where
    {-# INLINABLE inv #-}
    inv = scale @Integer @Value (-1)

deriving via (Additive Value) instance AdditiveSemigroup Value
deriving via (Additive Value) instance AdditiveMonoid Value
deriving via (Additive Value) instance AdditiveGroup Value

instance Module Integer Value where
    {-# INLINABLE scale #-}
    scale i (Value xs) = Value (fmap (fmap (\i' -> i * i')) xs)

instance JoinSemiLattice Value where
    {-# INLINABLE (\/) #-}
    (\/) = unionWith Ord.max

instance MeetSemiLattice Value where
    {-# INLINABLE (/\) #-}
    (/\) = unionWith Ord.min

{- note [Currencies]

The 'Value' type represents a collection of amounts of different currencies.

We can think of 'Value' as a vector space whose dimensions are
currencies. At the moment there is only a single currency (Ada), so 'Value'
contains one-dimensional vectors. When currency-creating transactions are
implemented, this will change and the definition of 'Value' will change to a
'Map Currency Int', effectively a vector with infinitely many dimensions whose
non-zero values are recorded in the map.

To create a value of 'Value', we need to specifiy a currency. This can be done
using 'Ledger.Ada.adaValueOf'. To get the ada dimension of 'Value' we use
'Ledger.Ada.fromValue'. Plutus contract authors will be able to define modules
similar to 'Ledger.Ada' for their own currencies.

-}

{-# INLINABLE valueOf #-}
-- | Get the quantity of the given currency in the 'Value'.
valueOf :: Value -> CurrencySymbol -> TokenName -> Integer
valueOf (Value mp) cur tn =
    case Map.lookup cur mp of
        Nothing -> 0 :: Integer
        Just i  -> case Map.lookup tn i of
            Nothing -> 0
            Just v  -> v

{-# INLINABLE symbols #-}
-- | The list of 'CurrencySymbol's of a 'Value'.
symbols :: Value -> [CurrencySymbol]
symbols (Value mp) = Map.keys mp

{-# INLINABLE singleton #-}
-- | Make a 'Value' containing only the given quantity of the given currency.
singleton :: CurrencySymbol -> TokenName -> Integer -> Value
singleton c tn i = Value (Map.singleton c (Map.singleton tn i))

{-# INLINABLE assetClassValue #-}
-- | A 'Value' containing the given amount of the asset class.
assetClassValue :: AssetClass -> Integer -> Value
assetClassValue (AssetClass (c, t)) i = singleton c t i

{-# INLINABLE assetClassValueOf #-}
-- | Get the quantity of the given 'AssetClass' class in the 'Value'.
assetClassValueOf :: Value -> AssetClass -> Integer
assetClassValueOf v (AssetClass (c, t)) = valueOf v c t

{-# INLINABLE unionVal #-}
-- | Combine two 'Value' maps
unionVal :: Value -> Value -> Map.Map CurrencySymbol (Map.Map TokenName (These Integer Integer))
unionVal (Value l) (Value r) =
    let
        combined = Map.union l r
        unThese k = case k of
            This a    -> This <$> a
            That b    -> That <$> b
            These a b -> Map.union a b
    in unThese <$> combined

{-# INLINABLE unionWith #-}
unionWith :: (Integer -> Integer -> Integer) -> Value -> Value -> Value
unionWith f ls rs =
    let
        combined = unionVal ls rs
        unThese k' = case k' of
            This a    -> f a 0
            That b    -> f 0 b
            These a b -> f a b
    in Value (fmap (fmap unThese) combined)

{-# INLINABLE flattenValue #-}
-- | Convert a value to a simple list, keeping only the non-zero amounts.
flattenValue :: Value -> [(CurrencySymbol, TokenName, Integer)]
flattenValue v = do
    (cs, m) <- Map.toList $ getValue v
    (tn, a) <- Map.toList m
    guard $ a /= 0
    return (cs, tn, a)

-- Num operations

{-# INLINABLE isZero #-}
-- | Check whether a 'Value' is zero.
isZero :: Value -> Bool
isZero (Value xs) = Map.all (Map.all (\i -> 0 == i)) xs

{-# INLINABLE checkPred #-}
checkPred :: (These Integer Integer -> Bool) -> Value -> Value -> Bool
checkPred f l r =
    let
      inner :: Map.Map TokenName (These Integer Integer) -> Bool
      inner = Map.all f
    in
      Map.all inner (unionVal l r)

{-# INLINABLE checkBinRel #-}
-- | Check whether a binary relation holds for value pairs of two 'Value' maps,
--   supplying 0 where a key is only present in one of them.
checkBinRel :: (Integer -> Integer -> Bool) -> Value -> Value -> Bool
checkBinRel f l r =
    let
        unThese k' = case k' of
            This a    -> f a 0
            That b    -> f 0 b
            These a b -> f a b
    in checkPred unThese l r

{-# INLINABLE geq #-}
-- | Check whether one 'Value' is greater than or equal to another. See 'Value' for an explanation of how operations on 'Value's work.
geq :: Value -> Value -> Bool
-- If both are zero then checkBinRel will be vacuously true, but this is fine.
geq = checkBinRel (>=)

{-# INLINABLE gt #-}
-- | Check whether one 'Value' is strictly greater than another. See 'Value' for an explanation of how operations on 'Value's work.
gt :: Value -> Value -> Bool
-- If both are zero then checkBinRel will be vacuously true. So we have a special case.
gt l r = not (isZero l && isZero r) && checkBinRel (>) l r

{-# INLINABLE leq #-}
-- | Check whether one 'Value' is less than or equal to another. See 'Value' for an explanation of how operations on 'Value's work.
leq :: Value -> Value -> Bool
-- If both are zero then checkBinRel will be vacuously true, but this is fine.
leq = checkBinRel (<=)

{-# INLINABLE lt #-}
-- | Check whether one 'Value' is strictly less than another. See 'Value' for an explanation of how operations on 'Value's work.
lt :: Value -> Value -> Bool
-- If both are zero then checkBinRel will be vacuously true. So we have a special case.
lt l r = not (isZero l && isZero r) && checkBinRel (<) l r

{-# INLINABLE eq #-}
-- | Check whether one 'Value' is equal to another. See 'Value' for an explanation of how operations on 'Value's work.
eq :: Value -> Value -> Bool
-- If both are zero then checkBinRel will be vacuously true, but this is fine.
eq = checkBinRel (==)

-- | Split a value into its positive and negative parts. The first element of
--   the tuple contains the negative parts of the value, the second element
--   contains the positive parts.
--
--   @negate (fst (split a)) `plus` (snd (split a)) == a@
--
{-# INLINABLE split #-}
split :: Value -> (Value, Value)
split (Value mp) = (negate (Value neg), Value pos) where
  (neg, pos) = Map.mapThese splitIntl mp

  splitIntl :: Map.Map TokenName Integer -> These (Map.Map TokenName Integer) (Map.Map TokenName Integer)
  splitIntl mp' = These l r where
    (l, r) = Map.mapThese (\i -> if i <= 0 then This i else That i) mp'
