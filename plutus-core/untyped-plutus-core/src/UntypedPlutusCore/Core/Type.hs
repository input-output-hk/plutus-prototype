{-# LANGUAGE DeriveAnyClass        #-}
{-# LANGUAGE DerivingStrategies    #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings     #-}
{-# LANGUAGE TypeFamilies          #-}
{-# LANGUAGE TypeOperators         #-}
{-# LANGUAGE UndecidableInstances  #-}

module UntypedPlutusCore.Core.Type
    ( TPLC.UniOf
    , TPLC.Version (..)
    , Term (..)
    , Program (..)
    , GName (..)
    , toTerm
    , bindFunM
    , bindFun
    , mapFun
    , termAnn
    , erase
    , eraseProgram
    ) where

import           Data.Functor.Identity
import           Data.Text.Prettyprint.Doc
import           PlutusPrelude

import           Data.Word
import qualified PlutusCore.Constant                    as TPLC
import qualified PlutusCore.Core                        as TPLC
import           PlutusCore.Evaluation.Machine.ExMemory
import           PlutusCore.MkPlc
import qualified PlutusCore.Name                        as TPLC
import           Universe

-- | A global name ('GName') or an underlying name.
data GName name = GName {-# UNPACK #-} !Int | NName !name
    deriving stock (Show, Eq, Ord, Generic)
    deriving anyclass (NFData)

instance Pretty name => Pretty (GName name) where
    pretty (GName w) = "global" <+> pretty w
    pretty (NName n) = pretty n

instance PrettyBy config name => PrettyBy config (GName name) where
    prettyBy _ (GName w)      = "global" <+> pretty w
    prettyBy config (NName n) = prettyBy config n

-- HACK: this instance should not exist, I just did it so 'termSubstFreeNames' would be happy,
-- even though it only really needs a prism.
instance TPLC.HasUnique name TPLC.TermUnique => TPLC.HasUnique (GName name) TPLC.TermUnique where
     unique = lens g s
         where
             g :: GName name -> TPLC.TermUnique
             g (NName n) = view TPLC.unique n
             g (GName _) = coerce (TPLC.Unique 0)
             s :: GName name -> TPLC.TermUnique -> GName name
             s (NName n) u   = NName (set TPLC.unique u n)
             s n@(GName{}) _ = n

{-| The type of Untyped Plutus Core terms. Mirrors the type of Typed Plutus Core terms except

1. all types are removed
2. 'IWrap' and 'Unwrap' are removed
3. type abstractions are replaced with 'Delay'
4. type instantiations are replaced with 'Force'

The latter two are due to the fact that we don't have value restriction in Typed Plutus Core
and hence a computation can be stuck expecting only a single type argument for the computation
to become unstuck. Therefore we can't just silently remove type abstractions and instantions and
need to replace them with something else that also blocks evaluation (in order for the semantics
of an erased program to match with the semantics of the original typed one). 'Delay' and 'Force'
serve exactly this purpose.
-}
-- Making all the fields strict gives us a couple of percent in benchmarks
data Term name uni fun ann
    = Constant !ann !(Some (ValueOf uni))
    | Builtin !ann !fun
    | Var !ann !name
    | LamAbs !ann !name !(Term name uni fun ann)
    | Apply !ann !(Term name uni fun ann) !(Term name uni fun ann)
    | Delay !ann !(Term name uni fun ann)
    | Force !ann !(Term name uni fun ann)
    | Error !ann
    deriving stock (Show, Functor, Generic)
    deriving anyclass (NFData)

-- | A 'Program' is simply a 'Term' coupled with a 'Version' of the core language.
data Program name uni fun ann = Program ann (TPLC.Version ann) (Term name uni fun ann)
    deriving stock (Show, Functor, Generic)
    deriving anyclass (NFData)

type instance TPLC.UniOf (Term name uni fun ann) = uni

instance TermLike (Term name uni fun) TPLC.TyName name uni fun where
    var      = Var
    tyAbs    = \ann _ _ -> Delay ann
    lamAbs   = \ann name _ -> LamAbs ann name
    apply    = Apply
    constant = Constant
    builtin  = Builtin
    tyInst   = \ann term _ -> Force ann term
    unwrap   = const id
    iWrap    = \_ _ _ -> id
    error    = \ann _ -> Error ann

instance TPLC.AsConstant (Term name uni fun ann) where
    asConstant (Constant _ val) = pure val
    asConstant term             = TPLC.throwNotAConstant term

instance TPLC.FromConstant (Term name uni fun ()) where
    fromConstant = Constant ()

type instance TPLC.HasUniques (Term name uni fun ann) = TPLC.HasUnique name TPLC.TermUnique
type instance TPLC.HasUniques (Program name uni fun ann) = TPLC.HasUniques (Term name uni fun ann)

deriving via GenericExMemoryUsage (Term name uni fun ann) instance
    ( ExMemoryUsage name, ExMemoryUsage fun, ExMemoryUsage ann
    , Closed uni, uni `Everywhere` ExMemoryUsage
    ) => ExMemoryUsage (Term name uni fun ann)

toTerm :: Program name uni fun ann -> Term name uni fun ann
toTerm (Program _ _ term) = term

-- | Return the outermost annotation of a 'Term'.
termAnn :: Term name uni fun ann -> ann
termAnn (Constant ann _) = ann
termAnn (Builtin ann _)  = ann
termAnn (Var ann _)      = ann
termAnn (LamAbs ann _ _) = ann
termAnn (Apply ann _ _)  = ann
termAnn (Delay ann _)    = ann
termAnn (Force ann _)    = ann
termAnn (Error ann)      = ann

bindFunM
    :: Monad m
    => (ann -> fun -> m (Term name uni fun' ann))
    -> Term name uni fun ann
    -> m (Term name uni fun' ann)
bindFunM f = go where
    go (Constant ann val)     = pure $ Constant ann val
    go (Builtin ann fun)      = f ann fun
    go (Var ann name)         = pure $ Var ann name
    go (LamAbs ann name body) = LamAbs ann name <$> go body
    go (Apply ann fun arg)    = Apply ann <$> go fun <*> go arg
    go (Delay ann term)       = Delay ann <$> go term
    go (Force ann term)       = Force ann <$> go term
    go (Error ann)            = pure $ Error ann

bindFun
    :: (ann -> fun -> Term name uni fun' ann)
    -> Term name uni fun ann
    -> Term name uni fun' ann
bindFun f = runIdentity . bindFunM (coerce f)

mapFun :: (ann -> fun -> fun') -> Term name uni fun ann -> Term name uni fun' ann
mapFun f = bindFun $ \ann fun -> Builtin ann (f ann fun)

-- | Erase a Typed Plutus Core term to its untyped counterpart.
erase :: TPLC.Term tyname name uni fun ann -> Term name uni fun ann
erase (TPLC.Var ann name)           = Var ann name
erase (TPLC.TyAbs ann _ _ body)     = Delay ann (erase body)
erase (TPLC.LamAbs ann name _ body) = LamAbs ann name (erase body)
erase (TPLC.Apply ann fun arg)      = Apply ann (erase fun) (erase arg)
erase (TPLC.Constant ann con)       = Constant ann con
erase (TPLC.Builtin ann bn)         = Builtin ann bn
erase (TPLC.TyInst ann term _)      = Force ann (erase term)
erase (TPLC.Unwrap _ term)          = erase term
erase (TPLC.IWrap _ _ _ term)       = erase term
erase (TPLC.Error ann _)            = Error ann

-- | Erase a Typed Plutus Core Program to its untyped counterpart.
eraseProgram :: TPLC.Program tyname name uni fun ann -> Program name uni fun ann
eraseProgram (TPLC.Program a v t) = Program a v $ erase t
