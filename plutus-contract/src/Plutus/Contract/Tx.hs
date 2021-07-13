{-# LANGUAGE DataKinds          #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE FlexibleContexts   #-}
{-# LANGUAGE FlexibleInstances  #-}
{-# LANGUAGE NamedFieldPuns     #-}
{-# LANGUAGE TypeApplications   #-}
module Plutus.Contract.Tx where

import           Control.Lens
import           Data.Maybe                       (fromMaybe)

import           Ledger                           (Redeemer (..), TxOutRef, TxOutTx, Validator)
import qualified Ledger.Address                   as Address
import           Ledger.AddressMap                (AddressMap)
import           Ledger.Constraints.TxConstraints (UntypedConstraints)
import qualified Plutus.Contract.Typed.Tx         as Typed
import qualified PlutusTx                         as PlutusTx

-- | A set of constraints for a transaction that collects script outputs
--   from the address of the given validator script, using the same redeemer
--   script for all outputs.
collectFromScript
    :: AddressMap
    -> Validator
    -> Redeemer
    -> UntypedConstraints
collectFromScript = collectFromScriptFilter (\_ -> const True)

-- | See
collectFromScriptFilter
    :: (TxOutRef -> TxOutTx -> Bool)
    -> AddressMap
    -> Validator
    -> Redeemer
    -> UntypedConstraints
collectFromScriptFilter flt am vls (Redeemer red) =
    let mp'  = fromMaybe mempty $ am ^. at (Address.scriptAddress vls)
    in Typed.collectFromScriptFilter @PlutusTx.BuiltinData @PlutusTx.BuiltinData flt mp' red
