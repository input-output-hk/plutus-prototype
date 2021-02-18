{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE MonoLocalBinds      #-}
{-# LANGUAGE NamedFieldPuns      #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE RankNTypes          #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell     #-}
{-# LANGUAGE TypeApplications    #-}
{-# OPTIONS_GHC -fno-warn-incomplete-uni-patterns #-}
module Spec.Future(tests, theFuture, increaseMarginTrace, settleEarlyTrace, payOutTrace) where

import           Control.Monad                                   (void)
import           Test.Tasty
import qualified Test.Tasty.HUnit                                as HUnit

import qualified Spec.Lib                                        as Lib
import           Spec.TokenAccount                               (assertAccountBalance)

import qualified Ledger
import qualified Ledger.Ada                                      as Ada
import           Ledger.Crypto                                   (PrivateKey, PubKey (..))
import           Ledger.Oracle                                   (Observation (..), SignedMessage)
import qualified Ledger.Oracle                                   as Oracle
import           Ledger.Slot                                     (Slot)
import           Ledger.Value                                    (Value, scale)

import           Language.Plutus.Contract.Test
import qualified Language.PlutusTx                               as PlutusTx
import           Language.PlutusTx.Coordination.Contracts.Future (Future (..), FutureAccounts (..), FutureError,
                                                                  FutureSchema, FutureSetup (..), Role (..))
import qualified Language.PlutusTx.Coordination.Contracts.Future as F
import           Plutus.Trace.Emulator                           (ContractHandle, EmulatorTrace)
import qualified Plutus.Trace.Emulator                           as Trace

tests :: TestTree
tests =
    testGroup "futures"
    [ checkPredicate "setup tokens"
        (assertDone (F.setupTokens @FutureSchema @FutureError) (Trace.walletInstanceTag w1) (const True) "setupTokens")
        $ void F.setupTokensTrace

    , checkPredicate "can initialise and obtain tokens"
        (walletFundsChange w1 (scale (-1) (F.initialMargin theFuture) <> F.tokenFor Short F.testAccounts)
        .&&. walletFundsChange w2 (scale (-1) (F.initialMargin theFuture) <> F.tokenFor Long F.testAccounts))
        (void (initContract >> joinFuture))

    , checkPredicate "can increase margin"
        (assertAccountBalance (ftoShort F.testAccounts) (== (Ada.lovelaceValueOf 1936))
        .&&. assertAccountBalance (ftoLong F.testAccounts) (== (Ada.lovelaceValueOf 2410)))
        increaseMarginTrace

    , checkPredicate "can settle early"
        (assertAccountBalance (ftoShort F.testAccounts) (== (Ada.lovelaceValueOf 0))
        .&&. assertAccountBalance (ftoLong F.testAccounts) (== (Ada.lovelaceValueOf 4246)))
        settleEarlyTrace

     , checkPredicate "can pay out"
        (assertAccountBalance (ftoShort F.testAccounts) (== (Ada.lovelaceValueOf 1936))
        .&&. assertAccountBalance (ftoLong F.testAccounts) (== (Ada.lovelaceValueOf 2310)))
        payOutTrace

    , Lib.goldenPir "test/Spec/future.pir" $$(PlutusTx.compile [|| F.futureStateMachine ||])

    , HUnit.testCase "script size is reasonable" (Lib.reasonable (F.validator theFuture F.testAccounts) 63000)

    ]

setup :: FutureSetup
setup =
    FutureSetup
        { shortPK = walletPubKey w1
        , longPK = walletPubKey (Wallet 2)
        , contractStart = 15
        }

w1 :: Wallet
w1 = Wallet 1

w2 :: Wallet
w2 = Wallet 2

-- | A futures contract over 187 units with a forward price of 1233 Lovelace,
--   due at slot #100.
theFuture :: Future
theFuture = Future {
    ftDeliveryDate  = Ledger.Slot 100,
    ftUnits         = units,
    ftUnitPrice     = forwardPrice,
    ftInitialMargin = Ada.lovelaceValueOf 800,
    ftPriceOracle   = snd oracleKeys,
    ftMarginPenalty = penalty
    }

increaseMarginTrace :: EmulatorTrace ()
increaseMarginTrace = do
    _ <- initContract
    hdl2 <- joinFuture
    _ <- Trace.waitNSlots 20
    increaseMargin hdl2
    _ <- Trace.waitUntilSlot 100
    payOut hdl2

settleEarlyTrace :: EmulatorTrace ()
settleEarlyTrace = do
    _ <- initContract
    hdl2 <- joinFuture
    _ <- Trace.waitNSlots 20
    settleEarly hdl2

payOutTrace :: EmulatorTrace ()
payOutTrace = do
    _ <- initContract
    hdl2 <- joinFuture
    _ <- Trace.waitUntilSlot 100
    payOut hdl2

-- | After this trace, the initial margin of wallet 1, and the two tokens,
--   are locked by the contract.
initContract :: EmulatorTrace (ContractHandle FutureSchema FutureError)
initContract = do
    hdl1 <- Trace.activateContractWallet w1 (F.futureContract theFuture)
    Trace.callEndpoint_ @"initialise-future" hdl1 (setup, Short)
    _ <- Trace.waitNSlots 3
    pure hdl1

-- | Calls the "join-future" endpoint for wallet 2 and processes
--   all resulting transactions.
joinFuture :: EmulatorTrace (ContractHandle FutureSchema FutureError)
joinFuture = do
    hdl2 <- Trace.activateContractWallet w2 (F.futureContract theFuture)
    Trace.callEndpoint_ @"join-future" hdl2 (F.testAccounts, setup)
    _ <- Trace.waitNSlots 2
    pure hdl2

-- | Calls the "settle-future" endpoint for wallet 2 and processes
--   all resulting transactions.
payOut :: ContractHandle FutureSchema FutureError -> EmulatorTrace ()
payOut hdl = do
    let
        spotPrice = Ada.lovelaceValueOf 1124
        ov = mkSignedMessage (ftDeliveryDate theFuture) spotPrice
    Trace.callEndpoint_ @"settle-future" hdl ov
    void $ Trace.waitNSlots 2

-- | Margin penalty
penalty :: Value
penalty = Ada.lovelaceValueOf 1000

-- | The forward price agreed at the beginning of the contract.
forwardPrice :: Value
forwardPrice = Ada.lovelaceValueOf 1123

-- | How many units of the underlying asset are covered by the contract.
units :: Integer
units = 187

oracleKeys :: (PrivateKey, PubKey)
oracleKeys =
    let wllt = Wallet 10 in
        (walletPrivKey wllt, walletPubKey wllt)

-- | Increase the margin of the 'Long' role by 100 lovelace
increaseMargin :: ContractHandle FutureSchema FutureError -> EmulatorTrace ()
increaseMargin hdl = do
    Trace.callEndpoint_ @"increase-margin" hdl (Ada.lovelaceValueOf 100, Long)
    void $ Trace.waitNSlots 2

-- | Call 'settleEarly' with a high spot price (11240 lovelace)
settleEarly :: ContractHandle FutureSchema FutureError -> EmulatorTrace ()
settleEarly hdl = do
    let
        spotPrice = Ada.lovelaceValueOf 11240
        ov = mkSignedMessage (Ledger.Slot 25) spotPrice
    Trace.callEndpoint_ @"settle-early" hdl ov
    void $ Trace.waitNSlots 1

mkSignedMessage :: Slot -> Value -> SignedMessage (Observation Value)
mkSignedMessage sl vl = Oracle.signObservation sl vl (fst oracleKeys)
