module Language.PlutusCore
    (
      -- * Parser
      parse
    , parseST
    , parseTermST
    , parseTypeST
    , parseScoped
    , parseProgram
    , parseTerm
    , parseType
    -- * AST
    , Term (..)
    , termSubterms
    , termSubtypes
    , Type (..)
    , typeSubtypes
    , Constant (..)
    , Builtin (..)
    , Kind (..)
    , ParseError (..)
    , Version (..)
    , Program (..)
    , Name (..)
    , TyName (..)
    , Unique (..)
    , UniqueMap (..)
    , Value
    , BuiltinName (..)
    , DynamicBuiltinName (..)
    , StagedBuiltinName (..)
    , TypeBuiltin (..)
    , Normalized (..)
    , defaultVersion
    , allBuiltinNames
    , allKeywords
    , termLoc
    , tyLoc
    -- * Lexer
    , AlexPosn (..)
    -- * Views
    , IterApp (..)
    , TermIterApp
    , PrimIterApp
    -- * Formatting
    , format
    , formatDoc
    -- * Processing
    , Gas (..)
    , rename
    -- * Type checking
    , module TypeCheck
    , fileType
    , fileNormalizeType
    , fileTypeCfg
    , printType
    , printNormalizeType
    , normalizeTypesFullIn
    , normalizeTypesFullInProgram
    , InternalTypeError (..)
    , TypeError (..)
    , AsTypeError (..)
    , parseTypecheck
    -- for testing
    , typecheckPipeline
    -- * Errors
    , Error (..)
    , AsError (..)
    , AsNormCheckError (..)
    , UnknownDynamicBuiltinNameError (..)
    , UniqueError (..)
    -- * Base functors
    , TermF (..)
    , TypeF (..)
    -- * Quotation and term construction
    , Quote
    , runQuote
    , QuoteT
    , runQuoteT
    , MonadQuote
    , liftQuote
    -- * Name generation
    , freshUnique
    , freshName
    , freshTyName
    -- * Evaluation
    , EvaluationResult (..)
    , EvaluationResultDef
    -- * Combining programs
    , applyProgram
    -- * Benchmarking
    , termSize
    , typeSize
    , kindSize
    , programSize
    , serialisedSize
    ) where

import           PlutusPrelude

import           Language.PlutusCore.CBOR                 ()
import qualified Language.PlutusCore.Check.Normal         as Normal
import qualified Language.PlutusCore.Check.Uniques        as Uniques
import qualified Language.PlutusCore.Check.Value          as VR
import           Language.PlutusCore.Error
import           Language.PlutusCore.Evaluation.CkMachine
import           Language.PlutusCore.Lexer
import           Language.PlutusCore.Lexer.Type
import           Language.PlutusCore.Name
import           Language.PlutusCore.Normalize
import           Language.PlutusCore.Parser
import           Language.PlutusCore.Quote
import           Language.PlutusCore.Rename
import           Language.PlutusCore.Size
import           Language.PlutusCore.Type
import           Language.PlutusCore.TypeCheck            as TypeCheck
import           Language.PlutusCore.View

import           Control.Monad.Except
import qualified Data.ByteString.Lazy                     as BSL
import qualified Data.Text                                as T

-- | Given a file at @fibonacci.plc@, @fileType "fibonacci.plc"@ will display
-- its type or an error message.
fileType :: FilePath -> IO T.Text
fileType = fileNormalizeType False

fileNormalizeType :: Bool -> FilePath -> IO T.Text
fileNormalizeType norm = fmap (either prettyErr id . printNormalizeType norm) . BSL.readFile
    where
        prettyErr :: Error AlexPosn -> T.Text
        prettyErr = prettyPlcDefText

-- | Given a file, display
-- its type or an error message, optionally dumping annotations and debug
-- information.
fileTypeCfg :: PrettyConfigPlc -> FilePath -> IO T.Text
fileTypeCfg cfg = fmap (either prettyErr id . printType) . BSL.readFile
    where
        prettyErr :: Error AlexPosn -> T.Text
        prettyErr = prettyTextBy cfg

-- | Print the type of a program contained in a 'ByteString'
printType
    :: (AsParseError e AlexPosn,
        AsUniqueError e AlexPosn,
        AsTypeError e AlexPosn,
        MonadError e m)
    => BSL.ByteString
    -> m T.Text
printType = printNormalizeType False

-- | Print the type of a program contained in a 'ByteString'
printNormalizeType
    :: (AsParseError e AlexPosn,
        AsUniqueError e AlexPosn,
        AsTypeError e AlexPosn,
        MonadError e m)
    => Bool
    -> BSL.ByteString
    -> m T.Text
printNormalizeType norm bs = runQuoteT $ prettyPlcDefText <$> do
    scoped <- parseScoped bs
    inferTypeOfProgram (TypeCheckConfig norm mempty $ Just defTypeCheckGas) scoped

-- | Parse and rewrite so that names are globally unique, not just unique within
-- their scope.
parseScoped
    :: (AsParseError e AlexPosn,
        AsUniqueError e AlexPosn,
        MonadError e m,
        MonadQuote m)
    => BSL.ByteString
    -> m (Program TyName Name AlexPosn)
-- don't require there to be no free variables at this point, we might be parsing an open term
parseScoped = through (Uniques.checkProgram (const True)) <=< rename <=< parseProgram

-- | Parse a program and typecheck it.
parseTypecheck
    :: (AsParseError e AlexPosn,
        AsValueRestrictionError e TyName AlexPosn,
        AsUniqueError e AlexPosn,
        AsNormCheckError e TyName Name AlexPosn,
        AsTypeError e AlexPosn,
        MonadError e m,
        MonadQuote m)
    => TypeCheckConfig -> BSL.ByteString -> m (Normalized (Type TyName ()))
parseTypecheck cfg = typecheckPipeline cfg <=< parseScoped

-- | Typecheck a program.
typecheckPipeline
    :: (AsValueRestrictionError e TyName a,
        AsNormCheckError e TyName Name a,
        AsTypeError e a,
        MonadError e m,
        MonadQuote m)
    => TypeCheckConfig
    -> Program TyName Name a
    -> m (Normalized (Type TyName ()))
typecheckPipeline cfg =
    inferTypeOfProgram cfg
    <=< through (unless (_tccDoNormTypes cfg) . Normal.checkProgram)
    <=< through VR.checkProgram

formatDoc
    :: (AsParseError e AlexPosn,
        AsUniqueError e AlexPosn,
        MonadError e m)
    => PrettyConfigPlc -> BSL.ByteString -> m (Doc a)
formatDoc cfg = runQuoteT . fmap (prettyBy cfg) . parseScoped

format
    :: (AsParseError e AlexPosn,
        AsUniqueError e AlexPosn,
        MonadError e m)
    => PrettyConfigPlc -> BSL.ByteString -> m T.Text
format cfg = runQuoteT . fmap (prettyTextBy cfg) . parseScoped
