{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_HADDOCK hide #-}
-- | The catalogue of all Plutus errors, obsolete or not.
module Errors (allErrors) where

import           ErrorCode
import           Language.Haskell.TH                      as TH

import qualified PlutusCore.DeBruijn                      as PLC
import qualified PlutusCore.Error                         as PLC
import qualified PlutusCore.Evaluation.Machine.Exception  as PLC
import qualified PlutusIR.Error                           as PIR
import qualified PlutusTx.Code                            as PTX
import qualified PlutusTx.Compiler.Error                  as PTX
import qualified PlutusTx.Lift.Class                      as PTX
import qualified UntypedPlutusCore.Evaluation.Machine.Cek as PLC

{- | A collection of error instances which are obsolete, together with their error codes bundled to one instance.
See plutus-errors/README.md
-}
{-# WARNING ObsoleteErrors "These errors and their error codes *should* not be thrown by any plutus code anymore" #-}
data ObsoleteErrors =
    ReservedErrorCode
    -- append here the obsolete errors

instance HasErrorCode ObsoleteErrors where
    errorCode ReservedErrorCode {} = ErrorCode 0
    -- append here the corresponding obsolete error codes

-- | All errors among the whole Plutus project. This includes both existing and obsolete errors.
-- Note: the order of adding to this list does not matter, except for haddock looks.
allErrors :: [TH.Name]
allErrors =
   [ 'ReservedErrorCode
   , 'PIR.MalformedDataConstrResType
   , 'PIR.CompilationError
   , 'PIR.UnsupportedError
   , 'PLC.LexErr
   , 'PLC.Unexpected
   , 'PLC.UnknownBuiltinType
   , 'PLC.BuiltinTypeNotAStar
   , 'PLC.UnknownBuiltinFunction
   , 'PLC.InvalidBuiltinConstant
   , 'PLC.MultiplyDefined
   , 'PLC.IncoherentUsage
   , 'PLC.BadType
   , 'PLC.BadTerm
   , 'PLC.KindMismatch
   , 'PLC.TypeMismatch
   , 'PLC.UnknownBuiltinFunctionE
   , 'PLC.FreeTypeVariableE
   , 'PLC.FreeVariableE
   , 'PLC.FreeVariable
   , 'PLC.FreeUnique
   , 'PLC.FreeIndex
   , 'PLC.NonPolymorphicInstantiationMachineError
   , 'PLC.NonWrapUnwrappedMachineError
   , 'PLC.NonFunctionalApplicationMachineError
   , 'PLC.OpenTermEvaluatedMachineError
   , 'PLC.UnliftingErrorE
   , 'PLC.BuiltinTermArgumentExpectedMachineError
   , 'PLC.UnexpectedBuiltinTermArgumentMachineError
   , 'PLC.EmptyBuiltinArityMachineError
   , 'PLC.CekOutOfExError
   , 'PLC.CekEvaluationFailure
   , 'PTX.ImpossibleDeserialisationFailure
   , 'PTX.CompilationError
   , 'PTX.UnsupportedError
   , 'PTX.FreeVariableError
   , 'PTX.InvalidMarkerError
   , 'PTX.CoreNameLookupError
   , 'PTX.UnsupportedLiftType
   , 'PTX.UnsupportedLiftKind
   , 'PTX.UserLiftError
   , 'PTX.LiftMissingDataCons
   , 'PTX.LiftMissingVar
   ]
