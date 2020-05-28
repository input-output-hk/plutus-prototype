{-# LANGUAGE RecordWildCards #-}

{- This module contains templates for Marlowe constructs required by ACTUS logic -}
module Language.Marlowe.ACTUS.ControlLp
    ( lpValidator
    , genLpContract
    , genStaticContract
    )
where

import           Language.Marlowe.ACTUS.STF.StateTransitionLp
import           Language.Marlowe.ACTUS.POF.PayoffLp
import           Language.Marlowe.ACTUS.Control
import           Language.Marlowe.ACTUS.Ops
import           Language.Marlowe.ACTUS.Schedule
import           Language.Marlowe.ACTUS.ProjectedCashFlows
import           Language.Marlowe.ACTUS.ContractTerms
import           Data.String                    ( IsString(fromString) )
import           Language.Marlowe

expectedPayoffAt :: Integer -> ValueId
expectedPayoffAt t = ValueId $ fromString $ "expected-payoff_" ++ show t

payoffAt :: Integer -> ValueId
payoffAt t = ValueId $ fromString $ "payoff_" ++ show t

lpValidator :: Integer -> Contract -> Contract
lpValidator t continue =
    let payoffOk = ValueEQ (UseValue $ expectedPayoffAt t)
                           (UseValue $ payoffAt t)
        --todo dateOk 
        --todo check that previous events happened
    in  (If payoffOk continue Close)

genLpContract :: ContractTerms -> Integer -> Contract -> Contract
genLpContract terms t continue =
    --todo: state initialization
    inquiry (show t) "party" 0 "oracle"
        $ stateTransitionLp terms t
        $ Let (expectedPayoffAt t) (payoffLp terms t)
        $ lpValidator t
        $ invoice "party" "counterparty" (UseValue $ payoffAt t) 1000000
        $ continue

genStaticContract :: ContractTerms -> Contract
genStaticContract terms = 
    let
        cfs = genProjectedCashflows terms
        gen CashFlow{..} = invoice "party" "counterparty" (Constant $ round amount) (Slot $ dayToSlotNumber cashPaymentDay)
    in foldl (flip gen) Close cfs
