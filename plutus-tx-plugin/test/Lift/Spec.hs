{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings     #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE TemplateHaskell       #-}
{-# OPTIONS_GHC   -Wno-orphans #-}
module Lift.Spec where

import           Common
import           Lib
import           PlcTestUtils
import           Plugin.Data.Spec
import           Plugin.Primitives.Spec

import qualified PlutusTx.Builtins      as Builtins
import           PlutusTx.Code
import qualified PlutusTx.Lift          as Lift

Lift.makeLift ''MyMonoData
Lift.makeLift ''MyMonoRecord
Lift.makeLift ''MyPolyData

data NestedRecord = NestedRecord { unNested :: Maybe (Integer, Integer) }
Lift.makeLift ''NestedRecord

data WrappedBS = WrappedBS { unWrap :: Builtins.ByteString }
Lift.makeLift ''WrappedBS

newtype NewtypeInt = NewtypeInt { unNt :: Integer }
Lift.makeLift ''NewtypeInt

newtype Newtype2 = Newtype2 { unNt2 :: NewtypeInt }
Lift.makeLift ''Newtype2

newtype Newtype3 = Newtype3 { unNt3 :: Newtype2 }
Lift.makeLift ''Newtype3

-- 'Z' so it sorts late and this doesn't work by accident
data Z = Z Integer
Lift.makeLift ''Z
type Syn = Z

data SynExample = SynExample { unSE :: Syn }
Lift.makeLift ''SynExample

tests :: TestNested
tests = testNested "Lift" [
    goldenUPlc "int" (Lift.liftProgramDef (1::Integer))
    , goldenUPlc "tuple" (Lift.liftProgramDef (1::Integer, 2::Integer))
    , goldenUPlc "mono" (Lift.liftProgramDef (Mono2 2))
    , goldenUEval "monoInterop" [ getPlc monoCase, Lift.liftProgramDef (Mono1 1 2) ]
    , goldenUPlc "poly" (Lift.liftProgramDef (Poly1 (1::Integer) (2::Integer)))
    , goldenUEval "polyInterop" [ getPlc defaultCasePoly, Lift.liftProgramDef (Poly1 (1::Integer) (2::Integer)) ]
    , goldenUPlc "record" (Lift.liftProgramDef (MyMonoRecord 1 2))
    , goldenUEval "boolInterop" [ getPlc andPlc, Lift.liftProgramDef True, Lift.liftProgramDef True ]
    , goldenUPlc "list" (Lift.liftProgramDef ([1]::[Integer]))
    , goldenUEval "listInterop" [ getPlc listMatch, Lift.liftProgramDef ([1]::[Integer]) ]
    , goldenUPlc "nested" (Lift.liftProgramDef (NestedRecord (Just (1, 2))))
    , goldenUPlc "bytestring" (Lift.liftProgramDef (WrappedBS (Builtins.fromHaskellByteString "hello")))
    , goldenUPlc "newtypeInt" (Lift.liftProgramDef (NewtypeInt 1))
    , goldenUPlc "newtypeInt2" (Lift.liftProgramDef (Newtype2 $ NewtypeInt 1))
    , goldenUPlc "newtypeInt3" (Lift.liftProgramDef (Newtype3 $ Newtype2 $ NewtypeInt 1))
    , goldenUPlc "syn" (Lift.liftProgramDef (SynExample $ Z $ 1))
 ]
