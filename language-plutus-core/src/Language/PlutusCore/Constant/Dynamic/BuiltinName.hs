{-# LANGUAGE DataKinds         #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications  #-}

module Language.PlutusCore.Constant.Dynamic.BuiltinName
    ( dynamicCharToStringName
    , dynamicCharToStringMeaning
    , dynamicCharToStringDefinition
    , dynamicCharToString
    , dynamicAppendName
    , dynamicAppendMeaning
    , dynamicAppendDefinition
    , dynamicAppend
    , dynamicTraceName
    , dynamicTraceMeaningMock
    , dynamicTraceDefinitionMock
    , dynamicSealMeaning
    , dynamicSealDefinition
    , dynamicUnsealMeaning
    , dynamicUnsealDefinition
    ) where

import           Language.PlutusCore.Constant.Dynamic.Instances
import           Language.PlutusCore.Constant.Make
import           Language.PlutusCore.Constant.Typed
import           Language.PlutusCore.Lexer.Type
import           Language.PlutusCore.Type

import           Data.Coerce
import           Data.Proxy
import           Debug.Trace                                    (trace)

dynamicCharToStringName :: DynamicBuiltinName
dynamicCharToStringName = DynamicBuiltinName "charToString"

dynamicCharToStringMeaning :: DynamicBuiltinNameMeaning
dynamicCharToStringMeaning = DynamicBuiltinNameMeaning sch pure where
    sch =
        Proxy @Char `TypeSchemeArrow`
        TypeSchemeResult (Proxy @String)

dynamicCharToStringDefinition :: DynamicBuiltinNameDefinition
dynamicCharToStringDefinition =
    DynamicBuiltinNameDefinition dynamicCharToStringName dynamicCharToStringMeaning

dynamicCharToString :: Term tyname name ()
dynamicCharToString = dynamicBuiltinNameAsTerm dynamicCharToStringName

dynamicAppendName :: DynamicBuiltinName
dynamicAppendName = DynamicBuiltinName "append"

dynamicAppendMeaning :: DynamicBuiltinNameMeaning
dynamicAppendMeaning = DynamicBuiltinNameMeaning sch (++) where
    sch =
        Proxy @String `TypeSchemeArrow`
        Proxy @String `TypeSchemeArrow`
        TypeSchemeResult (Proxy @String)

dynamicAppendDefinition :: DynamicBuiltinNameDefinition
dynamicAppendDefinition =
    DynamicBuiltinNameDefinition dynamicAppendName dynamicAppendMeaning

dynamicAppend :: Term tyname name ()
dynamicAppend = dynamicBuiltinNameAsTerm dynamicAppendName

dynamicTraceName :: DynamicBuiltinName
dynamicTraceName = DynamicBuiltinName "trace"

dynamicTraceMeaningMock :: DynamicBuiltinNameMeaning
dynamicTraceMeaningMock = DynamicBuiltinNameMeaning sch (flip trace ()) where
    sch =
        Proxy @String `TypeSchemeArrow`
        TypeSchemeResult (Proxy @())

dynamicTraceDefinitionMock :: DynamicBuiltinNameDefinition
dynamicTraceDefinitionMock =
    DynamicBuiltinNameDefinition dynamicTraceName dynamicTraceMeaningMock

dynamicSealMeaning :: DynamicBuiltinNameMeaning
dynamicSealMeaning = DynamicBuiltinNameMeaning sch Sealed where
    sch =
        TypeSchemeAllType @"a" @0 Proxy $ \a@(_ :: Proxy a) ->
        a `TypeSchemeArrow`
        TypeSchemeResult (Proxy @(Sealed a))

dynamicSealDefinition :: DynamicBuiltinNameDefinition
dynamicSealDefinition =
    DynamicBuiltinNameDefinition dynamicSealName dynamicSealMeaning

dynamicUnsealMeaning :: DynamicBuiltinNameMeaning
dynamicUnsealMeaning = DynamicBuiltinNameMeaning sch coerce where
    sch =
        TypeSchemeAllType @"a" @0 Proxy $ \a@(_ :: Proxy a) ->
        Proxy @(CrossSealed a) `TypeSchemeArrow`
        TypeSchemeResult a

dynamicUnsealDefinition :: DynamicBuiltinNameDefinition
dynamicUnsealDefinition =
    DynamicBuiltinNameDefinition dynamicUnsealName dynamicUnsealMeaning
