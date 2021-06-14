{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE ConstraintKinds     #-}
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE DerivingStrategies  #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE FlexibleInstances   #-}
{-# LANGUAGE GADTs               #-}
{-# LANGUAGE LambdaCase          #-}
{-# LANGUAGE NamedFieldPuns      #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE RankNTypes          #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TupleSections       #-}
{-# LANGUAGE TypeFamilies        #-}
{-# OPTIONS_GHC -Wno-orphans #-}
{-# OPTIONS_GHC -fno-omit-interface-pragmas #-}
{-# OPTIONS_GHC -fno-ignore-interface-pragmas #-}
-- | The interface between the wallet and Plutus client code.
module Wallet.API(
    WalletEffect,
    submitTxn,
    ownPubKey,
    updatePaymentWithChange,
    walletSlot,
    ownOutputs,
    NodeClientEffect,
    publishTx,
    getClientSlot,
    ChainIndexEffect,
    startWatching,
    watchedAddresses,
    PubKey(..),
    Payment(..),
    emptyPayment,
    signTxAndSubmit,
    signTxAndSubmit_,
    payToPublicKey,
    payToPublicKey_,
    -- * Slot ranges
    Interval(..),
    Slot,
    SlotRange,
    width,
    defaultSlotRange,
    interval,
    singleton,
    isEmpty,
    always,
    member,
    before,
    after,
    contains,
    -- * Error handling
    WalletAPIError(..),
    ChainIndexAPIError(..),
    throwInsufficientFundsError,
    throwOtherError,
    ) where

import           Control.Monad         (void)
import           Control.Monad.Freer
import qualified Data.Map              as Map
import           Data.Maybe            (maybeToList)
import qualified Data.Set              as Set
import           Ledger                hiding (inputs, out, value)
import           Wallet.Effects
import           Wallet.Emulator.Error
import           Wallet.Types          (emptyPayment)

import           Prelude               hiding (Ordering (..))

createPaymentWithChange :: Member WalletEffect effs => Value -> Eff effs Payment
createPaymentWithChange v =
    updatePaymentWithChange v emptyPayment

-- | Transfer some funds to an address locked by a public key, returning the
--   transaction that was submitted.
payToPublicKey ::
    ( Member WalletEffect effs
    )
    => SlotRange -> Value -> PubKey -> Eff effs Tx
payToPublicKey range v pk = do
    p <- createPaymentWithChange v
    let other = pubKeyTxOut v pk
    let tx = createTx range (paymentInputs p) (other : maybeToList (paymentChangeOutput p)) []
    p' <- updatePaymentWithChange (txFee tx) p
    let tx' = createTx range (paymentInputs p') (other : maybeToList (paymentChangeOutput p')) []
    signTxAndSubmit tx'

-- | Transfer some funds to an address locked by a public key.
payToPublicKey_ ::
    ( Member WalletEffect effs
    )
    => SlotRange -> Value -> PubKey -> Eff effs ()
payToPublicKey_ r v = void . payToPublicKey r v

-- | Create a transaction, sign it with the wallet's private key, and submit it.
--   TODO: This is here to make the calculation of fees easier for old-style contracts
--         and should be removed when all contracts have been ported to the new API.
createTx ::
       SlotRange
    -> Set.Set TxIn
    -> [TxOut]
    -> [Datum]
    -> Tx
createTx range ins outs datas = do
    let tx = mempty
            { txInputs = ins
            , txOutputs = outs
            , txValidRange = range
            , txData = Map.fromList $ fmap (\ds -> (datumHash ds, ds)) datas
            }
    tx { txFee = minFee tx }

-- | Add the wallet's signature to the transaction and submit it. Returns
--   the transaction with the wallet's signature.
signTxAndSubmit ::
    ( Member WalletEffect effs )
    => Tx -> Eff effs Tx
signTxAndSubmit t = do
    tx' <- walletAddSignature t
    submitTxn tx'
    pure tx'

-- | A version of 'signTxAndSubmit' that discards the result.
signTxAndSubmit_ ::
    ( Member WalletEffect effs )
    => Tx -> Eff effs ()
signTxAndSubmit_ = void . signTxAndSubmit

-- | The default slot validity range for transactions.
defaultSlotRange :: SlotRange
defaultSlotRange = always
