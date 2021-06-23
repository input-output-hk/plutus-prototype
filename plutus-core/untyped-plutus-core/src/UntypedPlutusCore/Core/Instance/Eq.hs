{-# OPTIONS_GHC -fno-warn-orphans #-}
{-# LANGUAGE FlexibleInstances    #-}
{-# LANGUAGE TypeOperators        #-}
{-# LANGUAGE UndecidableInstances #-}

module UntypedPlutusCore.Core.Instance.Eq where

import           PlutusPrelude

import           PlutusCore.Eq
import           PlutusCore.Name
import           PlutusCore.Rename.Monad
import           UntypedPlutusCore.Core.Type
import           UntypedPlutusCore.DeBruijn


import           Universe

instance (GEq uni, Closed uni, uni `Everywhere` Eq, Eq fun, HasUnique name TermUnique) =>
            Eq (Term name uni fun ann) where
    term1 == term2 = runEqRename $ eqTermM term1 term2

-- for NEAT/Spec.hs
deriving instance {-# OVERLAPPING #-} (GEq uni, Closed uni, uni `Everywhere` Eq, Eq fun) =>
                  Eq (Term DeBruijn uni fun ())

-- | Check equality of two 'Term's.
eqTermM
    :: (GEq uni, Closed uni, uni `Everywhere` Eq, Eq fun, HasUnique name TermUnique)
    => Term name uni fun ann -> Term name uni fun ann -> EqRename (Renaming TermUnique)
eqTermM (Constant _ con1) (Constant _ con2) =
    eqM con1 con2
eqTermM (Builtin _ bi1) (Builtin _ bi2) =
    eqM bi1 bi2
eqTermM (Var _ name1) (Var _ name2) =
    eqNameM name1 name2
eqTermM (LamAbs _ name1 body1) (LamAbs _ name2 body2) =
    withTwinBindings name1 name2 $ eqTermM body1 body2
eqTermM (Apply _ fun1 arg1) (Apply _ fun2 arg2) = do
    eqTermM fun1 fun2
    eqTermM arg1 arg2
eqTermM (Delay _ term1) (Delay _ term2) =
    eqTermM term1 term2
eqTermM (Force _ term1) (Force _ term2) =
    eqTermM term1 term2
eqTermM (Error _) (Error _) = pure ()
eqTermM Constant{} _ = empty
eqTermM Builtin{}  _ = empty
eqTermM Var{}      _ = empty
eqTermM LamAbs{}   _ = empty
eqTermM Apply{}    _ = empty
eqTermM Delay{}    _ = empty
eqTermM Force{}    _ = empty
eqTermM Error{}    _ = empty
