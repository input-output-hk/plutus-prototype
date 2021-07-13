{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE FlexibleContexts   #-}
{-# LANGUAGE LambdaCase         #-}
{-# LANGUAGE MonoLocalBinds     #-}
{-# LANGUAGE NamedFieldPuns     #-}
{-# LANGUAGE NoImplicitPrelude  #-}
{-# LANGUAGE OverloadedStrings  #-}
{-# OPTIONS_GHC -Wno-simplifiable-class-constraints #-}
{-# OPTIONS_GHC -fno-strictness #-}
{-# OPTIONS_GHC -fno-specialise #-}
{-# OPTIONS_GHC -fno-omit-interface-pragmas #-}
module Ledger.Constraints.OnChain where

import           PlutusTx                         (IsData (..))
import           PlutusTx.Prelude

import           Ledger.Constraints.TxConstraints
import qualified Plutus.V1.Ledger.Address         as Address
import           Plutus.V1.Ledger.Contexts        (ScriptContext (..), TxInInfo (..), TxInfo (..))
import qualified Plutus.V1.Ledger.Contexts        as V
import           Plutus.V1.Ledger.Interval        (contains)
import           Plutus.V1.Ledger.Scripts         (Datum (..))
import           Plutus.V1.Ledger.Tx              (TxOut (..))
import           Plutus.V1.Ledger.Value           (leq)
import qualified Plutus.V1.Ledger.Value           as Value

{-# INLINABLE checkOwnInputConstraint #-}
checkOwnInputConstraint :: ScriptContext -> InputConstraint a -> Bool
checkOwnInputConstraint ScriptContext{scriptContextTxInfo} InputConstraint{icTxOutRef} =
    let checkInput TxInInfo{txInInfoOutRef} =
            txInInfoOutRef == icTxOutRef -- TODO: We should also check the redeemer but we can't right now because it's hashed
    in traceIfFalse "Input constraint"
    $ any checkInput (txInfoInputs scriptContextTxInfo)

{-# INLINABLE checkOwnOutputConstraint #-}
checkOwnOutputConstraint
    :: IsData o
    => ScriptContext
    -> OutputConstraint o
    -> Bool
checkOwnOutputConstraint ctx@ScriptContext{scriptContextTxInfo} OutputConstraint{ocDatum, ocValue} =
    let hsh = V.findDatumHash (Datum $ toBuiltinData ocDatum) scriptContextTxInfo
        checkOutput TxOut{txOutValue, txOutDatumHash=Just svh} =
            txOutValue == ocValue && hsh == Just svh
        checkOutput _       = False
    in traceIfFalse "Output constraint"
    $ any checkOutput (V.getContinuingOutputs ctx)

{-# INLINABLE checkTxConstraint #-}
checkTxConstraint :: ScriptContext -> TxConstraint -> Bool
checkTxConstraint ScriptContext{scriptContextTxInfo} = \case
    MustIncludeDatum dv ->
        traceIfFalse "Missing datum"
        $ dv `elem` fmap snd (txInfoData scriptContextTxInfo)
    MustValidateIn interval ->
        traceIfFalse "Wrong validation interval"
        $ interval `contains` txInfoValidRange scriptContextTxInfo
    MustBeSignedBy pubKey ->
        traceIfFalse "Missing signature"
        $ scriptContextTxInfo `V.txSignedBy` pubKey
    MustSpendAtLeast vl ->
        traceIfFalse "Spent value not OK"
        $ vl `leq` V.valueSpent scriptContextTxInfo
    MustProduceAtLeast vl ->
        traceIfFalse "Produced value not OK"
        $ vl `leq` V.valueProduced scriptContextTxInfo
    MustSpendPubKeyOutput txOutRef ->
        traceIfFalse "Public key output not spent"
        $ maybe False (isNothing . txOutDatumHash . txInInfoResolved) (V.findTxInByTxOutRef txOutRef scriptContextTxInfo)
    MustSpendScriptOutput txOutRef _ ->
        traceIfFalse "Script output not spent"
        -- Unfortunately we can't check the redeemer, because TxInfo only
        -- gives us the redeemer's hash, but 'MustSpendScriptOutput' gives
        -- us the full redeemer
        $ isJust (V.findTxInByTxOutRef txOutRef scriptContextTxInfo)
    MustMintValue mps _ tn v ->
        traceIfFalse "Value minted not OK"
        $ Value.valueOf (txInfoForge scriptContextTxInfo) (Value.mpsSymbol mps) tn == v
    MustPayToPubKey pk vl ->
        traceIfFalse "MustPayToPubKey"
        $ vl `leq` V.valuePaidTo scriptContextTxInfo pk
    MustPayToOtherScript vlh dv vl ->
        let outs = V.txInfoOutputs scriptContextTxInfo
            hsh = V.findDatumHash dv scriptContextTxInfo
            addr = Address.scriptHashAddress vlh
            checkOutput TxOut{txOutAddress, txOutValue, txOutDatumHash=Just svh} =
                txOutValue == vl && hsh == Just svh && txOutAddress == addr
            checkOutput _ = False
        in
        traceIfFalse "MustPayToOtherScript"
        $ any checkOutput outs
    MustHashDatum dvh dv ->
        traceIfFalse "MustHashDatum"
        $ V.findDatum dvh scriptContextTxInfo == Just dv

{-# INLINABLE checkScriptContext #-}
-- | Does the 'ScriptContext' satisfy the constraints?
checkScriptContext :: forall i o. IsData o => TxConstraints i o -> ScriptContext -> Bool
checkScriptContext TxConstraints{txConstraints, txOwnInputs, txOwnOutputs} ptx =
    traceIfFalse "checkScriptContext failed"
    $ all (checkTxConstraint ptx) txConstraints
    && all (checkOwnInputConstraint ptx) txOwnInputs
    && all (checkOwnOutputConstraint ptx) txOwnOutputs
