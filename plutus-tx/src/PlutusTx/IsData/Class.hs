{-# LANGUAGE DataKinds            #-}
{-# LANGUAGE KindSignatures       #-}
{-# LANGUAGE NoImplicitPrelude    #-}
{-# LANGUAGE ScopedTypeVariables  #-}
{-# LANGUAGE TypeApplications     #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -fno-strictness #-}
{-# OPTIONS_GHC -fno-specialise #-}
{-# OPTIONS_GHC -fno-omit-interface-pragmas #-}
module PlutusTx.IsData.Class where

import           Data.ByteString            as BS

import           Prelude                    (Int, Integer, Maybe (..), error)

import qualified PlutusCore.Data            as PLC
import           PlutusTx.Builtins
import           PlutusTx.Builtins.Internal (BuiltinData (..))

import           PlutusTx.Functor
import           PlutusTx.Traversable

import           Data.Kind
import           Data.Void

import           GHC.TypeLits               (ErrorMessage (..), TypeError)


{- HLINT ignore -}

-- | A typeclass for types that can be converted to and from 'Data'.
class IsData (a :: Type) where
    toBuiltinData :: a -> BuiltinData
    -- TODO: this should probably provide some kind of diagnostics
    fromBuiltinData :: BuiltinData -> Maybe a

instance IsData BuiltinData where
    {-# INLINABLE toBuiltinData #-}
    toBuiltinData = id
    {-# INLINABLE fromBuiltinData #-}
    fromBuiltinData d = Just d

instance (TypeError ('Text "Int is not supported, use Integer instead"))
    => IsData Int where
    toBuiltinData = Prelude.error "unsupported"
    fromBuiltinData = Prelude.error "unsupported"

instance IsData Integer where
    {-# INLINABLE toBuiltinData #-}
    toBuiltinData i = mkI i
    {-# INLINABLE fromBuiltinData #-}
    fromBuiltinData d = matchData d (\_ _ -> Nothing) (const Nothing) (const Nothing) (\i -> Just i) (const Nothing)

instance IsData ByteString where
    {-# INLINABLE toBuiltinData #-}
    toBuiltinData b = mkB b
    {-# INLINABLE fromBuiltinData #-}
    fromBuiltinData d = matchData d (\_ _ -> Nothing) (const Nothing) (const Nothing) (const Nothing) (\b -> Just b)

instance IsData a => IsData [a] where
    {-# INLINABLE toBuiltinData #-}
    toBuiltinData xs = mkList (fmap toBuiltinData xs)
    {-# INLINABLE fromBuiltinData #-}
    fromBuiltinData d = matchData d (\_ _ -> Nothing) (const Nothing) (\l -> traverse fromBuiltinData l) (const Nothing) (const Nothing)

instance IsData Void where
    {-# INLINABLE toBuiltinData #-}
    toBuiltinData v = absurd v
    {-# INLINABLE fromBuiltinData #-}
    fromBuiltinData _ = Nothing

toData :: (IsData a) => a -> PLC.Data
toData a = builtinDataToData (toBuiltinData a)

fromData :: (IsData a) => PLC.Data -> Maybe a
fromData d = fromBuiltinData (BuiltinData d)
