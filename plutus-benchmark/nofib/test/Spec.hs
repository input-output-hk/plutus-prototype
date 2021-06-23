{- | Tests for the Plutus nofib benchmarks, mostly comparing the result of Plutus
evaluation with the result of Haskell evaluation. Lastpiece is currently omitted
because its memory consumption as a Plutus program is too great to allow it to
run to completion. -}

{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE PartialTypeSignatures #-}
{-# LANGUAGE TypeApplications      #-}

module Main where

import           Test.Tasty
import           Test.Tasty.HUnit
import           Test.Tasty.QuickCheck

import qualified Plutus.Benchmark.Clausify                as Clausify
import qualified Plutus.Benchmark.Knights                 as Knights
import           Plutus.Benchmark.Prime                   (Result (Composite, Prime))
import qualified Plutus.Benchmark.Prime                   as Prime
import qualified Plutus.Benchmark.Queens                  as Queens

import qualified PlutusCore                               as PLC
import           PlutusCore.Default
import qualified PlutusTx                                 as Tx
import qualified UntypedPlutusCore                        as UPLC
import           UntypedPlutusCore.Evaluation.Machine.Cek as UPLC (EvaluationResult (..), unsafeEvaluateCekNoEmit)

---------------- Evaluation ----------------

type Term = UPLC.Term UPLC.DeBruijn DefaultUni DefaultFun ()
type Term' = UPLC.Term PLC.DeBruijn DefaultUni DefaultFun ()

runCek :: Term -> EvaluationResult Term'
runCek = UPLC.unsafeEvaluateCekNoEmit PLC.defaultCekParameters

termOfHaskellValue :: Tx.Lift DefaultUni a => a -> Term
termOfHaskellValue v =
    case Tx.getPlc $ Tx.liftCode v of
      UPLC.Program _ _ term -> term

runCekWithErrMsg :: Term -> String -> IO Term'
runCekWithErrMsg term errMsg =
    case UPLC.unsafeEvaluateCekNoEmit PLC.defaultCekParameters term of
          EvaluationFailure        -> assertFailure errMsg
          EvaluationSuccess result -> pure result


{- | Evaluate a PLC term using the CEK machine and compare it with an expected
   Haskell value.  The Haskell value is lifted to a PLC term which we also
   evaluate, since lifting may produce reducible terms.  We use this for
   comparing the result of a compiled Plutus program with the value produced by
   evaluating the program as a Haskell term: this will certainly be safe for
   simple types, but it is not guaranteed that evaluation commutes with Plutus
   compilation in general. -}
runAndCheck :: Tx.Lift DefaultUni a => Term -> a -> IO ()
runAndCheck term  haskellValue = do
  result   <- runCekWithErrMsg term "CEK evaluation failed for PLC program"
  expected <- runCekWithErrMsg (termOfHaskellValue haskellValue) "CEK evaluation failed for lifted Haskell value"
  result @?= expected


---------------- Clausify ----------------

mkClausifyTest :: Clausify.StaticFormula -> IO ()
mkClausifyTest formula =
    runAndCheck (Clausify.mkClausifyTerm formula) (Clausify.runClausify formula)

testClausify :: TestTree
testClausify = testGroup "clausify"
               [ testCase "formula1" $ mkClausifyTest Clausify.F1
               , testCase "formula2" $ mkClausifyTest Clausify.F2
               , testCase "formula3" $ mkClausifyTest Clausify.F3
               , testCase "formula4" $ mkClausifyTest Clausify.F4
               , testCase "formula5" $ mkClausifyTest Clausify.F5
               ]


---------------- Knights ----------------

mkKnightsTest :: Integer -> Integer -> IO ()
mkKnightsTest depth sz  =
    runAndCheck (Knights.mkKnightsTerm depth sz) (Knights.runKnights depth sz)

testKnights :: TestTree
testKnights = testGroup "knights"  -- Odd sizes call "error" because there are no solutions
              [ testCase "depth 10, 4x4" $ mkKnightsTest 10 4
              , testCase "depth 10, 6x6" $ mkKnightsTest 10 6
              , testCase "depth 10, 8x8" $ mkKnightsTest 10 8
              , testCase "depth 100, 4x4" $ mkKnightsTest 100 4
              , testCase "depth 100, 6x6" $ mkKnightsTest 100 6
              , testCase "depth 100, 8x8" $ mkKnightsTest 100 8
              ]


---------------- Queens ----------------

mkQueensTest :: Integer -> Queens.Algorithm -> IO ()
mkQueensTest sz alg =
    runAndCheck (Queens.mkQueensTerm sz alg) (Queens.runQueens sz alg)

testQueens :: TestTree
testQueens = testGroup "queens"
             [ testGroup "4x4"
               [ testCase "Bt"    $ mkQueensTest 4 Queens.Bt
               , testCase "Bm"    $ mkQueensTest 4 Queens.Bm
               , testCase "Bjbt1" $ mkQueensTest 4 Queens.Bjbt1
               , testCase "Bjbt2" $ mkQueensTest 4 Queens.Bjbt2
               , testCase "Fc"    $ mkQueensTest 4 Queens.Fc
               ]
             , testGroup "5x5"
               [ testCase "Bt"    $ mkQueensTest 5 Queens.Bt
               , testCase "Bm"    $ mkQueensTest 5 Queens.Bm
               , testCase "Bjbt1" $ mkQueensTest 5 Queens.Bjbt1
               , testCase "Bjbt2" $ mkQueensTest 5 Queens.Bjbt2
               , testCase "Fc"    $ mkQueensTest 5 Queens.Fc
               ]
             ]


---------------- Primes ----------------

-- | Unit tests on some numbers which we know to be prime/composite, polymorphic
-- over 'test' so that we can test both Haskell and Plutus evaluation.

mkPrimalityTest :: String -> (Integer -> Prime.Result -> IO()) -> TestTree
mkPrimalityTest title test = testGroup title
             [ testCase "56123"
                   $ test 56123 Prime
             , testCase "81241579"
                   $ test 81241579 Prime
             , testCase "56123*81241579"
                   $ test (56123*81241579) Composite
             , testCase "81241579*81241579"
                   $ test (81241579*81241579) Composite
             , testCase "894781389423478364713284623422222229"
                   $ test 894781389423478364713284623422222229 Composite
             ]

-- Check that the Haskell version gives the right results
testPrimalityHs :: TestTree
testPrimalityHs = mkPrimalityTest "primality test (Haskell)"
                  (\n r -> Prime.runPrimalityTest n @?= r)

-- Check that the PLC version gives the right results
testPrimalityPlc :: TestTree
testPrimalityPlc = mkPrimalityTest "primality test (Plutus Core)"
                   (\n r -> runAndCheck (Prime.mkPrimalityTestTerm n) r)

-- QuickCheck tests on random six-digit numbers to make sure that the PLC and
-- Haskell versions give the same result.
sixDigits :: Gen Integer
sixDigits = choose (100000, 999999)

prop_primalityTest :: Integer -> Property
prop_primalityTest n =
    n >= 2 ==> (runCek $ Prime.mkPrimalityTestTerm n) === (runCek $ termOfHaskellValue (Prime.runPrimalityTest n))

testPrimalityQC :: TestTree
testPrimalityQC = testProperty "primality test (QuickCheck)" (forAll sixDigits prop_primalityTest)

---------------- Main ----------------

allTests :: TestTree
allTests =
  testGroup "plutus nofib tests"
    [ testClausify
    , testKnights
    , testPrimalityHs
    , testPrimalityPlc
    , testPrimalityQC
    , testQueens
    ]

main :: IO ()
main = defaultMain allTests
