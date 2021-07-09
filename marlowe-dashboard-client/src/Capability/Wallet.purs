module Capability.Wallet
  ( class ManageWallet
  , createWallet
  , submitWalletTransaction
  , getWalletInfo
  , getWalletTotalFunds
  , signTransaction
  ) where

import Prelude
import API.Wallet as API
import AppM (AppM)
import Bridge (toBack, toFront)
import Control.Monad.Except (lift, runExceptT)
import Data.Json.JsonTuple (JsonTuple)
import Data.Map (Map)
import Halogen (HalogenM)
import Marlowe.Semantics (Assets, Slot)
import Plutus.V1.Ledger.Tx (Tx, TxOutRef, TxOutTx)
import Types (AjaxResponse)
import WalletData.Types (Wallet, WalletInfo)

-- TODO (possibly): make `AppM` a `MonadError` and remove all the `runExceptT`s
class
  Monad m <= ManageWallet m where
  createWallet :: m (AjaxResponse WalletInfo)
  submitWalletTransaction :: Wallet -> Tx -> m (AjaxResponse Unit)
  getWalletInfo :: Wallet -> m (AjaxResponse WalletInfo)
  getWalletTotalFunds :: Wallet -> m (AjaxResponse Assets)
  signTransaction :: Wallet -> Tx -> m (AjaxResponse Tx)

instance monadWalletAppM :: ManageWallet AppM where
  createWallet = map toFront $ runExceptT $ API.createWallet
  submitWalletTransaction wallet tx = runExceptT $ API.submitWalletTransaction (toBack wallet) tx
  getWalletInfo wallet = map toFront $ runExceptT $ API.getWalletInfo (toBack wallet)
  getWalletTotalFunds wallet = map toFront $ runExceptT $ API.getWalletTotalFunds (toBack wallet)
  signTransaction wallet tx = runExceptT $ API.signTransaction (toBack wallet) tx

instance monadWalletHalogenM :: ManageWallet m => ManageWallet (HalogenM state action slots msg m) where
  createWallet = lift createWallet
  submitWalletTransaction tx wallet = lift $ submitWalletTransaction tx wallet
  getWalletInfo = lift <<< getWalletInfo
  getWalletTotalFunds = lift <<< getWalletTotalFunds
  signTransaction tx wallet = lift $ signTransaction tx wallet
