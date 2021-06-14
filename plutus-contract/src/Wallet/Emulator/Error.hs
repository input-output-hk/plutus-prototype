{-# LANGUAGE DeriveAnyClass     #-}
{-# LANGUAGE DeriveGeneric      #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE FlexibleContexts   #-}
{-# LANGUAGE LambdaCase         #-}
{-# LANGUAGE MonoLocalBinds     #-}
{-# LANGUAGE OverloadedStrings  #-}
module Wallet.Emulator.Error where

import           Control.Monad.Freer       (Eff, Member)
import           Control.Monad.Freer.Error (Error, throwError)
import           Data.Aeson                (FromJSON, ToJSON)
import           Data.Text                 (Text)
import           Data.Text.Prettyprint.Doc
import           GHC.Generics              (Generic)

import           Ledger                    (PubKeyHash, ValidationError)

-- | An error thrown by wallet interactions.
data WalletAPIError =
    InsufficientFunds Text
    -- ^ There were insufficient funds to perform the desired operation.
    | PrivateKeyNotFound PubKeyHash
    -- ^ The private key of this public key hahs is not known to the wallet.
    | ValidationError ValidationError
    -- ^ There was an error during off-chain validation.
    | OtherError Text
    -- ^ Some other error occurred.
    deriving stock (Show, Eq, Generic)

instance Pretty WalletAPIError where
    pretty = \case
        InsufficientFunds t ->
            "Insufficient funds:" <+> pretty t
        PrivateKeyNotFound pk ->
            "Private key not found:" <+> viaShow pk
        ValidationError e ->
            "Validation error:" <+> pretty e
        OtherError t ->
            "Other error:" <+> pretty t

instance FromJSON WalletAPIError
instance ToJSON WalletAPIError

throwInsufficientFundsError :: Member (Error WalletAPIError) effs => Text -> Eff effs a
throwInsufficientFundsError = throwError . InsufficientFunds

throwOtherError :: Member (Error WalletAPIError) effs => Text -> Eff effs a
throwOtherError = throwError . OtherError

-- | An error thrown by chain index APIs
newtype ChainIndexAPIError =
    OtherChainIndexError Text
    -- ^ Some other error occurred.
    deriving stock (Show, Eq, Ord, Generic)

instance Pretty ChainIndexAPIError where
    pretty (OtherChainIndexError e) = "Other error:" <+> pretty e

instance FromJSON ChainIndexAPIError
instance ToJSON ChainIndexAPIError
