{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}
{-# OPTIONS_GHC -fplugin PlutusTx.Plugin -fplugin-opt PlutusTx.Plugin:defer-errors -fplugin-opt PlutusTx.Plugin:no-context #-}

module StdLib.Spec where

import           Common
import           Control.DeepSeq
import           Control.Exception
import           Control.Monad.IO.Class
import           Data.Ratio             ((%))
import           GHC.Real               (reduce)
import           Hedgehog               (MonadGen, Property)
import qualified Hedgehog
import qualified Hedgehog.Gen           as Gen
import qualified Hedgehog.Range         as Range
import           Lib
import           PlcTestUtils
import           Test.Tasty             (TestName)
import           Test.Tasty.Hedgehog    (testProperty)

import           PlutusTx.Data          (Data (..))
import qualified PlutusTx.Eq            as PlutusTx
import qualified PlutusTx.Ord           as PlutusTx
import qualified PlutusTx.Prelude       as PlutusTx
import qualified PlutusTx.Ratio         as Ratio

import           PlutusTx.Code
import qualified PlutusTx.Lift          as Lift
import           PlutusTx.Plugin

import           Data.Proxy

roundPlc :: CompiledCode (Ratio.Rational -> Integer)
roundPlc = plc (Proxy @"roundPlc") Ratio.round

tests :: TestNested
tests =
  testNested "StdLib"
    [ goldenUEval "ratioInterop" [ getPlc roundPlc, Lift.liftProgram (Ratio.fromGHC 3.75) ]
    , testRatioProperty "round" Ratio.round round
    , testRatioProperty "truncate" Ratio.truncate truncate
    , testRatioProperty "abs" (fmap Ratio.toGHC Ratio.abs) abs
    , pure $ testProperty "ord" testOrd
    , pure $ testProperty "divMod" testDivMod
    , pure $ testProperty "quotRem" testQuotRem
    , pure $ testProperty "reduce" testReduce
    , pure $ testProperty "Eq @Data" eqData
    , goldenPir "errorTrace" errorTrace
    ]

eitherToMaybe :: Either e a -> Maybe a
eitherToMaybe (Left _)  = Nothing
eitherToMaybe (Right x) = Just x

-- | Evaluate (deeply, to get through tuples) a value, throwing away any exception and just representing it as 'Nothing'.
tryHard :: (MonadIO m, NFData a) => a -> m (Maybe a)
tryHard a = eitherToMaybe <$> (liftIO $ try @SomeException $ evaluate $ force a)

testRatioProperty :: (Show a, Eq a) => TestName -> (Ratio.Rational -> a) -> (Rational -> a) -> TestNested
testRatioProperty nm plutusFunc ghcFunc = pure $ testProperty nm $ Hedgehog.property $ do
    rat <- Hedgehog.forAll $ Gen.realFrac_ (Range.linearFrac (-10000) 100000)
    let ghcResult = ghcFunc rat
        plutusResult = plutusFunc $ Ratio.fromGHC rat
    Hedgehog.annotateShow ghcResult
    Hedgehog.annotateShow plutusResult
    Hedgehog.assert (ghcResult == plutusResult)

testDivMod :: Property
testDivMod = Hedgehog.property $ do
    let gen = Gen.integral (Range.linear (-10000) 100000)
    (n1, n2) <- Hedgehog.forAll $ (,) <$> gen <*> gen
    ghcResult <- tryHard $ divMod n1 n2
    plutusResult <- tryHard $ Ratio.divMod n1 n2
    Hedgehog.annotateShow ghcResult
    Hedgehog.annotateShow plutusResult
    Hedgehog.assert (ghcResult == plutusResult)

testQuotRem :: Property
testQuotRem = Hedgehog.property $ do
    let gen = Gen.integral (Range.linear (-10000) 100000)
    (n1, n2) <- Hedgehog.forAll $ (,) <$> gen <*> gen
    ghcResult <- tryHard $ quotRem n1 n2
    plutusResult <- tryHard $ Ratio.quotRem n1 n2
    Hedgehog.annotateShow ghcResult
    Hedgehog.annotateShow plutusResult
    Hedgehog.assert (ghcResult == plutusResult)

testReduce :: Property
testReduce = Hedgehog.property $ do
    let gen = Gen.integral (Range.linear (-10000) 100000)
    (n1, n2) <- Hedgehog.forAll $ (,) <$> gen <*> gen
    ghcResult <- tryHard $ reduce n1 n2
    plutusResult <- tryHard $ Ratio.toGHC $ Ratio.reduce n1 n2
    Hedgehog.annotateShow ghcResult
    Hedgehog.annotateShow plutusResult
    Hedgehog.assert (ghcResult == plutusResult)

testOrd :: Property
testOrd = Hedgehog.property $ do
    let gen = Gen.integral (Range.linear (-10000) 100000)
    n1 <- Hedgehog.forAll $ (%) <$> gen <*> gen
    n2 <- Hedgehog.forAll $ (%) <$> gen <*> gen
    ghcResult <- tryHard $ n1 <= n2
    plutusResult <- tryHard $ (PlutusTx.<=) (Ratio.fromGHC n1) (Ratio.fromGHC n2)
    Hedgehog.annotateShow ghcResult
    Hedgehog.annotateShow plutusResult
    Hedgehog.assert (ghcResult == plutusResult)

eqData :: Property
eqData = Hedgehog.property $ do
    theData <- Hedgehog.forAll genData
    let ghcResult = theData == theData
        plutusResult = theData PlutusTx.== theData
    Hedgehog.annotateShow theData
    Hedgehog.assert (ghcResult && plutusResult)

genData :: MonadGen m => m Data
genData =
    let genInteger = Gen.integral (Range.linear (-10000) 100000)
        genBytes   = Gen.bytes (Range.linear 0 1000)
        genList    = Gen.list (Range.linear 0 10)
    in Gen.recursive
            Gen.choice
            [ I <$> genInteger
            , (B . PlutusTx.fromHaskellByteString) <$> genBytes
            ]
            [ Constr <$> genInteger <*> genList genData
            , Map <$> genList ((,) <$> genData <*> genData)
            , List <$> genList genData
            ]

errorTrace :: CompiledCode (Integer)
errorTrace = plc (Proxy @"errorTrace") (PlutusTx.traceError "")
