{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE LambdaCase            #-}
{-# LANGUAGE NamedFieldPuns        #-}
{-# LANGUAGE OverloadedStrings     #-}
{-# LANGUAGE PartialTypeSignatures #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE TemplateHaskell       #-}
{-# LANGUAGE TypeApplications      #-}
{-# LANGUAGE TypeFamilies          #-}
{-# LANGUAGE TypeOperators         #-}
{-# OPTIONS_GHC -Wno-partial-type-signatures #-}
module Spec.Contract(tests) where

import           Control.Lens
import           Control.Monad                                 (forever, void)
import           Control.Monad.Error.Lens
import           Control.Monad.Except                          (catchError, throwError)
import           Control.Monad.Freer                           (Eff)
import           Control.Monad.Freer.Log                       (LogLevel (..))
import qualified Control.Monad.Freer.Log                       as Log
import           Test.Tasty

import           Language.Plutus.Contract                      as Con
import           Language.Plutus.Contract.Test
import           Language.Plutus.Contract.Types                (ResumableResult (..))
import           Language.Plutus.Contract.Util                 (loopM)
import qualified Language.PlutusTx                             as PlutusTx
import           Language.PlutusTx.Lattice
import           Ledger                                        (Address, PubKey, Slot)
import qualified Ledger                                        as Ledger
import qualified Ledger.Ada                                    as Ada
import qualified Ledger.Constraints                            as Constraints
import qualified Ledger.Crypto                                 as Crypto
import qualified Plutus.Trace                                  as Trace
import           Plutus.Trace.Emulator                         (ContractInstanceTag, Emulator, EmulatorTrace,
                                                                activateContract, callEndpoint, callEndpoint_)
import           Plutus.Trace.Emulator.Types                   (ContractInstanceLog (..), ContractInstanceMsg (..),
                                                                ContractInstanceState (..), UserThreadMsg (..))
import           Prelude                                       hiding (not)
import qualified Wallet.Emulator                               as EM

import qualified Language.Plutus.Contract.Effects.AwaitSlot    as AwaitSlot
import           Language.Plutus.Contract.Trace.RequestHandler (maybeToHandler)



tests :: TestTree
tests =
    let run :: Slot -> String -> TracePredicate -> EmulatorTrace () -> _
        run sl = checkPredicateOptions (defaultCheckOptions & maxSlot .~ sl & minLogLevel .~ Debug)

        check :: Slot -> String -> Contract Schema ContractError () -> _ -> _
        check sl nm contract pred = run sl nm (pred contract) (void $ activateContract w1 contract tag)

        tag :: ContractInstanceTag
        tag = "instance 1"

    in
    testGroup "contracts"
        [ check 1 "awaitSlot" (void $ awaitSlot 10) $ \con ->
            (waitingForSlot con tag 10)

        , check 1 "selectEither" (void $ selectEither (awaitSlot 10) (awaitSlot 5)) $ \con ->
            (waitingForSlot con tag 5)

        , check 1 "until" (void $ void $ awaitSlot 10 `Con.until` 5) $ \con ->
            (waitingForSlot con tag 5)

        , check 1 "both" (void $ Con.both (awaitSlot 10) (awaitSlot 20)) $ \con ->
            (waitingForSlot con tag 10)

        , check 1 "both (2)" (void $ Con.both (awaitSlot 10) (awaitSlot 20)) $ \con ->
            (waitingForSlot con tag 20)

        , check 1 "watchAddressUntil" (void $ watchAddressUntil someAddress 5) $ \con ->
            (waitingForSlot con tag 5)

        , check 1 "endpoint" (endpoint @"ep") $ \con ->
            (endpointAvailable @"ep" con tag)

        , check 1 "forever" (forever $ endpoint @"ep") $ \con ->
            (endpointAvailable @"ep" con tag)

        , let
            oneTwo :: Contract Schema ContractError Int = endpoint @"1" >> endpoint @"2" >> endpoint @"4"
            oneThree :: Contract Schema ContractError Int = endpoint @"1" >> endpoint @"3" >> endpoint @"4"
            con = void (oneTwo `select` oneThree)
          in
            run 1 "alternative"
                (endpointAvailable @"3" con tag
                    .&&. not (endpointAvailable @"2" con tag))
                $ do
                    hdl <- activateContract w1 con tag
                    callEndpoint_ @"1" hdl 1

        , let theContract :: Contract Schema ContractError () = void $ endpoint @"1" @Int >> endpoint @"2" @Int
          in run 1 "call endpoint (1)"
                (endpointAvailable @"1" theContract tag)
                (void $ activateContract w1 theContract tag)

        , let theContract :: Contract Schema ContractError () = void $ endpoint @"1" @Int >> endpoint @"2" @Int
          in run 1 "call endpoint (2)"
                (endpointAvailable @"2" theContract tag
                    .&&. not (endpointAvailable @"1" theContract tag))
                (activateContract w1 theContract tag >>= \hdl -> callEndpoint_ @"1" hdl 1)

        , let theContract :: Contract Schema ContractError () = void $ endpoint @"1" @Int >> endpoint @"2" @Int
          in run 1 "call endpoint (3)"
                (not (endpointAvailable @"2" theContract tag)
                    .&&. not (endpointAvailable @"1" theContract tag))
                (activateContract w1 theContract tag >>= \hdl -> callEndpoint_ @"1" hdl 1 >> callEndpoint_ @"2" hdl 2)

        , let theContract :: Contract Schema ContractError () = void $ endpoint @"1" @Int >> endpoint @"2" @Int
          in run 1 "call endpoint (4)"
                (endpointAvailable @"2" theContract tag
                .&&. not (endpointAvailable @"1" theContract tag))
                -- only call endpoint "1" if the previous call (to endpoint "2", which is not active) fails.
                (activateContract w1 theContract tag >>= \hdl -> callEndpoint @"2" hdl 1 >>= \case { Nothing -> pure (); Just _ -> callEndpoint_ @"1" hdl 1})

        , let theContract :: Contract Schema ContractError () = void $ submitTx mempty >> watchAddressUntil someAddress 20
          in run 1 "submit tx"
                (waitingForSlot theContract tag 20)
                (void $ activateContract w1 theContract tag)

        , let smallTx = Constraints.mustPayToPubKey (Crypto.pubKeyHash $ walletPubKey (Wallet 2)) (Ada.lovelaceValueOf 10)
              theContract :: Contract Schema ContractError () = submitTx smallTx >>= awaitTxConfirmed . Ledger.txId >> submitTx smallTx >>= awaitTxConfirmed . Ledger.txId
          in run 3 "handle several blockchain events"
                (walletFundsChange w1 (Ada.lovelaceValueOf (-20))
                    .&&. assertNoFailedTransactions
                    .&&. assertDone theContract tag (const True) "all blockchain events should be processed")
                (void $ activateContract w1 theContract tag >> Trace.waitUntilSlot 3)

        , let l = endpoint @"1" >> endpoint @"2"
              r = endpoint @"3" >> endpoint @"4"
              theContract :: Contract Schema ContractError () = void $ selectEither l r
          in run 1 "select either"
                (assertDone theContract tag (const True) "left branch should finish")
                (activateContract w1 theContract tag >>= (\hdl -> callEndpoint_ @"1" hdl 1 >> callEndpoint_ @"2" hdl 2))

        , let theContract :: Contract Schema ContractError () = void $ loopM (\_ -> Left <$> endpoint @"1" @Int) 0
          in run 1 "loopM"
                (endpointAvailable @"1" theContract tag)
                (void $ activateContract w1 theContract tag >>= \hdl -> callEndpoint @"1" hdl 1)

        , let theContract :: Contract Schema ContractError () = void $ collectUntil (+) 0 (endpoint @"1") 10
          in run 1 "collect until"
                (endpointAvailable @"1" theContract tag
                    .&&. waitingForSlot theContract tag 10)
                (activateContract w1 theContract tag >>= \hdl -> callEndpoint_ @"1" hdl 1)

        , let theContract :: Contract Schema ContractError () = void $ throwing Con._ContractError $ OtherError "error"
          in run 1 "throw an error"
                (assertContractError theContract tag (\case { OtherError "error" -> True; _ -> False}) "failed to throw error")
                (void $ activateContract w1 theContract tag)

        , run 2 "pay to wallet"
            (walletFundsChange w1 (Ada.lovelaceValueOf (-20))
                .&&. walletFundsChange w2 (Ada.lovelaceValueOf 20)
                .&&. assertNoFailedTransactions)
            (void $ Trace.payToWallet w1 w2 (Ada.lovelaceValueOf 20))

        , let theContract :: Contract Schema ContractError PubKey = ownPubKey
          in run 1 "own public key"
                (assertDone theContract tag (== (walletPubKey w2)) "should return the wallet's public key")
                (void $ activateContract w2 (void theContract) tag)

        , let payment = Constraints.mustPayToPubKey (Crypto.pubKeyHash $ walletPubKey w2) (Ada.lovelaceValueOf 10)
              theContract :: Contract Schema ContractError () = submitTx payment >>= awaitTxConfirmed . Ledger.txId
          in run 2 "await tx confirmed"
            (assertDone theContract tag (const True) "should be done")
            (activateContract w1 theContract tag >> void (Trace.waitNSlots 1))

        , run 1 "checkpoints"
            (not (endpointAvailable @"2" checkpointContract tag) .&&. (endpointAvailable @"1" checkpointContract tag))
            (void $ activateContract w1 checkpointContract tag >>= \hdl -> callEndpoint @"1" hdl 1 >> callEndpoint @"2" hdl 1)

        , run 1 "error handling & checkpoints"
            (assertDone errorContract tag (\i -> i == 11) "should finish")
            (void $ activateContract w1 (void errorContract) tag >>= \hdl -> callEndpoint @"1" hdl 1 >> callEndpoint @"2" hdl 10 >> callEndpoint @"3" hdl 11)

        , let theContract :: Contract Schema ContractError () = logInfo @String "waiting for endpoint 1" >> endpoint @"1" >>= logInfo . (<>) "Received value: " . show
              matchLogs :: [EM.EmulatorTimeEvent ContractInstanceLog] -> Bool
              matchLogs lgs =
                  case (_cilMessage . EM._eteEvent <$> lgs) of
                            [ Started, ContractLog "waiting for endpoint 1", CurrentRequests [_], ReceiveEndpointCall _, ContractLog "Received value: 27", HandledRequest _, CurrentRequests [], StoppedNoError] -> True
                            _ -> False

          in run 1 "contract logs"
                (assertInstanceLog tag matchLogs)
                (void $ activateContract w1 theContract tag >>= \hdl -> callEndpoint @"1" hdl 27)

        , let theContract :: Contract Schema ContractError () = logInfo @String "waiting for endpoint 1" >> endpoint @"1" >>= logInfo . (<>) "Received value: " . show
              matchLogs :: [EM.EmulatorTimeEvent UserThreadMsg] -> Bool
              matchLogs lgs =
                  case (EM._eteEvent <$> lgs) of
                            [ UserLog "Received contract state", UserLog "Final state: Right Nothing"] -> True
                            _                                                                          -> False

          in run 4 "contract state"
                (assertUserLog matchLogs)
                $ do
                    hdl <- Trace.activateContractWallet w1 theContract
                    Trace.waitNSlots 1
                    ContractInstanceState{instContractState=ResumableResult{_finalState}} <- Trace.getContractState hdl
                    Log.logInfo @String "Received contract state"
                    Log.logInfo @String $ "Final state: " <> show _finalState

        ]

w1 :: EM.Wallet
w1 = EM.Wallet 1

w2 :: EM.Wallet
w2 = EM.Wallet 2

checkpointContract :: Contract Schema ContractError ()
checkpointContract = void $ do
    checkpoint $ do
        endpoint @"1" @Int
        endpoint @"2" @Int
    checkpoint $ do
        endpoint @"1" @Int
        endpoint @"3" @Int

errorContract :: Contract Schema ContractError Int
errorContract = do
    catchError
        (endpoint @"1" @Int >> throwError (OtherError "something went wrong"))
        (\_ -> do { checkpoint $ endpoint @"2" @Int; endpoint @"3" @Int })

someAddress :: Address
someAddress = Ledger.scriptAddress $
    Ledger.mkValidatorScript $$(PlutusTx.compile [|| \(_ :: PlutusTx.Data) (_ :: PlutusTx.Data) (_ :: PlutusTx.Data) -> () ||])

type Schema =
    BlockchainActions
        .\/ Endpoint "1" Int
        .\/ Endpoint "2" Int
        .\/ Endpoint "3" Int
        .\/ Endpoint "4" Int
        .\/ Endpoint "ep" ()
