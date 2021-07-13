{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings     #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE TemplateHaskell       #-}
{-# LANGUAGE TypeApplications      #-}
{-# OPTIONS_GHC   -Wno-orphans #-}
{-# OPTIONS_GHC -fplugin PlutusTx.Plugin #-}
{-# OPTIONS_GHC -fplugin-opt PlutusTx.Plugin:defer-errors #-}
{-# OPTIONS_GHC -fplugin-opt PlutusTx.Plugin:no-context #-}
module IsData.Spec where

import           Common
import           Lib
import           PlcTestUtils
import           Plugin.Data.Spec
import           Plugin.Primitives.Spec

import qualified PlutusTx.Builtins      as Builtins
import           PlutusTx.Code
import qualified PlutusTx.IsData        as IsData
import           PlutusTx.Plugin
import qualified PlutusTx.Prelude       as P

import qualified PlutusCore             as PLC
import qualified PlutusCore.MkPlc       as PLC
import qualified UntypedPlutusCore      as UPLC

import           Data.Proxy

IsData.unstableMakeIsData ''MyMonoData
IsData.unstableMakeIsData ''MyMonoRecord
IsData.unstableMakeIsData ''MyPolyData

data NestedRecord = NestedRecord { unNested :: Maybe (Integer, Integer) }
IsData.unstableMakeIsData ''NestedRecord

instance P.Eq NestedRecord where
    {-# INLINABLE (==) #-}
    (NestedRecord i1) == (NestedRecord i2) = i1 P.== i2

data WrappedBS = WrappedBS { unWrap :: Builtins.ByteString }
IsData.unstableMakeIsData ''WrappedBS

instance P.Eq WrappedBS where
    {-# INLINABLE (==) #-}
    (WrappedBS i1) == (WrappedBS i2) = i1 P.== i2

-- 'Z' so it sorts late and this doesn't work by accident
data Z = Z Integer
IsData.unstableMakeIsData ''Z
type Syn = Z

instance P.Eq Z where
    {-# INLINABLE (==) #-}
    (Z i1) == (Z i2) = i1 P.== i2

data SynExample = SynExample { unSE :: Syn }
IsData.unstableMakeIsData ''SynExample

instance P.Eq SynExample where
    (SynExample i1) == (SynExample i2) = i1 P.== i2

{-# INLINABLE isDataRoundtrip #-}
isDataRoundtrip :: (IsData.IsData a, P.Eq a) => a -> Bool
isDataRoundtrip a = case IsData.fromBuiltinData (IsData.toBuiltinData a) of
    Just a' -> a P.== a'
    Nothing -> False

tests :: TestNested
tests = testNested "IsData" [
    goldenUEval "int" [plc (Proxy @"int") (isDataRoundtrip (1::Integer))]
    , goldenUEval "tuple" [plc (Proxy @"tuple") (isDataRoundtrip (1::Integer, 2::Integer))]
    , goldenUEval "tupleInterop" [
            getPlc (plc (Proxy @"tupleInterop") (\(d :: P.BuiltinData) -> case IsData.fromBuiltinData d of { Just t -> t P.== (1::Integer, 2::Integer); Nothing -> False}))
            , UPLC.Program () (PLC.defaultVersion ()) (PLC.mkConstant () (IsData.toData (1::Integer, 2::Integer)))]
    , goldenUEval "unit" [plc (Proxy @"unit") (isDataRoundtrip ())]
    , goldenUEval "unitInterop" [
            getPlc (plc (Proxy @"unitInterop") (\(d :: P.BuiltinData) -> case IsData.fromBuiltinData d of { Just t -> t P.== (); Nothing -> False}))
            , UPLC.Program () (PLC.defaultVersion ()) (PLC.mkConstant () (IsData.toData ()))]
    , goldenUEval "mono" [plc (Proxy @"mono") (isDataRoundtrip (Mono2 2))]
    , goldenUEval "poly" [plc (Proxy @"poly") (isDataRoundtrip (Poly1 (1::Integer) (2::Integer)))]
    , goldenUEval "record" [plc (Proxy @"record") (isDataRoundtrip (MyMonoRecord 1 2))]
    , goldenUEval "list" [plc (Proxy @"list") (isDataRoundtrip ([1]::[Integer]))]
    , goldenUEval "nested" [plc (Proxy @"nested") (isDataRoundtrip (NestedRecord (Just (1, 2))))]
    , goldenUEval "bytestring" [plc (Proxy @"bytestring") (isDataRoundtrip (WrappedBS Builtins.emptyByteString))]
    , goldenUEval "syn" [plc (Proxy @"syn") (isDataRoundtrip (SynExample (Z 1)))]
  ]
