{-# LANGUAGE ConstraintKinds   #-}
{-# LANGUAGE DataKinds         #-}
{-# LANGUAGE FlexibleContexts  #-}
{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell   #-}
{-# LANGUAGE TypeApplications  #-}
{-# LANGUAGE TypeFamilies      #-}
{-# LANGUAGE TypeOperators     #-}
{-# LANGUAGE ViewPatterns      #-}

-- | Functions for compiling Plutus Core builtins.
module PlutusTx.Compiler.Builtins (
    builtinNames
    , defineBuiltinTypes
    , defineBuiltinTerms
    , lookupBuiltinTerm
    , lookupBuiltinType
    , errorTy
    , errorFunc) where

import                qualified PlutusTx.Builtins             as Builtins
import                qualified PlutusTx.ByteString           as ByteString
import                qualified PlutusTx.String               as String

import                          PlutusTx.Compiler.Error
import {-# SOURCE #-}           PlutusTx.Compiler.Expr
import                          PlutusTx.Compiler.Laziness
import                          PlutusTx.Compiler.Names
import {-# SOURCE #-}           PlutusTx.Compiler.Type
import                          PlutusTx.Compiler.Types
import                          PlutusTx.Compiler.Utils
import                          PlutusTx.PIRTypes

import                qualified PlutusIR                      as PIR
import                qualified PlutusIR.Compiler.Definitions as PIR
import                          PlutusIR.Compiler.Names
import                qualified PlutusIR.MkPir                as PIR
import                qualified PlutusIR.Purity               as PIR

import                qualified PlutusCore                    as PLC
import                qualified PlutusCore.Constant           as PLC
import                          PlutusCore.Quote
import                qualified PlutusCore.StdLib.Data.Bool   as Bool
import                qualified PlutusCore.StdLib.Data.Unit   as Unit

import                qualified GhcPlugins                    as GHC

import                qualified Language.Haskell.TH.Syntax    as TH

import                          Control.Monad
import                          Control.Monad.Reader

import                qualified Data.ByteString               as BS
import                qualified Data.Map                      as Map
import                          Data.Proxy
import                qualified Data.Set                      as Set

{- Note [Mapping builtins]
We want the user to be able to call the Plutus builtins as normal Haskell functions.

To do this, we provide a library of such functions in Haskell, and we define corresponding
functions and types in PIR so that we can translate references to the Haskell functions and
types into references to the PIR ones.

We can then do whatever we need to inside the definitions to line things up with the real builtins.
(See Note [Builtin types and Haskell types])

To do this, we first need a map from the Haskell TH names to the corresponding GHC names
(in fact the TyThings, so we have the types too). Annoyingly, this has to be done in the
GHC Core monad and then passed to us.

This map lets us write code that defines all the builtins (by their TH names), and also to look
up things by their TH names in the few other cases where we need to (mostly where we use specific
known builtins to implement primitives).

This is a bit fragile, since we rely on having all the names that we need, and having them
mapped to the right things (GHC will panic on us if we e.g. get the wrong kind of TyThing for
a name). We should probably revisit this later.
-}

{- Note [Builtin types and Haskell types]
Several of the PLC builtins use types that should (morally) line up with types that we compile from
Haskell (see also Note [Which types map to builtin types?]).
But there is a problem: they use either primitive or Scott-encoded versions of these types,
whereas when we compile them from Haskell they will end up as abstract types, and so the types
won't line up at the call site.

That is, we generate something like this:
(/\ (Integer :: *) .
  (\ addInteger : Integer -> Integer -> Integer .
      <use addInteger>
  )
  (\ x,y : Integer . <builtin addInteger> x y) -- Uh oh, type error, can't show that Integer = <builtin int>!
)
{<builtin int>}

We handle this in two different ways:
- For the types like Bool and Unit which are really algebraic types, and which have constructors etc.
that we care about elsewhere, we insert adaptor code into the definition of the builtin (see note [Mapping builtins]).
- For types like Integer and Bytestring which don't have visible constructors, we can treat them as completely opaque,
and we use a transparent type alias. (Actually we fake the alias by actually just substituting the definition in
everywhere until we have aliases in PIR. Bear this in mind for the examples below.)

Here's how that looks for a primitive that takes Ints and returns a Boolean, assuming we have bound Integer and Bool
already as an alias and an abstract type respectively:
(\ equalsInteger : Integer -> Integer -> Bool .
  <use equalsInteger>
)
(\ x, y : Integer . -- No need to do anything to the arguments, since we're using a transparent alias for Int
  (<builtin equalsInteger> x y) {Bool} True False -- Immediately match the builtin bool into an abstract Bool
)

We *could* do something like the interleaved definitions that we do for datatypes in PIR. Morally this is perhaps the
right thing to do: we should think of Integer and its builtins as a "module" that goes together and where all the definitions
have access to the internals of the other definitions. A datatype definition is then a special case of a module definition.
However, for the moment this would be quite a bit more design work and so we leave it for future work.

For an example of how the "abstract module" approach would look:
(/\ (Integer :: *) .
  (\ addInteger : Integer -> Integer -> Integer . -- Type signature is fine inside the abstraction
      <use addInteger>
  )
)
{<builtin int>}
(\ x,y : <builtin int> . <builtin addInteger> x y) -- No type error any more, abstraction is gone
-}

{- Note [Which types map to builtin types?]
We have (will have) Bool in the default builtin universe. Why do we not map the Haskell Bool type to the
builtin Bool, but rather compile it as a normal ADT?

The advantage of mapping a type to a builtin type is mainly performance:
- We can directly use (potentially optimized) implementations of operations on that type.
- We do not need adaptors to interoperate with builtin functions that use the builtin version of the type.

On the other hand, the advantages of *not* doing this are:
- User-written code that operates on the type as normal (e.g. pattern matching) will work.
    - We could make this work by compiling pattern matching specially for the builtin type, but this means
      more special cases in the compiler (boo). Maybe we can do this generically in future.
- Code that uses these types will also be compilable/runnable if those builtins are not present.

Overall, this means that we only map performance-critical types like Integer and ByteString directly to
builtin types, and the others we compile normally.
-}

{- Note [Builtin terms and values]
When generating let-bindings, we would like to generate strict bindings only for things that are obviously
pure, and non-strict bindings otherwise. This ensures that we won't evaluate the RHS of the binding prematurely,
which matters if it could trigger an error, or some other effect.

Additionally, strict bindings are a bit more efficient than non-strict ones (non-strict ones get turned into
lambdas from unit and forcing in the body). So we would like to use strict bindings where possible.

Now, we generate bindings for all our builtin functions... but they are not *obviously* pure!
Fortunately, we have a more sophisticated purity check that also detects unsaturated builtin applications,
which handles these cases too.
-}

mkBuiltin :: fun -> PIR.Term tyname name uni fun ()
mkBuiltin = PIR.Builtin ()

-- | The 'TH.Name's for which 'BuiltinNameInfo' needs to be provided.
builtinNames :: [TH.Name]
builtinNames = [
      ''Builtins.ByteString
    , ''Integer
    , ''Bool
    , ''()

    , 'Builtins.concatenate
    , 'Builtins.takeByteString
    , 'Builtins.dropByteString
    , 'Builtins.sha2_256
    , 'Builtins.sha3_256
    , 'Builtins.equalsByteString
    , 'Builtins.lessThanByteString
    , 'Builtins.greaterThanByteString
    , 'Builtins.emptyByteString
    , 'Builtins.decodeUtf8
    , 'Builtins.encodeUtf8
    , 'ByteString.stringToBuiltinByteString

    , 'Builtins.verifySignature

    , 'Builtins.addInteger
    , 'Builtins.subtractInteger
    , 'Builtins.multiplyInteger
    , 'Builtins.divideInteger
    , 'Builtins.modInteger
    , 'Builtins.quotientInteger
    , 'Builtins.remainderInteger
    , 'Builtins.greaterThanInteger
    , 'Builtins.greaterThanEqInteger
    , 'Builtins.lessThanInteger
    , 'Builtins.lessThanEqInteger
    , 'Builtins.equalsInteger

    , 'Builtins.error

    , ''Builtins.String
    , ''Char
    , 'Builtins.appendString
    , 'Builtins.emptyString
    , 'Builtins.charToString
    , 'Builtins.equalsString
    , 'String.stringToBuiltinString

    , 'Builtins.trace
    ]

-- | Get the 'GHC.TyThing' for a given 'TH.Name' which was stored in the builtin name info,
-- failing if it is missing.
getThing :: Compiling uni fun m => TH.Name -> m GHC.TyThing
getThing name = do
    CompileContext{ccBuiltinNameInfo=names} <- ask
    case Map.lookup name names of
        Nothing    -> throwSd CompilationError $ "Missing builtin name:" GHC.<+> (GHC.text $ show name)
        Just thing -> pure thing

defineBuiltinTerm :: Compiling uni fun m => TH.Name -> PIRTerm uni fun -> [GHC.Name] -> m ()
defineBuiltinTerm name term deps = do
    ghcId <- GHC.tyThingId <$> getThing name
    var <- compileVarFresh ghcId
    -- See Note [Builtin terms and values]
    let strictness = if PIR.isPure (const PIR.NonStrict) term then PIR.Strict else PIR.NonStrict
        def = PIR.Def var (term, strictness)
    PIR.defineTerm (LexName $ GHC.getName ghcId) def (Set.fromList $ LexName <$> deps)

-- | Add definitions for all the builtin types to the environment.
defineBuiltinType :: forall uni fun m. Compiling uni fun m => TH.Name -> PIRType uni -> [GHC.Name] -> m ()
defineBuiltinType name ty deps = do
    tc <- GHC.tyThingTyCon <$> getThing name
    var <- compileTcTyVarFresh tc
    PIR.defineType (LexName $ GHC.getName tc) (PIR.Def var ty) (Set.fromList $ LexName <$> deps)
    -- these are all aliases for now
    PIR.recordAlias @LexName @uni @fun @() (LexName $ GHC.getName tc)

-- | Add definitions for all the builtin terms to the environment.
defineBuiltinTerms :: CompilingDefault uni fun m => m ()
defineBuiltinTerms = do
    bs <- GHC.getName <$> getThing ''Builtins.ByteString
    int <- GHC.getName <$> getThing ''Integer
    bool <- GHC.getName <$> getThing ''Bool
    unit <- GHC.getName <$> getThing ''()
    str <- GHC.getName <$> getThing ''Builtins.String
    char <- GHC.getName <$> getThing ''Char

    intTy <- lookupBuiltinType ''Integer
    bsTy <- lookupBuiltinType ''Builtins.ByteString
    strTy <- lookupBuiltinType ''Builtins.String

    -- See Note [Builtin terms and values] for the eta expansion below

    -- Bytestring builtins
    do
        let term = mkBuiltin PLC.Concatenate
        defineBuiltinTerm 'Builtins.concatenate term [bs]
    do
        let term = mkBuiltin PLC.TakeByteString
        defineBuiltinTerm 'Builtins.takeByteString term [int, bs]
    do
        let term = mkBuiltin PLC.DropByteString
        defineBuiltinTerm 'Builtins.dropByteString term [int, bs]
    do
        let term = mkBuiltin PLC.SHA2
        defineBuiltinTerm 'Builtins.sha2_256 term [bs]
    do
        let term = mkBuiltin PLC.SHA3
        defineBuiltinTerm 'Builtins.sha3_256 term [bs]
    do
        term <- wrapRel bsTy 2 $ mkBuiltin PLC.EqByteString
        defineBuiltinTerm 'Builtins.equalsByteString term [bs, bool]
    do
        term <- wrapRel bsTy 2 $ mkBuiltin PLC.LtByteString
        defineBuiltinTerm 'Builtins.lessThanByteString term [bs, bool]
    do
        term <- wrapRel bsTy 2 $ mkBuiltin PLC.GtByteString
        defineBuiltinTerm 'Builtins.greaterThanByteString term [bs, bool]
    do
        let term = PIR.mkConstant () BS.empty
        defineBuiltinTerm 'Builtins.emptyByteString term [bs]
    do
        let term = mkBuiltin PLC.DecodeUtf8
        defineBuiltinTerm 'Builtins.decodeUtf8 term [bs]
    do
        let term = mkBuiltin PLC.EncodeUtf8
        defineBuiltinTerm 'Builtins.encodeUtf8 term [str]

    -- Integer builtins
    do
        let term = mkBuiltin PLC.AddInteger
        defineBuiltinTerm 'Builtins.addInteger term [int]
    do
        let term = mkBuiltin PLC.SubtractInteger
        defineBuiltinTerm 'Builtins.subtractInteger term [int]
    do
        let term = mkBuiltin PLC.MultiplyInteger
        defineBuiltinTerm 'Builtins.multiplyInteger term [int]
    do
        let term = mkBuiltin PLC.DivideInteger
        defineBuiltinTerm 'Builtins.divideInteger term [int]
    do
        let term = mkBuiltin PLC.ModInteger
        defineBuiltinTerm 'Builtins.modInteger term [int]
    do
        let term = mkBuiltin PLC.QuotientInteger
        defineBuiltinTerm 'Builtins.quotientInteger term [int]
    do
        let term = mkBuiltin PLC.RemainderInteger
        defineBuiltinTerm 'Builtins.remainderInteger term [int]
    do
        term <- wrapRel intTy 2 $ mkBuiltin PLC.GreaterThanInteger
        defineBuiltinTerm 'Builtins.greaterThanInteger term [int, bool]
    do
        term <- wrapRel intTy 2 $ mkBuiltin PLC.GreaterThanEqInteger
        defineBuiltinTerm 'Builtins.greaterThanEqInteger term [int, bool]
    do
        term <- wrapRel intTy 2 $ mkBuiltin PLC.LessThanInteger
        defineBuiltinTerm 'Builtins.lessThanInteger term [int, bool]
    do
        term <- wrapRel intTy 2 $ mkBuiltin PLC.LessThanEqInteger
        defineBuiltinTerm 'Builtins.lessThanEqInteger term [int, bool]
    do
        term <- wrapRel intTy 2 $ mkBuiltin PLC.EqInteger
        defineBuiltinTerm 'Builtins.equalsInteger term [int, bool]

    -- Blockchain builtins
    do
        term <- wrapRel bsTy 3 $ mkBuiltin PLC.VerifySignature
        defineBuiltinTerm 'Builtins.verifySignature term [bs, bool]

    -- Error
    do
        -- See Note [Delaying error]
        term <- delayedErrorFunc
        defineBuiltinTerm 'Builtins.error term [unit]

    -- Strings and chars
    do
        let term = mkBuiltin PLC.Append
        defineBuiltinTerm 'Builtins.appendString term [str]
    do
        let term = PIR.mkConstant () ("" :: String)
        defineBuiltinTerm 'Builtins.emptyString term [str]
    do
        let term = mkBuiltin PLC.CharToString
        defineBuiltinTerm 'Builtins.charToString term [char, str]
    do
        term <- wrapRel strTy 2 $ mkBuiltin PLC.EqualsString
        defineBuiltinTerm 'Builtins.equalsString term [str, bool]
    do
        term <- wrapUnitFun strTy $ mkBuiltin PLC.Trace
        defineBuiltinTerm 'Builtins.trace term [str, unit]

defineBuiltinTypes
    :: CompilingDefault uni fun m
    => m ()
defineBuiltinTypes = do
    do
        let ty = PLC.toTypeAst $ Proxy @BS.ByteString
        defineBuiltinType ''Builtins.ByteString ty []
    do
        let ty = PLC.toTypeAst $ Proxy @Integer
        defineBuiltinType ''Integer ty []

    -- Strings and chars
    do
        let ty = PLC.toTypeAst $ Proxy @String
        defineBuiltinType ''Builtins.String ty []
    do
        let ty = PLC.toTypeAst $ Proxy @Char
        defineBuiltinType ''Char ty []

-- | Lookup a builtin term by its TH name. These are assumed to be present, so fails if it cannot find it.
lookupBuiltinTerm :: Compiling uni fun m => TH.Name -> m (PIRTerm uni fun)
lookupBuiltinTerm name = do
    ghcName <- GHC.getName <$> getThing name
    maybeTerm <- PIR.lookupTerm () (LexName ghcName)
    case maybeTerm of
        Just t  -> pure t
        Nothing -> throwSd CompilationError $ "Missing builtin definition:" GHC.<+> (GHC.text $ show name)

-- | Lookup a builtin type by its TH name. These are assumed to be present, so fails if it is cannot find it.
lookupBuiltinType :: Compiling uni fun m => TH.Name -> m (PIRType uni)
lookupBuiltinType name = do
    ghcName <- GHC.getName <$> getThing name
    maybeType <- PIR.lookupType () (LexName ghcName)
    case maybeType of
        Just t  -> pure t
        Nothing -> throwSd CompilationError $ "Missing builtin definition:" GHC.<+> (GHC.text $ show name)

-- | The function 'error :: forall a . a'.
errorFunc :: Compiling uni fun m => m (PIRTerm uni fun)
errorFunc = do
    n <- safeFreshTyName "e"
    pure $ PIR.TyAbs () n (PIR.Type ()) (PIR.Error () (PIR.TyVar () n))

-- | The delayed error function 'error :: forall a . () -> a'.
delayedErrorFunc :: Compiling uni fun m => m (PIRTerm uni fun)
delayedErrorFunc = do
    n <- safeFreshTyName "e"
    let body = PIR.Error () (PIR.TyVar () n)
    PIR.TyAbs () n (PIR.Type ()) <$> delay body

-- | The type 'forall a. a'.
errorTy :: Compiling uni fun m => m (PIRType uni)
errorTy = do
    tyname <- safeFreshTyName "a"
    pure $ PIR.TyForall () tyname (PIR.Type ()) (PIR.TyVar () tyname)

-- TODO: bind the converter to a name too. Need an appropriate GHC.Name for
-- it, since that's what our definitions are hung off. Also the type wouldn't
-- be a simple conversion of the Haskell type, because it takes a Scott boolean.
-- | Convert a Scott-encoded Boolean into a Haskell Boolean.
scottBoolToHaskellBool :: CompilingDefault uni fun m => m (PIRTerm uni fun)
scottBoolToHaskellBool = do
    let scottBoolTy = Bool.bool
    haskellBoolTy <- compileType GHC.boolTy

    arg <- liftQuote $ freshName "b"
    let instantiatedMatch = PIR.TyInst () (PIR.Builtin () PLC.IfThenElse) haskellBoolTy

    haskellTrue <- compileDataConRef GHC.trueDataCon
    haskellFalse <- compileDataConRef GHC.falseDataCon
    pure $
        PIR.LamAbs () arg scottBoolTy $
        PIR.mkIterApp () instantiatedMatch [ (PIR.Var () arg), haskellTrue, haskellFalse ]

-- | Wrap an relation of arity @n@ that produces a Scott boolean.
wrapRel :: CompilingDefault uni fun m => PIRType uni -> Int -> PIRTerm uni fun -> m (PIRTerm uni fun)
wrapRel argTy arity term = do
    args <- replicateM arity $ do
        name <- safeFreshName "arg"
        pure $ PIR.VarDecl () name argTy

    converter <- scottBoolToHaskellBool

    pure $
        PIR.mkIterLamAbs args $
        PIR.Apply () converter (PIR.mkIterApp () term (fmap (PIR.mkVar ()) args))

-- | Convert a Scott-encoded Unit into a Haskell Unit.
scottUnitToHaskellUnit :: CompilingDefault uni fun m => m (PIRTerm uni fun)
scottUnitToHaskellUnit = do
    let scottUnitTy = Unit.unit

    arg <- liftQuote $ freshName "b"

    haskellUnitVal <- compileDataConRef GHC.unitDataCon
    pure $ PIR.LamAbs () arg scottUnitTy haskellUnitVal

-- | Wrap an function with the given argument type that produces a Scott unit.
wrapUnitFun :: CompilingDefault uni fun m => PIRType uni -> PIRTerm uni fun -> m (PIRTerm uni fun)
wrapUnitFun argTy term = do
    arg <- do
        name <- safeFreshName "arg"
        pure $ PIR.VarDecl () name argTy

    converter <- scottUnitToHaskellUnit

    pure $
        PIR.mkIterLamAbs [arg] $
        PIR.Apply () converter (PIR.Apply () term (PIR.mkVar () arg))
