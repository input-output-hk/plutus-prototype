{-# LANGUAGE NamedFieldPuns   #-}
{-# LANGUAGE TypeApplications #-}

module Cardano.Wallet.Client where

import           Cardano.Wallet.API     (API)
import           Cardano.Wallet.Types   (WalletId)
import qualified Data.ByteString.Lazy   as BSL
import           Data.Function          ((&))
import           Data.Proxy             (Proxy (Proxy))
import           Ledger                 (Address, PubKey, Signature, Value)
import           Ledger.AddressMap      (AddressMap)
import           Servant                (NoContent)
import           Servant.Client         (ClientM, client)
import           Servant.Extra          (left, right)
import           Wallet.Emulator.Wallet (Wallet)

selectCoins :: WalletId -> Value -> ClientM ([Value], Value)
allocateAddress :: WalletId -> ClientM PubKey
getWatchedAddresses :: ClientM AddressMap
getWallets :: ClientM [Wallet]
getOwnPubKey :: ClientM PubKey
startWatching :: Address -> ClientM NoContent
sign :: BSL.ByteString -> ClientM Signature
(getWallets, getOwnPubKey, sign, getWatchedAddresses, startWatching, selectCoins, allocateAddress) =
    ( getWallets_
    , getOwnPubKey_
    , sign_
    , getWatchedAddresses_
    , startWatching_
    , selectCoins_
    , allocateAddress_)
  where
    api = client (Proxy @API)
    getWallets_ = api & left
    active_ = api & right & left
    getOwnPubKey_ = active_ & left
    sign_ = active_ & right & left
    getWatchedAddresses_ = active_ & right & right & left
    startWatching_ = active_ & right & right & right
    byWalletId = api & right & right
    selectCoins_ walletId = byWalletId walletId & left
    allocateAddress_ walletId = byWalletId walletId & right
