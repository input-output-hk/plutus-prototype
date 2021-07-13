{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs            #-}
{-# LANGUAGE LambdaCase       #-}
{-# LANGUAGE RankNTypes       #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators    #-}

module Cardano.Node.Client where

import           Control.Monad.Freer
import           Control.Monad.Freer.Reader     (Reader, ask)
import           Control.Monad.IO.Class
import           Data.Proxy                     (Proxy (Proxy))
import           Servant                        (NoContent, (:<|>) (..))
import           Servant.Client                 (ClientM, client)

import           Cardano.Node.API               (API)
import           Cardano.Node.Types             (MockServerLogMsg)
import qualified Cardano.Protocol.Socket.Client as Client
import           Control.Monad.Freer.Extras.Log (LogMessage)
import           Wallet.Effects                 (NodeClientEffect (..))

healthcheck :: ClientM NoContent
consumeEventHistory :: ClientM [LogMessage MockServerLogMsg]
(healthcheck, consumeEventHistory) =
    ( healthcheck_
    , consumeEventHistory_
    )
  where
    healthcheck_ :<|> consumeEventHistory_ =
        client (Proxy @API)

handleNodeClientClient ::
    forall m effs.
    ( LastMember m effs
    , MonadIO m
    , Member (Reader Client.TxSendHandle) effs
    , Member (Reader Client.ChainSyncHandle) effs
    )
    => NodeClientEffect
    ~> Eff effs
handleNodeClientClient e = do
    txSendHandle <- ask @Client.TxSendHandle
    chainSyncHandle <- ask @Client.ChainSyncHandle
    case e of
        PublishTx tx  ->
            liftIO $ Client.queueTx txSendHandle tx
        GetClientSlot -> liftIO $ Client.getCurrentSlot chainSyncHandle
