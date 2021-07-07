{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs            #-}
{-# LANGUAGE LambdaCase       #-}
{-# LANGUAGE RankNTypes       #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators    #-}

module Cardano.Wallet.Client where

import           Cardano.Wallet.API          (API)
import           Cardano.Wallet.Types        (WalletInfo (..))
import           Control.Monad               (void)
import           Control.Monad.Freer
import           Control.Monad.Freer.Error   (Error, throwError)
import           Control.Monad.Freer.Reader  (Reader, ask)
import           Control.Monad.IO.Class      (MonadIO (..))
import           Data.Proxy                  (Proxy (Proxy))
import           Ledger                      (Value)
import           Ledger.Constraints.OffChain (UnbalancedTx)
import           Ledger.Tx                   (Tx)
import           Servant                     ((:<|>) (..))
import           Servant.Client              (ClientEnv, ClientError, ClientM, client, runClientM)
import           Wallet.Effects              (WalletEffect (..))
import           Wallet.Emulator.Error       (WalletAPIError)
import           Wallet.Emulator.Wallet      (Wallet (..))

createWallet :: ClientM WalletInfo
submitTxn :: Wallet -> Tx -> ClientM ()
ownPublicKey :: Wallet -> ClientM WalletInfo
balanceTx :: Wallet -> UnbalancedTx -> ClientM (Either WalletAPIError Tx)
totalFunds :: Wallet -> ClientM Value
(createWallet, submitTxn, ownPublicKey, balanceTx, totalFunds) =
  ( createWallet_
  , \(Wallet wid) tx -> void (submitTxn_ wid tx)
  , ownPublicKey_ . getWallet
  , \(Wallet w) -> balanceTx_ w
  , totalFunds_ . getWallet)
  where
    ( createWallet_
      :<|> (submitTxn_
      :<|> ownPublicKey_
      :<|> balanceTx_
      :<|> totalFunds_)) = client (Proxy @(API Integer))

handleWalletClient ::
  forall m effs.
  ( LastMember m effs
  , MonadIO m
  , Member (Error ClientError) effs
  , Member (Reader ClientEnv) effs
  )
  => Wallet
  -> WalletEffect
  ~> Eff effs
handleWalletClient wallet event = do
    clientEnv <- ask @ClientEnv
    let
        runClient :: forall a. ClientM a -> Eff effs a
        runClient a = (sendM $ liftIO $ runClientM a clientEnv) >>= either throwError pure
    case event of
        SubmitTxn t   -> runClient (submitTxn wallet t)
        OwnPubKey     -> wiPubKey <$> runClient (ownPublicKey wallet)
        BalanceTx utx -> runClient (balanceTx wallet utx)
        TotalFunds    -> runClient (totalFunds wallet)
