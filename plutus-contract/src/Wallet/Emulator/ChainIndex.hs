{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE DeriveAnyClass        #-}
{-# LANGUAGE DeriveGeneric         #-}
{-# LANGUAGE DerivingVia           #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE GADTs                 #-}
{-# LANGUAGE LambdaCase            #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE NamedFieldPuns        #-}
{-# LANGUAGE OverloadedStrings     #-}
{-# LANGUAGE TemplateHaskell       #-}
{-# LANGUAGE TypeOperators         #-}
{-# LANGUAGE UndecidableInstances  #-}
{-# OPTIONS_GHC -Wno-orphans  #-}
module Wallet.Emulator.ChainIndex where

import           Control.Lens
import           Control.Monad.Freer
import           Control.Monad.Freer.Error
import           Control.Monad.Freer.Extras.Log
import           Control.Monad.Freer.State
import           Control.Monad.Freer.TH
import           Data.Aeson                       (FromJSON, ToJSON)
import           Data.Foldable                    (for_)
import           Data.Map.Strict                  (Map)
import qualified Data.Map.Strict                  as Map
import           Data.Semigroup                   (Max (..))
import           Data.Semigroup.Generic           (GenericSemigroupMonoid (..))
import           Data.Text.Prettyprint.Doc
import           GHC.Generics                     (Generic)
import           Wallet.Effects                   (ChainIndexEffect (..))
import           Wallet.Emulator.ChainIndex.Index (ChainIndex, ChainIndexItem (..))
import qualified Wallet.Emulator.ChainIndex.Index as Index
import           Wallet.Emulator.Error
import           Wallet.Emulator.NodeClient       (ChainClientNotification (..))
import           Wallet.Types                     (AddressChangeRequest (..), AddressChangeResponse (..), slotRange)

import           Ledger.Address                   (Address)
import           Ledger.AddressMap                (AddressMap)
import qualified Ledger.AddressMap                as AM
import           Ledger.Blockchain                (Blockchain, eitherTx)
import           Ledger.Slot                      (Slot)
import           Ledger.Tx                        (txId)
import           Ledger.TxId                      (TxId)

data ChainIndexControlEffect r where
    ChainIndexNotify :: ChainClientNotification -> ChainIndexControlEffect ()
makeEffect ''ChainIndexControlEffect

data ChainIndexEvent =
    AddressStartWatching Address
    | ReceiveBlockNotification Int
    | HandlingAddressChangeRequest AddressChangeRequest [ChainIndexItem]
    deriving stock (Eq, Show, Generic)
    deriving anyclass (FromJSON, ToJSON)

makePrisms ''ChainIndexEvent

instance Pretty ChainIndexEvent where
    pretty = \case
        AddressStartWatching addr  -> "StartWatching:" <+> pretty addr
        ReceiveBlockNotification i -> "ReceiveBlockNotification:" <+> pretty i <+> "transactions."
        HandlingAddressChangeRequest req itms ->
            let prettyItem ChainIndexItem{ciSlot, ciTxId} = pretty ciSlot <+> pretty ciTxId
            in hang 2 $ vsep
                [ "AddressChangeRequest:"
                , pretty req
                , vsep (fmap prettyItem itms)
                ]

data ChainIndexState =
    ChainIndexState
        { _idxWatchedAddresses      :: AddressMap -- ^ Utxo set annotated with datums
        , _idxConfirmedTransactions :: Map TxId Slot -- ^ Transactions with confirmation date
        , _idxConfirmedBlocks       :: Blockchain -- ^ The blockchain
        , _idxCurrentSlot           :: Maybe (Max Slot) -- ^ The current slot
        , _idxIdx                   :: ChainIndex  -- ^ Transactions indexed by time and address
        }
        deriving stock (Eq, Show, Generic)
        deriving (Semigroup, Monoid) via (GenericSemigroupMonoid ChainIndexState)

makeLenses ''ChainIndexState

type ChainIndexEffs = '[State ChainIndexState, LogMsg ChainIndexEvent, Error ChainIndexAPIError]

handleChainIndexControl
    :: Members ChainIndexEffs effs
    => Eff (ChainIndexControlEffect ': effs) ~> Eff effs
handleChainIndexControl = interpret $ \case
    ChainIndexNotify (SlotChanged sl) -> modify (idxCurrentSlot ?~ Max sl)
    ChainIndexNotify (BlockValidated txns) -> do
        logDebug $ ReceiveBlockNotification (length txns)
        modify (idxConfirmedBlocks <>~ pure txns)
        (cs, addressMap) <- (,) <$> gets _idxCurrentSlot <*> gets _idxWatchedAddresses
        let currentSlot = maybe 0 getMax cs
        for_ txns $ \txn -> do
            let i = eitherTx txId txId txn
                itm = ChainIndexItem{ciSlot=currentSlot, ciTx = txn, ciTxId = i}
            modify $ \s ->
                s & idxWatchedAddresses %~ AM.updateAllAddresses txn
                  & idxConfirmedTransactions %~ Map.insert i currentSlot
                  & idxIdx %~ Index.insert addressMap itm

handleChainIndex
    :: Members ChainIndexEffs effs
    => Eff (ChainIndexEffect ': effs) ~> Eff effs
handleChainIndex = interpret $ \case
    StartWatching addr -> logDebug (AddressStartWatching addr) >> (modify $ \s ->
        s & idxWatchedAddresses %~ AM.addAddress addr)
    WatchedAddresses -> gets _idxWatchedAddresses
    ConfirmedBlocks -> gets _idxConfirmedBlocks
    TransactionConfirmed txid ->
        Map.member txid <$> gets _idxConfirmedTransactions
    AddressChanged r@AddressChangeRequest{acreqAddress} -> do
        idx <- gets _idxIdx
        let itms = Index.transactionsAt idx (slotRange r) acreqAddress
        logDebug $ HandlingAddressChangeRequest r itms
        pure $ AddressChangeResponse
            { acrAddress=acreqAddress
            , acrSlotRange=slotRange r
            , acrTxns = fmap ciTx itms
            }
