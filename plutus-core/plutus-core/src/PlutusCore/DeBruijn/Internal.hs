{-# LANGUAGE DeriveAnyClass        #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE LambdaCase            #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings     #-}
{-# LANGUAGE TemplateHaskell       #-}
-- | Support for using de Bruijn indices for term and type names.
module PlutusCore.DeBruijn.Internal
    ( Index (..)
    , DeBruijn (..)
    , NamedDeBruijn (..)
    , TyDeBruijn (..)
    , NamedTyDeBruijn (..)
    , FreeVariableError (..)
    , AsFreeVariableError (..)
    , Level (..)
    , Levels (..)
    , ixToLevel
    , levelToIndex
    , declareUnique
    , declareIndex
    , withScope
    , getIndex
    , getUnique
    , unNameDeBruijn
    , unNameTyDeBruijn
    , fakeNameDeBruijn
    , nameToDeBruijn
    , tyNameToDeBruijn
    , deBruijnToName
    , deBruijnToTyName
    ) where

import           PlutusCore.Name
import           PlutusCore.Pretty
import           PlutusCore.Quote

import           Control.Exception
import           Control.Lens              hiding (Index, Level, index, ix)
import           Control.Monad.Error.Lens
import           Control.Monad.Except
import           Control.Monad.Reader

import qualified Data.Bimap                as BM
import qualified Data.Text                 as T
import           Data.Text.Prettyprint.Doc

import           Control.DeepSeq           (NFData)
import           ErrorCode
import           GHC.Generics

-- | A relative index used for de Bruijn identifiers.
newtype Index = Index Word
    deriving stock Generic
    deriving newtype (Show, Num, Eq, Ord, Pretty)
    deriving anyclass NFData

-- | A term name as a de Bruijn index.
data NamedDeBruijn = NamedDeBruijn { ndbnString :: T.Text, ndbnIndex :: Index }
    deriving (Show, Generic)
    deriving anyclass NFData

-- | A term name as a de Bruijn index, without the name string.
newtype DeBruijn = DeBruijn { dbnIndex :: Index }
    deriving (Show, Generic, Eq)
    deriving anyclass NFData

-- | A type name as a de Bruijn index.
newtype NamedTyDeBruijn = NamedTyDeBruijn NamedDeBruijn
    deriving stock (Show, Generic)
    deriving newtype (PrettyBy config)
    deriving anyclass NFData
instance Wrapped NamedTyDeBruijn

-- | A type name as a de Bruijn index, without the name string.
newtype TyDeBruijn = TyDeBruijn DeBruijn
    deriving stock (Show, Generic)
    deriving newtype (PrettyBy config)
    deriving anyclass NFData
instance Wrapped TyDeBruijn

instance HasPrettyConfigName config => PrettyBy config NamedDeBruijn where
    prettyBy config (NamedDeBruijn txt (Index ix))
        | showsUnique = pretty txt <> "_i" <> pretty ix
        | otherwise   = pretty txt
        where PrettyConfigName showsUnique = toPrettyConfigName config

instance HasPrettyConfigName config => PrettyBy config DeBruijn where
    prettyBy _config (DeBruijn (Index ix))
        -- we lost the information about the unique, so no point in checking for config
        = "i" <> pretty ix

class HasIndex a where
    index :: Lens' a Index

instance HasIndex NamedDeBruijn where
    index = lens g s where
        g = ndbnIndex
        s n i = n{ndbnIndex=i}

instance HasIndex DeBruijn where
    index = lens g s where
        g = dbnIndex
        s n i = n{dbnIndex=i}

instance HasIndex NamedTyDeBruijn where
    index = _Wrapped' . index

instance HasIndex TyDeBruijn where
    index = _Wrapped' . index

-- Converting from normal names to DeBruijn indices, and vice versa

{- Note [Levels and indices]
The indices ('Index') that we actually store as our de Bruijn indices in the program
are *relative* - that is, they say how many levels above the *current* level to look for
the binder.

However, when doing conversions it is easier to record the  *absolute* level of a variable,
in our state, since that way we don't have to adjust our mapping when we go under a binder (whereas
for relative indices we would need to increment them all by one, as the current level has increased).

However, this means that we *do* need to do an adjustment when we store an index as a level or extract
a level to use it as an index. The adjustment is fairly straightforward:
- An index `i` points to a binder `i` levels above (smaller than) the current level, so the level
  of `i` is `current - i`.
- A level `l` which is `i` levels above (smaller than) the current level has an index of `i`, so it
  is also calculated as `current - l`.

We use a newtype to keep these separate, since getting it wrong will lead to annoying bugs.
-}

-- | An absolute level in the program.
newtype Level = Level Index deriving newtype (Eq, Ord, Num)
data Levels = Levels Level (BM.Bimap Unique Level)

-- | Compute the absolute 'Level' of a relative 'Index' relative to the current 'Level'.
ixToLevel :: Level -> Index -> Level
ixToLevel (Level current) ix = Level (current - ix)

-- | Compute the relative 'Index' of a absolute 'Level' relative to the current 'Level'.
levelToIndex :: Level -> Level -> Index
levelToIndex (Level current) (Level l) = current - l

-- | Declare a name with a unique, recording the mapping to a 'Level'.
declareUnique :: (MonadReader Levels m, HasUnique name unique) => name -> m a -> m a
declareUnique n =
    local $ \(Levels current ls) -> Levels current $ BM.insert (n ^. theUnique) current ls

-- | Declare a name with an index, recording the mapping from the corresponding 'Level' to a fresh unique.
declareIndex :: (MonadReader Levels m, MonadQuote m, HasIndex name) => name -> m a -> m a
declareIndex n act = do
    newU <- freshUnique
    local (\(Levels current ls) -> Levels current $ BM.insert newU (ixToLevel current (n ^. index)) ls) act

-- | Enter a scope, incrementing the current 'Level' by one
withScope :: MonadReader Levels m => m a -> m a
withScope = local $ \(Levels current ls) -> Levels (current+1) ls

-- | We cannot do a correct translation to or from de Bruijn indices if the program is not well-scoped.
-- So we throw an error in such a case.
data FreeVariableError
    = FreeUnique Unique
    | FreeIndex Index
    deriving stock (Show, Eq, Ord, Generic)
    deriving anyclass (Exception, NFData)


instance Pretty FreeVariableError where
    pretty (FreeUnique u) = "Free unique:" <+> pretty u
    pretty (FreeIndex i)  = "Free index:" <+> pretty i
makeClassyPrisms ''FreeVariableError

instance HasErrorCode FreeVariableError where
    errorCode  FreeIndex {}  = ErrorCode 23
    errorCode  FreeUnique {} = ErrorCode 22

-- | Get the 'Index' corresponding to a given 'Unique'.
getIndex :: (MonadReader Levels m, AsFreeVariableError e, MonadError e m) => Unique -> m Index
getIndex u = do
    Levels current ls <- ask
    case BM.lookup u ls of
        Just ix -> pure $ levelToIndex current ix
        Nothing -> throwing _FreeVariableError $ FreeUnique u

-- | Get the 'Unique' corresponding to a given 'Index'.
getUnique :: (MonadReader Levels m, AsFreeVariableError e, MonadError e m) => Index -> m Unique
getUnique ix = do
    Levels current ls <- ask
    case BM.lookupR (ixToLevel current ix) ls of
        Just u  -> pure u
        Nothing -> throwing _FreeVariableError $ FreeIndex ix

unNameDeBruijn
    :: NamedDeBruijn -> DeBruijn
unNameDeBruijn (NamedDeBruijn _ ix) = DeBruijn ix

unNameTyDeBruijn
    :: NamedTyDeBruijn -> TyDeBruijn
unNameTyDeBruijn (NamedTyDeBruijn db) = TyDeBruijn $ unNameDeBruijn db

fakeNameDeBruijn
    :: DeBruijn -> NamedDeBruijn
fakeNameDeBruijn (DeBruijn ix) = NamedDeBruijn "" ix

nameToDeBruijn
    :: (MonadReader Levels m, AsFreeVariableError e, MonadError e m)
    => Name -> m NamedDeBruijn
nameToDeBruijn (Name str u) = NamedDeBruijn str <$> getIndex u

tyNameToDeBruijn
    :: (MonadReader Levels m, AsFreeVariableError e, MonadError e m)
    => TyName -> m NamedTyDeBruijn
tyNameToDeBruijn (TyName n) = NamedTyDeBruijn <$> nameToDeBruijn n

deBruijnToName
    :: (MonadReader Levels m, AsFreeVariableError e, MonadError e m)
    => NamedDeBruijn -> m Name
deBruijnToName (NamedDeBruijn str ix) = Name str <$> getUnique ix

deBruijnToTyName
    :: (MonadReader Levels m, AsFreeVariableError e, MonadError e m)
    => NamedTyDeBruijn -> m TyName
deBruijnToTyName (NamedTyDeBruijn n) = TyName <$> deBruijnToName n
