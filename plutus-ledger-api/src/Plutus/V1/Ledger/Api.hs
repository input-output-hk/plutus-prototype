{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings  #-}
{-# LANGUAGE TypeApplications   #-}
{- |
The interface to Plutus V1 for the ledger.
-}
module Plutus.V1.Ledger.Api (
    SerializedScript
    -- * Validating scripts
    , validateScript
    -- * Cost model
    , validateCostModelParams
    , defaultCostModelParams
    , CostModelParams
    -- * Running scripts
    , evaluateScriptRestricting
    , evaluateScriptCounting
    -- * Serialising scripts
    , plutusScriptEnvelopeType
    , plutusDatumEnvelopeType
    , plutusRedeemerEnvelopeType
    -- * Data
    , Data (..)
    , IsData (..)
    -- ** Costing-related types
    , ExBudget (..)
    , ExCPU (..)
    , ExMemory (..)
    -- ** Verbose mode and log output
    , VerboseMode (..)
    , LogOutput
    -- * Context types
    , ScriptContext(..)
    , ScriptPurpose(..)
    -- ** Supporting types used in the context types
    -- *** Bytes
    , LedgerBytes (..)
    , fromBytes
    -- *** Certificates
    , DCert(..)
    -- *** Credentials
    , StakingCredential(..)
    , Credential(..)
    -- *** Types for representing transactions
    , Address (..)
    , PubKeyHash (..)
    , TxInfo (..)
    , TxOut(..)
    , TxOutRef(..)
    , TxInInfo(..)
    , Slot (..)
    , SlotRange
    -- *** Intervals
    , Interval (..)
    , Extended (..)
    , Closure
    , UpperBound (..)
    , LowerBound (..)
    -- *** Newtypes for script/datum types and hash types
    , Validator (..)
    , ValidatorHash (..)
    , MintingPolicy (..)
    , MintingPolicyHash (..)
    , Redeemer (..)
    , RedeemerHash (..)
    , Datum (..)
    , DatumHash (..)
    -- * Errors
    , EvaluationError (..)
) where

import qualified Codec.Serialise                                  as CBOR
import           Control.Monad.Except
import           Control.Monad.Writer
import           Data.Bifunctor
import           Data.ByteString.Lazy                             (fromStrict)
import           Data.ByteString.Short
import           Data.Either
import           Data.Maybe                                       (isJust)
import           Data.Text                                        (Text)
import qualified Data.Text                                        as Text
import           Data.Text.Prettyprint.Doc
import           Data.Tuple
import           Plutus.V1.Ledger.Address
import           Plutus.V1.Ledger.Bytes
import           Plutus.V1.Ledger.Contexts
import           Plutus.V1.Ledger.Credential
import           Plutus.V1.Ledger.Crypto
import           Plutus.V1.Ledger.DCert
import           Plutus.V1.Ledger.Interval
import           Plutus.V1.Ledger.Scripts
import           Plutus.V1.Ledger.Slot
import           PlutusCore                                       as PLC
import           PlutusCore.Evaluation.Machine.CostModelInterface (CostModelParams, applyCostModelParams)
import           PlutusCore.Evaluation.Machine.ExBudget           (ExBudget (..))
import qualified PlutusCore.Evaluation.Machine.ExBudget           as PLC
import           PlutusCore.Evaluation.Machine.ExMemory           (ExCPU (..), ExMemory (..))
import           PlutusCore.Evaluation.Machine.MachineParameters
import qualified PlutusCore.MkPlc                                 as PLC
import           PlutusCore.Pretty
import           PlutusTx                                         (Data (..), IsData (..))
import qualified PlutusTx.Lift                                    as PlutusTx
import qualified UntypedPlutusCore                                as UPLC
import qualified UntypedPlutusCore.Evaluation.Machine.Cek         as UPLC

plutusScriptEnvelopeType :: Text
plutusScriptEnvelopeType = "PlutusV1Script"

-- | It was discussed with the Ledger team that the envelope types for 'Datum'
-- and 'Redeemer' should be in plutus-ledger-api.
--
-- For now, those types will be generic and versioning might be included in
-- the future.
plutusDatumEnvelopeType, plutusRedeemerEnvelopeType  :: Text
plutusDatumEnvelopeType = "ScriptDatum"
plutusRedeemerEnvelopeType = "ScriptRedeemer"

{- Note [Abstract types in the ledger API]
We need to support old versions of the ledger API as we update the code that it depends on. You
might think that we should therefore make the types that we expose abstract, and only expose
specific functions for constructing and working with them. However the situation is slightly
different for us.

Normally, when you are in this situation, you want to retain the same *interface* as the old version,
but with the new types and functions underneath. Abstraction lets you do this easily. But we actually
want to keep the old *implementation*, because things really have to work the same, bug-for-bug. And
the types have to translate into Plutus Core in exactly the same way, and so on.

So we're going to end up with multiple versions of the types and functions that we expose here, even
internally. That means we don't lose anything by exposing all the details: we're never going to remove
anything, we're just going to create new versions.
-}

-- | Check if a 'Script' is "valid". At the moment this just means "deserialises correctly", which in particular
-- implies that it is (almost certainly) an encoded script and cannot be interpreted as some other kind of encoded data.
validateScript :: SerializedScript -> Bool
validateScript = isRight . CBOR.deserialiseOrFail @Script . fromStrict . fromShort

validateCostModelParams :: CostModelParams -> Bool
validateCostModelParams = isJust . applyCostModelParams PLC.defaultCekCostModel

data VerboseMode = Verbose | Quiet
    deriving (Eq)

type LogOutput = [Text]

-- | Scripts to the ledger are serialised bytestrings.
type SerializedScript = ShortByteString

-- | Errors that can be thrown when evaluating a Plutus script.
data EvaluationError =
    CekError (UPLC.CekEvaluationException PLC.DefaultUni PLC.DefaultFun) -- ^ An error from the evaluator itself
    | DeBruijnError PLC.FreeVariableError -- ^ An error in the pre-evaluation step of converting from de-Bruijn indices
    | CodecError CBOR.DeserialiseFailure -- ^ A serialisation error
    | IncompatibleVersionError (PLC.Version ()) -- ^ An error indicating a version tag that we don't support
    -- TODO: make this error more informative when we have more information about what went wrong
    | CostModelParameterMismatch -- ^ An error indicating that the cost model parameters didn't match what we expected
    deriving stock (Show, Eq)

instance Pretty EvaluationError where
    pretty (CekError e)      = prettyClassicDef e
    pretty (DeBruijnError e) = pretty e
    pretty (CodecError e) = viaShow e
    pretty (IncompatibleVersionError actual) = "This version of the Plutus Core interface does not support the version indicated by the AST:" <+> pretty actual
    pretty CostModelParameterMismatch = "Cost model parameters were not as we expected"

-- | Shared helper for the evaluation functions, deserializes the 'SerializedScript' , applies it to its arguments, and un-deBruijn-ifies it.
mkTermToEvaluate :: (MonadError EvaluationError m) => SerializedScript -> [Data] -> m (UPLC.Term UPLC.DeBruijn PLC.DefaultUni PLC.DefaultFun ())
mkTermToEvaluate bs args = do
    (Script (UPLC.Program _ v t)) <- liftEither $ first CodecError $ CBOR.deserialiseOrFail $ fromStrict $ fromShort bs
    unless (v == PLC.defaultVersion ()) $ throwError $ IncompatibleVersionError v
    let
        -- This should go away when Data is a builtin
        termArgs = fmap PlutusTx.lift args
        applied = PLC.mkIterApp () t termArgs
    pure applied

-- | Evaluates a script, with a cost model and a budget that restricts how many
-- resources it can use according to the cost model.  There's a default cost
-- model in  'UPLC.defaultBuiltinCostModel' and a budget called 'enormousBudget' in
-- 'UntypedPlutusCore.Evaluation.Machine.Cek.ExBudgetMode' which should be large
-- enough to evaluate any sensible program.
evaluateScriptRestricting
    :: VerboseMode     -- ^ Whether to produce log output
    -> CostModelParams -- ^ The cost model to use
    -> ExBudget        -- ^ The resource budget which must not be exceeded during evaluation
    -> SerializedScript          -- ^ The script to evaluate
    -> [Data]          -- ^ The arguments to the script
    -> (LogOutput, Either EvaluationError ())
evaluateScriptRestricting verbose cmdata budget p args = swap $ runWriter @LogOutput $ runExceptT $ do
    appliedTerm <- mkTermToEvaluate p args
    model <- case applyCostModelParams PLC.defaultCekCostModel cmdata of
        Just model -> pure model
        Nothing    -> throwError CostModelParameterMismatch

    let (res, _, logs) =
            UPLC.runCek
                (toMachineParameters model)
                (UPLC.restricting $ PLC.ExRestrictingBudget budget)
                (verbose == Verbose)
                appliedTerm

    tell $ Prelude.map Text.pack logs
    liftEither $ first CekError $ void res

-- | Evaluates a script, returning the minimum budget that the script would need
-- to evaluate successfully.
evaluateScriptCounting
    :: VerboseMode     -- ^ Whether to produce log output
    -> CostModelParams -- ^ The cost model to use
    -> SerializedScript          -- ^ The script to evaluate
    -> [Data]          -- ^ The arguments to the script
    -> (LogOutput, Either EvaluationError ExBudget)
evaluateScriptCounting verbose cmdata p args = swap $ runWriter @LogOutput $ runExceptT $ do
    appliedTerm <- mkTermToEvaluate p args
    model <- case applyCostModelParams PLC.defaultCekCostModel cmdata of
        Just model -> pure model
        Nothing    -> throwError CostModelParameterMismatch

    let (res, UPLC.CountingSt final, logs) =
            UPLC.runCek
                (toMachineParameters model)
                UPLC.counting
                (verbose == Verbose)
                appliedTerm

    tell $ Prelude.map Text.pack logs
    liftEither $ first CekError $ void res
    pure final
