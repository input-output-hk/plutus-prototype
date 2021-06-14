{-# LANGUAGE DataKinds         #-}
{-# LANGUAGE DeriveAnyClass    #-}
{-# LANGUAGE DeriveGeneric     #-}
{-# LANGUAGE DerivingVia       #-}
{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData        #-}
{-# LANGUAGE TemplateHaskell   #-}
{-# LANGUAGE TypeApplications  #-}

module Cardano.ChainIndex.Types where

import           Control.Lens                   (makeLenses)
import           Control.Monad.Freer.Error
import           Control.Monad.Freer.Extras.Log (LogMessage)
import           Control.Monad.Freer.State
import           Data.Aeson                     (FromJSON, ToJSON)
import           Data.Sequence                  (Seq)
import           Data.Text.Prettyprint.Doc      (Pretty (..), parens, (<+>))
import           GHC.Generics                   (Generic)
import           Servant                        (ServerError)
import           Servant.Client                 (BaseUrl)

import           Cardano.BM.Data.Trace          (Trace)
import           Cardano.BM.Data.Tracer         (ToObject (..))
import           Cardano.BM.Data.Tracer.Extras  (Tagged (..), mkObjectStr)
import           Control.Monad.Freer.Extras     (LogMsg)
import           Ledger.Address                 (Address)
import           Wallet.API                     (ChainIndexAPIError)
import           Wallet.Effects                 (ChainIndexEffect)
import           Wallet.Emulator.ChainIndex     (ChainIndexControlEffect, ChainIndexEvent, ChainIndexState)


type ChainIndexEffects m
     = '[ ChainIndexControlEffect
        , ChainIndexEffect
        , State ChainIndexState
        , LogMsg ChainIndexEvent
        , Error ChainIndexAPIError
        , Error ServerError
        , m
        ]

newtype ChainIndexUrl = ChainIndexUrl BaseUrl
    deriving (Eq, Show, FromJSON, ToJSON) via BaseUrl

data AppState =
    AppState
        { _indexState  :: ChainIndexState
        , _indexEvents :: Seq (LogMessage ChainIndexEvent)
        } deriving (Eq, Show)

initialAppState :: AppState
initialAppState = AppState mempty mempty

data ChainIndexConfig =
    ChainIndexConfig
        { ciBaseUrl          :: ChainIndexUrl
        , ciWatchedAddresses :: [Address]
        }
    deriving stock (Show, Eq, Generic)
    deriving anyclass (FromJSON, ToJSON)

makeLenses ''AppState
makeLenses ''ChainIndexConfig

-- | Messages from the ChainIndex Server
data ChainIndexServerMsg =
    -- | Starting a node client thread
      StartingNodeClientThread
    -- | Starting ChainIndex service
    | StartingChainIndex
        Int    -- ^ Port number
      -- | Received transaction
    | ReceivedBlocksTxns
        Int    -- ^ Blocks
        Int    -- ^ Transactions
    | ChainEvent ChainIndexEvent
    deriving stock (Show, Generic)
    deriving anyclass (ToJSON, FromJSON)

type ChainIndexTrace = Trace IO ChainIndexServerMsg

instance Pretty ChainIndexServerMsg where
    pretty = \case
        ReceivedBlocksTxns blocks txns -> "Received" <+> pretty blocks <+> "blocks" <+> parens (pretty txns <+> "transactions")
        StartingNodeClientThread -> "Starting node client thread"
        StartingChainIndex port -> "Starting chain index on port: " <> pretty port
        ChainEvent e -> "Processing chain index event: " <> pretty e

instance ToObject ChainIndexServerMsg where
    toObject _ = \case
      ReceivedBlocksTxns x y   -> mkObjectStr "received block transactions" (Tagged @"blocks" x, Tagged @"transactions" y)
      StartingNodeClientThread -> mkObjectStr "starting node client thread" ()
      StartingChainIndex p     -> mkObjectStr "starting chain index" (Tagged @"port" p)
      ChainEvent e             -> mkObjectStr "processing chain event" (Tagged @"event" e)
