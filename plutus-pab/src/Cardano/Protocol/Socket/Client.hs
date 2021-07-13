{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE FlexibleInstances   #-}
{-# LANGUAGE GADTs               #-}
{-# LANGUAGE NamedFieldPuns      #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}
{-# LANGUAGE TypeFamilies        #-}

module Cardano.Protocol.Socket.Client where

import qualified Data.ByteString.Lazy                                as LBS
import           Data.Time.Units                                     (Second, TimeUnit, toMicroseconds)
import           Data.Void                                           (Void)

import           Codec.Serialise.Class                               (Serialise)
import           Control.Concurrent
import           Control.Concurrent.STM
import           Control.Monad.Catch                                 (catchAll)
import           Control.Tracer

import           Ouroboros.Network.Block                             (HeaderHash, Point (..))
import qualified Ouroboros.Network.Protocol.ChainSync.Client         as ChainSync
import qualified Ouroboros.Network.Protocol.LocalTxSubmission.Client as TxSubmission

import           Ledger.TimeSlot                                     (SlotConfig, currentSlot)
import           Ouroboros.Network.IOManager
import           Ouroboros.Network.Mux
import           Ouroboros.Network.NodeToClient                      (NodeToClientProtocols (..), connectTo,
                                                                      versionedNodeToClientProtocols)
import           Ouroboros.Network.Snocket
import           Ouroboros.Network.Socket
import           Ouroboros.Network.Util.ShowProxy                    (ShowProxy)

import           Cardano.Protocol.Socket.Type
import           Ledger                                              (Slot (..), Tx (..))

data ChainSyncHandle block = ChainSyncHandle
    { cshCurrentSlot :: IO Slot
    , cshHandler     :: block -> Slot -> IO ()
    }

newtype TxSendHandle = TxSendHandle
    { tshQueue :: TQueue Tx }

-- | Queue a transaction to be sent to the server.
queueTx ::
    TxSendHandle
 -> Tx
 -> IO ()
queueTx TxSendHandle { tshQueue } tx =
    atomically (writeTQueue tshQueue tx)

getCurrentSlot
  :: forall block.
     ChainSyncHandle block
  -> IO Slot
getCurrentSlot = cshCurrentSlot

-- | Run the chain sync protocol to get access to the current slot number.
runChainSync'
  :: forall block.
     ( Serialise block
     , Serialise (HeaderHash block)
     , ShowProxy block
     )
  => FilePath
  -> SlotConfig
  -> IO (ChainSyncHandle block)
runChainSync' socketPath slotConfig =
  runChainSync socketPath slotConfig (\_ _ -> pure ())

runChainSync
  :: forall block.
     ( Serialise block
     , Serialise (HeaderHash block)
     , ShowProxy block
     )
  => FilePath
  -> SlotConfig
  -> (block -> Slot -> IO ())
  -> IO (ChainSyncHandle block)
runChainSync socketPath slotConfig onNewBlock = do
    let handle = ChainSyncHandle { cshCurrentSlot = currentSlot slotConfig
                                 , cshHandler = onNewBlock
                                 }

    _ <- forkIO $ withIOManager $ loop (1 :: Second) handle
    pure handle
    where
      loop :: forall a. TimeUnit a
           => a
           -> (ChainSyncHandle block)
           -> IOManager
           -> IO ()
      loop timeout ch@ChainSyncHandle{ cshHandler } iocp = do
        catchAll
          (connectTo
            (localSnocket iocp socketPath)
            nullNetworkConnectTracers
            (versionedNodeToClientProtocols
              nodeToClientVersion
              nodeToClientVersionData
              (\_ _ -> nodeToClientProtocols cshHandler))
            socketPath)
          {- If we receive any error or disconnect, try to reconnect.
             This happens a lot on startup, until the server starts. -}
          (\_ -> do
               threadDelay (fromIntegral $ toMicroseconds timeout)
               loop timeout ch iocp)

      nodeToClientProtocols
        :: (block -> Slot -> IO ())
        -> NodeToClientProtocols 'InitiatorMode LBS.ByteString IO () Void
      nodeToClientProtocols blockHandler =
        NodeToClientProtocols
          { localChainSyncProtocol = chainSync blockHandler
          , localTxSubmissionProtocol = doNothingInitiatorProtocol
          , localStateQueryProtocol = doNothingInitiatorProtocol
          }

      chainSync
        :: (block -> Slot -> IO ())
        -> RunMiniProtocol 'InitiatorMode LBS.ByteString IO () Void
      chainSync onNewBlock' =
          InitiatorProtocolOnly $
          MuxPeer
            nullTracer
            codecChainSync
            (ChainSync.chainSyncClientPeer
               (chainSyncClient @block slotConfig onNewBlock'))

-- | The client updates the application state when the protocol state changes.
chainSyncClient
  :: forall block.
     SlotConfig
  -> (block -> Slot -> IO ())
  -> ChainSync.ChainSyncClient block (Point block) Tip IO ()
chainSyncClient slotConfig onNewBlock =
    ChainSync.ChainSyncClient $ pure requestNext
    where
      requestNext :: ChainSync.ClientStIdle block (Point block) Tip IO ()
      requestNext =
        ChainSync.SendMsgRequestNext
          handleNext
          (return handleNext)

      handleNext :: ChainSync.ClientStNext block (Point block) Tip IO ()
      handleNext =
        ChainSync.ClientStNext
        {
          ChainSync.recvMsgRollForward  = \block _ ->
            ChainSync.ChainSyncClient $ do
              slot <- currentSlot slotConfig
              onNewBlock block slot
              return requestNext
        , ChainSync.recvMsgRollBackward = error "Not supported."
        }

runTxSender :: FilePath
            -> IO TxSendHandle
runTxSender socketPath = do
    inputQueue  <- newTQueueIO
    let handle = TxSendHandle { tshQueue = inputQueue }

    _ <- forkIO $ withIOManager $ loop (1 :: Second) handle
    pure handle
    where
      loop :: TimeUnit a => a -> TxSendHandle -> IOManager -> IO ()
      loop timeout ch@TxSendHandle{ tshQueue } iocp = do
        catchAll
          (connectTo
            (localSnocket iocp socketPath)
            nullNetworkConnectTracers
            (versionedNodeToClientProtocols
              nodeToClientVersion
              nodeToClientVersionData
              (\_ _ -> nodeToClientProtocols tshQueue))
            socketPath)
          {- If we receive any error or disconnect, try to reconnect.
             This happens a lot on startup, until the server starts. -}
          (\_ -> do
               threadDelay (fromIntegral $ toMicroseconds timeout)
               loop timeout ch iocp)

      nodeToClientProtocols
        :: TQueue Tx
        -> NodeToClientProtocols 'InitiatorMode LBS.ByteString IO () Void
      nodeToClientProtocols sendQueue =
        NodeToClientProtocols
          { localChainSyncProtocol = doNothingInitiatorProtocol
          , localTxSubmissionProtocol = txSubmission sendQueue
          , localStateQueryProtocol = doNothingInitiatorProtocol
          }

      txSubmission :: TQueue Tx
                   -> RunMiniProtocol 'InitiatorMode LBS.ByteString IO () Void
      txSubmission inputQueue =
          InitiatorProtocolOnly $
          MuxPeer
            (showTracing stdoutTracer)
            codecTxSubmission
            (TxSubmission.localTxSubmissionClientPeer
               (txSubmissionClient inputQueue))

-- | The client updates the application state when the protocol state changes.
txSubmissionClient :: TQueue Tx
                   -> TxSubmission.LocalTxSubmissionClient Tx String IO ()
txSubmissionClient txQueue =
    TxSubmission.LocalTxSubmissionClient pushTxs
    where
      pushTxs :: IO (TxSubmission.LocalTxClientStIdle Tx String IO ())
      pushTxs = do
        header <- atomically $ readTQueue txQueue
        return $ TxSubmission.SendMsgSubmitTx
                   header
                   (const pushTxs) -- ignore rejects for now
