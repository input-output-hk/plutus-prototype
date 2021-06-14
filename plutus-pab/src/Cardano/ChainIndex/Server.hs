{-# LANGUAGE DataKinds         #-}
{-# LANGUAGE FlexibleContexts  #-}
{-# LANGUAGE MonoLocalBinds    #-}
{-# LANGUAGE NamedFieldPuns    #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes        #-}
{-# LANGUAGE TypeApplications  #-}

module Cardano.ChainIndex.Server(
    -- $chainIndex
    main
    , ChainIndexConfig(..)
    , ChainIndexServerMsg
    , syncState
    ) where

import           Control.Concurrent.MVar         (MVar, newMVar)
import           Control.Monad.Freer.Extras.Log
import           Servant.Client                  (BaseUrl (baseUrlPort))

import           Data.Coerce                     (coerce)
import           Plutus.PAB.Monitoring.Util      (runLogEffects)
import qualified Wallet.Effects                  as WalletEffects

import           Cardano.ChainIndex.ChainIndex   (confirmedBlocks, healthcheck, processIndexEffects,
                                                  processIndexEffectsServant, startWatching, syncState,
                                                  watchedAddresses)
import           Cardano.Node.Types              (SlotConfig)
import           Control.Monad.IO.Class          (MonadIO (..))
import           Data.Function                   ((&))
import           Data.Proxy                      (Proxy (Proxy))
import           Ledger.Blockchain               (Block)
import qualified Network.Wai.Handler.Warp        as Warp
import           Servant                         (Application, hoistServer, serve, (:<|>) ((:<|>)))

import           Cardano.ChainIndex.API
import           Cardano.ChainIndex.Types
import           Cardano.Protocol.Socket.Client  (runChainSync)
import           Control.Concurrent.Availability (Availability, available)
import           Ledger.Slot                     (Slot (..))

-- $chainIndex
-- The PAB chain index that keeps track of transaction data (UTXO set enriched
-- with datums)

app :: ChainIndexTrace -> MVar AppState -> Application
app trace stateVar =
    serve (Proxy @API) $
    hoistServer
        (Proxy @API)
        (processIndexEffectsServant trace stateVar)
        (healthcheck :<|> startWatching :<|> watchedAddresses :<|> confirmedBlocks :<|> WalletEffects.transactionConfirmed :<|> WalletEffects.addressChanged)

main :: ChainIndexTrace -> ChainIndexConfig -> FilePath -> SlotConfig -> Availability -> IO ()
main trace ChainIndexConfig{ciBaseUrl} socketPath slotConfig availability = runLogEffects trace $ do
    mVarState <- liftIO $ newMVar initialAppState

    logInfo StartingNodeClientThread
    _ <- liftIO $ runChainSync socketPath slotConfig $ updateChainState mVarState

    logInfo $ StartingChainIndex servicePort
    liftIO $ Warp.runSettings warpSettings $ app trace mVarState
        where
            isAvailable = available availability
            servicePort = baseUrlPort (coerce ciBaseUrl)
            warpSettings = Warp.defaultSettings & Warp.setPort servicePort & Warp.setBeforeMainLoop isAvailable
            updateChainState :: MVar AppState -> Block -> Slot -> IO ()
            updateChainState mv block slot =
              processIndexEffects trace mv $ syncState block slot
