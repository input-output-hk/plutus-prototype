{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE DeriveAnyClass        #-}
{-# LANGUAGE DerivingVia           #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE GADTs                 #-}
{-# LANGUAGE PartialTypeSignatures #-}
{-# LANGUAGE TypeApplications      #-}
{-# LANGUAGE TypeFamilies          #-}
{-# OPTIONS_GHC -Wno-orphans           #-}
module Cardano.Protocol.Socket.Type where

import           Codec.Serialise.Class                              (Serialise)
import           Control.Monad                                      (forever)
import           Control.Monad.Class.MonadTimer
import           Crypto.Hash                                        (SHA256, hash)
import           Data.Aeson                                         (FromJSON, ToJSON)
import qualified Data.ByteArray                                     as BA
import qualified Data.ByteString                                    as BS
import qualified Data.ByteString.Lazy                               as BSL
import           Data.Text.Prettyprint.Doc                          (Pretty)
import           Data.Time.Units.Extra                              ()
import           Data.Void                                          (Void)

import           GHC.Generics
import           NoThunks.Class                                     (NoThunks)

import           Codec.Serialise                                    (DeserialiseFailure)
import qualified Codec.Serialise                                    as CBOR
import           Network.TypedProtocol.Codec
import           Ouroboros.Network.Block                            (HeaderHash, Point, StandardHash)
import           Ouroboros.Network.Magic                            (NetworkMagic (..))
import           Ouroboros.Network.Mux
import           Ouroboros.Network.NodeToClient                     (NodeToClientVersion (..),
                                                                     NodeToClientVersionData (..))
import qualified Ouroboros.Network.Protocol.ChainSync.Codec         as ChainSync
import qualified Ouroboros.Network.Protocol.ChainSync.Type          as ChainSync
import qualified Ouroboros.Network.Protocol.LocalTxSubmission.Codec as TxSubmission
import qualified Ouroboros.Network.Protocol.LocalTxSubmission.Type  as TxSubmission
import           Ouroboros.Network.Util.ShowProxy

import           Ledger                                             (Block, OnChainTx (..), Tx (..), TxId (..))
import           Ledger.Bytes                                       (LedgerBytes (..))

-- | Tip of the block chain type (used by node protocols).
type Tip = Block

-- | The node protocols require a block header type.
newtype BlockId = BlockId { getBlockId :: BS.ByteString }
  deriving (Eq, Ord, Generic)
  deriving anyclass (ToJSON, FromJSON)
  deriving newtype (Serialise, NoThunks)
  deriving (Pretty, Show) via LedgerBytes

-- | A hash of the block's contents.
blockId :: Block -> BlockId
blockId = BlockId
        . BA.convert
        . hash @_ @SHA256
        . BSL.toStrict
        . CBOR.serialise

-- | Explains why our (plutus) data structures are hashable.
type instance HeaderHash Tx = TxId
type instance HeaderHash Block = BlockId
deriving instance StandardHash Tx

-- TODO: Is this the best place for these instances?
instance ShowProxy Char
instance ShowProxy Tx where
instance ShowProxy OnChainTx where
instance ShowProxy a => ShowProxy [a] where
  showProxy _ = "[" ++ showProxy (Proxy @a) ++ "]"

deriving instance StandardHash Block
deriving newtype instance NoThunks TxId

-- | Limits for the protocols we use.
maximumMiniProtocolLimits :: MiniProtocolLimits
maximumMiniProtocolLimits =
    MiniProtocolLimits {
        maximumIngressQueue = maxBound
    }

-- | Protocol versions
nodeToClientVersion :: NodeToClientVersion
nodeToClientVersion = NodeToClientV_4

-- | A temporary definition of the protocol version. This will be moved as an
-- argument to the client connection function in a future PR (the network magic
-- number matches the one in the test net created by scripts)
nodeToClientVersionData :: NodeToClientVersionData
nodeToClientVersionData = NodeToClientVersionData { networkMagic = NetworkMagic 42 }

-- | A protocol client that will never leave the initial state.
doNothingInitiatorProtocol
  :: MonadTimer m => RunMiniProtocol 'InitiatorMode BSL.ByteString m a Void
doNothingInitiatorProtocol =
    InitiatorProtocolOnly $ MuxPeerRaw $
    const $ forever $ threadDelay 1e6

doNothingResponderProtocol
  :: MonadTimer m => RunMiniProtocol 'ResponderMode BSL.ByteString m Void a
doNothingResponderProtocol =
  ResponderProtocolOnly $ MuxPeerRaw $
  const $ forever $ threadDelay 1e6

type Offset = Integer

-- | Boilerplate codecs used for protocol serialisation.
codecChainSync
  :: forall block.
     ( Serialise block
     , Serialise (HeaderHash block)
     )
  => Codec (ChainSync.ChainSync block (Point block) Tip)
           DeserialiseFailure
           IO BSL.ByteString
codecChainSync =
    ChainSync.codecChainSync
      CBOR.encode             CBOR.decode
      CBOR.encode             CBOR.decode
      CBOR.encode             CBOR.decode

codecTxSubmission :: Codec (TxSubmission.LocalTxSubmission Tx String)
                           DeserialiseFailure
                           IO BSL.ByteString
codecTxSubmission =
    TxSubmission.codecLocalTxSubmission
      CBOR.encode CBOR.decode
      CBOR.encode CBOR.decode
