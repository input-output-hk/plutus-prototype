{-# LANGUAGE DataKinds         #-}
{-# LANGUAGE DeriveAnyClass    #-}
{-# LANGUAGE DeriveGeneric     #-}
{-# LANGUAGE DerivingVia       #-}
{-# LANGUAGE FlexibleContexts  #-}
{-# LANGUAGE GADTs             #-}
{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE NamedFieldPuns    #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData        #-}
{-# LANGUAGE TemplateHaskell   #-}
{-# LANGUAGE TypeApplications  #-}

{-| This module exports data types for logging, events and configuration
-}
module Cardano.Node.Types
    (
      -- * Logging types
      MockServerLogMsg (..)

     -- * Event types
    , BlockEvent (..)

     -- * Effects
    , NodeServerEffects

     -- *  State types
    , AppState (..)
    , initialAppState
    , initialChainState

    -- * Lens functions
    , chainState
    , eventHistory

    -- * Config types
    , MockServerConfig (..)
    , BlockReaperConfig (..)
    , MockServerMode (..)

    -- * newtype wrappers
    , NodeUrl (..)
    )
        where

import           Control.Lens                   (makeLenses, view)
import           Control.Monad.IO.Class         (MonadIO (..))
import           Data.Aeson                     (FromJSON, ToJSON)
import qualified Data.Map                       as Map
import           Data.Text.Prettyprint.Doc      (Pretty (..), pretty, viaShow, (<+>))
import           Data.Time.Clock                (UTCTime)
import qualified Data.Time.Format.ISO8601       as F
import           Data.Time.Units                (Millisecond, Second)
import           Data.Time.Units.Extra          ()
import           GHC.Generics                   (Generic)
import           Ledger                         (Tx, txId)
import           Servant.Client                 (BaseUrl)

import           Cardano.BM.Data.Tracer         (ToObject (..))
import           Cardano.BM.Data.Tracer.Extras  (Tagged (..), mkObjectStr)
import           Cardano.Chain                  (MockNodeServerChainState, fromEmulatorChainState)
import qualified Cardano.Protocol.Socket.Client as Client
import           Control.Monad.Freer.Extras.Log (LogMessage, LogMsg (..))
import           Control.Monad.Freer.Reader     (Reader)
import           Control.Monad.Freer.State      (State)
import           Ledger.TimeSlot                (SlotConfig)
import qualified Plutus.Contract.Trace          as Trace
import           Wallet.Emulator                (Wallet)
import qualified Wallet.Emulator                as EM
import           Wallet.Emulator.Chain          (ChainControlEffect, ChainEffect, ChainEvent)
import qualified Wallet.Emulator.MultiAgent     as MultiAgent

import           Plutus.PAB.Arbitrary           ()

-- Configuration ------------------------------------------------------------------------------------------------------

{- Note [Slot numbers in mock node]

The mock node has an internal clock that generates new slots in a regular
interval. Slots are identified by consecutive integers. What should the
initial slot number be? We can either set it to 0, so that the slot number
is the number of intervals that have passed since the process was started.
Or we can define an initial timestamp, so that the slot number is the number
of intervals since that timestamp.

The first option of counting from 0 is useful for integration tests where we
want the test outcome to be independent of when the test was run. This approach
is used in the PAB simulator.
The second option, counting from a timestamp, is more realistic and it is
useful for frontends that need to convert the slot number back to a timestamp.
We use this approach for the "proper" pab executable.

-}

newtype NodeUrl = NodeUrl BaseUrl
    deriving (Show, Eq) via BaseUrl

-- | The mock node server can be replaced with a cardano node, in which case
--   we don't want to start it.
data MockServerMode =
      WithMockServer
    | WithoutMockServer
    deriving (Show, Eq, Generic)
    deriving anyclass ToJSON

-- | Mock Node server configuration
data MockServerConfig =
    MockServerConfig
        { mscBaseUrl          :: BaseUrl
        -- ^ base url of the service
        , mscBlockReaper      :: Maybe BlockReaperConfig
        -- ^ When to discard old blocks
        , mscInitialTxWallets :: [Wallet]
        -- ^ The wallets that receive money from the initial transaction.
        , mscSocketPath       :: FilePath
        -- ^ Path to the socket used to communicate with the server.
        , mscKeptBlocks       :: Integer
        -- ^ The number of blocks to keep for replaying to a newly connected clients
        , mscSlotConfig       :: SlotConfig
        -- ^ Beginning of slot 0.
        }
    deriving (Show, Eq, Generic, FromJSON)

-- | Configuration for 'Cardano.Node.Mock.blockReaper'
data BlockReaperConfig =
    BlockReaperConfig
        { brcInterval     :: Second -- ^ interval in seconds for discarding blocks
        , brcBlocksToKeep :: Int    -- ^ number of blocks to keep
        }
    deriving (Show, Eq, Generic, FromJSON)


-- Logging ------------------------------------------------------------------------------------------------------------

-- | Top-level logging data type for structural logging
-- inside the Mock Node server.
data MockServerLogMsg =
    StartingSlotCoordination UTCTime Millisecond
    | KeepingOldBlocks
    | RemovingOldBlocks
    | StartingMockServer Int
    | ProcessingChainEvent ChainEvent
    | BlockOperation BlockEvent
    | CreatingRandomTransaction
    deriving (Generic, Show, ToJSON, FromJSON)

instance Pretty MockServerLogMsg where
    pretty = \case
        KeepingOldBlocks          -> "Not starting block reaper thread (old blocks will be retained in-memory forever"
        RemovingOldBlocks         -> "Starting block reaper thread (old blocks will be removed)"
        StartingMockServer p      -> "Starting Mock Node Server on port " <+> pretty p
        StartingSlotCoordination initialSlotTime slotLength  ->
            "Starting slot coordination thread."
            <+> "Initial slot time:" <+> pretty (F.iso8601Show initialSlotTime)
            <+> "Slot length:" <+> viaShow slotLength
        ProcessingChainEvent e    -> "Processing chain event " <+> pretty e
        BlockOperation e          -> "Block operation " <+> pretty e
        CreatingRandomTransaction -> "Generating a random transaction"

instance ToObject MockServerLogMsg where
    toObject _ = \case
        KeepingOldBlocks          ->  mkObjectStr "Not starting block reaper thread (old blocks will be retained in-memory forever" ()
        RemovingOldBlocks         ->  mkObjectStr "Starting block reaper thread (old blocks will be removed)" ()
        StartingMockServer p      ->  mkObjectStr "Starting Mock Node Server on port " (Tagged @"port" p)
        StartingSlotCoordination i l  -> mkObjectStr "Starting slot coordination thread" (Tagged @"initial-slot-time" (F.iso8601Show  i), Tagged @"slot-length" l)
        ProcessingChainEvent e    ->  mkObjectStr "Processing chain event" (Tagged @"event" e)
        BlockOperation e          ->  mkObjectStr "Block operation" (Tagged @"event" e)
        CreatingRandomTransaction ->  mkObjectStr "Creating random transaction" ()

data BlockEvent = NewSlot
    | NewTransaction Tx
    deriving (Generic, Show, ToJSON, FromJSON)

instance Pretty BlockEvent where
    pretty = \case
        NewSlot          -> "Adding a new slot"
        NewTransaction t -> "Adding a transaction " <+> pretty (Ledger.txId t)


-- State --------------------------------------------------------------------------------------------------------------

-- | Application State
data AppState =
    AppState
        { _chainState   :: MockNodeServerChainState -- ^ blockchain state
        , _eventHistory :: [LogMessage MockServerLogMsg] -- ^ history of all log messages
        }
    deriving (Show)

makeLenses 'AppState

-- | 'AppState' with an initial transaction that pays some Ada to
--   the wallets.
initialAppState :: MonadIO m => [Wallet] -> m AppState
initialAppState wallets = do
    initialState <- initialChainState (Trace.defaultDistFor wallets)
    pure $ AppState
        { _chainState = initialState
        , _eventHistory = mempty
        }

-- | 'ChainState' with initial values
initialChainState :: MonadIO m => Trace.InitialDistribution -> m MockNodeServerChainState
initialChainState =
    fromEmulatorChainState . view EM.chainState .
    MultiAgent.emulatorStateInitialDist . Map.mapKeys EM.walletPubKey

-- Effects -------------------------------------------------------------------------------------------------------------

type NodeServerEffects m
     = '[ ChainControlEffect
        , ChainEffect
        , State MockNodeServerChainState
        , LogMsg MockServerLogMsg
        , Reader Client.TxSendHandle
        , State AppState
        , LogMsg MockServerLogMsg
        , m]
