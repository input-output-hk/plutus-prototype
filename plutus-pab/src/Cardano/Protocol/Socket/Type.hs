{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE DeriveAnyClass        #-}
{-# LANGUAGE DerivingVia           #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE GADTs                 #-}
{-# LANGUAGE NamedFieldPuns        #-}
{-# LANGUAGE PartialTypeSignatures #-}
{-# LANGUAGE TypeApplications      #-}
{-# LANGUAGE TypeFamilies          #-}
{-# OPTIONS_GHC -Wno-orphans           #-}
module Cardano.Protocol.Socket.Type where

import           Codec.Serialise.Class                              (Serialise)
import           Crypto.Hash                                        (SHA256, hash)
import           Data.Aeson                                         (FromJSON, ToJSON)
import qualified Data.ByteArray                                     as BA
import qualified Data.ByteString.Lazy                               as BSL
import           Data.Default                                       (Default (..))
import           Data.Text.Prettyprint.Doc                          (Pretty)
import           Data.Time.Calendar                                 (fromGregorian)
import           Data.Time.Clock                                    (UTCTime (..), diffUTCTime, getCurrentTime,
                                                                     nominalDiffTimeToSeconds, secondsToNominalDiffTime)
import           Data.Time.Units                                    (Second)
import           Data.Time.Units.Extra                              ()
import           Data.Word                                          (Word16)

import           GHC.Generics
import           NoThunks.Class                                     (NoThunks)

import           Codec.Serialise                                    (DeserialiseFailure)
import qualified Codec.Serialise                                    as CBOR
import           Network.TypedProtocol.Codec
import           Ouroboros.Network.Block                            (HeaderHash, Point, StandardHash)
import           Ouroboros.Network.Mux
import qualified Ouroboros.Network.Protocol.ChainSync.Codec         as ChainSync
import qualified Ouroboros.Network.Protocol.ChainSync.Type          as ChainSync
import qualified Ouroboros.Network.Protocol.LocalTxSubmission.Codec as TxSubmission
import qualified Ouroboros.Network.Protocol.LocalTxSubmission.Type  as TxSubmission
import           Ouroboros.Network.Util.ShowProxy

import           Ledger                                             (Block, OnChainTx (..), Slot (..), Tx (..),
                                                                     TxId (..))
import           Ledger.Bytes                                       (LedgerBytes (..))
import qualified PlutusTx.ByteString                                as PlutusTx

-- | Tip of the block chain type (used by node protocols).
type Tip = Block

-- | The node protocols require a block header type.
newtype BlockId = BlockId { getBlockId :: PlutusTx.ByteString }
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

-- | Build an application from a set of protocol numbers and protocols.
mkApplication
  :: [ (Word16, RunMiniProtocol appType bytes m a b) ]
  -> OuroborosApplication appType addr bytes m a b
mkApplication protocols =
  OuroborosApplication $ \_connectionId _shoudStomSTM ->
    map (\(ix, protocol) -> MiniProtocol {
                             miniProtocolNum = MiniProtocolNum ix,
                             miniProtocolLimits = maximumMiniProtocolLimits,
                             miniProtocolRun = protocol
                            })
    protocols

chainSyncMiniProtocolNum :: Word16
chainSyncMiniProtocolNum = 5

txSubmissionMiniProtocolNum :: Word16
txSubmissionMiniProtocolNum = 2

type Offset = Integer

-- | Boilerplate codecs used for protocol serialisation.
codecChainSync :: Codec (ChainSync.ChainSync Block (Point Block) Tip)
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

data SlotConfig =
    SlotConfig
        { scSlotLength   :: Second -- ^ Length of 1 slot
        , scZeroSlotTime :: UTCTime -- ^ Beginning of the first slot
        }
    deriving (Show, Eq, Generic, FromJSON)

instance Default SlotConfig where
  def =
    let shelleyLaunchDate =
          let ninePm = 21 * 60 * 60
              fourtyFourMinutes = 44 * 60
          in UTCTime (fromGregorian 2020 07 29) (ninePm + fourtyFourMinutes + 51)
    in SlotConfig{ scSlotLength = 1, scZeroSlotTime = shelleyLaunchDate }

-- | Convert a timestamp to a slot number
slotNumber :: SlotConfig -> UTCTime -> Slot
slotNumber SlotConfig{scSlotLength, scZeroSlotTime} currentTime =
    let timePassed = currentTime `diffUTCTime` scZeroSlotTime
        slotsPassed = timePassed / (secondsToNominalDiffTime $ fromIntegral scSlotLength)
    in Slot $ round $ nominalDiffTimeToSeconds slotsPassed

-- | Get the current slot number
currentSlot :: SlotConfig -> IO Slot
currentSlot sc = slotNumber sc <$> getCurrentTime
