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
{-|

Mock wallet implementation

-}
module Wallet.API(
    WalletEffect,
    submitTxn,
    ownPubKey,
    balanceTx,
    NodeClientEffect,
    publishTx,
    getClientSlot,
    ChainIndexEffect,
    startWatching,
    watchedAddresses,
    PubKey(..),
    Payment(..),
    emptyPayment,
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
    throwInsufficientFundsError,
    throwOtherError,
    ) where

import           Control.Monad               (void)
import           Control.Monad.Freer
import           Control.Monad.Freer.Error   (Error, throwError)
import           Ledger                      hiding (inputs, out, value)
import           Ledger.Constraints.OffChain (UnbalancedTx (..), emptyUnbalancedTx)
import           Wallet.Effects
import           Wallet.Emulator.Error
import           Wallet.Types                (emptyPayment)

import           Prelude                     hiding (Ordering (..))

-- | Transfer some funds to an address locked by a public key, returning the
--   transaction that was submitted.
payToPublicKey ::
    ( Member WalletEffect effs
    , Member (Error WalletAPIError) effs
    )
    => SlotRange -> Value -> PubKey -> Eff effs Tx
payToPublicKey range v pk = do
    let tx = mempty{txOutputs = [pubKeyTxOut v pk], txValidRange = range}
    balancedTx <- balanceTx emptyUnbalancedTx{unBalancedTxTx = tx}
    either throwError (\t -> do { submitTxn t; pure t }) balancedTx

-- | Transfer some funds to an address locked by a public key.
payToPublicKey_ ::
    ( Member WalletEffect effs
    , Member (Error WalletAPIError) effs
    )
    => SlotRange -> Value -> PubKey -> Eff effs ()
payToPublicKey_ r v = void . payToPublicKey r v

-- | The default slot validity range for transactions.
defaultSlotRange :: SlotRange
defaultSlotRange = always
