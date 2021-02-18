{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TemplateHaskell  #-}
{-# LANGUAGE TypeApplications #-}

module Spec.Game
    ( tests
    ) where

import           Control.Monad                                 (void)
import           Language.Plutus.Contract                      (Contract, ContractError)
import           Language.Plutus.Contract.Test
import qualified Language.PlutusTx                             as PlutusTx
import           Language.PlutusTx.Coordination.Contracts.Game
import qualified Language.PlutusTx.Prelude                     as PlutusTx
import           Ledger.Ada                                    (adaValueOf)
import           Plutus.Trace.Emulator                         (ContractInstanceTag)
import qualified Plutus.Trace.Emulator                         as Trace
import           Spec.Lib                                      (timesFeeAdjust)
import qualified Spec.Lib                                      as Lib
import           Test.Tasty
import qualified Test.Tasty.HUnit                              as HUnit

w1, w2 :: Wallet
w1 = Wallet 1
w2 = Wallet 2

t1, t2 :: ContractInstanceTag
t1 = Trace.walletInstanceTag w1
t2 = Trace.walletInstanceTag w2

theContract :: Contract GameSchema ContractError ()
theContract = game

tests :: TestTree
tests = testGroup "game"
    [ checkPredicate "Expose 'lock' and 'guess' endpoints"
        (endpointAvailable @"lock" theContract (Trace.walletInstanceTag w1)
        .&&. endpointAvailable @"guess" theContract  (Trace.walletInstanceTag w1))
        $ void (Trace.activateContractWallet w1 theContract)

    , checkPredicate "'lock' endpoint submits a transaction"
        (anyTx theContract (Trace.walletInstanceTag w1))
        $ do
            hdl <- Trace.activateContractWallet w1 theContract
            Trace.callEndpoint_ @"lock" hdl (LockParams "secret" (adaValueOf 10))

    , checkPredicate "'guess' endpoint is available after locking funds"
        (endpointAvailable @"guess" theContract (Trace.walletInstanceTag w2))
        lockTrace

    , checkPredicate "guess right (unlock funds)"
        (walletFundsChange w2 (1 `timesFeeAdjust` 10)
            .&&. walletFundsChange w1 (1 `timesFeeAdjust` (-10)))
        guessTrace

    , checkPredicate "guess wrong"
        (walletFundsChange w2 PlutusTx.zero
            .&&. walletFundsChange w1 (1 `timesFeeAdjust` (-10)))
        guessWrongTrace
    , Lib.goldenPir "test/Spec/game.pir" $$(PlutusTx.compile [|| validateGuess ||])
    , HUnit.testCase "script size is reasonable" (Lib.reasonable gameValidator 20000)
    ]
