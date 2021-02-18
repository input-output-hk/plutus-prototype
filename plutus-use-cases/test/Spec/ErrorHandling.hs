{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE LambdaCase       #-}
{-# LANGUAGE TypeApplications #-}
module Spec.ErrorHandling(tests) where

import           Control.Monad                                          (void)
import           Language.Plutus.Contract.Test

import           Language.PlutusTx.Coordination.Contracts.ErrorHandling
import qualified Plutus.Trace.Emulator                                  as Trace

import           Test.Tasty

tests :: TestTree
tests = testGroup "error handling"
    [ checkPredicate "throw an error"
        (assertContractError contract (Trace.walletInstanceTag w1) (\case { Error1 _ -> True; _ -> False}) "should throw error")
        $ do
            hdl <- Trace.activateContractWallet @_ @MyError w1 contract
            Trace.callEndpoint_ @"throwError" hdl ()
            void $ Trace.nextSlot

    , checkPredicate "catch an error"
        (assertDone @_ @MyError contract (Trace.walletInstanceTag w1) (const True) "should be done")
        $ do
            hdl <- Trace.activateContractWallet @_ @MyError w1 contract
            Trace.callEndpoint_ @"catchError" hdl ()
            void $ Trace.nextSlot

    ]

w1 :: Wallet
w1 = Wallet 1
