{-# LANGUAGE DataKinds         #-}
{-# LANGUAGE KindSignatures    #-}
{-# LANGUAGE NamedFieldPuns    #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE TemplateHaskell   #-}
{-# LANGUAGE TypeFamilies      #-}
{-# LANGUAGE ViewPatterns      #-}
{-# OPTIONS_GHC -fno-specialise #-}
{-# OPTIONS_GHC -fno-strictness #-}
{-# OPTIONS_GHC -Wno-simplifiable-class-constraints #-}
{-# OPTIONS_GHC -fno-omit-interface-pragmas #-}
{-# OPTIONS_GHC -fno-ignore-interface-pragmas #-}
module Ledger.Typed.Scripts.MonetaryPolicies (
    WrappedMintingPolicyType
    , wrapMintingPolicy
    , mkForwardingMintingPolicy
    , forwardToValidator
    , Any
    ) where

import           PlutusTx
import           PlutusTx.Prelude

import           Plutus.V1.Ledger.Address    (Address (..))
import           Plutus.V1.Ledger.Contexts   (ScriptContext (..), ScriptPurpose (..), TxInfo (..))
import qualified Plutus.V1.Ledger.Contexts   as Validation
import           Plutus.V1.Ledger.Credential (Credential (..))
import           Plutus.V1.Ledger.Scripts
import           Plutus.V1.Ledger.Tx         (TxOut (..))

import           Ledger.Typed.TypeUtils

type WrappedMintingPolicyType = BuiltinData -> BuiltinData -> ()

-- TODO: we should add a TypedMintingPolicy interface here

{-# INLINABLE wrapMintingPolicy #-}
wrapMintingPolicy
    :: IsData r
    => (r -> Validation.ScriptContext -> Bool)
    -> WrappedMintingPolicyType
wrapMintingPolicy f (fromBuiltinData -> Just r) (fromBuiltinData -> Just p) = check $ f r p
wrapMintingPolicy _ _                    _                                  = check False

-- | A minting policy that checks whether the validator script was run
--   in the minting transaction.
mkForwardingMintingPolicy :: ValidatorHash -> MintingPolicy
mkForwardingMintingPolicy vshsh =
    mkMintingPolicyScript
    $ ($$(PlutusTx.compile [|| \(hsh :: ValidatorHash) -> wrapMintingPolicy (forwardToValidator hsh) ||]))
       `PlutusTx.applyCode` PlutusTx.liftCode vshsh

{-# INLINABLE forwardToValidator #-}
forwardToValidator :: ValidatorHash -> () -> ScriptContext -> Bool
forwardToValidator h _ ScriptContext{scriptContextTxInfo=TxInfo{txInfoInputs}, scriptContextPurpose=Minting _} =
    let checkHash TxOut{txOutAddress=Address{addressCredential=ScriptCredential vh}} = vh == h
        checkHash _                                                                  = False
    in any (checkHash . Validation.txInInfoResolved) txInfoInputs
forwardToValidator _ _ _ = False
