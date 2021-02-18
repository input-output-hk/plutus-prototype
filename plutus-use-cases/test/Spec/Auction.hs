{-# LANGUAGE DataKinds         #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications  #-}
module Spec.Auction(tests, auctionTrace1, auctionTrace2) where

import           Control.Lens
import           Control.Monad                                    (void)

import           Language.Plutus.Contract
import           Language.Plutus.Contract.Test
import           Ledger                                           (Ada, Value, pubKeyHash)
import qualified Ledger.Ada                                       as Ada

import qualified Language.Plutus.Contract.StateMachine            as SM
import           Language.PlutusTx.Coordination.Contracts.Auction
import           Language.PlutusTx.Monoid                         (inv)
import qualified Ledger.Value                                     as Value
import qualified Plutus.Trace.Emulator                            as Trace

import           Test.Tasty

tests :: TestTree
tests =
    testGroup "auction"
        [ checkPredicateOptions options "run an auction"
            (assertDone seller (Trace.walletInstanceTag w1) (const True) "seller should be done"
            .&&. assertDone buyer (Trace.walletInstanceTag w2) (const True) "buyer should be done"
            .&&. walletFundsChange w1 (Ada.toValue trace1WinningBid <> inv theToken)
            .&&. walletFundsChange w2 (inv (Ada.toValue trace1WinningBid) <> theToken))
            auctionTrace1
        , checkPredicateOptions options "run an auction with multiple bids"
            (assertDone seller (Trace.walletInstanceTag w1) (const True) "seller should be done"
            .&&. assertDone buyer (Trace.walletInstanceTag w2) (const True) "buyer should be done"
            .&&. assertDone buyer (Trace.walletInstanceTag w3) (const True) "3rd party should be done"
            .&&. walletFundsChange w1 (Ada.toValue trace2WinningBid <> inv theToken)
            .&&. walletFundsChange w2 (inv (Ada.toValue trace2WinningBid) <> theToken)
            .&&. walletFundsChange w3 mempty)
            auctionTrace2
        ]

params :: AuctionParams
params =
    AuctionParams
        { apOwner   = pubKeyHash $ walletPubKey (Wallet 1)
        , apAsset   = theToken
        , apEndTime = 100

        }

-- | The token that we are auctioning off.
theToken :: Value
theToken =
    -- "ffff" is not a valid MPS hash. But this doesn't matter because we
    -- never try to forge any value of "ffff" using a script.
    -- This currency is created by the initial transaction.
    Value.singleton "ffff" "token" 1

-- | 'CheckOptions' that inclues 'theToken' in the initial distribution of wallet 1.
options :: CheckOptions
options =
    let initialDistribution = defaultDist & over (at (Wallet 1) . _Just) ((<>) theToken)
    in defaultCheckOptions & emulatorConfig . Trace.initialChainState .~ Left initialDistribution

seller :: Contract SellerSchema SM.SMContractError ()
seller = auctionSeller (apAsset params) (apEndTime params)

buyer :: Contract BuyerSchema SM.SMContractError ()
buyer = auctionBuyer params

w1, w2, w3 :: Wallet
w1 = Wallet 1
w2 = Wallet 2
w3 = Wallet 3

trace1WinningBid :: Ada
trace1WinningBid = 50

auctionTrace1 :: Trace.EmulatorTrace ()
auctionTrace1 = do
    _ <- Trace.activateContractWallet w1 seller
    _ <- Trace.waitNSlots 1
    hdl2 <- Trace.activateContractWallet w2 buyer
    _ <- Trace.waitNSlots 1
    Trace.callEndpoint_ @"bid" hdl2 50
    void $ Trace.waitUntilSlot (succ $ succ $ apEndTime params)

trace2WinningBid :: Ada
trace2WinningBid = 70

auctionTrace2 :: Trace.EmulatorTrace ()
auctionTrace2 = do
    _ <- Trace.activateContractWallet w1 seller
    _ <- Trace.waitNSlots 1
    hdl2 <- Trace.activateContractWallet w2 buyer
    hdl3 <- Trace.activateContractWallet w3 buyer
    _ <- Trace.waitNSlots 1
    Trace.callEndpoint_ @"bid" hdl2 50
    _ <- Trace.waitNSlots 15
    Trace.callEndpoint_ @"bid" hdl3 60
    _ <- Trace.waitNSlots 35
    Trace.callEndpoint_ @"bid" hdl2 70
    void $ Trace.waitUntilSlot (succ $ succ $ apEndTime params)
