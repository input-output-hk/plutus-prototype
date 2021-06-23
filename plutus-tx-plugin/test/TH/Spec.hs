{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE NoImplicitPrelude     #-}
{-# LANGUAGE OverloadedStrings     #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE TemplateHaskell       #-}
{-# LANGUAGE TypeApplications      #-}
{-# LANGUAGE TypeFamilies          #-}
{-# OPTIONS_GHC -fplugin PlutusTx.Plugin -fplugin-opt PlutusTx.Plugin:defer-errors -fplugin-opt PlutusTx.Plugin:debug-context #-}
{-# OPTIONS_GHC -Wno-orphans #-}
{-# OPTIONS_GHC   -g #-}

module TH.Spec (tests) where

import           Common
import           Lib
import           PlcTestUtils
import           PlutusPrelude             (view)

import           TH.TestTH

import qualified Prelude                   as Haskell

import           PlutusTx
import qualified PlutusTx.Builtins         as Builtins
import           PlutusTx.Code
import           PlutusTx.Evaluation
import           PlutusTx.Prelude
import           PlutusTx.TH

import qualified PlutusIR                  as PIR

import qualified PlutusCore                as PLC
import           PlutusCore.Pretty
import           UntypedPlutusCore
import qualified UntypedPlutusCore         as UPLC

import           Control.Exception
import           Control.Lens.Combinators  (_1)
import           Control.Monad.Except

import           Data.Text.Prettyprint.Doc
import           Test.Tasty

runPlcCek :: ToUPlc a PLC.DefaultUni PLC.DefaultFun => [a] -> ExceptT SomeException Haskell.IO (Term DeBruijn PLC.DefaultUni PLC.DefaultFun ())
runPlcCek values = do
     ps <- Haskell.traverse toUPlc values
     let p = Haskell.foldl1 UPLC.applyProgram ps
     either (throwError . SomeException) Haskell.pure $ evaluateCek p

runPlcCekTrace :: ToUPlc a PLC.DefaultUni PLC.DefaultFun => [a] -> ExceptT SomeException Haskell.IO ([Haskell.String], CekExTally PLC.DefaultFun, (Term DeBruijn PLC.DefaultUni PLC.DefaultFun ()))
runPlcCekTrace values = do
     ps <- Haskell.traverse toUPlc values
     let p = Haskell.foldl1 UPLC.applyProgram ps
     let (logOut, tally, result) = evaluateCekTrace p
     res <- either (throwError . SomeException) Haskell.pure result
     Haskell.pure (logOut, tally, res)

goldenEvalCek :: ToUPlc a PLC.DefaultUni PLC.DefaultFun => Haskell.String -> [a] -> TestNested
goldenEvalCek name values = nestedGoldenVsDocM name $ prettyPlcClassicDebug Haskell.<$> (rethrow $ runPlcCek values)

goldenEvalCekLog :: ToUPlc a PLC.DefaultUni PLC.DefaultFun => Haskell.String -> [a] -> TestNested
goldenEvalCekLog name values = nestedGoldenVsDocM name $ (pretty . (view _1)) Haskell.<$> (rethrow $ runPlcCekTrace values)

tests :: TestNested
tests = testNested "TH" [
    goldenPir "simple" simple
    , goldenPir "power" powerPlc
    , goldenPir "and" andPlc
    , goldenEvalCek "all" [allPlc]
    , goldenEvalCek "convertString" [convertString]
    , goldenEvalCekLog "traceDirect" [traceDirect]
    , goldenEvalCekLog "tracePrelude" [tracePrelude]
    , goldenEvalCekLog "traceRepeatedly" [traceRepeatedly]
    -- want to see the raw structure, so using Show
    , nestedGoldenVsDoc "someData" (pretty $ Haskell.show someData)
  ]

simple :: CompiledCode (Bool -> Integer)
simple = $$(compile [|| \(x::Bool) -> if x then (1::Integer) else (2::Integer) ||])

-- similar to the power example for Feldspar - should be completely unrolled at compile time
powerPlc :: CompiledCode (Integer -> Integer)
powerPlc = $$(compile [|| $$(power (4::Integer)) ||])

andPlc :: CompiledCode Bool
andPlc = $$(compile [|| $$(andTH) True False ||])

allPlc :: CompiledCode Bool
allPlc = $$(compile [|| all (\(x::Integer) -> x > 5) [7, 6] ||])

convertString :: CompiledCode Builtins.String
convertString = $$(compile [|| "test" ||])

traceDirect :: CompiledCode ()
traceDirect = $$(compile [|| Builtins.trace "test" ||])

tracePrelude :: CompiledCode Integer
tracePrelude = $$(compile [|| trace "test" (1::Integer) ||])

traceRepeatedly :: CompiledCode Integer
traceRepeatedly = $$(compile
     [||
               let i1 = trace "Making my first int" (1::Integer)
                   i2 = trace "Making my second int" (2::Integer)
                   i3 = trace "Adding them up" (i1 + i2)
              in i3
    ||])

data SomeType = One Integer | Two | Three ()

someData :: (Data, Data, Data)
someData = (toData (One 1), toData Two, toData (Three ()))

makeIsDataIndexed ''SomeType [('Two, 0), ('One, 1), ('Three, 2)]
