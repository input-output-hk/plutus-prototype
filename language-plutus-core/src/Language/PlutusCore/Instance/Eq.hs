{-# OPTIONS_GHC -fno-warn-orphans #-}

{-# LANGUAGE TypeFamilies         #-}
{-# LANGUAGE UndecidableInstances #-}

module Language.PlutusCore.Instance.Eq
    ( Global (..)
    ) where

import           PlutusPrelude

import           Language.PlutusCore.Instance.Eq.Internal
import           Language.PlutusCore.Instance.Eq.Monad
import           Language.PlutusCore.Name
import           Language.PlutusCore.Type

newtype Global name = Global
    { unGlobal :: name
    }

instance (HasUnique name unique, Eq unique) => Eq (Global name) where
    Global name1 == Global name2 = name1 ^. unique == name2 ^. unique

instance HasUniques (Type tyname ann) => Eq (Type tyname ann) where
    ty1 == ty2 = runEqRename $ eqTypeM ty1 ty2

instance HasUniques (Term tyname name ann) => Eq (Term tyname name ann) where
    term1 == term2 = runScopedEqRename $ eqTermM term1 term2

instance HasUniques (Program tyname name ann) => Eq (Program tyname name ann) where
    prog1 == prog2 = runScopedEqRename $ eqProgramM prog1 prog2
