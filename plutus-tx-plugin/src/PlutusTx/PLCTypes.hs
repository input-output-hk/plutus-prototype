module PlutusTx.PLCTypes where

import qualified PlutusCore        as PLC
import qualified PlutusCore.MkPlc  as PLC
import qualified UntypedPlutusCore as UPLC

type PLCKind = PLC.Kind ()
type PLCType uni = PLC.Type PLC.TyName uni ()
type PLCTerm uni fun = PLC.Term PLC.TyName PLC.Name uni fun ()
type PLCProgram uni fun = PLC.Program PLC.TyName PLC.Name uni fun ()

type PLCVar uni fun = PLC.VarDecl PLC.TyName PLC.Name uni fun ()
type PLCTyVar = PLC.TyVarDecl PLC.TyName ()

type UPLCProgram uni fun = UPLC.Program UPLC.DeBruijn uni fun ()
