{-# LANGUAGE LambdaCase   #-}
{-# LANGUAGE TypeFamilies #-}
module UntypedPlutusCore.Transform.Globalify (globalifyProgram, globalifyTerm, maxGlobal) where

import           Control.Lens.Fold
import           Control.Lens.Plated
import           Control.Monad.Reader
import           Data.Semigroup
import qualified PlutusCore.Name               as TPLC
import           PlutusCore.Quote
import           UntypedPlutusCore.Core.Plated
import           UntypedPlutusCore.Core.Type
import           UntypedPlutusCore.Rename
import           UntypedPlutusCore.Subst

{- Note [Globalifying]
It's a bit awkward to deal with global variables. Initially, I tried to match on things of the shape

    [ (lam n body) rhs ]

i.e. things that look like a compiled let-binding. But this is not sufficient, because we generate code like
this from datatype bindings:

    [ [ [ (lam n1 (lam n2 (lam n3 body) ) ) rhs3 ] rhs2 ] rhs1]

Furthermore, scripts as we see them before evaluation will be applied to some number of arguments!

I spent a while trying to figure out how to identify the stuff that we wanted as globals, and then I thought
of a different way of thinking of it.

> Look for lambdas which are only ever called once

If you spot a lambda like this, you can safely write its variable binding into a global location, since it
will only ever be assigned to once, and we don't have to worry about escape analysis etc. Conveniently, this
is exactly what all of our compiled let-bindings look like.

How do we spot such a thing? Simple: the only things which can get evaluated multiple times are things that
actually get bound to a variable, i.e. things which appear on the RHS of an application. So we can just recurse
down the tree, ignoring stuff on the RHS of an application.

In terms of implementation, we can also handle this neatly with a new kind of name ('GName') which is either
a normal name of a global name. Mostly "global" lambdas are just like normal lambdas, otherwise.
-}

globalifyProgram :: Program TPLC.Name uni fun ann -> Program (GName TPLC.Name) uni fun ann
globalifyProgram (Program x v t) = Program x v $ globalifyTerm t

globalifyTerm :: Term TPLC.Name uni fun ann -> Term (GName TPLC.Name) uni fun ann
globalifyTerm t = flip runReader (0, mempty) $ gatherGlobals $ runQuote $ rename t

maxGlobal :: Term (GName name) uni fun a -> Int
maxGlobal t = getMax $ foldMapOf (cosmosOf termSubterms) (\case {LamAbs _ (GName w) _  -> Max w; _ -> Max 0}) t

gatherGlobals :: forall m uni fun ann . (m ~ Reader (Int, TPLC.UniqueMap TPLC.TermUnique Int)) => Term TPLC.Name uni fun ann -> m (Term (GName TPLC.Name) uni fun ann)
-- See Note [Globalifying]
-- This is the key part!
gatherGlobals (Apply x l r) = Apply x <$> gatherGlobals l <*> rewriteGlobals r
gatherGlobals (LamAbs x n b) = do
    currentCounter <- asks fst
    b' <- local (\(c, m) -> (c+1, TPLC.insertByName n c m)) $ gatherGlobals b
    pure $ LamAbs x (GName currentCounter) b'
gatherGlobals (Delay x b) = Delay x <$> gatherGlobals b
gatherGlobals (Force x b) = Force x <$> gatherGlobals b
-- This is just the non-recursive bits
gatherGlobals t = rewriteGlobals t

rewriteGlobals :: Term TPLC.Name uni fun ann -> Reader (Int, TPLC.UniqueMap TPLC.TermUnique Int) (Term (GName TPLC.Name) uni fun ann)
rewriteGlobals t = do
    m <- asks snd
    let go n  =
          case TPLC.lookupName n m of
              Just w  -> GName w
              Nothing -> NName n
    pure $ termMapNames go t
