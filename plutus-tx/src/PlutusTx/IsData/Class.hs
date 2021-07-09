{-# LANGUAGE DataKinds            #-}
{-# LANGUAGE KindSignatures       #-}
{-# LANGUAGE NoImplicitPrelude    #-}
{-# LANGUAGE ScopedTypeVariables  #-}
{-# LANGUAGE TypeApplications     #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -fno-strictness #-}
{-# OPTIONS_GHC -fno-specialise #-}
module PlutusTx.IsData.Class where

import           Data.ByteString      as BS

import           Prelude              (Int, Integer, Maybe (..), error)

import           PlutusCore.Data

import           PlutusTx.Functor
import           PlutusTx.Traversable

import           Data.Kind
import           Data.Void

import           GHC.TypeLits         (ErrorMessage (..), TypeError)

{- HLINT ignore -}

-- | A typeclass for types that can be converted to and from 'Data'.
class IsData (a :: Type) where
    toData :: a -> Data
    -- TODO: this should probably provide some kind of diagnostics
    fromData :: Data -> Maybe a

instance IsData Data where
    {-# INLINABLE toData #-}
    toData d = d
    {-# INLINABLE fromData #-}
    fromData d = Just d

instance (TypeError ('Text "Int is not supported, use Integer instead"))
    => IsData Int where
    toData = error "unsupported"
    fromData = error "unsupported"

instance IsData Integer where
    {-# INLINABLE toData #-}
    toData = I
    {-# INLINABLE fromData #-}
    fromData (I i) = Just i
    fromData _     = Nothing

instance IsData ByteString where
    {-# INLINABLE toData #-}
    toData b = B b
    {-# INLINABLE fromData #-}
    fromData (B b) = Just b
    fromData _     = Nothing

instance IsData a => IsData [a] where
    {-# INLINABLE toData #-}
    toData xs = List (fmap toData xs)
    {-# INLINABLE fromData #-}
    fromData (List ds) = traverse fromData ds
    fromData _         = Nothing

instance IsData Void where
    {-# INLINABLE toData #-}
    toData v = absurd v
    {-# INLINABLE fromData #-}
    fromData _ = Nothing
