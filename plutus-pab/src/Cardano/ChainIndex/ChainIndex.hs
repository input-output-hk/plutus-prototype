{-# LANGUAGE DataKinds         #-}
{-# LANGUAGE FlexibleContexts  #-}
{-# LANGUAGE MonoLocalBinds    #-}
{-# LANGUAGE NamedFieldPuns    #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes        #-}

module Cardano.ChainIndex.ChainIndex
    ( processIndexEffectsServant
    , processIndexEffects
    , startWatching
    , watchedAddresses
    , confirmedBlocks
    , syncState
    , healthcheck
    ) where

import           Cardano.BM.Data.Trace            (Trace)
import           Control.Concurrent.MVar          (MVar, putMVar, takeMVar)
import qualified Control.Monad.Except             as MonadError
import           Control.Monad.Freer              hiding (run)
import           Control.Monad.Freer.Error
import qualified Control.Monad.Freer.State        as Eff
import           Control.Monad.IO.Class           (MonadIO (..))
import qualified Data.ByteString.Lazy             as BSL
import qualified Data.ByteString.Lazy.Char8       as Char8
import           Data.Either                      (fromRight)
import           Data.Foldable                    (traverse_)
import           Data.Function                    ((&))
import           Data.Text.Encoding               (encodeUtf8)
import           Ledger.Blockchain                (Block)
import           Ledger.Slot                      (Slot)
import           Servant                          (NoContent (NoContent), ServerError (..), err400)

import           Cardano.ChainIndex.Types
import           Ledger.Address                   (Address)
import           Ledger.AddressMap                (AddressMap)
import           Plutus.PAB.Monitoring.Monitoring (convertLog, handleLogMsgTrace)
import           Wallet.API                       (ChainIndexAPIError (..))
import           Wallet.Effects                   (ChainIndexEffect)
import qualified Wallet.Effects                   as WalletEffects
import           Wallet.Emulator.ChainIndex       (ChainIndexControlEffect, ChainIndexState)
import qualified Wallet.Emulator.ChainIndex       as ChainIndex
import           Wallet.Emulator.NodeClient       (ChainClientNotification (BlockValidated, SlotChanged))

healthcheck :: Monad m => m NoContent
healthcheck = pure NoContent

startWatching :: (Member ChainIndexEffect effs) => Address -> Eff effs NoContent
startWatching addr = WalletEffects.startWatching addr >> pure NoContent

watchedAddresses :: (Member ChainIndexEffect effs) => Eff effs AddressMap
watchedAddresses = WalletEffects.watchedAddresses

confirmedBlocks :: (Member ChainIndexEffect effs) => Eff effs [Block]
confirmedBlocks = WalletEffects.confirmedBlocks

-- | Update the chain index by asking the node for new blocks since the last
--   time.
syncState ::
    ( Member ChainIndexControlEffect effs)
    => Block
    -> Slot
    -> Eff effs ()
syncState block slot =
    traverse_ ChainIndex.chainIndexNotify [BlockValidated block, SlotChanged slot]

-- Generalize this function to be able to throw both Servant's ServerError and IO error
processIndexEffectsServant ::
    (MonadIO m, MonadError.MonadError ServerError m)
    => ChainIndexTrace
    -> MVar AppState
    -> Eff (ChainIndexEffects IO) a
    -> m a
processIndexEffectsServant trace stateVar eff = do
    AppState {_indexState, _indexEvents} <- liftIO $ takeMVar stateVar
    result <- liftIO $ runIndexEffects trace _indexState eff
    case result of
        Left e -> do
            liftIO $ putMVar stateVar AppState {_indexState, _indexEvents}
            MonadError.throwError $ err400 { errBody = Char8.pack (show e) }
        Right (result_, newState) -> do
            liftIO $ putMVar stateVar AppState{_indexState=newState, _indexEvents=_indexEvents}
            pure result_

processIndexEffects ::
    MonadIO m
    => ChainIndexTrace
    -> MVar AppState
    -> Eff (ChainIndexEffects IO) a
    -> m a
processIndexEffects trace stateVar eff = do
    AppState {_indexState, _indexEvents} <- liftIO $ takeMVar stateVar
    result <- liftIO $ runIndexEffects trace _indexState eff
    let (result_, newState) = fromRight undefined result -- FIXME: Unsafe code!
    liftIO $ putMVar stateVar AppState{_indexState=newState, _indexEvents=_indexEvents}
    pure result_

-- | Interpret index effects
runIndexEffects ::
    MonadIO m
    => Trace m ChainIndexServerMsg
    -> ChainIndexState
    -> Eff (ChainIndexEffects m) a
    -> m (Either ServerError (a, ChainIndexState))
runIndexEffects trace state eff =
    ChainIndex.handleChainIndexControl eff
    & ChainIndex.handleChainIndex
    & Eff.runState state
    & interpret (handleLogMsgTrace (toChainIndexServerMsg trace))
    & handleChainIndexApiErrors
    & runError
    & runM
        where
            handleChainIndexApiErrors = flip handleError (throwError . fromChainIndexAPIError)
            toChainIndexServerMsg = convertLog ChainEvent

fromChainIndexAPIError :: ChainIndexAPIError -> ServerError
fromChainIndexAPIError (OtherChainIndexError text) =
    err400 {errBody = BSL.fromStrict $ encodeUtf8 text}
