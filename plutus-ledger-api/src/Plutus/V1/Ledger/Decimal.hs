{-# LANGUAGE DeriveAnyClass       #-}
{-# LANGUAGE DerivingStrategies   #-}
{-# LANGUAGE FlexibleContexts     #-}
{-# LANGUAGE TemplateHaskell      #-}
{-# LANGUAGE UndecidableInstances #-}

-- TODO: Minimize round-off errors
module Plutus.V1.Ledger.Decimal
  ( OnChainDecimal(..)
  , decimalUnit
  ) where

import           Data.Aeson
import           Data.Scientific (Scientific)
import qualified PlutusTx

decimalsCnt :: Int
decimalsCnt = 6

decimalUnit :: Integer
decimalUnit = 10 ^ decimalsCnt

scientificUnit :: Scientific
scientificUnit = fromIntegral decimalUnit

-- TODO: Change `Integer` to `Double` then wrap it here?
-- Also use this for `Value`?
newtype OnChainDecimal = OnChainDecimal { getOnChainInt :: Integer }
  deriving newtype (PlutusTx.IsData, Num, Enum, Real, Integral)
  deriving (Eq, Ord, Show)

instance ToJSON OnChainDecimal where
  toJSON (OnChainDecimal i) = Number . (/ scientificUnit) . fromIntegral $ i

instance FromJSON OnChainDecimal where
  parseJSON = withScientific
    "OnChainDecimal"
    (return . OnChainDecimal . round . (*) scientificUnit)

PlutusTx.makeLift ''OnChainDecimal
