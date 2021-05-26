{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE ConstraintKinds     #-}
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE DeriveAnyClass      #-}
{-# LANGUAGE DerivingVia         #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE LambdaCase          #-}
{-# LANGUAGE MonoLocalBinds      #-}
{-# LANGUAGE OverloadedLabels    #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE TypeApplications    #-}
{-# LANGUAGE TypeOperators       #-}
module Plutus.Contract.Effects.WriteTx where

import           Control.Lens
import           Data.Aeson                               (FromJSON, ToJSON)
import qualified Data.Map                                 as M
import           Data.Row
import           Data.Text.Prettyprint.Doc
import           Data.Void                                (Void)
import           GHC.Generics                             (Generic)

import           Plutus.Contract.Effects.AwaitTxConfirmed (HasTxConfirmation, awaitTxConfirmed)
import           Plutus.Contract.Effects.UtxoAt           (HasUtxoAt, utxoAt)
import           Plutus.Contract.Request                  as Req
import           Plutus.Contract.Schema                   (Event (..), Handlers (..), Input, Output)
import           Plutus.Contract.Typed.Tx                 (collectFromScript)
import           Plutus.Contract.Types                    (AsContractError, Contract, _ConstraintResolutionError,
                                                           _WalletError, throwError)
import qualified PlutusTx

import qualified Ledger
import           Ledger.AddressMap                        (UtxoMap)
import           Ledger.Constraints                       (TxConstraints, mustPayToTheScript)
import           Ledger.Constraints.OffChain              (ScriptLookups, UnbalancedTx)
import qualified Ledger.Constraints.OffChain              as Constraints
import           Ledger.Tx                                (Tx, txId)
import           Ledger.Typed.Scripts                     (ScriptInstance, ScriptType (..), validatorScript)

import           Wallet.API                               (WalletAPIError)

type TxSymbol = "tx"

data WriteTxResponse =
  WriteTxFailed WalletAPIError
  | WriteTxSuccess Tx
  deriving stock (Eq, Show, Generic)
  deriving anyclass (ToJSON, FromJSON)

instance Pretty WriteTxResponse where
  pretty = \case
    WriteTxFailed e  -> "WriteTxFailed:" <+> pretty e
    WriteTxSuccess i -> "WriteTxSuccess:" <+> pretty (txId i)

writeTxResponse :: Iso' WriteTxResponse (Either WalletAPIError Tx)
writeTxResponse = iso f g where
  f = \case { WriteTxFailed w -> Left w; WriteTxSuccess t -> Right t }
  g = either WriteTxFailed WriteTxSuccess

type HasWriteTx s =
    ( HasType TxSymbol WriteTxResponse (Input s)
    , HasType TxSymbol UnbalancedTx (Output s)
    , ContractRow s)

type WriteTx = TxSymbol .== (WriteTxResponse, UnbalancedTx)

-- | Send an unbalanced transaction to be balanced and signed. Returns the ID
--    of the final transaction when the transaction was submitted. Throws an
--    error if balancing or signing failed.
submitUnbalancedTx :: forall w s e. (AsContractError e, HasWriteTx s) => UnbalancedTx -> Contract w s e Tx
-- See Note [Injecting errors into the user's error type]
submitUnbalancedTx t =
  let req = request @w @TxSymbol @_ @_ @s t in
  req >>= either (throwError . review _WalletError) pure . view writeTxResponse

-- | Build a transaction that satisfies the constraints, then submit it to the
--   network. The constraints do not refer to any typed script inputs or
--   outputs.
submitTx :: forall w s e.
  ( HasWriteTx s
  , AsContractError e
  )
  => TxConstraints Void Void
  -> Contract w s e Tx
submitTx = submitTxConstraintsWith @Void mempty

-- | Build a transaction that satisfies the constraints, then submit it to the
--   network. Using the current outputs at the contract address and the
--   contract's own public key to solve the constraints.
submitTxConstraints
  :: forall a w s e.
  ( HasWriteTx s
  , PlutusTx.IsData (RedeemerType a)
  , PlutusTx.IsData (DatumType a)
  , AsContractError e
  )
  => ScriptInstance a
  -> TxConstraints (RedeemerType a) (DatumType a)
  -> Contract w s e Tx
submitTxConstraints inst = submitTxConstraintsWith (Constraints.scriptInstanceLookups inst)

-- | Build a transaction that satisfies the constraints using the UTXO map
--   to resolve any input constraints (see 'Ledger.Constraints.TxConstraints.InputConstraint')
submitTxConstraintsSpending
  :: forall a w s e.
  ( HasWriteTx s
  , PlutusTx.IsData (RedeemerType a)
  , PlutusTx.IsData (DatumType a)
  , AsContractError e
  )
  => ScriptInstance a
  -> UtxoMap
  -> TxConstraints (RedeemerType a) (DatumType a)
  -> Contract w s e Tx
submitTxConstraintsSpending inst utxo =
  let lookups = Constraints.scriptInstanceLookups inst <> Constraints.unspentOutputs utxo
  in submitTxConstraintsWith lookups

-- | Build a transaction that satisfies the constraints, then submit it to the
--   network. Using the given constraints.
submitTxConstraintsWith
  :: forall a w s e.
  ( HasWriteTx s
  , PlutusTx.IsData (RedeemerType a)
  , PlutusTx.IsData (DatumType a)
  , AsContractError e
  )
  => ScriptLookups a
  -> TxConstraints (RedeemerType a) (DatumType a)
  -> Contract w s e Tx
submitTxConstraintsWith sl constraints = do
  tx <- either (throwError . review _ConstraintResolutionError) pure (Constraints.mkTx sl constraints)
  submitUnbalancedTx tx

-- | A version of 'submitTx' that waits until the transaction has been
--   confirmed on the ledger before returning.
submitTxConfirmed
  :: forall w s e.
  ( HasWriteTx s
  , HasTxConfirmation s
  , AsContractError e
  )
  => UnbalancedTx
  -> Contract w s e ()
submitTxConfirmed t = submitUnbalancedTx t >>= awaitTxConfirmed . txId

event
  :: forall s. (HasType TxSymbol WriteTxResponse (Input s), AllUniqueLabels (Input s))
  => WriteTxResponse
  -> Event s
event r = Event (IsJust #tx r)

pendingTransaction
  :: forall s. ( HasType TxSymbol UnbalancedTx (Output s) )
   => Handlers s
   -> Maybe UnbalancedTx
pendingTransaction (Handlers r) = trial' r (Label @TxSymbol)

-- Utility functions

-- Create an on-chain script with a datum and some locked value
createScript
  :: ( HasWriteTx s
     , PlutusTx.IsData (RedeemerType a)
     , PlutusTx.IsData (DatumType a)
     , AsContractError e
     )
  => ScriptInstance a
  -> DatumType a
  -> Ledger.Value
  -> Contract w s e Tx
createScript i d v =
  submitTxConstraints i (mustPayToTheScript d v)

-- Update an on-chain script
-- TODO: Support Semigroup-style append update
updateScript
  :: ( HasWriteTx s
     , HasUtxoAt s
     , PlutusTx.IsData (RedeemerType a)
     , PlutusTx.IsData (DatumType a)
     , AsContractError e
     )
  => ScriptInstance a
  -> DatumType a
  -> RedeemerType a
  -> Ledger.Value
  -> Contract w s e Tx
updateScript i d r v = do
  unspentOuts <- utxoAt $ getAddressFromInstance i
  submitTxConstraintsSpending i unspentOuts
    $  collectFromScript unspentOuts r
    <> mustPayToTheScript d v

-- Check if an on-chain script exists,
-- If it does, update it, if not then create it
-- TODO: Add a parameter for a possible locked value?
upsertScript
  :: ( HasWriteTx s
     , HasUtxoAt s
     , PlutusTx.IsData (RedeemerType a)
     , PlutusTx.IsData (DatumType a)
     , Semigroup (DatumType a)
     , AsContractError e
     )
  => ScriptInstance a
  -> DatumType a
  -> RedeemerType a
  -> Contract w s e Tx
upsertScript i d r = getDatumFromAddress (getAddressFromInstance i) >>= \case
  Just prevDatum -> updateScript i (prevDatum <> d) r mempty
  _              -> createScript i d mempty

getAddressFromInstance :: ScriptInstance a -> Ledger.Address
getAddressFromInstance = Ledger.scriptAddress . validatorScript

-- Get the datum at an address
-- TODO: Generalize this, remove unsafe code
getDatumFromAddress
  :: (HasUtxoAt s, PlutusTx.IsData a, AsContractError e)
  => Ledger.Address
  -> Contract w s e (Maybe a)
getDatumFromAddress address =
  utxoAt address
    >>= (\case
          [(_, tx)] ->
            pure
              $ PlutusTx.fromData
              $ Ledger.getDatum
              $ snd
              $ head
              $ M.toList
              $ Ledger.txData (Ledger.txOutTxTx tx)
          _ -> pure Nothing
        )
    .   M.toList
