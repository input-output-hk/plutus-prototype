{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE LambdaCase       #-}
{-# LANGUAGE TypeApplications #-}
module Spec.RPC(tests) where

import           Control.Monad                                (void)
import           Data.Either                                  (isRight)
import           Language.Plutus.Contract
import           Language.Plutus.Contract.Test
import qualified Plutus.Trace.Emulator                        as Trace

import           Language.PlutusTx.Coordination.Contracts.RPC

import           Test.Tasty

cancelContract :: Contract AdderSchema AdderError (Either (Either CancelRPC Integer) ())
cancelContract = callAdderCancel `selectEither` respondAdder

server, client :: Wallet
server = Wallet 1
client = Wallet 2

tests :: TestTree
tests = testGroup "RPC"
    [ checkPredicate "call RPC"
        (assertDone respondAdder (Trace.walletInstanceTag server) (const True) "server not done"
        .&&. assertDone callAdder (Trace.walletInstanceTag client) (\case { (Right 4) -> True; _ -> False}) "client not done")
        $ do
            shdl <- Trace.activateContractWallet server (void respondAdder)
            chdl <- Trace.activateContractWallet client (void callAdder)
            Trace.callEndpoint_ @"serve" shdl ()
            Trace.callEndpoint_ @"target instance" chdl (Trace.chInstanceId shdl)
            void $ Trace.nextSlot

    , checkPredicate "call RPC with error"
        (assertDone cancelContract (Trace.walletInstanceTag server) isRight ""
        .&&. assertDone cancelContract (Trace.walletInstanceTag client) (\case { Left (Left CancelRPC) -> True; _ -> False}) "")
        $ do
            (shdl, chdl) <-
                (,) <$> Trace.activateContractWallet server (void cancelContract)
                    <*> Trace.activateContractWallet client (void cancelContract)
            Trace.callEndpoint_ @"serve" shdl ()
            Trace.callEndpoint_ @"target instance" chdl (Trace.chInstanceId shdl)
            void $ Trace.nextSlot
    ]
