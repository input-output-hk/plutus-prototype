{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE LambdaCase          #-}
{-# LANGUAGE MagicHash           #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}
{-# OPTIONS_GHC -fplugin PlutusTx.Plugin -fplugin-opt PlutusTx.Plugin:defer-errors -fplugin-opt PlutusTx.Plugin:no-context #-}

module Plugin.Errors.Spec where

import           Common
import           Lib
import           PlcTestUtils
import           Plugin.Lib

import qualified PlutusTx.Builtins         as Builtins
import           PlutusTx.Code
import           PlutusTx.Plugin

import qualified PlutusCore.Default        as PLC

import           Data.Proxy
import           Data.String

-- Normally GHC will irritatingly case integers for us in some circumstances, but we want to do it
-- explicitly here, so we need to see the constructors.
import           GHC.Integer.GMP.Internals

-- this module does lots of weird stuff deliberately
{- HLINT ignore -}

errors :: TestNested
errors = testNested "Errors" [
    goldenUPlcCatch "machInt" machInt
    -- FIXME: This fails differently in nix, possibly due to slightly different optimization settings
    -- , goldenPlcCatch "negativeInt" negativeInt
    , goldenUPlcCatch "caseInt" caseInt
    , goldenUPlcCatch "recursiveNewtype" recursiveNewtype
    , goldenUPlcCatch "mutualRecursionUnfoldingsLocal" mutualRecursionUnfoldingsLocal
    , goldenUPlcCatch "literalCaseInt" literalCaseInt
    , goldenUPlcCatch "literalCaseBs" literalCaseBs
    , goldenUPlcCatch "literalCaseOther" literalCaseOther
  ]

machInt :: CompiledCode Int
machInt = plc (Proxy @"machInt") (1::Int)

negativeInt :: CompiledCode Integer
negativeInt = plc (Proxy @"negativeInt") (-1 :: Integer)

caseInt :: CompiledCode (Integer -> Bool)
caseInt = plc (Proxy @"caseInt") (\(i::Integer) -> case i of { S# i -> True; _ -> False; } )

newtype RecursiveNewtype = RecursiveNewtype [RecursiveNewtype]

recursiveNewtype :: CompiledCode (RecursiveNewtype)
recursiveNewtype = plc (Proxy @"recursiveNewtype") (RecursiveNewtype [])

{-# INLINABLE evenDirectLocal #-}
evenDirectLocal :: Integer -> Bool
evenDirectLocal n = if Builtins.equalsInteger n 0 then True else oddDirectLocal (Builtins.subtractInteger n 1)

{-# INLINABLE oddDirectLocal #-}
oddDirectLocal :: Integer -> Bool
oddDirectLocal n = if Builtins.equalsInteger n 0 then False else evenDirectLocal (Builtins.subtractInteger n 1)

-- FIXME: these seem to only get unfoldings when they're in a separate module, even with the simplifier pass
mutualRecursionUnfoldingsLocal :: CompiledCode Bool
mutualRecursionUnfoldingsLocal = plc (Proxy @"mutualRecursionUnfoldingsLocal") (evenDirectLocal 4)

literalCaseInt :: CompiledCode (Integer -> Integer)
literalCaseInt = plc (Proxy @"literalCaseInt") (\case { 1 -> 2; x -> x})

literalCaseBs :: CompiledCode (Builtins.ByteString -> Builtins.ByteString)
literalCaseBs = plc (Proxy @"literalCaseBs") (\x -> case x of { "abc" -> ""; x -> x})

data AType = AType

instance IsString AType where
    fromString _ = AType

instance Eq AType where
    AType == AType = True

-- Unfortunately, this actually succeeds, since the match gets turned into an equality and we can actually inline it.
-- I'm leaving it here since I'd really prefer it were an error for consistency, but I'm not sure how to do that nicely.
literalCaseOther :: CompiledCode (AType -> AType)
literalCaseOther = plc (Proxy @"literalCaseOther") (\x -> case x of { "abc" -> ""; x -> x})
