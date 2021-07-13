{-# LANGUAGE FlexibleContexts  #-}
{-# LANGUAGE GADTs             #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes        #-}
{-# LANGUAGE TypeOperators     #-}

module PlutusIR.Parser
    ( topSourcePos
    , parse
    , parseQuoted
    , term
    , typ
    , program
    , plcTerm
    , plcProgram
    , Parser
    , SourcePos
    ) where

import           PlutusPrelude
import           Prelude                            hiding (fail)


import qualified PlutusCore                         as PLC
import qualified PlutusCore.Parsable                as PLC
import           PlutusCore.ParserCommon
import           PlutusIR                           as PIR
import qualified PlutusIR.MkPir                     as PIR
import           Text.Megaparsec                    hiding (ParseError, State, many, parse, some)

import qualified Control.Monad.Combinators.NonEmpty as NE


recursivity :: Parser SourcePos Recursivity
recursivity = inParens $ (wordPos "rec" >> return Rec) <|> (wordPos "nonrec" >> return NonRec)

strictness :: Parser SourcePos Strictness
strictness = inParens $ (wordPos "strict" >> return Strict) <|> (wordPos "nonstrict" >> return NonStrict)

funType
    :: PLC.Parsable (PLC.SomeTypeIn (PLC.Kinded uni))
    => Parser SourcePos (Type TyName uni SourcePos)
funType = TyFun <$> wordPos "fun" <*> typ <*> typ

allType
    :: PLC.Parsable (PLC.SomeTypeIn (PLC.Kinded uni))
    => Parser SourcePos (Type TyName uni SourcePos)
allType = TyForall <$> wordPos "all" <*> tyName <*> kind <*> typ

lamType
    :: PLC.Parsable (PLC.SomeTypeIn (PLC.Kinded uni))
    => Parser SourcePos (Type TyName uni SourcePos)
lamType = TyLam <$> wordPos "lam" <*> tyName <*> kind <*> typ

ifixType
    :: PLC.Parsable (PLC.SomeTypeIn (PLC.Kinded uni))
    => Parser SourcePos (Type TyName uni SourcePos)
ifixType = TyIFix <$> wordPos "ifix" <*> typ <*> typ

conType
    :: PLC.Parsable (PLC.SomeTypeIn (PLC.Kinded uni))
    => Parser SourcePos (Type TyName uni SourcePos)
conType = wordPos "con" >> builtinType

builtinType
    :: PLC.Parsable (PLC.SomeTypeIn (PLC.Kinded uni))
    => Parser SourcePos (Type TyName uni SourcePos)
builtinType = do
    p <- getSourcePos
    PLC.SomeTypeIn (PLC.Kinded uni) <- builtinTypeTag
    pure . TyBuiltin p $ PLC.SomeTypeIn uni

appType
    :: PLC.Parsable (PLC.SomeTypeIn (PLC.Kinded uni))
    => Parser SourcePos (Type TyName uni SourcePos)
appType = do
    pos  <- getSourcePos
    fn   <- typ
    args <- some typ
    pure $ foldl' (TyApp pos) fn args

kind :: Parser SourcePos (Kind SourcePos)
kind = inParens (typeKind <|> funKind)
    where
        typeKind = Type <$> wordPos "type"
        funKind  = KindArrow <$> wordPos "fun" <*> kind <*> kind

typ
    :: PLC.Parsable (PLC.SomeTypeIn (PLC.Kinded uni))
    => Parser SourcePos (Type TyName uni SourcePos)
typ = (tyName >>= (\n -> getSourcePos >>= \p -> return $ TyVar p n))
    <|> (inParens $ funType <|> allType <|> lamType <|> ifixType <|> conType)
    <|> inBrackets appType

varDecl
    :: PLC.Parsable (PLC.SomeTypeIn (PLC.Kinded uni))
    => Parser SourcePos (VarDecl TyName Name uni fun SourcePos)
varDecl = inParens $ VarDecl <$> wordPos "vardecl" <*> name <*> typ

tyVarDecl :: Parser SourcePos (TyVarDecl TyName SourcePos)
tyVarDecl = inParens $ TyVarDecl <$> wordPos "tyvardecl" <*> tyName <*> kind

datatype
    :: PLC.Parsable (PLC.SomeTypeIn (PLC.Kinded uni))
    => Parser SourcePos (Datatype TyName Name uni fun SourcePos)
datatype = inParens $ Datatype <$> wordPos "datatype"
    <*> tyVarDecl
    <*> many tyVarDecl
    <*> name
    <*> many varDecl

binding
    :: ( PLC.Parsable (PLC.SomeTypeIn (PLC.Kinded uni))
       , PLC.Closed uni, uni `PLC.Everywhere` PLC.Parsable
       , Bounded fun, Enum fun, Pretty fun
       )
    => Parser SourcePos (Binding TyName Name uni fun SourcePos)
binding = inParens $
    (try $ wordPos "termbind" >> TermBind <$> getSourcePos <*> strictness <*> varDecl <*> term)
    <|> (wordPos "typebind" >> TypeBind <$> getSourcePos <*> tyVarDecl <*> typ)
    <|> (wordPos "datatypebind" >> DatatypeBind <$> getSourcePos <*> datatype)

-- A small type wrapper for parsers that are parametric in the type of term they parse
type Parametric uni fun
    = forall term. PIR.TermLike term TyName Name uni fun
    => Parser SourcePos (term SourcePos)
    -> Parser SourcePos (term SourcePos)

absTerm :: Parametric uni fun
absTerm tm = PIR.tyAbs <$> wordPos "abs" <*> tyName <*> kind <*> tm

lamTerm :: PLC.Parsable (PLC.SomeTypeIn (PLC.Kinded uni)) => Parametric uni fun
lamTerm tm = PIR.lamAbs <$> wordPos "lam" <*> name <*> typ <*> tm

conTerm
    :: ( PLC.Parsable (PLC.SomeTypeIn (PLC.Kinded uni))
       , PLC.Closed uni, uni `PLC.Everywhere` PLC.Parsable
       )
    => Parametric uni fun
conTerm _tm = PIR.constant <$> wordPos "con" <*> constant

iwrapTerm :: PLC.Parsable (PLC.SomeTypeIn (PLC.Kinded uni)) => Parametric uni fun
iwrapTerm tm = PIR.iWrap <$> wordPos "iwrap" <*> typ <*> typ <*> tm

builtinTerm :: (Bounded fun, Enum fun, Pretty fun) => Parametric uni fun
builtinTerm _term = PIR.builtin <$> wordPos "builtin" <*> builtinFunction

unwrapTerm :: Parametric uni fun
unwrapTerm tm = PIR.unwrap <$> wordPos "unwrap" <*> tm

errorTerm :: PLC.Parsable (PLC.SomeTypeIn (PLC.Kinded uni)) => Parametric uni fun
errorTerm _tm = PIR.error <$> wordPos "error" <*> typ

letTerm
    :: ( PLC.Parsable (PLC.SomeTypeIn (PLC.Kinded uni))
       , PLC.Closed uni, uni `PLC.Everywhere` PLC.Parsable
       , Bounded fun, Enum fun, Pretty fun
       )
    => Parser SourcePos (Term TyName Name uni fun SourcePos)
letTerm = Let <$> wordPos "let" <*> recursivity <*> NE.some (try binding) <*> term

appTerm :: Parametric uni fun
appTerm tm = PIR.mkIterApp <$> getSourcePos <*> tm <*> some tm

tyInstTerm :: PLC.Parsable (PLC.SomeTypeIn (PLC.Kinded uni)) => Parametric uni fun
tyInstTerm tm = PIR.mkIterInst <$> getSourcePos <*> tm <*> some typ

term'
    :: ( PLC.Parsable (PLC.SomeTypeIn (PLC.Kinded uni))
       , PLC.Closed uni, uni `PLC.Everywhere` PLC.Parsable
       , Bounded fun, Enum fun, Pretty fun
       )
    => Parametric uni fun
term' other = (name >>= (\n -> getSourcePos >>= \p -> return $ PIR.var p n))
    <|> (inParens $ absTerm self <|> lamTerm self <|> conTerm self <|> iwrapTerm self <|> builtinTerm self <|> unwrapTerm self <|> errorTerm self <|> other)
    <|> inBraces (tyInstTerm self)
    <|> inBrackets (appTerm self)
    where self = term' other

term
    :: ( PLC.Parsable (PLC.SomeTypeIn (PLC.Kinded uni))
       , PLC.Closed uni, uni `PLC.Everywhere` PLC.Parsable
       , Bounded fun, Enum fun, Pretty fun
       )
    => Parser SourcePos (Term TyName Name uni fun SourcePos)
term = term' letTerm

plcTerm
    :: ( PLC.Parsable (PLC.SomeTypeIn (PLC.Kinded uni))
       , PLC.Closed uni, uni `PLC.Everywhere` PLC.Parsable
       , Bounded fun, Enum fun, Pretty fun
       )
    => Parser SourcePos (PLC.Term TyName Name uni fun SourcePos)
plcTerm = term' empty

-- Note that PIR programs do not actually carry a version number
-- we (optionally) parse it all the same so we can parse all PLC code
program
    :: ( PLC.Parsable (PLC.SomeTypeIn (PLC.Kinded uni))
       , PLC.Closed uni, uni `PLC.Everywhere` PLC.Parsable
       , Bounded fun, Enum fun, Pretty fun
       )
    => Parser SourcePos (Program TyName Name uni fun SourcePos)
program = whitespace >> do
    prog <- inParens $ do
        p <- wordPos "program"
        option () $ void version
        Program p <$> term
    notFollowedBy anySingle
    return prog

plcProgram
    :: ( PLC.Parsable (PLC.SomeTypeIn (PLC.Kinded uni))
       , PLC.Closed uni, uni `PLC.Everywhere` PLC.Parsable
       , Bounded fun, Enum fun, Pretty fun
       )
    => Parser SourcePos (PLC.Program TyName Name uni fun SourcePos)
plcProgram = whitespace >> do
    prog <- inParens $ PLC.Program <$> wordPos "program" <*> version <*> plcTerm
    notFollowedBy anySingle
    return prog
