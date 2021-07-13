{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE NamedFieldPuns #-}

-- | Configuring and calculating transaction fees.
module Ledger.Fee(
  FeeConfig (..)
, calcFees
) where

import           Data.Aeson           (FromJSON, ToJSON)
import           Data.Default         (Default (def))
import           GHC.Generics         (Generic)
import           Ledger.Index         (minFee)
import           Plutus.V1.Ledger.Ada (Ada)
import qualified Plutus.V1.Ledger.Ada as Ada

-- | Datatype to configure the fee in a transaction.
--
-- The fee for a transaction is typically: 'fcConstantFee + 'fcScriptsFeeFactor' *
-- <SIZE_DEPENDENT_SCRIPTS_FEE>
data FeeConfig =
    FeeConfig
        { fcConstantFee      :: Ada    -- ^ Constant fee per transaction in lovelace
        , fcScriptsFeeFactor :: Double -- ^ Factor by which to multiply the size-dependent scripts fee
        }
    deriving (Show, Eq, Generic, ToJSON, FromJSON)

instance Default FeeConfig where
  def = FeeConfig { fcConstantFee = Ada.fromValue $ minFee mempty
                  , fcScriptsFeeFactor = 1.0
                  }

calcFees :: FeeConfig
         -> Integer -- ^ Scripts fee in lovelace
         -> Ada -- ^ Fees in lovelace
calcFees FeeConfig { fcConstantFee , fcScriptsFeeFactor } scriptsFee =
     fcConstantFee
  <> Ada.lovelaceOf (floor $ fcScriptsFeeFactor * fromIntegral scriptsFee)
