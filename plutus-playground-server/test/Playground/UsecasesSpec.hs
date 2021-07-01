{-# LANGUAGE NamedFieldPuns     #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings  #-}
{-# LANGUAGE RecordWildCards    #-}
{-# OPTIONS_GHC -fno-ignore-interface-pragmas #-}

module Playground.UsecasesSpec
    ( tests
    ) where

import           Control.Monad                (unless)
import           Control.Monad.Except         (runExceptT)
import           Control.Monad.Except.Extras  (mapError)
import           Control.Newtype.Generics     (over)
import           Crowdfunding                 (Contribution (Contribution), contribValue)
import           Data.Aeson                   (ToJSON)
import qualified Data.Aeson                   as JSON
import qualified Data.Aeson.Text              as JSON
import           Data.Foldable                (traverse_)
import           Data.List                    (isPrefixOf)
import           Data.List.NonEmpty           (NonEmpty ((:|)))
import           Data.Maybe                   (fromMaybe)
import qualified Data.Text                    as Text
import qualified Data.Text.IO                 as Text
import qualified Data.Text.Lazy               as TL
import           Data.Time.Units              (Minute)
import           Game                         (GuessParams (GuessParams), LockParams (LockParams), amount, guessWord,
                                               secretWord)
import qualified Interpreter                  as Webghc
import           Language.Haskell.Interpreter (InterpreterError, InterpreterResult (InterpreterResult, result),
                                               SourceCode (SourceCode))
import           Ledger.Ada                   (adaValueOf, lovelaceValueOf)
import           Ledger.Blockchain            (OnChainTx (..))
import           Ledger.Value                 (Value)
import qualified Playground.Interpreter       as PI
import           Playground.Types             (CompilationResult (CompilationResult),
                                               ContractCall (AddBlocks, AddBlocksUntil, CallEndpoint, PayToWallet),
                                               Evaluation (Evaluation), EvaluationResult (EvaluationResult), Expression,
                                               FunctionSchema (FunctionSchema), KnownCurrency (KnownCurrency),
                                               PlaygroundError (InterpreterError), SimulatorWallet (SimulatorWallet),
                                               adaCurrency, argument, argumentValues, caller, emulatorLog,
                                               endpointDescription, feesDistribution, fundsDistribution, program,
                                               resultRollup, simulatorWalletBalance, simulatorWalletWallet, sourceCode,
                                               walletKeys, wallets)
import           Playground.Usecases          (crowdFunding, errorHandling, game, vesting)
import           Schema                       (FormSchema (FormSchemaUnit, FormSchemaValue))
import           System.Environment           (lookupEnv)
import           Test.Tasty                   (TestTree, testGroup)
import           Test.Tasty.HUnit             (Assertion, assertBool, assertEqual, assertFailure, testCase)
import           Wallet.Emulator.Types        (Wallet (Wallet))
import           Wallet.Rollup.Render         (showBlockchain)
import           Wallet.Rollup.Types          (AnnotatedTx (..))
import           Wallet.Types                 (EndpointDescription (EndpointDescription))

tests :: TestTree
tests =
    testGroup
        "Playground.Usecases"
        [ runningInNixBuildTest
        , vestingTest
        , gameTest
        , errorHandlingTest
        , crowdfundingTest
        , knownCurrencyTest
        ]

maxInterpretationTime :: Minute
maxInterpretationTime = 2

w1, w2, w3, w4, w5 :: Wallet
w1 = Wallet 1

w2 = Wallet 2

w3 = Wallet 3

w4 = Wallet 4

w5 = Wallet 5

mkSimulatorWallet :: Wallet -> Value -> SimulatorWallet
mkSimulatorWallet simulatorWalletWallet simulatorWalletBalance =
    SimulatorWallet {..}

--  Unfortunately it's currently not possible to get these tests to work outside of a nix build.
--  Running `cabal test` will yield a lot of import errors because of missing modules.
runningInNixBuildTest :: TestTree
runningInNixBuildTest =
    testGroup
        "nixBuild"
        [ testCase "needs to be executed via nix-build" $ do
            nixBuildTop <- fromMaybe "" <$> lookupEnv "NIX_BUILD_TOP"
            assertBool "UsecasesSpec will only work when executed as part of a nix build" (nixBuildTop == "/build" || "/private/tmp/nix-build" `isPrefixOf` nixBuildTop)
        ]

vestingTest :: TestTree
vestingTest =
    testGroup
        "vesting"
        [ compilationChecks vesting
        , testCase "should compile with the expected schema" $ do
              Right (InterpreterResult _ (CompilationResult result _)) <-
                  compile vesting
              assertEqual
                  ""
                  [ FunctionSchema
                        { endpointDescription = EndpointDescription "retrieve funds"
                        , argument = FormSchemaValue
                        }
                  , FunctionSchema
                        { endpointDescription = EndpointDescription "vest funds"
                        , argument = FormSchemaUnit
                        }
                  ]
                  result
        , testCase "should run simple evaluation" $
          evaluate (mkEvaluation []) >>=
          hasFundsDistribution
              [ mkSimulatorWallet w1 hundredMLovelace
              , mkSimulatorWallet w2 hundredMLovelace
              ]
        , testCase "should run simple wait evaluation" $
          evaluate (mkEvaluation [AddBlocks 10]) >>=
          hasFundsDistribution
              [ mkSimulatorWallet w1 hundredMLovelace
              , mkSimulatorWallet w2 hundredMLovelace
              ]
        , testCase "should run vest funds evaluation" $
          evaluate vestFundsEval >>=
          hasFundsDistribution
              [ mkSimulatorWallet w1 hundredMLovelace
              , mkSimulatorWallet w2 $ lovelaceValueOf 20_000_000
              ]
        , testCase "should run vest and a partial retrieve of funds" $
          evaluate vestAndPartialRetrieveEval >>=
          hasFundsDistribution
              [ mkSimulatorWallet w1 $ lovelaceValueOf 150_000_000
              , mkSimulatorWallet w2 $ lovelaceValueOf 20_000_000
              ]
        , testCase "should run vest and a full retrieve of funds" $
          evaluate vestAndFullRetrieveEval >>=
          hasFundsDistribution
              [ mkSimulatorWallet w1 $ lovelaceValueOf 180_000_000
              , mkSimulatorWallet w2 $ lovelaceValueOf 20_000_000
              ]
        ]
  where
    hundredMLovelace = lovelaceValueOf 100_000_000
    mkEvaluation :: [Expression] -> Evaluation
    mkEvaluation expressions =
        Evaluation
            { wallets =
                  [ mkSimulatorWallet w1 hundredMLovelace
                  , mkSimulatorWallet w2 hundredMLovelace
                  ]
            , sourceCode = vesting
            , program = toJSONString expressions
            }
    vestFundsEval = mkEvaluation [vestFunds w2, AddBlocks 1]
    vestAndPartialRetrieveEval =
        mkEvaluation
            [vestFunds w2, AddBlocks 20, retrieveFunds w1 50_000_000, AddBlocks 1]
    vestAndFullRetrieveEval =
        mkEvaluation
            [vestFunds w2, AddBlocks 40, retrieveFunds w1 80_000_000, AddBlocks 5]
    vestFunds caller = callEndpoint "vest funds" caller ()
    retrieveFunds caller balance =
        callEndpoint "retrieve funds" caller $ lovelaceValueOf balance

gameTest :: TestTree
gameTest =
    testGroup
        "game"
        [ compilationChecks game
        , testCase "should keep the funds" $
          evaluate (mkEvaluation [lock w2 "abcde" twoAda, AddBlocks 1, guess w1 "ade", AddBlocks 1]) >>=
          hasFundsDistribution
              [ mkSimulatorWallet w1 tenAda
              , mkSimulatorWallet w2 (adaValueOf 8)
              ]
        , testCase "should unlock the funds" $
          evaluate (mkEvaluation [lock w2 "abcde" twoAda, AddBlocks 1, guess w1 "abcde", AddBlocks 1]) >>=
          hasFundsDistribution
              [ mkSimulatorWallet w1 (adaValueOf 12)
              , mkSimulatorWallet w2 (adaValueOf 8)
              ]
        , testCase "Sequential fund transfer - PayToWallet" $
          evaluate (payAll w3 w4 w5) >>=
          hasFundsDistribution
              [ mkSimulatorWallet w3 tenAda
              , mkSimulatorWallet w4 tenAda
              , mkSimulatorWallet w5 tenAda
              ]
        , testCase "Sequential fund transfer - PayToWallet" $
          evaluate (payAll w1 w2 w3) >>=
          hasFundsDistribution
              [ mkSimulatorWallet w1 tenAda
              , mkSimulatorWallet w2 tenAda
              , mkSimulatorWallet w3 tenAda
              ]
        ]
  where
    tenAda = adaValueOf 10
    sourceCode = game
    wallets = [mkSimulatorWallet w1 tenAda, mkSimulatorWallet w2 tenAda]
    mkEvaluation :: [Expression] -> Evaluation
    mkEvaluation expressions =
        Evaluation
            {sourceCode = game, wallets, program = toJSONString expressions}
    lock caller secretWord amount =
        callEndpoint "lock" caller $ LockParams {secretWord, amount}
    guess caller guessWord =
        callEndpoint "guess" caller $ GuessParams {guessWord}
    payAll a b c =
        Evaluation
            { sourceCode
            , wallets =
                  [ mkSimulatorWallet a tenAda
                  , mkSimulatorWallet b tenAda
                  , mkSimulatorWallet c tenAda
                  ]
            , program =
                  toJSONString
                      ([ PayToWallet a b nineAda
                       , PayToWallet b c nineAda
                       , PayToWallet c a nineAda
                       ] :: [Expression])
            }
    nineAda = adaValueOf 9
    twoAda = adaValueOf 2

hasFundsDistribution ::
       [SimulatorWallet]
    -> Either PlaygroundError (InterpreterResult EvaluationResult)
    -> Assertion
hasFundsDistribution _ (Left err) = assertFailure $ show err
hasFundsDistribution requiredDistribution (Right InterpreterResult {result = EvaluationResult {..}}) = do
    let addFees fund fee = fund { simulatorWalletBalance = simulatorWalletBalance fund <> simulatorWalletBalance fee }
    let noFeesDistribution = zipWith addFees fundsDistribution feesDistribution
    unless (requiredDistribution == noFeesDistribution) $ do
        Text.putStrLn $
            either id id $ showBlockchain walletKeys $ fmap (fmap (\AnnotatedTx {tx, valid} -> if valid then Valid tx else Invalid tx)) resultRollup
        traverse_ print $ reverse emulatorLog
    assertEqual "" requiredDistribution noFeesDistribution

errorHandlingTest :: TestTree
errorHandlingTest = testGroup "errorHandling" [compilationChecks errorHandling]

crowdfundingTest :: TestTree
crowdfundingTest =
    testGroup
        "crowdfunding"
        [ compilationChecks crowdFunding
        , testCase "should run successful campaign" $
          evaluate successfulCampaign >>=
          hasFundsDistribution
              [ mkSimulatorWallet w1 $ lovelaceValueOf 600000
              , mkSimulatorWallet w2 $ lovelaceValueOf 190000
              , mkSimulatorWallet w3 $ lovelaceValueOf 200000
              , mkSimulatorWallet w4 $ lovelaceValueOf 210000
              ]
        ]
  where
    sourceCode = crowdFunding
    successfulCampaign =
        Evaluation
            { wallets =
                  [ mkSimulatorWallet w1 $ lovelaceValueOf 300000
                  , mkSimulatorWallet w2 $ lovelaceValueOf 300000
                  , mkSimulatorWallet w3 $ lovelaceValueOf 300000
                  , mkSimulatorWallet w4 $ lovelaceValueOf 300000
                  ]
            , program =
                  toJSONString
                      [ scheduleCollection w1
                      , contribute w2 $ lovelaceValueOf 110000
                      , contribute w3 $ lovelaceValueOf 100000
                      , contribute w4 $ lovelaceValueOf 90000
                      , AddBlocks 1
                      , AddBlocksUntil 40
                      , AddBlocks 1
                      ]
            , sourceCode
            }
    scheduleCollection caller = callEndpoint "schedule collection" caller ()
    contribute caller contribValue =
        callEndpoint "contribute" caller $ Contribution {contribValue}

knownCurrencyTest :: TestTree
knownCurrencyTest =
    testCase "should return registered known currencies" $ do
        currencies <- compile source
        hasKnownCurrency currencies
  where
    source =
        SourceCode $
        Text.unlines
            [ "import Playground.Contract"
            , "import Data.Text"
            , "import Data.List.NonEmpty (NonEmpty ((:|)))"
            , "import Ledger.Value (tokenName)"
            , "import Playground.Types (KnownCurrency (..))"
            , "import PlutusTx.Prelude"
            , ""
            , "myCurrency :: KnownCurrency"
            , "myCurrency = KnownCurrency \"\" \"MyCurrency\" (tokenName \"MyToken\" :| [])"
            , "$(mkKnownCurrencies ['myCurrency])"
            , ""
            , "schemas = []"
            , "iotsDefinitions = \"\""
            ]
    expectedCurrencies =
        [ adaCurrency
        , KnownCurrency
              ""
              "MyCurrency"
              ("MyToken" :| [])
        ]
    hasKnownCurrency (Right (InterpreterResult _ (CompilationResult _ currencies))) =
        assertEqual "" expectedCurrencies currencies
    hasKnownCurrency other =
        assertFailure $ "Compilation failed: " <> show other

compile ::
       SourceCode
    -> IO (Either InterpreterError (InterpreterResult CompilationResult))
compile source = runExceptT $ do
  PI.checkCode source
  result <- Webghc.compile maxInterpretationTime False $ over SourceCode PI.mkCompileScript source
  PI.getCompilationResult result

evaluate ::
       Evaluation
    -> IO (Either PlaygroundError (InterpreterResult EvaluationResult))
evaluate evaluation = runExceptT $ do
    expr <- PI.evaluationToExpr evaluation
    result <- mapError InterpreterError $ Webghc.compile maxInterpretationTime False (SourceCode expr)
    PI.decodeEvaluation result

compilationChecks :: SourceCode -> TestTree
compilationChecks source =
    testCase "should compile" $ do
        compiled <- compile source
        case compiled of
            Left err -> assertFailure $ "Compilation failed: " <> show err
            Right _  -> pure ()

-- | Encode a value in JSON, then make a JSON *string* from that
toJSONString :: ToJSON a => a -> JSON.Value
toJSONString = JSON.String . TL.toStrict . JSON.encodeToLazyText

callEndpoint :: ToJSON a => EndpointDescription -> Wallet -> a -> Expression
callEndpoint endpointDescription caller param =
    CallEndpoint
        { caller
        , argumentValues =
              FunctionSchema {endpointDescription, argument = toJSONString param}
        }
