{-# LANGUAGE DataKinds         #-}
{-# LANGUAGE DeriveAnyClass    #-}
{-# LANGUAGE DerivingVia       #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell   #-}
{-# OPTIONS_GHC -fno-specialise #-}
{-# OPTIONS_GHC -fno-strictness #-}
{-# OPTIONS_GHC -Wno-simplifiable-class-constraints #-}
{-# OPTIONS_GHC -fno-omit-interface-pragmas #-}

module Plutus.V1.Ledger.Address (
    Address (..),
    pubKeyAddress,
    pubKeyHashAddress,
    scriptAddress,
    scriptHashAddress,
    toPubKeyHash,
    toValidatorHash,
    stakingCredential
    ) where

import           Codec.Serialise.Class       (Serialise)
import           Control.DeepSeq             (NFData)
import           Data.Aeson                  (FromJSON, FromJSONKey (..), ToJSON, ToJSONKey (..))
import           Data.Hashable               (Hashable)
import           Data.Text.Prettyprint.Doc
import           GHC.Generics                (Generic)
import qualified PlutusTx                    as PlutusTx
import qualified PlutusTx.Bool               as PlutusTx
import qualified PlutusTx.Eq                 as PlutusTx

import           Plutus.V1.Ledger.Credential (Credential (..), StakingCredential)
import           Plutus.V1.Ledger.Crypto
import           Plutus.V1.Ledger.Orphans    ()
import           Plutus.V1.Ledger.Scripts

-- | Address with two kinds of credentials, normal and staking
data Address = Address{ addressCredential :: !Credential, addressStakingCredential :: !(Maybe StakingCredential)}
    deriving stock (Eq, Ord, Show, Generic)
    deriving anyclass (ToJSON, FromJSON, ToJSONKey, FromJSONKey, Serialise, Hashable, NFData)

instance Pretty Address where
    pretty (Address cred stakingCred) = pretty cred <+> pretty stakingCred

instance PlutusTx.Eq Address where
    Address cred stakingCred == Address cred' stakingCred' =
        cred PlutusTx.== cred'
        PlutusTx.&& stakingCred PlutusTx.== stakingCred'

{-# INLINABLE pubKeyAddress #-}
-- | The address that should be targeted by a transaction output locked by the given public key.
pubKeyAddress :: PubKey -> Address
pubKeyAddress pk = Address (PubKeyCredential (pubKeyHash pk)) Nothing

{-# INLINABLE pubKeyHashAddress #-}
-- | The address that should be targeted by a transaction output locked by the public key with the given hash.
pubKeyHashAddress :: PubKeyHash -> Address
pubKeyHashAddress pkh = Address (PubKeyCredential pkh) Nothing

{-# INLINABLE toPubKeyHash #-}
-- | The PubKeyHash of the address, if any
toPubKeyHash :: Address -> Maybe PubKeyHash
toPubKeyHash (Address (PubKeyCredential k) _) = Just k
toPubKeyHash _                                = Nothing

{-# INLINABLE toValidatorHash #-}
-- | The validator hash of the address, if any
toValidatorHash :: Address -> Maybe ValidatorHash
toValidatorHash (Address (ScriptCredential k) _) = Just k
toValidatorHash _                                = Nothing

-- | The address that should be used by a transaction output locked by the given validator script.
scriptAddress :: Validator -> Address
scriptAddress validator = Address (ScriptCredential (validatorHash validator)) Nothing

{-# INLINABLE scriptHashAddress #-}
-- | The address that should be used by a transaction output locked by the given validator script hash.
scriptHashAddress :: ValidatorHash -> Address
scriptHashAddress vh = Address (ScriptCredential vh) Nothing

{-# INLINABLE stakingCredential #-}
-- | The staking credential of an address (if any)
stakingCredential :: Address -> Maybe StakingCredential
stakingCredential (Address _ s) = s

PlutusTx.makeIsDataIndexed ''Address [('Address,0)]
PlutusTx.makeLift ''Address
