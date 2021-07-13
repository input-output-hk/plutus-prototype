{-# LANGUAGE GADTs             #-}
{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}
{-# LANGUAGE ViewPatterns      #-}
{-|

Interface to the transaction types from 'cardano-api'

-}
module Plutus.Contract.CardanoAPI(
    fromCardanoTx
  , fromCardanoTxIn
  , fromCardanoTxInsCollateral
  , fromCardanoTxInWitness
  , fromCardanoTxOut
  , fromCardanoAddress
  , fromCardanoMintValue
  , fromCardanoValue
  , fromCardanoFee
  , fromCardanoValidityRange
  , fromCardanoExtraScriptData
  , fromCardanoScriptInEra
  , toCardanoTxBody
  , toCardanoTxIn
  , toCardanoTxInsCollateral
  , toCardanoTxInWitness
  , toCardanoTxOut
  , toCardanoAddress
  , toCardanoMintValue
  , toCardanoValue
  , toCardanoFee
  , toCardanoValidityRange
  , toCardanoExtraScriptData
  , toCardanoScriptInEra
) where

import qualified Cardano.Api                 as C
import qualified Cardano.Api.Shelley         as C
import qualified Cardano.Ledger.Era          as C
import qualified Codec.Serialise             as Codec
import           Data.Bifunctor              (first)
import           Data.ByteString             (ByteString)
import qualified Data.ByteString.Lazy        as BSL
import           Data.ByteString.Short       as BSS
import qualified Data.Map                    as Map
import qualified Data.Set                    as Set
import           Data.Text.Prettyprint.Doc   (Pretty (..))
import qualified Ledger                      as P
import qualified Ledger.Ada                  as Ada
import qualified Plutus.V1.Ledger.Api        as Api
import qualified Plutus.V1.Ledger.Credential as Credential
import qualified Plutus.V1.Ledger.Value      as Value
import qualified PlutusCore.Data             as Data

fromCardanoTx :: C.Era era => C.Tx era -> Either FromCardanoError P.Tx
fromCardanoTx (C.Tx (C.TxBody C.TxBodyContent{..}) _keyWitnesses) = do
    txOutputs <- traverse fromCardanoTxOut txOuts
    pure $ P.Tx
        { txInputs = Set.fromList $ fmap ((`P.TxIn` Nothing) . fromCardanoTxIn . fst) txIns
        , txCollateral = fromCardanoTxInsCollateral txInsCollateral
        , txOutputs = txOutputs
        , txMint = fromCardanoMintValue txMintValue
        , txFee = fromCardanoFee txFee
        , txValidRange = fromCardanoValidityRange txValidityRange
        , txData = mempty -- only available with a Build Tx
        , txSignatures = mempty -- TODO: convert from _keyWitnesses?
        , txMintScripts = mempty -- only available with a Build Tx
        , txRedeemers = mempty -- only available with a Build Tx
        }

toCardanoTxBody :: P.Tx -> Either ToCardanoError (C.TxBody C.AlonzoEra)
toCardanoTxBody P.Tx{..} = do
    txIns <- traverse toCardanoTxInBuild $ Set.toList txInputs
    txInsCollateral <- toCardanoTxInsCollateral txCollateral
    txOuts <- traverse toCardanoTxOut txOutputs
    txFee' <- toCardanoFee txFee
    txValidityRange <- toCardanoValidityRange txValidRange
    txMintValue <- toCardanoMintValue txMint txMintScripts
    first TxBodyError $ C.makeTransactionBody C.TxBodyContent
        { txIns = txIns
        , txInsCollateral = txInsCollateral
        , txOuts = txOuts
        , txFee = txFee'
        , txValidityRange = txValidityRange
        , txExtraScriptData = C.BuildTxWith $ toCardanoExtraScriptData (Map.elems txData)
        , txMintValue = txMintValue
        -- unused:
        , txMetadata = C.TxMetadataNone
        , txAuxScripts = C.TxAuxScriptsNone
        , txExtraKeyWits = C.TxExtraKeyWitnessesNone
        , txProtocolParams = C.BuildTxWith Nothing
        , txWithdrawals = C.TxWithdrawalsNone
        , txCertificates = C.TxCertificatesNone
        , txUpdateProposal = C.TxUpdateProposalNone
        }

fromCardanoTxIn :: C.TxIn -> P.TxOutRef
fromCardanoTxIn (C.TxIn txId (C.TxIx txIx)) = P.TxOutRef (fromCardanoTxId txId) (toInteger txIx)

toCardanoTxInBuild :: P.TxIn -> Either ToCardanoError (C.TxIn, C.BuildTxWith C.BuildTx (C.Witness C.WitCtxTxIn C.AlonzoEra))
toCardanoTxInBuild (P.TxIn txInRef (Just txInType)) = (,) <$> toCardanoTxIn txInRef <*> (C.BuildTxWith <$> toCardanoTxInWitness txInType)
toCardanoTxInBuild (P.TxIn _ Nothing) = Left MissingTxInType

toCardanoTxIn :: P.TxOutRef -> Either ToCardanoError C.TxIn
toCardanoTxIn (P.TxOutRef txId txIx) = C.TxIn <$> toCardanoTxId txId <*> pure (C.TxIx (fromInteger txIx))

fromCardanoTxId :: C.TxId -> P.TxId
fromCardanoTxId txId = P.TxId $ C.serialiseToRawBytes txId

toCardanoTxId :: P.TxId -> Either ToCardanoError C.TxId
toCardanoTxId (P.TxId bs) = deserialiseFromRawBytes C.AsTxId bs

fromCardanoTxInsCollateral :: C.TxInsCollateral era -> Set.Set P.TxIn
fromCardanoTxInsCollateral C.TxInsCollateralNone       = mempty
fromCardanoTxInsCollateral (C.TxInsCollateral _ txIns) = Set.fromList $ fmap (P.pubKeyTxIn . fromCardanoTxIn) txIns

toCardanoTxInsCollateral :: Set.Set P.TxIn -> Either ToCardanoError (C.TxInsCollateral C.AlonzoEra)
toCardanoTxInsCollateral = fmap (C.TxInsCollateral C.CollateralInAlonzoEra) . traverse (toCardanoTxIn . P.txInRef) . Set.toList

fromCardanoTxInWitness :: C.Witness C.WitCtxTxIn era -> Either FromCardanoError P.TxInType
fromCardanoTxInWitness (C.KeyWitness C.KeyWitnessForSpending) = pure P.ConsumePublicKeyAddress
fromCardanoTxInWitness
    (C.ScriptWitness _
        (C.PlutusScriptWitness C.PlutusScriptV1InAlonzo C.PlutusScriptV1
            script
            (C.ScriptDatumForTxIn datum)
            redeemer
            _))
    = pure $ P.ConsumeScriptAddress
        (P.Validator $ fromCardanoPlutusScript script)
        (P.Redeemer $ fromCardanoScriptData redeemer)
        (P.Datum $ fromCardanoScriptData datum)
fromCardanoTxInWitness (C.ScriptWitness _ C.SimpleScriptWitness{}) = Left SimpleScriptsNotSupported

toCardanoTxInWitness :: P.TxInType -> Either ToCardanoError (C.Witness C.WitCtxTxIn C.AlonzoEra)
toCardanoTxInWitness P.ConsumePublicKeyAddress = pure (C.KeyWitness C.KeyWitnessForSpending)
toCardanoTxInWitness
    (P.ConsumeScriptAddress
        (P.Validator validator)
        (P.Redeemer redeemer)
        (P.Datum datum))
    = C.ScriptWitness C.ScriptWitnessForSpending <$>
        (C.PlutusScriptWitness C.PlutusScriptV1InAlonzo C.PlutusScriptV1
        <$> toCardanoPlutusScript validator
        <*> pure (C.ScriptDatumForTxIn $ toCardanoScriptData datum)
        <*> pure (toCardanoScriptData redeemer)
        <*> toCardanoExecutionUnits validator [Api.builtinDataToData datum, Api.builtinDataToData redeemer] -- TODO: is [datum, redeemer] correct?
        )

toCardanoMintWitness :: P.MintingPolicy -> Either ToCardanoError (C.ScriptWitness C.WitCtxMint C.AlonzoEra)
toCardanoMintWitness (P.MintingPolicy script) = C.PlutusScriptWitness C.PlutusScriptV1InAlonzo C.PlutusScriptV1
    <$> toCardanoPlutusScript script
    <*> pure C.NoScriptDatumForMint
    <*> pure (C.ScriptDataNumber 0) -- TODO: redeemers not modelled yet in Plutus MP scripts, value is ignored
    <*> toCardanoExecutionUnits script [] -- TODO: is [] correct?

fromCardanoTxOut :: C.TxOut era -> Either FromCardanoError P.TxOut
fromCardanoTxOut (C.TxOut addr value datumHash) =
    P.TxOut
    <$> fromCardanoAddress addr
    <*> pure (fromCardanoTxOutValue value)
    <*> pure (fromCardanoTxOutDatumHash datumHash)

toCardanoTxOut :: P.TxOut -> Either ToCardanoError (C.TxOut C.AlonzoEra)
toCardanoTxOut (P.TxOut addr value datumHash) = C.TxOut <$> toCardanoAddress addr <*> toCardanoTxOutValue value <*> toCardanoTxOutDatumHash datumHash

fromCardanoAddress :: C.AddressInEra era -> Either FromCardanoError P.Address
fromCardanoAddress (C.AddressInEra C.ByronAddressInAnyEra _) = Left ByronAddressesNotSupported
fromCardanoAddress (C.AddressInEra _ (C.ShelleyAddress _ paymentCredential stakeAddressReference)) =
    P.Address (fromCardanoPaymentCredential (C.fromShelleyPaymentCredential paymentCredential))
        <$> fromCardanoStakeAddressReference (C.fromShelleyStakeReference stakeAddressReference)

toCardanoAddress :: P.Address -> Either ToCardanoError (C.AddressInEra C.AlonzoEra)
toCardanoAddress (P.Address addressCredential addressStakingCredential) =
    C.AddressInEra (C.ShelleyAddressInEra C.ShelleyBasedEraAlonzo) <$>
        (C.makeShelleyAddress C.Mainnet -- TODO: use actual network id
            <$> toCardanoPaymentCredential addressCredential
            <*> toCardanoStakeAddressReference addressStakingCredential)

fromCardanoPaymentCredential :: C.PaymentCredential -> Credential.Credential
fromCardanoPaymentCredential (C.PaymentCredentialByKey paymentKeyHash) = Credential.PubKeyCredential (fromCardanoPaymentKeyHash paymentKeyHash)
fromCardanoPaymentCredential (C.PaymentCredentialByScript scriptHash) = Credential.ScriptCredential (fromCardanoScriptHash scriptHash)

toCardanoPaymentCredential :: Credential.Credential -> Either ToCardanoError C.PaymentCredential
toCardanoPaymentCredential (Credential.PubKeyCredential pubKeyHash) = C.PaymentCredentialByKey <$> toCardanoPaymentKeyHash pubKeyHash
toCardanoPaymentCredential (Credential.ScriptCredential validatorHash) = C.PaymentCredentialByScript <$> toCardanoScriptHash validatorHash

fromCardanoPaymentKeyHash :: C.Hash C.PaymentKey -> P.PubKeyHash
fromCardanoPaymentKeyHash paymentKeyHash = P.PubKeyHash $ C.serialiseToRawBytes paymentKeyHash

toCardanoPaymentKeyHash :: P.PubKeyHash -> Either ToCardanoError (C.Hash C.PaymentKey)
toCardanoPaymentKeyHash (P.PubKeyHash bs) = deserialiseFromRawBytes (C.AsHash C.AsPaymentKey) bs

fromCardanoScriptHash :: C.ScriptHash -> P.ValidatorHash
fromCardanoScriptHash scriptHash = P.ValidatorHash $ C.serialiseToRawBytes scriptHash

toCardanoScriptHash :: P.ValidatorHash -> Either ToCardanoError C.ScriptHash
toCardanoScriptHash (P.ValidatorHash bs) = deserialiseFromRawBytes C.AsScriptHash bs

fromCardanoStakeAddressReference :: C.StakeAddressReference -> Either FromCardanoError (Maybe Credential.StakingCredential)
fromCardanoStakeAddressReference C.NoStakeAddress = pure Nothing
fromCardanoStakeAddressReference (C.StakeAddressByValue stakeCredential) =
    pure $ Just (Credential.StakingHash $ fromCardanoStakeCredential stakeCredential)
fromCardanoStakeAddressReference C.StakeAddressByPointer{} = Left StakeAddressPointersNotSupported

toCardanoStakeAddressReference :: Maybe Credential.StakingCredential -> Either ToCardanoError C.StakeAddressReference
toCardanoStakeAddressReference Nothing = pure C.NoStakeAddress
toCardanoStakeAddressReference (Just (Credential.StakingHash credential)) =
    C.StakeAddressByValue <$> toCardanoStakeCredential credential
toCardanoStakeAddressReference (Just Credential.StakingPtr{}) = Left StakingPointersNotSupported

fromCardanoStakeCredential :: C.StakeCredential -> Credential.Credential
fromCardanoStakeCredential (C.StakeCredentialByKey stakeKeyHash) = Credential.PubKeyCredential (fromCardanoStakeKeyHash stakeKeyHash)
fromCardanoStakeCredential (C.StakeCredentialByScript scriptHash) = Credential.ScriptCredential (fromCardanoScriptHash scriptHash)

toCardanoStakeCredential :: Credential.Credential -> Either ToCardanoError C.StakeCredential
toCardanoStakeCredential (Credential.PubKeyCredential pubKeyHash) = C.StakeCredentialByKey <$> toCardanoStakeKeyHash pubKeyHash
toCardanoStakeCredential (Credential.ScriptCredential validatorHash) = C.StakeCredentialByScript <$> toCardanoScriptHash validatorHash

fromCardanoStakeKeyHash :: C.Hash C.StakeKey -> P.PubKeyHash
fromCardanoStakeKeyHash stakeKeyHash = P.PubKeyHash $ C.serialiseToRawBytes stakeKeyHash

toCardanoStakeKeyHash :: P.PubKeyHash -> Either ToCardanoError (C.Hash C.StakeKey)
toCardanoStakeKeyHash (P.PubKeyHash bs) = deserialiseFromRawBytes (C.AsHash C.AsStakeKey) bs

fromCardanoTxOutValue :: C.TxOutValue era -> P.Value
fromCardanoTxOutValue (C.TxOutAdaOnly _ lovelace) = fromCardanoLovelace lovelace
fromCardanoTxOutValue (C.TxOutValue _ value)      = fromCardanoValue value

toCardanoTxOutValue :: P.Value -> Either ToCardanoError (C.TxOutValue C.AlonzoEra)
toCardanoTxOutValue value = C.TxOutValue C.MultiAssetInAlonzoEra <$> toCardanoValue value

fromCardanoTxOutDatumHash :: C.TxOutDatumHash era -> Maybe P.DatumHash
fromCardanoTxOutDatumHash C.TxOutDatumHashNone   = Nothing
fromCardanoTxOutDatumHash (C.TxOutDatumHash _ h) = Just $ P.DatumHash (C.serialiseToRawBytes h)

toCardanoTxOutDatumHash :: Maybe P.DatumHash -> Either ToCardanoError (C.TxOutDatumHash C.AlonzoEra)
toCardanoTxOutDatumHash Nothing = pure C.TxOutDatumHashNone
toCardanoTxOutDatumHash (Just (P.DatumHash bs)) = C.TxOutDatumHash C.ScriptDataInAlonzoEra <$> deserialiseFromRawBytes (C.AsHash C.AsScriptData) bs

fromCardanoMintValue :: C.TxMintValue build era -> P.Value
fromCardanoMintValue C.TxMintNone              = mempty
fromCardanoMintValue (C.TxMintValue _ value _) = fromCardanoValue value

toCardanoMintValue :: P.Value -> Set.Set P.MintingPolicy -> Either ToCardanoError (C.TxMintValue C.BuildTx C.AlonzoEra)
toCardanoMintValue value mps =
    C.TxMintValue C.MultiAssetInAlonzoEra
        <$> toCardanoValue value
        <*> (C.BuildTxWith . Map.fromList <$> traverse (\mp -> (,) <$> (toCardanoPolicyId . P.mintingPolicyHash) mp <*> toCardanoMintWitness mp) (Set.toList mps))

fromCardanoValue :: C.Value -> P.Value
fromCardanoValue (C.valueToList -> list) = foldMap toValue list
    where
        toValue (C.AdaAssetId, C.Quantity q) = Ada.lovelaceValueOf q
        toValue (C.AssetId policyId assetName, C.Quantity q)
            = Value.singleton (Value.mpsSymbol $ fromCardanoPolicyId policyId) (fromCardanoAssetName assetName) q

toCardanoValue :: P.Value -> Either ToCardanoError C.Value
toCardanoValue = fmap C.valueFromList . traverse fromValue . Value.flattenValue
    where
        fromValue (currencySymbol, tokenName, amount) =
            (,) <$> (C.AssetId <$> toCardanoPolicyId (Value.currencyMPSHash currencySymbol) <*> pure (toCardanoAssetName tokenName)) <*> pure (C.Quantity amount)

fromCardanoPolicyId :: C.PolicyId -> P.MintingPolicyHash
fromCardanoPolicyId (C.PolicyId scriptHash) = P.MintingPolicyHash (C.serialiseToRawBytes scriptHash)

toCardanoPolicyId :: P.MintingPolicyHash -> Either ToCardanoError C.PolicyId
toCardanoPolicyId (P.MintingPolicyHash bs) = C.PolicyId <$> deserialiseFromRawBytes C.AsScriptHash bs

fromCardanoAssetName :: C.AssetName -> Value.TokenName
fromCardanoAssetName (C.AssetName bs) = Value.TokenName bs

toCardanoAssetName :: Value.TokenName -> C.AssetName
toCardanoAssetName (Value.TokenName bs) = C.AssetName bs

fromCardanoFee :: C.TxFee era -> P.Value
fromCardanoFee (C.TxFeeImplicit _)          = mempty
fromCardanoFee (C.TxFeeExplicit _ lovelace) = fromCardanoLovelace lovelace

toCardanoFee :: P.Value -> Either ToCardanoError (C.TxFee C.AlonzoEra)
toCardanoFee value = C.TxFeeExplicit C.TxFeesExplicitInAlonzoEra <$> toCardanoLovelace value

fromCardanoLovelace :: C.Lovelace -> P.Value
fromCardanoLovelace (C.lovelaceToQuantity -> C.Quantity lovelace) = Ada.lovelaceValueOf lovelace

toCardanoLovelace :: P.Value -> Either ToCardanoError C.Lovelace
toCardanoLovelace value = if value == Ada.lovelaceValueOf lovelace then pure . C.quantityToLovelace . C.Quantity $ lovelace else Left ValueNotPureAda
    where
        Ada.Lovelace lovelace = Ada.fromValue value

fromCardanoValidityRange :: (C.TxValidityLowerBound era, C.TxValidityUpperBound era) -> P.SlotRange
fromCardanoValidityRange (l, u) = P.Interval (fromCardanoValidityLowerBound l) (fromCardanoValidityUpperBound u)

toCardanoValidityRange :: P.SlotRange -> Either ToCardanoError (C.TxValidityLowerBound C.AlonzoEra, C.TxValidityUpperBound C.AlonzoEra)
toCardanoValidityRange (P.Interval l u) = (,) <$> toCardanoValidityLowerBound l <*> toCardanoValidityUpperBound u

fromCardanoValidityLowerBound :: C.TxValidityLowerBound era -> P.LowerBound P.Slot
fromCardanoValidityLowerBound C.TxValidityNoLowerBound = P.LowerBound P.NegInf True
fromCardanoValidityLowerBound (C.TxValidityLowerBound _ slotNo) = P.LowerBound (P.Finite $ fromCardanoSlotNo slotNo) True

toCardanoValidityLowerBound :: P.LowerBound P.Slot -> Either ToCardanoError (C.TxValidityLowerBound C.AlonzoEra)
toCardanoValidityLowerBound (P.LowerBound P.NegInf _) = pure C.TxValidityNoLowerBound
toCardanoValidityLowerBound (P.LowerBound (P.Finite slotNo) closed)
    = pure . C.TxValidityLowerBound C.ValidityLowerBoundInAlonzoEra . toCardanoSlotNo $ if closed then slotNo else slotNo + 1
toCardanoValidityLowerBound (P.LowerBound P.PosInf _) = Left InvalidValidityRange

fromCardanoValidityUpperBound :: C.TxValidityUpperBound era -> P.UpperBound P.Slot
fromCardanoValidityUpperBound (C.TxValidityNoUpperBound _) = P.UpperBound P.PosInf True
fromCardanoValidityUpperBound (C.TxValidityUpperBound _ slotNo) = P.UpperBound (P.Finite $ fromCardanoSlotNo slotNo) False

toCardanoValidityUpperBound :: P.UpperBound P.Slot -> Either ToCardanoError (C.TxValidityUpperBound C.AlonzoEra)
toCardanoValidityUpperBound (P.UpperBound P.PosInf _) = pure $ C.TxValidityNoUpperBound C.ValidityNoUpperBoundInAlonzoEra
toCardanoValidityUpperBound (P.UpperBound (P.Finite slotNo) closed)
    = pure . C.TxValidityUpperBound C.ValidityUpperBoundInAlonzoEra . toCardanoSlotNo $ if closed then slotNo + 1 else slotNo
toCardanoValidityUpperBound (P.UpperBound P.NegInf _) = Left InvalidValidityRange

fromCardanoSlotNo :: C.SlotNo -> P.Slot
fromCardanoSlotNo (C.SlotNo w64) = P.Slot (toInteger w64)

toCardanoSlotNo :: P.Slot -> C.SlotNo
toCardanoSlotNo (P.Slot i) = C.SlotNo (fromInteger i)

fromCardanoExtraScriptData :: C.TxExtraScriptData era -> [P.Datum]
fromCardanoExtraScriptData C.TxExtraScriptDataNone            = []
fromCardanoExtraScriptData (C.TxExtraScriptData _ scriptData) = fmap (P.Datum . fromCardanoScriptData) scriptData

toCardanoExtraScriptData :: [P.Datum] -> C.TxExtraScriptData C.AlonzoEra
toCardanoExtraScriptData = C.TxExtraScriptData C.ScriptDataInAlonzoEra . fmap (toCardanoScriptData . P.getDatum)

fromCardanoScriptData :: C.ScriptData -> Api.BuiltinData
fromCardanoScriptData = Api.dataToBuiltinData . C.toPlutusData

toCardanoScriptData :: Api.BuiltinData -> C.ScriptData
toCardanoScriptData = C.fromPlutusData . Api.builtinDataToData

fromCardanoScriptInEra :: C.ScriptInEra era -> Either FromCardanoError P.Script
fromCardanoScriptInEra (C.ScriptInEra C.PlutusScriptV1InAlonzo (C.PlutusScript C.PlutusScriptV1 script)) =
    pure $ fromCardanoPlutusScript script
fromCardanoScriptInEra (C.ScriptInEra _ C.SimpleScript{}) = Left SimpleScriptsNotSupported

toCardanoScriptInEra :: P.Script -> Either ToCardanoError (C.ScriptInEra C.AlonzoEra)
toCardanoScriptInEra script = C.ScriptInEra C.PlutusScriptV1InAlonzo . C.PlutusScript C.PlutusScriptV1 <$> toCardanoPlutusScript script

fromCardanoPlutusScript :: C.HasTypeProxy lang => C.PlutusScript lang -> P.Script
fromCardanoPlutusScript = Codec.deserialise . BSL.fromStrict . C.serialiseToRawBytes

toCardanoPlutusScript :: P.Script -> Either ToCardanoError (C.PlutusScript C.PlutusScriptV1)
toCardanoPlutusScript = deserialiseFromRawBytes (C.AsPlutusScript C.AsPlutusScriptV1) . BSL.toStrict . Codec.serialise

toCardanoExecutionUnits :: P.Script -> [Data.Data] -> Either ToCardanoError C.ExecutionUnits
toCardanoExecutionUnits script datum = do
    cmp <- maybe (Left NoDefaultCostModelParams) Right Api.defaultCostModelParams -- TODO: Configurable cost model params
    let apiScript = BSS.toShort . BSL.toStrict $ Codec.serialise script
    case Api.evaluateScriptCounting Api.Quiet cmp apiScript datum of
        (_, Left err) -> Left $ EvaluationError err
        (_, Right (Api.ExBudget (Api.ExCPU cpu) (Api.ExMemory memory))) ->
            pure $ C.ExecutionUnits (fromIntegral cpu) (fromIntegral memory)

deserialiseFromRawBytes :: C.SerialiseAsRawBytes t => C.AsType t -> ByteString -> Either ToCardanoError t
deserialiseFromRawBytes asType = maybe (Left DeserialisationError) Right . C.deserialiseFromRawBytes asType

data FromCardanoError
    = SimpleScriptsNotSupported
    | ByronAddressesNotSupported
    | StakeAddressPointersNotSupported

instance Pretty FromCardanoError where
    pretty SimpleScriptsNotSupported        = "Simple scripts are not supported"
    pretty ByronAddressesNotSupported       = "Byron era addresses are not supported"
    pretty StakeAddressPointersNotSupported = "Stake address pointers are not supported"

data ToCardanoError
    = EvaluationError Api.EvaluationError
    | TxBodyError (C.TxBodyError C.AlonzoEra)
    | DeserialisationError
    | InvalidValidityRange
    | ValueNotPureAda
    | NoDefaultCostModelParams
    | StakingPointersNotSupported
    | MissingTxInType

instance Pretty ToCardanoError where
    pretty (EvaluationError err)       = pretty err
    pretty (TxBodyError err)           = pretty $ C.displayError err
    pretty DeserialisationError        = "ByteString deserialisation failed"
    pretty InvalidValidityRange        = "Invalid validity range"
    pretty ValueNotPureAda             = "Fee values should only contain Ada"
    pretty NoDefaultCostModelParams    = "Extracting default cost model failed"
    pretty StakingPointersNotSupported = "Staking pointers are not supported"
    pretty MissingTxInType             = "Missing TxInType"
