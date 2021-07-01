{-# LANGUAGE LambdaCase       #-}
{-# LANGUAGE TypeApplications #-}
module Main(main) where

import qualified Codec.CBOR.FlatTerm as FlatTerm
import           Codec.Serialise     (deserialiseOrFail, serialise)
import qualified Codec.Serialise     as Serialise
import           Hedgehog            (MonadGen, Property, annotateShow, assert, forAll, property, tripping)
import qualified Hedgehog.Gen        as Gen
import qualified Hedgehog.Range      as Range
import           PlutusTx.ByteString (fromHaskellByteString)
import           PlutusTx.Data       (Data (..))
import           PlutusTx.Ratio      (Rational, denominator, numerator, (%))
import           PlutusTx.Sqrt       (Sqrt (..), isqrt, rsqrt)
import           Prelude             hiding (Rational)
import           Test.Tasty
import           Test.Tasty.Hedgehog (testProperty)

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests = testGroup "plutus-tx" [
    serdeTests
    , sqrtTests
    ]

sqrtTests :: TestTree
sqrtTests = testGroup "isqrt/rsqrt tests"
  [ testProperty "isqrt x^2 = x" isqrtRoundTrip
  , testProperty "rsqrt (a/b)^2 = integer part of a/b" rsqrtRoundTrip
  , testProperty "rsqrt (-x/b) = Imaginary" rsqrtRoundTripImaginary
  ]

rsqrtRoundTripImaginary :: Property
rsqrtRoundTripImaginary = property $ do
  let numerators   = Gen.integral (Range.linear (-100000) 0)
  let denominators = Gen.integral (Range.linear 1 100000)

  -- Note: We're using the fact that (a % -b) is reduced to (-a % b)
  -- so we only need to test those negative numbers.

  a <- forAll numerators
  b <- forAll denominators

  let x      = a % b
      decode = \case
            Imaginary -> True
            _         -> False

  assert $ decode (rsqrt x)

rsqrtRoundTrip :: Property
rsqrtRoundTrip = property $ do
  let numerators   = Gen.integral (Range.linear 0 100000)
  let denominators = Gen.integral (Range.linear 1 100000)

  a <- forAll numerators
  b <- forAll denominators

  let x = a % b
      f = square
      g = decode . rsqrt
      integerPart = a `div` b
      remainder = rem a b
      decode = \case
            Exactly       i -> i == integerPart && remainder == 0
            Approximately i -> i == integerPart && remainder > 0
            Imaginary       -> False

  assert $ g (f x)

square :: Rational -> Rational
square r =
  let
    n = numerator r
    d = denominator r
    two = 2 :: Integer
    in (n^two) % (d^two)

isqrtRoundTrip :: Property
isqrtRoundTrip = property $ do
  let positiveInteger = Gen.integral (Range.linear 0 100000)
  x' <- forAll positiveInteger
  tripping x' sq (decodeExact . isqrt)
    where
      sq x = x ^ (2 :: Integer)
      decodeExact (Exactly x) = Right x
      decodeExact s           = Left  s

serdeTests :: TestTree
serdeTests = testGroup "Data serialisation"
    [ testProperty "data round-trip" dataRoundTrip
    ]

dataRoundTrip :: Property
dataRoundTrip = property $ do
    dt :: Data <- forAll genData
    let res = deserialiseOrFail (serialise dt)
    annotateShow res

    -- Debugging info
    let ft = FlatTerm.toFlatTerm $ Serialise.encode dt
    annotateShow ft
    annotateShow $ FlatTerm.validFlatTerm ft
    assert (res == Right dt)

genData :: MonadGen m => m Data
genData =
    let st = Gen.subterm genData id
        positiveInteger = Gen.integral (Range.linear 0 100000)
        constructorArgList = Gen.list (Range.linear 0 50) st
        kvMapList = Gen.list (Range.linear 0 50) ((,) <$> st <*> st)
    in
    Gen.recursive Gen.choice
        [ I <$> Gen.integral (Range.linear (-100000) 100000)
        , (B . fromHaskellByteString) <$> Gen.bytes (Range.linear 0 64) ]
        [ Constr <$> positiveInteger <*> constructorArgList
        , List <$> constructorArgList
        , Map <$> kvMapList
        ]
