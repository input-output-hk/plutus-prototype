{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE NamedFieldPuns      #-}
{-# LANGUAGE NumericUnderscores  #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}

{-# OPTIONS_GHC -w #-}
module Spec.Marlowe.Marlowe
    ( prop_noFalsePositives, tests, prop_showWorksForContracts, prop_jsonLoops
    )
where

import           Control.Exception                     (SomeException, catch)
import           Control.Lens                          ((&), (.~))
import           Control.Monad                         (void)
import           Control.Monad.Freer                   (run)
import           Control.Monad.Freer.Error             (runError)
import qualified Data.Map.Strict                       as Map
import           Data.Maybe                            (isJust)
import qualified Data.Text                             as T
import qualified Data.Text.IO                          as T
import           Data.Text.Lazy                        (toStrict)
import           Language.Marlowe.Analysis.FSSemantics
import           Language.Marlowe.Client
import           Language.Marlowe.Semantics
import           Language.Marlowe.Util
import qualified Language.PlutusTx.AssocMap            as AssocMap
import           System.IO.Unsafe                      (unsafePerformIO)

import           Data.Aeson                            (decode, encode)
import           Data.Aeson.Text                       (encodeToLazyText)
import qualified Data.ByteString                       as BS
import           Data.Either                           (isRight)
import           Data.Ratio                            ((%))
import qualified Data.Set                              as Set
import           Data.String

import qualified Codec.CBOR.Write                      as Write
import qualified Codec.Serialise                       as Serialise
import           Language.Haskell.Interpreter          (Extension (OverloadedStrings), MonadInterpreter,
                                                        OptionVal ((:=)), as, interpret, languageExtensions,
                                                        runInterpreter, set, setImports)
import           Language.Plutus.Contract.Test         hiding ((.&&.))
import qualified Language.Plutus.Contract.Test         as T
import           Language.PlutusTx.Lattice
import qualified Plutus.Trace.Emulator                 as Trace

import qualified Language.PlutusTx.Prelude             as P
import           Ledger                                hiding (Value)
import           Ledger.Ada                            (lovelaceValueOf)
import           Ledger.Constraints.TxConstraints      (TxConstraints)
import           Ledger.Typed.Scripts                  (scriptHash, validatorScript)
import qualified Ledger.Value                          as Val
import           Spec.Marlowe.Common
import qualified Streaming.Prelude                     as S
import           Test.Tasty
import           Test.Tasty.HUnit
import           Test.Tasty.QuickCheck
import qualified Wallet.Emulator.Folds                 as Folds
import           Wallet.Emulator.Stream                (foldEmulatorStreamM, takeUntilSlot)

{-# ANN module ("HLint: ignore Reduce duplication" :: String) #-}
{-# ANN module ("HLint: ignore Redundant if" :: String) #-}

tests :: TestTree
tests = testGroup "Marlowe"
    [ testCase "Contracts with different creators have different hashes" uniqueContractHash
    , testCase "Token Show instance respects HEX and Unicode" tokenShowTest
    , testCase "Pangram Contract serializes into valid JSON" pangramContractSerialization
    , testCase "State serializes into valid JSON" stateSerialization
    , testCase "Validator size is reasonable" validatorSize
    , testCase "Mul analysis" mulAnalysisTest
    , testCase "extractContractRoles" extractContractRolesTest
    , testProperty "Value equality is reflexive, symmetric, and transitive" checkEqValue
    , testProperty "Value double negation" doubleNegation
    , testProperty "Values form abelian group" valuesFormAbelianGroup
    , testProperty "Values can be serialized to JSON" valueSerialization
    , testProperty "Scale Value multiplies by a constant rational" scaleMulTest
    , testProperty "Multiply by zero" mulTest
    , testProperty "Scale rounding" scaleRoundingTest
    , zeroCouponBondTest
    , trustFundTest
    ]


alice, bob :: Wallet
alice = Wallet 1
bob = Wallet 2


zeroCouponBondTest :: TestTree
zeroCouponBondTest = checkPredicateOptions (defaultCheckOptions & maxSlot .~ 250) "Zero Coupon Bond Contract"
    (assertNoFailedTransactions
    -- T..&&. emulatorLog (const False) ""
    T..&&. assertNotDone marlowePlutusContract (Trace.walletInstanceTag alice) "contract should close"
    T..&&. assertNotDone marlowePlutusContract (Trace.walletInstanceTag bob) "contract should close"
    T..&&. walletFundsChange alice (lovelaceValueOf (150))
    T..&&. walletFundsChange bob (lovelaceValueOf (-150))
    ) $ do
    -- Init a contract
    let alicePk = PK $ (pubKeyHash $ walletPubKey alice)
        bobPk = PK $ (pubKeyHash $ walletPubKey bob)

    let params = defaultMarloweParams

    let zeroCouponBond = When [ Case
            (Deposit alicePk alicePk ada (Constant 850))
            (Pay alicePk (Party bobPk) ada (Constant 850)
                (When
                    [ Case (Deposit alicePk bobPk ada (Constant 1000)) Close] (Slot 200) Close
                ))] (Slot 100) Close

    bobHdl <- Trace.activateContractWallet @MarloweSchema @MarloweError bob marlowePlutusContract
    aliceHdl <- Trace.activateContractWallet @MarloweSchema @MarloweError alice marlowePlutusContract

    Trace.callEndpoint_ @"create" aliceHdl (AssocMap.empty, zeroCouponBond)
    Trace.waitNSlots 2

    Trace.callEndpoint_ @"wait" bobHdl (params)

    Trace.callEndpoint_ @"apply-inputs" aliceHdl (params, [IDeposit alicePk alicePk ada 850])
    Trace.waitNSlots 2

    Trace.callEndpoint_ @"wait" aliceHdl (params)

    Trace.callEndpoint_ @"apply-inputs" bobHdl (params, [IDeposit alicePk bobPk ada 1000])
    void $ Trace.waitNSlots 2


trustFundTest :: TestTree
trustFundTest = checkPredicateOptions (defaultCheckOptions & maxSlot .~ 200) "Trust Fund Contract"
    (assertNoFailedTransactions
    -- T..&&. emulatorLog (const False) ""
    T..&&. assertNotDone marlowePlutusContract (Trace.walletInstanceTag alice) "contract should not have any errors"
    T..&&. assertNotDone marlowePlutusContract (Trace.walletInstanceTag bob) "contract should not have any errors"
    T..&&. walletFundsChange alice (lovelaceValueOf (-256) <> Val.singleton (rolesCurrency params) "alice" 1)
    T..&&. walletFundsChange bob (lovelaceValueOf 256 <> Val.singleton (rolesCurrency params) "bob" 1)
    ) $ do

    -- Init a contract
    let alicePkh = pubKeyHash $ walletPubKey alice
        bobPkh = pubKeyHash $ walletPubKey bob
    bobHdl <- Trace.activateContractWallet @MarloweSchema @MarloweError bob marlowePlutusContract
    aliceHdl <- Trace.activateContractWallet @MarloweSchema @MarloweError alice marlowePlutusContract

    Trace.callEndpoint_ @"create" aliceHdl
        (AssocMap.fromList [("alice", alicePkh), ("bob", bobPkh)],
        contract)
    Trace.waitNSlots 5

    Trace.callEndpoint_ @"wait" bobHdl (params)

    Trace.callEndpoint_ @"apply-inputs" aliceHdl (params,
        [ IChoice chId 256
        , IDeposit "alice" "alice" ada 256
        ])
    Trace.waitNSlots 17

    Trace.callEndpoint_ @"wait" aliceHdl (params)

    Trace.callEndpoint_ @"apply-inputs" bobHdl (params, [INotify])

    Trace.waitNSlots 2
    Trace.callEndpoint_ @"redeem" bobHdl (params, "bob", bobPkh)
    void $ Trace.waitNSlots 2
    where
        alicePk = PK $ pubKeyHash $ walletPubKey alice
        bobPk = PK $ pubKeyHash $ walletPubKey bob
        chId = ChoiceId "1" alicePk

        contract = When [
            Case (Choice chId [Bound 10 1500])
                (When [Case
                    (Deposit "alice" "alice" ada (ChoiceValue chId))
                        (When [Case (Notify (SlotIntervalStart `ValueGE` Constant 15))
                            (Pay "alice" (Party "bob") ada
                                (ChoiceValue chId) Close)]
                        (Slot 40) Close)
                    ] (Slot 30) Close)
            ] (Slot 20) Close
        (params, (_ :: TxConstraints MarloweInput MarloweData)) =
            let con = setupMarloweParams @MarloweSchema @MarloweError
                        (AssocMap.fromList [("alice", pubKeyHash $ walletPubKey alice), ("bob", pubKeyHash $ walletPubKey bob)])
                        contract
                fld = Folds.instanceOutcome con (Trace.walletInstanceTag alice)
                getOutcome (Done a) = a
                getOutcome e        = error $ "not finished: " <> show e
            in either (error . show) (getOutcome . S.fst')
                    $ run
                    $ runError @Folds.EmulatorFoldErr
                    $ foldEmulatorStreamM fld
                    $ Trace.runEmulatorStream Trace.defaultEmulatorConfig
                    $ do
                        void $ Trace.activateContractWallet @MarloweSchema @MarloweError alice (void con)
                        Trace.waitNSlots 10


uniqueContractHash :: IO ()
uniqueContractHash = do
    let params cs = MarloweParams
            { rolesCurrency = cs
            , rolePayoutValidatorHash = validatorHash (rolePayoutScript cs) }

    let hash1 = scriptHash $ scriptInstance (params "11")
    let hash2 = scriptHash $ scriptInstance (params "22")
    let hash3 = scriptHash $ scriptInstance (params "22")
    assertBool "Hashes must be different" (hash1 /= hash2)
    assertBool "Hashes must be same" (hash2 == hash3)


validatorSize :: IO ()
validatorSize = do
    let validator = validatorScript $ scriptInstance defaultMarloweParams
    let vsize = BS.length $ Write.toStrictByteString (Serialise.encode validator)
    assertBool ("Validator is too large " <> show vsize) (vsize < 1100000)


extractContractRolesTest :: IO ()
extractContractRolesTest = do
    extractContractRoles Close @=? mempty
    extractContractRoles
        (Pay (Role "Alice") (Party (Role "Bob")) ada (Constant 1) Close)
            @=? Set.fromList ["Alice", "Bob"]
    extractContractRoles
        (When [Case (Deposit (Role "Bob") (Role "Alice") ada (Constant 10)) Close] 10 Close)
            @=? Set.fromList ["Alice", "Bob"]
    extractContractRoles
        (When [Case (Choice (ChoiceId "test" (Role "Alice")) [Bound 0 1]) Close] 10 Close)
            @=? Set.fromList ["Alice"]


checkEqValue :: Property
checkEqValue = property $ do
    let gen = do
            a <- valueGen
            b <- valueGen
            c <- valueGen
            return (a, b, c)
    forAll gen $ \(a, b, c) ->
        (a P.== a) -- reflective
            .&&. (a P.== b == b P.== a) -- symmetric
            .&&. (if a P.== b && b P.== c then a P.== c else True) -- transitive


doubleNegation :: Property
doubleNegation = property $ do
    let eval = evalValue (Environment (Slot 10, Slot 1000)) (emptyState (Slot 10))
    forAll valueGen $ \a -> eval (NegValue (NegValue a)) === eval a


valuesFormAbelianGroup :: Property
valuesFormAbelianGroup = property $ do
    let gen = do
            a <- valueGen
            b <- valueGen
            c <- valueGen
            return (a, b, c)
    let eval = evalValue (Environment (Slot 10, Slot 1000)) (emptyState (Slot 10))
    forAll gen $ \(a, b, c) ->
        -- associativity of addition
        eval (AddValue (AddValue a b) c) === eval (AddValue a (AddValue b c)) .&&.
        -- commutativity of addition
        eval (AddValue a b) === eval (AddValue b a) .&&.
        -- additive identity
        eval (AddValue a (Constant 0)) === eval a .&&.
        -- additive inverse
        eval (AddValue a (NegValue a)) === 0 .&&.
        -- substraction works
        eval (SubValue (AddValue a b) b) === eval a


scaleRoundingTest :: Property
scaleRoundingTest = property $ do
    let eval = evalValue (Environment (Slot 10, Slot 1000)) (emptyState (Slot 10))
    -- test half-even rounding
    let gen = do
            n <- amount
            d <- suchThat amount (/= 0)
            return (n, d)
    forAll gen $ \(n, d) -> eval (Scale (n P.% d) (Constant 1)) === halfAwayRound (n % d)
    where
      halfAwayRound fraction = let (n,f) = properFraction fraction in n + round (f + 1) - 1


scaleMulTest :: Property
scaleMulTest = property $ do
    let eval = evalValue (Environment (Slot 10, Slot 1000)) (emptyState (Slot 10))
    forAll valueGen $ \a ->
        eval (Scale (0 P.% 1) a) === 0 .&&. eval (Scale (1 P.% 1) a) === eval a


mulTest :: Property
mulTest = property $ do
    let eval = evalValue (Environment (Slot 10, Slot 1000)) (emptyState (Slot 10))
    forAll valueGen $ \a ->
        eval (MulValue (Constant 0) a) === 0


valueSerialization :: Property
valueSerialization = property $
    forAll valueGen $ \a ->
        let decoded :: Maybe (Value Observation)
            decoded = decode $ encode a
        in Just a === decoded


mulAnalysisTest :: IO ()
mulAnalysisTest = do
    let muliply = foldl (\a _ -> MulValue (UseValue $ ValueId "a") a) (Constant 1) [1..100]
        alicePk = PK $ pubKeyHash $ walletPubKey alice
        contract = If (muliply `ValueGE` Constant 10000) Close (Pay alicePk (Party alicePk) ada (Constant (-100)) Close)
    result <- warningsTrace contract
    --print result
    assertBool "Analysis ok" $ isRight result


pangramContractSerialization :: IO ()
pangramContractSerialization = do
    let json = toStrict (encodeToLazyText pangramContract)
    -- uncomment to generate json after updating pangramContract
    -- T.putStrLn json
    Just pangramContract @=? (decode $ encode pangramContract)
    contract <- readFile "test/contract.json"
    let decoded :: Maybe Contract
        decoded = decode (fromString contract)
    case decoded of
        Just cont -> cont @=? pangramContract
        _         -> assertFailure "Nope"


tokenShowTest :: IO ()
tokenShowTest = do
    -- SCP-834, CurrencySymbol is HEX encoded ByteString,
    -- and TokenSymbol as UTF8 encoded Unicode string
    let actual :: Value Observation
        actual = AvailableMoney (Role "alice") (Token "00010afF" "ÚSD©")

    show actual @=? "AvailableMoney \"alice\" (Token \"00010aff\" \"ÚSD©\")"


stateSerialization :: IO ()
stateSerialization = do
    state <- readFile "test/state.json"
    let decoded :: Maybe State
        decoded = decode (fromString state)
    case decoded of
        Just st ->
            case decode $ encode st of
                Just st' -> assertBool "Should be equal" (st P.== st')
                Nothing  -> assertFailure "Nope"
        Nothing -> assertFailure "Nope"

prop_showWorksForContracts :: Property
prop_showWorksForContracts = forAllShrink contractGen shrinkContract showWorksForContract


showWorksForContract :: Contract -> Property
showWorksForContract contract = unsafePerformIO $ do
  res <- runInterpreter $ setImports ["Language.Marlowe"]
                        >> set [ languageExtensions := [ OverloadedStrings ] ]
                        >> interpretContractString (show contract)
  return (case res of
            Right x  -> x === contract
            Left err -> counterexample (show err) False)


interpretContractString :: MonadInterpreter m => String -> m Contract
interpretContractString contractStr = interpret contractStr (as :: Contract)


noFalsePositivesForContract :: Contract -> Property
noFalsePositivesForContract cont =
  unsafePerformIO (do res <- catch (wrapLeft $ warningsTrace cont)
                                   (\exc -> return $ Left (Left (exc :: SomeException)))
                      return (case res of
                                Left err -> counterexample (show err) False
                                Right answer ->
                                   tabulate "Has counterexample" [show (isJust answer)]
                                   (case answer of
                                      Nothing ->
                                         tabulate "Is empty contract" [show (cont == Close)]
                                                  True
                                      Just (is, li, warns) ->
                                         counterexample ("Trace: " ++ show (is, li)) $
                                         tabulate "Number of warnings" [show (length warns)]
                                                  (warns =/= []))))


wrapLeft :: IO (Either a b) -> IO (Either (Either c a) b)
wrapLeft r = do tempRes <- r
                return (case tempRes of
                          Left x  -> Left (Right x)
                          Right y -> Right y)


prop_noFalsePositives :: Property
prop_noFalsePositives = forAllShrink contractGen shrinkContract noFalsePositivesForContract

jsonLoops :: Contract -> Property
jsonLoops cont = decode (encode cont) === Just cont

prop_jsonLoops :: Property
prop_jsonLoops = withMaxSuccess 1000 $ forAllShrink contractGen shrinkContract jsonLoops

