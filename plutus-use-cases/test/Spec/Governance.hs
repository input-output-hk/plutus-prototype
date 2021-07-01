{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE LambdaCase          #-}
{-# LANGUAGE MonoLocalBinds      #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell     #-}
{-# LANGUAGE TupleSections       #-}
{-# LANGUAGE TypeApplications    #-}
{-# OPTIONS_GHC -fno-strictness  #-}
{-# OPTIONS_GHC -fno-ignore-interface-pragmas #-}
module Spec.Governance(tests, doVoting) where

import           Test.Tasty                  (TestTree, testGroup)
import qualified Test.Tasty.HUnit            as HUnit

import           Control.Lens                (view)
import           Control.Monad               (void)
import           Data.Foldable               (traverse_)

import qualified Ledger
import qualified Ledger.TimeSlot             as TimeSlot
import qualified Ledger.Typed.Scripts        as Scripts
import qualified Wallet.Emulator             as EM

import           Plutus.Contract.Test
import qualified Plutus.Contracts.Governance as Gov
import           Plutus.Trace.Emulator       (EmulatorTrace)
import qualified Plutus.Trace.Emulator       as Trace
import qualified PlutusTx
import           PlutusTx.Prelude            (ByteString, fromHaskellByteString)

tests :: TestTree
tests =
    testGroup "governance tests"
    [ checkPredicate "vote all in favor, 2 rounds - SUCCESS"
        (assertNoFailedTransactions
        .&&. dataAtAddress (Scripts.validatorAddress $ Gov.typedValidator params) ((== lawv3) . Gov.law))
        (doVoting 10 0 2)

    , checkPredicate "vote 60/40, accepted - SUCCESS"
        (assertNoFailedTransactions
        .&&. dataAtAddress (Scripts.validatorAddress $ Gov.typedValidator params) ((== lawv2) . Gov.law))
        (doVoting 6 4 1)

    , checkPredicate "vote 50/50, rejected - SUCCESS"
        (assertNoFailedTransactions
        .&&. dataAtAddress (Scripts.validatorAddress $ Gov.typedValidator params) ((== lawv1) . Gov.law))
        (doVoting 5 5 1)

    , goldenPir "test/Spec/governance.pir" $$(PlutusTx.compile [|| Gov.mkValidator ||])
    , HUnit.testCase "script size is reasonable" (reasonable (Scripts.validatorScript $ Gov.typedValidator params) 20000)
    ]

numberOfHolders :: Integer
numberOfHolders = 10

baseName :: Ledger.TokenName
baseName = "TestLawToken"

-- | A governance contract that requires 6 votes out of 10
params :: Gov.Params
params = Gov.Params
    { Gov.initialHolders = Ledger.pubKeyHash . EM.walletPubKey . EM.Wallet <$> [1..numberOfHolders]
    , Gov.requiredVotes = 6
    , Gov.baseTokenName = baseName
    }

lawv1, lawv2, lawv3 :: ByteString
lawv1 = fromHaskellByteString "Law v1"
lawv2 = fromHaskellByteString "Law v2"
lawv3 = fromHaskellByteString "Law v3"

doVoting :: Int -> Int -> Integer -> EmulatorTrace ()
doVoting ayes nays rounds = do
    let activate w = (Gov.mkTokenName baseName w,) <$> Trace.activateContractWallet (EM.Wallet w) (Gov.contract @Gov.GovError params)
    namesAndHandles <- traverse activate [1..numberOfHolders]
    let handle1 = snd (head namesAndHandles)
    let token2 = fst (namesAndHandles !! 1)
    void $ Trace.callEndpoint @"new-law" handle1 lawv1
    void $ Trace.waitNSlots 10
    let votingRound (_, law) = do
            now <- view Trace.currentSlot <$> Trace.chainState
            void $ Trace.activateContractWallet (EM.Wallet 2)
                (Gov.proposalContract @Gov.GovError params
                    Gov.Proposal{ Gov.newLaw = law, Gov.votingDeadline = TimeSlot.slotToPOSIXTime $ now + 20, Gov.tokenName = token2 })
            void $ Trace.waitNSlots 1
            traverse_ (\(nm, hdl) -> Trace.callEndpoint @"add-vote" hdl (nm, True)  >> Trace.waitNSlots 1) (take ayes namesAndHandles)
            traverse_ (\(nm, hdl) -> Trace.callEndpoint @"add-vote" hdl (nm, False) >> Trace.waitNSlots 1) (take nays $ drop ayes namesAndHandles)
            Trace.waitNSlots 15

    traverse_ votingRound (zip [1..rounds] (cycle [lawv2, lawv3]))
