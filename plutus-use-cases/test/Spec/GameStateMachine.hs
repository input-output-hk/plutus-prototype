{-# LANGUAGE DataKinds         #-}
{-# LANGUAGE FlexibleContexts  #-}
{-# LANGUAGE MonoLocalBinds    #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell   #-}
{-# LANGUAGE TypeApplications  #-}
module Spec.GameStateMachine(tests, successTrace, successTrace2, failTrace) where

import           Test.Tasty
import qualified Test.Tasty.HUnit                                          as HUnit

import qualified Spec.Lib                                                  as Lib

import qualified Language.PlutusTx                                         as PlutusTx

import           Control.Monad                                             (void)
import           Language.Plutus.Contract.Test
import           Language.PlutusTx.Coordination.Contracts.GameStateMachine as G
import qualified Ledger.Ada                                                as Ada
import qualified Ledger.Typed.Scripts                                      as Scripts
import           Ledger.Value                                              (Value)
import           Plutus.Trace.Emulator                                     (EmulatorTrace)
import qualified Plutus.Trace.Emulator                                     as Trace
import qualified Wallet.Emulator                                           as EM

tests :: TestTree
tests =
    testGroup "state machine tests"
    [ checkPredicate "run a successful game trace"
        (walletFundsChange w2 (Ada.lovelaceValueOf 3 <> gameTokenVal)
        .&&. valueAtAddress (Scripts.scriptAddress G.scriptInstance) (Ada.lovelaceValueOf 5 ==)
        .&&. walletFundsChange w1 (Ada.lovelaceValueOf (-8)))
        successTrace

    , checkPredicate "run a 2nd successful game trace"
        (walletFundsChange w2 (Ada.lovelaceValueOf 3)
        .&&. valueAtAddress (Scripts.scriptAddress G.scriptInstance) (Ada.lovelaceValueOf 1 ==)
        .&&. walletFundsChange w1 (Ada.lovelaceValueOf (-8))
        .&&. walletFundsChange w3 (Ada.lovelaceValueOf 4 <> gameTokenVal))
        successTrace2

    , checkPredicate "run a failed trace"
        (walletFundsChange w2 gameTokenVal
        .&&. valueAtAddress (Scripts.scriptAddress G.scriptInstance) (Ada.lovelaceValueOf 8 ==)
        .&&. walletFundsChange w1 (Ada.lovelaceValueOf (-8)))
        failTrace

    , Lib.goldenPir "test/Spec/gameStateMachine.pir" $$(PlutusTx.compile [|| mkValidator ||])

    , HUnit.testCase "script size is reasonable"
        (Lib.reasonable (Scripts.validatorScript G.scriptInstance) 49000)

    ]

initialVal :: Value
initialVal = Ada.adaValueOf 10

w1 :: EM.Wallet
w1 = EM.Wallet 1

w2 :: EM.Wallet
w2 = EM.Wallet 2

w3 :: EM.Wallet
w3 = EM.Wallet 3

-- | Wallet 1 locks some funds, transfers the token to wallet 2
--   which then makes a correct guess and locks the remaining
--   funds with a new secret
successTrace :: EmulatorTrace ()
successTrace = do
    hdl <- Trace.activateContractWallet w1 G.contract
    Trace.callEndpoint_ @"lock" hdl LockArgs{lockArgsSecret="hello", lockArgsValue= Ada.lovelaceValueOf 8}
    _ <- Trace.waitNSlots 2
    _ <- Trace.payToWallet w1 w2 gameTokenVal
    _ <- Trace.waitNSlots 1
    hdl2 <- Trace.activateContractWallet w2 G.contract
    Trace.callEndpoint_ @"guess" hdl2 GuessArgs{guessArgsOldSecret="hello", guessArgsNewSecret="new secret", guessArgsValueTakenOut=Ada.lovelaceValueOf 3}
    void $ Trace.waitNSlots 1

-- | Run 'successTrace', then wallet 2 transfers the token to wallet 3, which
--   makes another correct guess
successTrace2 :: EmulatorTrace ()
successTrace2 = do
    successTrace
    _ <- Trace.payToWallet w2 w3 gameTokenVal
    _ <- Trace.waitNSlots 1
    hdl3 <- Trace.activateContractWallet w3 G.contract
    Trace.callEndpoint_ @"guess" hdl3 GuessArgs{guessArgsOldSecret="new secret", guessArgsNewSecret="hello", guessArgsValueTakenOut=Ada.lovelaceValueOf 4}
    void $ Trace.waitNSlots 1


-- | Wallet 1 locks some funds, transfers the token to wallet 2
--   which then makes a wrong guess
failTrace :: EmulatorTrace ()
failTrace = do
    hdl <- Trace.activateContractWallet w1 G.contract
    Trace.callEndpoint_ @"lock" hdl LockArgs{lockArgsSecret="hello", lockArgsValue= Ada.lovelaceValueOf 8}
    _ <- Trace.waitNSlots 2
    _ <- Trace.payToWallet w1 w2 gameTokenVal
    _ <- Trace.waitNSlots 1
    hdl2 <- Trace.activateContractWallet w2 G.contract
    _ <- Trace.callEndpoint_ @"guess" hdl2 GuessArgs{guessArgsOldSecret="hola", guessArgsNewSecret="new secret", guessArgsValueTakenOut=Ada.lovelaceValueOf 3}
    void $ Trace.waitNSlots 1

gameTokenVal :: Value
gameTokenVal =
    let sym = Scripts.monetaryPolicyHash G.scriptInstance
    in G.token sym "guess"
