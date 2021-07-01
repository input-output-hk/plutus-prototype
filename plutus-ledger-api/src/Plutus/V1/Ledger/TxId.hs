{-# LANGUAGE DeriveAnyClass    #-}
{-# LANGUAGE DerivingVia       #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell   #-}
{-# OPTIONS_GHC -fno-strictness   #-}

-- | The type of transaction IDs
module Plutus.V1.Ledger.TxId(
    TxId (..)
    ) where

import           Codec.Serialise.Class     (Serialise)
import           Control.DeepSeq           (NFData)
import           Data.Aeson                (FromJSON, FromJSONKey, ToJSON, ToJSONKey)
import           Data.Text.Prettyprint.Doc (Pretty)
import           GHC.Generics              (Generic)
import           Plutus.V1.Ledger.Bytes    (LedgerBytes (..))
import           Plutus.V1.Ledger.Orphans  ()
import qualified PlutusTx                  as PlutusTx
import qualified PlutusTx.Prelude          as PlutusTx

-- | A transaction ID, using a SHA256 hash as the transaction id.
newtype TxId = TxId { getTxId :: PlutusTx.ByteString }
    deriving (Eq, Ord, Generic)
    deriving anyclass (ToJSON, FromJSON, ToJSONKey, FromJSONKey, NFData)
    deriving newtype (PlutusTx.Eq, PlutusTx.Ord, Serialise)
    deriving (Show, Pretty) via LedgerBytes

PlutusTx.makeLift ''TxId
PlutusTx.makeIsDataIndexed ''TxId [('TxId,0)]
