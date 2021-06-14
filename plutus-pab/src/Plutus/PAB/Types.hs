{-# LANGUAGE DeriveAnyClass     #-}
{-# LANGUAGE DeriveGeneric      #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE FlexibleInstances  #-}
{-# LANGUAGE LambdaCase         #-}
{-# LANGUAGE NamedFieldPuns     #-}
{-# LANGUAGE OverloadedStrings  #-}
{-# LANGUAGE StrictData         #-}
{-# LANGUAGE TemplateHaskell    #-}
{-# LANGUAGE TypeApplications   #-}

module Plutus.PAB.Types where

import qualified Cardano.ChainIndex.Types  as ChainIndex
import qualified Cardano.Metadata.Types    as Metadata
import           Cardano.Node.Types        (MockServerConfig (..))
import qualified Cardano.Wallet.Types      as Wallet
import           Control.Lens.TH           (makePrisms)
import           Data.Aeson                (FromJSON, ToJSON (..))
import           Data.Map.Strict           (Map)
import qualified Data.Map.Strict           as Map
import           Data.Text                 (Text)
import           Data.Text.Prettyprint.Doc (Pretty, pretty, viaShow, (<+>))
import           Data.Time.Units           (Second)
import           Data.UUID                 (UUID)
import qualified Data.UUID.Extras          as UUID
import           GHC.Generics              (Generic)
import           Ledger                    (Block, Blockchain, Tx, TxId, eitherTx, txId)
import           Ledger.Index              as UtxoIndex
import           Plutus.Contract.Types     (ContractError)
import           Plutus.PAB.Instances      ()
import           Servant.Client            (BaseUrl, ClientError)
import           Wallet.API                (ChainIndexAPIError, WalletAPIError)
import           Wallet.Emulator.Wallet    (Wallet)
import           Wallet.Types              (ContractInstanceId (..), NotificationError)

data PABError
    = FileNotFound FilePath
    | ContractNotFound FilePath
    | ContractInstanceNotFound ContractInstanceId
    | PABContractError ContractError
    | ChainIndexClientError ClientError
    | WalletClientError ClientError
    | NodeClientError ClientError
    | RandomTxClientError ClientError
    | MetadataError Metadata.MetadataError
    | ChainIndexError ChainIndexAPIError
    | WalletError WalletAPIError
    | ContractCommandError Int Text -- ?
    | InvalidUUIDError  Text
    | OtherError Text -- ?
    | EndpointCallError NotificationError
    | InstanceAlreadyStopped ContractInstanceId -- ^ Attempt to stop the instance failed because it was not running
    | WalletNotFound Wallet
    | MissingConfigFileOption
    deriving stock (Show, Eq, Generic)
    deriving anyclass (ToJSON, FromJSON)

instance Pretty PABError where
    pretty = \case
        FileNotFound fp            -> "File not found:" <+> pretty fp
        ContractNotFound fp        -> "Contract not found:" <+> pretty fp
        ContractInstanceNotFound i -> "Contract instance not found:" <+> pretty i
        PABContractError e         -> "Contract error:" <+> pretty e
        WalletClientError e        -> "Wallet client error:" <+> viaShow e
        ChainIndexClientError e    -> "Chain index client error:" <+> viaShow e
        NodeClientError e          -> "Node client error:" <+> viaShow e
        RandomTxClientError e      -> "Random tx client error:" <+> viaShow e
        MetadataError e            -> "Metadata error:" <+> viaShow e
        ChainIndexError e          -> "Chain index error:" <+> viaShow e
        WalletError e              -> "Wallet error:" <+> pretty e
        ContractCommandError i t   -> "Contract command error:" <+> pretty i <+> pretty t
        InvalidUUIDError t         -> "Invalid UUID:" <+> pretty t
        OtherError t               -> "Other error:" <+> pretty t
        EndpointCallError n        -> "Endpoint call failed:" <+> pretty n
        InstanceAlreadyStopped i   -> "Instance already stopped:" <+> pretty i
        WalletNotFound w           -> "Wallet not found:" <+> pretty w
        MissingConfigFileOption    -> "The --config-file option is required"

data DbConfig =
    DbConfig
        { dbConfigFile     :: Text
        -- ^ The path to the sqlite database file. May be absolute or relative.
        , dbConfigPoolSize :: Int
        -- ^ Max number of concurrent sqlite database connections.
        }
    deriving (Show, Eq, Generic)
    deriving anyclass (ToJSON, FromJSON)

data Config =
    Config
        { dbConfig                :: DbConfig
        , walletServerConfig      :: Wallet.WalletConfig
        , nodeServerConfig        :: MockServerConfig
        , metadataServerConfig    :: Metadata.MetadataConfig
        , pabWebserverConfig      :: WebserverConfig
        , chainIndexConfig        :: ChainIndex.ChainIndexConfig
        , requestProcessingConfig :: RequestProcessingConfig
        , endpointTimeout         :: Maybe Second
        }
    deriving (Show, Eq, Generic, FromJSON)

newtype RequestProcessingConfig =
    RequestProcessingConfig
        { requestProcessingInterval :: Second -- ^ How many seconds to wait between calls to 'Plutus.PAB.Core.ContractInstance.processAllContractOutboxes'
        }
    deriving (Show, Eq, Generic)
    deriving anyclass (FromJSON)

data WebserverConfig =
    WebserverConfig
        { baseUrl   :: BaseUrl
        , staticDir :: FilePath
        }
    deriving (Show, Eq, Generic)
    deriving anyclass (FromJSON, ToJSON)

-- | The source of a PAB event, used for sharding of the event stream
data Source
    = PABEventSource
    | InstanceEventSource ContractInstanceId
    deriving (Show, Eq)

toUUID :: Source -> UUID
toUUID = \case
    InstanceEventSource (ContractInstanceId i) -> i
    PABEventSource                             -> UUID.sequenceIdToMockUUID 1

data ChainOverview =
    ChainOverview
        { chainOverviewBlockchain     :: Blockchain
        , chainOverviewUnspentTxsById :: Map TxId Tx
        , chainOverviewUtxoIndex      :: UtxoIndex
        }
    deriving (Show, Eq, Generic)
    deriving anyclass (ToJSON, FromJSON)

mkChainOverview :: Blockchain -> ChainOverview
mkChainOverview = foldl reducer emptyChainOverview
  where
    reducer :: ChainOverview -> Block -> ChainOverview
    reducer ChainOverview { chainOverviewBlockchain = oldBlockchain
                          , chainOverviewUnspentTxsById = oldTxById
                          , chainOverviewUtxoIndex = oldUtxoIndex
                          } txs =
        let unprunedTxById =
                foldl (\m -> eitherTx (const m) (\tx -> Map.insert (txId tx) tx m)) oldTxById txs
            newTxById = unprunedTxById -- TODO Prune spent keys.
            newUtxoIndex = UtxoIndex.insertBlock txs oldUtxoIndex
         in ChainOverview
                { chainOverviewBlockchain = txs : oldBlockchain
                , chainOverviewUnspentTxsById = newTxById
                , chainOverviewUtxoIndex = newUtxoIndex
                }
    emptyChainOverview =
        ChainOverview
            { chainOverviewBlockchain = []
            , chainOverviewUnspentTxsById = Map.empty
            , chainOverviewUtxoIndex = UtxoIndex Map.empty
            }

makePrisms ''PABError
