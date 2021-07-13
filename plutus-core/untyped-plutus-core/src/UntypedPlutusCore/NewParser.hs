{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE RankNTypes          #-}
{-# LANGUAGE TypeApplications    #-}
{-# LANGUAGE TypeOperators       #-}

{-# OPTIONS_GHC -fno-warn-orphans #-}

-- | Parser for untyped Plutus Core using megaparsec, as in Plutus IR.
-- Will replace UntypedPlutusCore.Parser.hs.
-- Parser.y and Lexer.x, which currently generate Parser.hs, will be removed.

module UntypedPlutusCore.NewParser
    ( topSourcePos
    , parse
    , parseQuoted
    , term
    , program
    , parseTerm
    , parseProgram
    , parseScoped
    , Parser
    , SourcePos
    ) where

import           Prelude                         hiding (fail)

import           Control.Monad.Except            ((<=<))
import           Control.Monad.State             (StateT)

import qualified NewUntypedPlutusCore            as UPLC
import qualified PlutusCore                      as PLC
import qualified PlutusCore.Parsable             as PLC
import           PlutusPrelude                   (Pretty, through)
import           Text.Megaparsec                 hiding (ParseError, State, parse)
import           UntypedPlutusCore.Check.Uniques (checkProgram)
import           UntypedPlutusCore.Rename        (Rename (rename))

import           Data.ByteString.Lazy            (ByteString)
import           Data.ByteString.Lazy.Internal   (unpackChars)
import qualified Data.Text                       as T
import           PlutusCore.ParserCommon

-- Parsers for UPLC terms

conTerm
    :: (PLC.Closed uni, uni `PLC.Everywhere` PLC.Parsable, PLC.Parsable (PLC.SomeTypeIn (PLC.Kinded uni)))
    => Parser SourcePos (UPLC.Term PLC.Name uni fun SourcePos)
conTerm = inParens $ UPLC.Constant <$> wordPos "con" <*> constant

builtinTerm :: (Bounded fun, Enum fun, Pretty fun)
    => Parser SourcePos (UPLC.Term PLC.Name uni fun SourcePos)
builtinTerm = inParens $ UPLC.Builtin <$> wordPos "builtin" <*> builtinFunction

varTerm :: Parser SourcePos (UPLC.Term PLC.Name uni fun SourcePos)
varTerm = UPLC.Var <$> getSourcePos <*> name

lamTerm :: ParsecT (PLC.ParseError SourcePos)
                   T.Text
                   (StateT ParserState PLC.Quote)
                   (UPLC.Term PLC.Name uni fun SourcePos)
                   -> Parser SourcePos (UPLC.Term PLC.Name uni fun SourcePos)
lamTerm tm = inParens $ UPLC.LamAbs <$> wordPos "lam" <*> name <*> tm

appTerm :: ParsecT (PLC.ParseError SourcePos)
                   T.Text
                   (StateT ParserState PLC.Quote)
                   (UPLC.Term PLC.Name uni fun SourcePos)
                   -> Parser SourcePos (UPLC.Term PLC.Name uni fun SourcePos)
appTerm tm = inBrackets $ UPLC.Apply <$> getSourcePos <*> tm <*> tm

delayTerm :: ParsecT (PLC.ParseError SourcePos)
                   T.Text
                   (StateT ParserState PLC.Quote)
                   (UPLC.Term PLC.Name uni fun SourcePos)
                   -> Parser SourcePos (UPLC.Term PLC.Name uni fun SourcePos)
delayTerm tm = inParens $ UPLC.Delay <$> wordPos "abs" <*> tm

forceTerm :: ParsecT (PLC.ParseError SourcePos)
                   T.Text
                   (StateT ParserState PLC.Quote)
                   (UPLC.Term PLC.Name uni fun SourcePos)
                   -> Parser SourcePos (UPLC.Term PLC.Name uni fun SourcePos)
forceTerm tm = inBraces $ UPLC.Force <$> getSourcePos <*> tm

errorTerm
    :: Parser SourcePos (UPLC.Term PLC.Name uni fun SourcePos)
errorTerm = inParens $ UPLC.Error <$> wordPos "error"

-- | Parser for all UPLC terms.
term
    :: ( PLC.Parsable (PLC.Some uni), PLC.Closed uni, uni `PLC.Everywhere` PLC.Parsable
       , Bounded fun, Enum fun, Pretty fun, PLC.Parsable (PLC.SomeTypeIn (PLC.Kinded uni)))
        => Parser SourcePos (UPLC.Term PLC.Name uni fun SourcePos)
term = conTerm
    <|> builtinTerm
    <|> varTerm
    <|> lamTerm self
    <|> appTerm self
    <|> delayTerm self
    <|> forceTerm self
    <|> errorTerm
    where self = term

-- | Parser for UPLC programs.
program
    :: ( PLC.Parsable (PLC.Some uni), PLC.Closed uni, uni `PLC.Everywhere` PLC.Parsable
       , Bounded fun, Enum fun, Pretty fun, PLC.Parsable (PLC.SomeTypeIn (PLC.Kinded uni)))
    => Parser SourcePos (UPLC.Program PLC.Name uni fun SourcePos)
program = whitespace >> do
    prog <- inParens $ UPLC.Program <$> wordPos "program" <*> version <*> term
    notFollowedBy anySingle
    return prog

-- | Generic parser function.
parseGen :: Parser SourcePos a -> ByteString -> Either (ParseErrorBundle T.Text (PLC.ParseError SourcePos)) a
parseGen stuff bs = parse stuff "test" $ (T.pack . unpackChars) bs

-- | Parse a PLC term. The resulting program will have fresh names. The underlying monad must be capable
-- of handling any parse errors.
parseTerm ::
    (PLC.Parsable (PLC.Some uni), PLC.Closed uni, uni `PLC.Everywhere` PLC.Parsable
    , Bounded fun, Enum fun, Pretty fun, PLC.Parsable (PLC.SomeTypeIn (PLC.Kinded uni))) =>
    ByteString ->
    Either (ParseErrorBundle T.Text (PLC.ParseError SourcePos)) (UPLC.Term PLC.Name uni fun SourcePos)
parseTerm = parseGen term

-- | Parse a PLC program. The resulting program will have fresh names. The underlying monad must be capable
-- of handling any parse errors.
parseProgram :: (PLC.Parsable (PLC.Some uni), PLC.Closed uni, uni `PLC.Everywhere` PLC.Parsable
       , Bounded fun, Enum fun, Pretty fun, PLC.Parsable (PLC.SomeTypeIn (PLC.Kinded uni))) => ByteString -> Either (ParseErrorBundle T.Text (PLC.ParseError SourcePos)) (UPLC.Program PLC.Name uni fun SourcePos)
parseProgram = parseGen program

-- | Parse and rewrite so that names are globally unique, not just unique within
-- their scope.
parseScoped
    :: (PLC.MonadQuote (Either (ParseErrorBundle T.Text (PLC.ParseError SourcePos)))
        , PLC.AsUniqueError (ParseErrorBundle T.Text (PLC.ParseError SourcePos)) SourcePos
        , PLC.Parsable (PLC.Some PLC.DefaultUni))
    => ByteString
    -> Either (ParseErrorBundle T.Text (PLC.ParseError SourcePos)) (UPLC.Program PLC.Name PLC.DefaultUni PLC.DefaultFun SourcePos)
-- don't require there to be no free variables at this point, we might be parsing an open term
parseScoped = through (checkProgram (const True)) <=< rename <=< parseProgram
