{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE NamedFieldPuns      #-}
{-# LANGUAGE NumericUnderscores  #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}

{-# OPTIONS_GHC -w #-}
module Spec.Marlowe.AutoExecute
    ( tests
    )
where

import           Control.Exception                     (SomeException, catch)
import           Control.Monad                         (void)
import qualified Data.Map.Strict                       as Map
import           Data.Maybe                            (isJust)
import qualified Data.Text                             as T
import qualified Data.Text.IO                          as T
import           Data.Text.Lazy                        (toStrict)
import           Language.Marlowe.Analysis.FSSemantics
import           Language.Marlowe.Client
import           Language.Marlowe.Semantics
import           Language.Marlowe.Util
import           System.IO.Unsafe                      (unsafePerformIO)

import           Data.Aeson                            (decode, encode)
import           Data.Aeson.Text                       (encodeToLazyText)
import qualified Data.ByteString                       as BS
import           Data.Either                           (isRight)
import           Data.Ratio                            ((%))
import           Data.String

import qualified Codec.CBOR.Write                      as Write
import qualified Codec.Serialise                       as Serialise
import           Language.Haskell.Interpreter          (Extension (OverloadedStrings), MonadInterpreter,
                                                        OptionVal ((:=)), as, interpret, languageExtensions,
                                                        runInterpreter, set, setImports)
import           Language.Plutus.Contract.Test         as T
import qualified Language.PlutusTx.AssocMap            as AssocMap
import           Language.PlutusTx.Lattice
import qualified Plutus.Trace.Emulator                 as Trace

import qualified Language.PlutusTx.Prelude             as P
import           Ledger                                hiding (Value)
import qualified Ledger
import           Ledger.Ada                            (lovelaceValueOf)
import           Ledger.Typed.Scripts                  (scriptHash, validatorScript)
import           Spec.Marlowe.Common
import           Test.Tasty
import           Test.Tasty.HUnit
import           Test.Tasty.QuickCheck

{-# ANN module ("HLint: ignore Reduce duplication" :: String) #-}
{-# ANN module ("HLint: ignore Redundant if" :: String) #-}

tests :: TestTree
tests = testGroup "Marlowe Auto Execution"
    [ awaitUntilTimeoutTest
    , autoexecZCBTest
    , autoexecZCBTestAliceWalksAway
    , autoexecZCBTestBobWalksAway
    ]


alice, bob, carol :: Wallet
alice = Wallet 1
bob = Wallet 2
carol = Wallet 3


autoexecZCBTest :: TestTree
autoexecZCBTest = checkPredicate "ZCB Auto Execute Contract"
    (assertNoFailedTransactions
    -- /\ emulatorLog (const False) ""
    T..&&. assertNotDone (marlowePlutusContract) (Trace.walletInstanceTag alice) "contract should not have any errors"
    T..&&. assertNotDone (marlowePlutusContract) (Trace.walletInstanceTag bob) "contract should not have any errors"
    T..&&. walletFundsChange alice (lovelaceValueOf (150))
    T..&&. walletFundsChange bob (lovelaceValueOf (-150))
    ) $ do

    bobHdl <- Trace.activateContractWallet @MarloweSchema @MarloweError bob marlowePlutusContract
    aliceHdl <- Trace.activateContractWallet @MarloweSchema @MarloweError alice marlowePlutusContract

    -- Bob will wait for the contract to appear on chain
    Trace.callEndpoint_ @"auto" bobHdl (params, bobPk, contractLifespan)

    -- Init a contract
    Trace.callEndpoint_ @"create" aliceHdl (AssocMap.empty, zeroCouponBond)
    Trace.waitNSlots 1

    -- Move all Alice's money to Carol, so she can't make a payment
    Trace.payToWallet alice carol defaultLovelaceAmount
    Trace.waitNSlots 1

    Trace.callEndpoint_ @"auto" aliceHdl (params, alicePk, contractLifespan)
    Trace.waitNSlots 1

    -- Return money to Alice
    Trace.payToWallet carol alice defaultLovelaceAmount
    Trace.waitNSlots 1

    -- Now Alice should be able to retry and pay to Bob
    void $ Trace.waitNSlots 1


autoexecZCBTestAliceWalksAway :: TestTree
autoexecZCBTestAliceWalksAway = checkPredicate
    "ZCB Auto Execute Contract when Alice walks away"
    (assertNoFailedTransactions
    -- /\ emulatorLog (const False) ""
    T..&&. assertNotDone (marlowePlutusContract) (Trace.walletInstanceTag alice) "contract should not have any errors"
    T..&&. assertNotDone (marlowePlutusContract) (Trace.walletInstanceTag bob) "contract should not have any errors"
    T..&&. walletFundsChange alice (P.inv defaultLovelaceAmount)
    T..&&. walletFundsChange carol defaultLovelaceAmount
    ) $ do
    bobHdl <- Trace.activateContractWallet @MarloweSchema @MarloweError bob marlowePlutusContract
    aliceHdl <- Trace.activateContractWallet @MarloweSchema @MarloweError alice marlowePlutusContract

    -- Bob will wait for the contract to appear on chain
    Trace.callEndpoint_ @"auto" bobHdl (params, bobPk, contractLifespan)

    -- Init a contract
    Trace.callEndpoint_ @"create" aliceHdl (AssocMap.empty, zeroCouponBond)
    Trace.waitNSlots 1

    -- Move all Alice's money to Carol, so she can't make a payment
    Trace.payToWallet alice carol defaultLovelaceAmount
    Trace.waitNSlots 1

    Trace.callEndpoint_ @"auto" aliceHdl (params, alicePk, contractLifespan)
    Trace.waitNSlots 1
    Trace.waitNSlots 20
    -- Here Alice deposit timeout happened, so Bob should Close the contract
    void $ Trace.waitNSlots 1


autoexecZCBTestBobWalksAway :: TestTree
autoexecZCBTestBobWalksAway = checkPredicate
    "ZCB Auto Execute Contract when Bob walks away"
    (assertNoFailedTransactions
    -- /\ emulatorLog (const False) ""
    T..&&. assertNotDone (marlowePlutusContract) (Trace.walletInstanceTag alice) "contract should not have any errors"
    T..&&. assertNotDone (marlowePlutusContract) (Trace.walletInstanceTag bob) "contract should not have any errors"
    T..&&. walletFundsChange alice (lovelaceValueOf (-850))
    T..&&. walletFundsChange carol defaultLovelaceAmount
    ) $ do
    bobHdl <- Trace.activateContractWallet @MarloweSchema @MarloweError bob marlowePlutusContract
    aliceHdl <- Trace.activateContractWallet @MarloweSchema @MarloweError alice marlowePlutusContract

    -- Bob will wait for the contract to appear on chain
    Trace.callEndpoint_ @"auto" bobHdl (params, bobPk, contractLifespan)

    -- Init a contract
    Trace.callEndpoint_ @"create" aliceHdl (AssocMap.empty, zeroCouponBond)
    Trace.waitNSlots 1

    Trace.payToWallet bob carol defaultLovelaceAmount
    Trace.waitNSlots 1

    Trace.callEndpoint_ @"auto" aliceHdl (params, alicePk, contractLifespan)
    Trace.waitNSlots 1 -- Alice pays to Bob
    Trace.waitNSlots 15 -- Bob can't pay back
    Trace.waitNSlots 15 -- Bob can't pay back
    void $ Trace.waitNSlots 15 -- Bob can't pay back, walks away


awaitUntilTimeoutTest :: TestTree
awaitUntilTimeoutTest = checkPredicate "Party waits for contract to appear on chain until timeout"
    (assertNoFailedTransactions
    -- /\ emulatorLog (const False) ""
    T..&&. assertNotDone marlowePlutusContract (Trace.walletInstanceTag bob) "contract should close"
    ) $ do

    bobHdl <- Trace.activateContractWallet @MarloweSchema @MarloweError bob marlowePlutusContract
    aliceHdl <- Trace.activateContractWallet @MarloweSchema @MarloweError alice marlowePlutusContract

    -- Bob will wait for the contract to appear on chain
    Trace.callEndpoint_ @"auto" bobHdl (params, bobPk, contractLifespan)

    Trace.waitNSlots 15
    Trace.waitNSlots 15
    -- here Bob gets Timeout and closes the contract
    void $ Trace.waitNSlots 15

alicePk = PK $ (pubKeyHash $ walletPubKey alice)
bobPk = PK $ (pubKeyHash $ walletPubKey bob)

params = defaultMarloweParams

zeroCouponBond = When [ Case
        (Deposit alicePk alicePk ada (Constant 850))
        (Pay alicePk (Party bobPk) ada (Constant 850)
            (When
                [ Case (Deposit alicePk bobPk ada (Constant 1000)) Close] 40 Close
            ))] 20 Close

contractLifespan = contractLifespanUpperBound zeroCouponBond

defaultLovelaceAmount :: Ledger.Value
defaultLovelaceAmount = defaultDist Map.! alice
