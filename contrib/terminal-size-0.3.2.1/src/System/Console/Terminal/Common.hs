{-# LANGUAGE CPP #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE DeriveFoldable #-}
{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE DeriveTraversable #-}

#if __GLASGOW_HASKELL__ >= 702
#define LANGUAGE_DeriveGeneric
{-# LANGUAGE DeriveGeneric #-}
#endif

module System.Console.Terminal.Common
  ( Window(..)
  ) where

import Data.Data (Typeable, Data)

#if __GLASGOW_HASKELL__ < 710
import Data.Foldable (Foldable)
import Data.Traversable (Traversable)
#endif

#ifdef LANGUAGE_DeriveGeneric
import GHC.Generics
  ( Generic
#if __GLASGOW_HASKELL__ >= 706
  , Generic1
#endif
  )
#endif

-- | Terminal window width and height
data Window a = Window
  { height :: !a
  , width  :: !a
  } deriving
    ( Show, Eq, Read, Data, Typeable
    , Foldable, Functor, Traversable
#ifdef LANGUAGE_DeriveGeneric
    , Generic
#if __GLASGOW_HASKELL__ >= 706
    , Generic1
#endif
#endif
    )
