{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}
{-# OPTIONS_GHC -fplugin PlutusTx.Plugin -fplugin-opt PlutusTx.Plugin:defer-errors -fplugin-opt PlutusTx.Plugin:debug-context #-}

module Plugin.Primitives.Spec where

import           Common
import           Lib
import           PlcTestUtils
import           Plugin.Lib

import qualified PlutusTx.Builtins  as Builtins
import           PlutusTx.Code
import           PlutusTx.Lift
import           PlutusTx.Plugin
import qualified PlutusTx.Prelude   as P

import qualified PlutusCore.Default as PLC

import           Data.Proxy

import           GHC.Magic

primitives :: TestNested
primitives = testNested "Primitives" [
    goldenPir "string" string
  , goldenPir "int" int
  , goldenPir "int2" int2
  , goldenPir "bool" bool
  , goldenPir "and" andPlc
  , goldenUEval "andApply" [ toUPlc andPlc, toUPlc $ plc (Proxy @"T") True, toUPlc $ plc (Proxy @"F") False ]
  , goldenPir "tuple" tuple
  , goldenPir "tupleMatch" tupleMatch
  , goldenUEval "tupleConstDest" [ toUPlc tupleMatch, toUPlc tuple ]
  , goldenPir "intCompare" intCompare
  , goldenPir "intEq" intEq
  , goldenUEval "intEqApply" [ toUPlc intEq, toUPlc int, toUPlc int ]
  , goldenPir "void" void
  , goldenPir "intPlus" intPlus
  , goldenPir "intDiv" intDiv
  , goldenUEval "intPlusApply" [ toUPlc intPlus, toUPlc int, toUPlc int2 ]
  , goldenPir "error" errorPlc
  , goldenPir "ifThenElse" ifThenElse
  , goldenUEval "ifThenElseApply" [ toUPlc ifThenElse, toUPlc int, toUPlc int2 ]
  , goldenPir "emptyByteString" emptyByteString
  , goldenUEval "emptyByteStringApply" [ getPlc emptyByteString, liftProgram Builtins.emptyByteString ]
  , goldenPir "bytestring" bytestring
  , goldenUEval "bytestringApply" [ getPlc bytestring, liftProgram ((Builtins.fromHaskellByteString "hello") ::Builtins.ByteString) ]
  , goldenUEval "sha2_256" [ getPlc sha2, liftProgram ((Builtins.fromHaskellByteString "hello") :: Builtins.ByteString)]
  , goldenUEval "equalsByteString" [ getPlc bsEquals, liftProgram ((Builtins.fromHaskellByteString "hello") :: Builtins.ByteString), liftProgram ((Builtins.fromHaskellByteString "hello") :: Builtins.ByteString)]
  , goldenUEval "ltByteString" [ getPlc bsLt, liftProgram ((Builtins.fromHaskellByteString "hello") :: Builtins.ByteString), liftProgram ((Builtins.fromHaskellByteString "world") :: Builtins.ByteString)]
  , goldenUEval "decodeUtf8" [ getPlc bsDecode, liftProgram ((Builtins.fromHaskellByteString "hello") :: Builtins.ByteString)]
  , goldenPir "verify" verify
  , goldenPir "trace" trace
  , goldenPir "stringLiteral" stringLiteral
  , goldenPir "stringConvert" stringConvert
  , goldenUEval "equalsString" [ getPlc stringEquals, liftProgram ("hello" :: String), liftProgram ("hello" :: String)]
  , goldenPir "encodeUtf8" stringEncode
  ]

string :: CompiledCode String
string = plc (Proxy @"string") "test"

int :: CompiledCode Integer
int = plc (Proxy @"int") (1::Integer)

int2 :: CompiledCode Integer
int2 = plc (Proxy @"int2") (2::Integer)

emptyBS :: CompiledCode Builtins.ByteString
emptyBS = plc (Proxy @"emptyBS") Builtins.emptyByteString

bool :: CompiledCode Bool
bool = plc (Proxy @"bool") True

andPlc :: CompiledCode (Bool -> Bool -> Bool)
andPlc = plc (Proxy @"andPlc") (\(x::Bool) (y::Bool) -> if x then (if y then True else False) else False)

tuple :: CompiledCode (Integer, Integer)
tuple = plc (Proxy @"tuple") (1::Integer, 2::Integer)

tupleMatch :: CompiledCode ((Integer, Integer) -> Integer)
tupleMatch = plc (Proxy @"tupleMatch") (\(x:: (Integer, Integer)) -> let (a, b) = x in a)

intCompare :: CompiledCode (Integer -> Integer -> Bool)
intCompare = plc (Proxy @"intCompare") (\(x::Integer) (y::Integer) -> Builtins.lessThanInteger x y)

intEq :: CompiledCode (Integer -> Integer -> Bool)
intEq = plc (Proxy @"intEq") (\(x::Integer) (y::Integer) -> Builtins.equalsInteger x y)

-- Has a Void in it
void :: CompiledCode (Integer -> Integer -> Bool)
void = plc (Proxy @"void") (\(x::Integer) (y::Integer) -> let a x' y' = case (x', y') of { (True, True) -> True; _ -> False; } in Builtins.equalsInteger x y `a` Builtins.equalsInteger y x)

intPlus :: CompiledCode (Integer -> Integer -> Integer)
intPlus = plc (Proxy @"intPlus") (\(x::Integer) (y::Integer) -> Builtins.addInteger x y)

intDiv :: CompiledCode (Integer -> Integer -> Integer)
intDiv = plc (Proxy @"intDiv") (\(x::Integer) (y::Integer) -> Builtins.divideInteger x y)

errorPlc :: CompiledCode (() -> Integer)
errorPlc = plc (Proxy @"errorPlc") (Builtins.error @Integer)

ifThenElse :: CompiledCode (Integer -> Integer -> Integer)
ifThenElse = plc (Proxy @"ifThenElse") (\(x::Integer) (y::Integer) -> if Builtins.equalsInteger x y then x else y)

emptyByteString :: CompiledCode (Builtins.ByteString -> Builtins.ByteString)
emptyByteString = plc (Proxy @"emptyByteString") (\(x :: Builtins.ByteString) -> x)

bytestring :: CompiledCode (Builtins.ByteString -> Builtins.ByteString)
bytestring = plc (Proxy @"bytestring") (\(x::Builtins.ByteString) -> x)

sha2 :: CompiledCode (Builtins.ByteString -> Builtins.ByteString)
sha2 = plc (Proxy @"sha2") (\(x :: Builtins.ByteString) -> Builtins.sha2_256 x)

bsEquals :: CompiledCode (Builtins.ByteString -> Builtins.ByteString -> Bool)
bsEquals = plc (Proxy @"bs32Equals") (\(x :: Builtins.ByteString) (y :: Builtins.ByteString) -> Builtins.equalsByteString x y)

bsLt :: CompiledCode (Builtins.ByteString -> Builtins.ByteString -> Bool)
bsLt = plc (Proxy @"bsLt") (\(x :: Builtins.ByteString) (y :: Builtins.ByteString) -> Builtins.lessThanByteString x y)

bsDecode :: CompiledCode (Builtins.ByteString -> Builtins.String)
bsDecode = plc (Proxy @"bsDecode") (\(x :: Builtins.ByteString) -> Builtins.decodeUtf8 x)

verify :: CompiledCode (Builtins.ByteString -> Builtins.ByteString -> Builtins.ByteString -> Bool)
verify = plc (Proxy @"verify") (\(x::Builtins.ByteString) (y::Builtins.ByteString) (z::Builtins.ByteString) -> Builtins.verifySignature x y z)

trace :: CompiledCode (Builtins.String -> ())
trace = plc (Proxy @"trace") (\(x :: Builtins.String) -> Builtins.trace x)

stringLiteral :: CompiledCode (Builtins.String)
stringLiteral = plc (Proxy @"stringLiteral") ("abc"::Builtins.String)

stringConvert :: CompiledCode (Builtins.String)
stringConvert = plc (Proxy @"stringConvert") ((noinline P.stringToBuiltinString) "abc")

stringEquals :: CompiledCode (String -> String -> Bool)
stringEquals = plc (Proxy @"string32Equals") (\(x :: String) (y :: String) -> Builtins.equalsString (P.stringToBuiltinString x) (P.stringToBuiltinString y))

stringEncode :: CompiledCode (Builtins.ByteString)
stringEncode = plc (Proxy @"stringEncode") (Builtins.encodeUtf8 "abc")
