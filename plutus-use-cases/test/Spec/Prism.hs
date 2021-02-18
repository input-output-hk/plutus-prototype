{-# LANGUAGE DataKinds         #-}
{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications  #-}
module Spec.Prism(tests, prismTrace) where

import           Control.Monad                                             (void)
import           Language.Plutus.Contract.Test
import qualified Ledger.Ada                                                as Ada
import           Ledger.Crypto                                             (pubKeyHash)
import           Ledger.Value                                              (TokenName)

import           Test.Tasty

import           Language.PlutusTx.Coordination.Contracts.Prism            hiding (credentialManager, mirror)
import qualified Language.PlutusTx.Coordination.Contracts.Prism.Credential as Credential
import           Language.PlutusTx.Coordination.Contracts.Prism.STO        (STOData (..))
import qualified Language.PlutusTx.Coordination.Contracts.Prism.STO        as STO
import qualified Plutus.Trace.Emulator                                     as Trace

user, credentialManager, mirror, issuer :: Wallet
user = Wallet 1
mirror = Wallet 2
credentialManager = Wallet 3
issuer = Wallet 4

kyc :: TokenName
kyc = "KYC"

sto :: TokenName
sto = "STO token"

numTokens :: Integer
numTokens = 1000

credential :: Credential
credential =
    Credential
        { credName = kyc
        , credAuthority = CredentialAuthority (pubKeyHash $ walletPubKey mirror)
        }

stoSubscriber :: STOSubscriber
stoSubscriber =
    STOSubscriber
        { wCredential = credential
        , wSTOIssuer = pubKeyHash $ walletPubKey issuer
        , wSTOTokenName = sto
        , wSTOAmount = numTokens
        }

stoData :: STOData
stoData =
    STOData
        { stoIssuer = pubKeyHash $ walletPubKey issuer
        , stoTokenName = sto
        , stoCredentialToken = Credential.token credential
        }

tests :: TestTree
tests = testGroup "PRISM"
    [ checkPredicate "withdraw"
        (assertDone contract (Trace.walletInstanceTag user) (const True) ""
        .&&. walletFundsChange issuer (Ada.lovelaceValueOf numTokens)
        .&&. walletFundsChange user (Ada.lovelaceValueOf (negate numTokens) <> STO.coins stoData numTokens)
        )
        prismTrace
    ]

-- | 'mirror' issues a KYC token to 'user', who then uses it in an STO transaction
prismTrace :: Trace.EmulatorTrace ()
prismTrace = do
    uhandle <- Trace.activateContractWallet user contract
    mhandle <- Trace.activateContractWallet mirror contract
    chandle <- Trace.activateContractWallet credentialManager contract

    Trace.callEndpoint_ @"role" uhandle UnlockSTO
    Trace.callEndpoint_ @"role" mhandle Mirror
    Trace.callEndpoint_ @"role" chandle CredMan
    _ <- Trace.waitNSlots 2

    -- issue a KYC credential to a user
    Trace.callEndpoint_ @"issue" mhandle CredentialOwnerReference{coTokenName=kyc, coOwner=user}
    _ <- Trace.waitNSlots 2

    -- participate in STO presenting the token
    Trace.callEndpoint_ @"sto" uhandle stoSubscriber
    _ <- Trace.waitNSlots 2 -- needed?
    Trace.callEndpoint_ @"credential manager" uhandle (Trace.chInstanceId chandle)
    void $ Trace.waitNSlots 2
