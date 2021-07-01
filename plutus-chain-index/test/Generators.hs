{-# LANGUAGE DataKinds            #-}
{-# LANGUAGE FlexibleContexts     #-}
{-# LANGUAGE LambdaCase           #-}
{-# LANGUAGE MonoLocalBinds       #-}
{-# LANGUAGE TemplateHaskell      #-}
{-# LANGUAGE TypeOperators        #-}
{-# LANGUAGE UndecidableInstances #-}
{-| Hedgehog generators for types used in plutus-chain-index
-}
module Generators(
    genTxOutRef,
    genRandomTxId,
    genSlot,
    genBlockId,
    -- * Stateful generator for UTXO modifications
    genTxUtxoBalance,
    evalUtxoGenState
    ) where

import           Codec.Serialise             (serialise)
import           Control.Lens                (makeLenses, over, view)
import           Control.Monad.Freer         (Eff, LastMember, Member, runM, sendM, type (~>))
import           Control.Monad.Freer.State   (State, evalState, gets, modify)
import qualified Data.ByteString.Lazy        as BSL
import           Data.Set                    (Set)
import qualified Data.Set                    as Set
import           Hedgehog                    (MonadGen)
import qualified Hedgehog.Gen                as Gen
import qualified Hedgehog.Range              as Range
import           Ledger.Slot                 (Slot (..))
import           Ledger.Tx                   (TxOutRef (..))
import           Ledger.TxId                 (TxId (..))
import           Plutus.ChainIndex.Types     (BlockId (..))
import           Plutus.ChainIndex.UtxoState (TxUtxoBalance (..))
import qualified PlutusTx.ByteString         as PlutusTx

-- | Generate a random tx id
genRandomTxId :: MonadGen m => m TxId
genRandomTxId = TxId . PlutusTx.fromHaskellByteString <$> Gen.bytes (Range.singleton 32)

-- | Generate one of a known set of tx IDs
genKnownTxId :: MonadGen m => m TxId
genKnownTxId = Gen.element (txIdFromInt <$> [(1::Int)..50])

txIdFromInt :: Int -> TxId
txIdFromInt = TxId . PlutusTx.fromHaskellByteString . BSL.toStrict . serialise

-- | Generate a tx id, using a known tx id in 80% of cases and a random one
--   in 20%.
genTxId :: MonadGen m => m TxId
genTxId = Gen.frequency [(8, genKnownTxId), (2, genRandomTxId)]

-- | Generate a random 'TxOutRef'
genTxOutRef :: MonadGen m => m TxOutRef
genTxOutRef =  TxOutRef <$> genTxId <*> Gen.integral (Range.linear 0 50)

genBlockId :: MonadGen m => m BlockId
genBlockId = BlockId <$> Gen.bytes (Range.singleton 32)

genSlot :: MonadGen m => m Slot
genSlot = Slot <$> Gen.integral (Range.linear 0 100000000)

-- | State of the TxOutRef generator.
data UtxoGenState =
        UtxoGenState
            { _uxUtxoSet         :: Set TxOutRef
            , _uxNumTransactions :: Int
            }

makeLenses ''UtxoGenState

initialState :: UtxoGenState
initialState = UtxoGenState mempty 0

data ChainAction = AddTx | DoNothing

genChainAction :: MonadGen m => m ChainAction
genChainAction = Gen.frequency [(6, pure AddTx), (4, pure DoNothing)]

nextTxId :: forall effs. Member (State UtxoGenState) effs => Eff effs TxId
nextTxId = do
    lastIdx <- gets (view uxNumTransactions)
    let newId = txIdFromInt lastIdx
    modify (over uxNumTransactions succ)
    pure newId

availableInputs :: forall effs. Member (State UtxoGenState) effs => Eff effs [TxOutRef]
availableInputs = gets (Set.toList . view uxUtxoSet)

deleteInputs :: forall effs. Member (State UtxoGenState) effs => Set TxOutRef -> Eff effs ()
deleteInputs spent = modify (over uxUtxoSet (\s -> s `Set.difference` spent))

-- | Generate a 'TxUtxoBalance' based on the state of utxo changes produced so
--   far. Ensures that tx outputs are created before they are spent, and that
--   tx IDs are unique.
genTxUtxoBalance ::
    forall m effs.
    ( Member (State UtxoGenState) effs
    , LastMember m effs
    , MonadGen m
    ) => Eff effs TxUtxoBalance
genTxUtxoBalance = sendM genChainAction >>= \case
    DoNothing -> pure mempty
    AddTx -> do
        txId <- nextTxId
        numOutputs <- sendM (Gen.integral (Range.linear 0 50))
        let newOutputs = TxOutRef txId <$> [1..numOutputs]
        inputs <- availableInputs
        spentInputs <- Set.fromList <$> sendM (Gen.subsequence inputs)
        deleteInputs spentInputs
        pure $ TxUtxoBalance{tubUnspentOutputs = Set.fromList newOutputs, tubUnmatchedSpentInputs = spentInputs}

evalUtxoGenState :: forall m. Monad m => Eff '[State UtxoGenState, m] ~> m
evalUtxoGenState = runM . evalState initialState
