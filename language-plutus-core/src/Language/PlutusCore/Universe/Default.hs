-- | The universe used by default and its instances.

-- Appears in generated instances.
{-# OPTIONS_GHC -fno-warn-unused-matches #-}

{-# LANGUAGE GADTs                 #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TemplateHaskell       #-}
{-# LANGUAGE TypeFamilies          #-}
{-# LANGUAGE TypeOperators         #-}

module Language.PlutusCore.Universe.Default
    ( ByteString16 (..)
    , DefaultUni (..)
    ) where

import           Language.PlutusCore.Pretty.Utils
import           Language.PlutusCore.Universe.Core

import           Codec.Serialise
import qualified Data.ByteString.Lazy              as BSL
import           Data.GADT.Compare.TH
import           Data.Text.Prettyprint.Doc
import           Language.Haskell.TH.Syntax

-- TODO: use strict bytestrings.
-- | A 'ByteString' pretty-printed in hex form.
newtype ByteString16 = ByteString16
    { unByteString16 :: BSL.ByteString
    } deriving newtype (Show, Eq, Ord, Semigroup, Monoid, Serialise)

instance Pretty ByteString16 where
    pretty = prettyBytes . unByteString16

-- The universe used by default.
data DefaultUni a where
    DefaultUniInteger    :: DefaultUni Integer
    DefaultUniByteString :: DefaultUni ByteString16
    DefaultUniChar       :: DefaultUni Char
    DefaultUniString     :: DefaultUni String

deriveGEq ''DefaultUni
deriving instance Lift (DefaultUni a)
instance GLift DefaultUni

instance GShow DefaultUni where gshowsPrec = showsPrec
instance Show (DefaultUni a) where
    show DefaultUniInteger    = "integer"
    show DefaultUniByteString = "bytestring"
    show DefaultUniChar       = "char"
    show DefaultUniString     = "string"

instance DefaultUni `Includes` Integer         where knownUni = DefaultUniInteger
instance DefaultUni `Includes` ByteString16    where knownUni = DefaultUniByteString
instance DefaultUni `Includes` Char            where knownUni = DefaultUniChar
instance a ~ Char => DefaultUni `Includes` [a] where knownUni = DefaultUniString

instance Closed DefaultUni where
    type DefaultUni `Everywhere` constr =
        ( constr Integer
        , constr ByteString16
        , constr Char
        , constr String
        )

    tagOf DefaultUniInteger    = 0
    tagOf DefaultUniByteString = 1
    tagOf DefaultUniString     = 2
    tagOf DefaultUniChar       = 3

    uniAt 0 = Just . Some $ In DefaultUniInteger
    uniAt 1 = Just . Some $ In DefaultUniByteString
    uniAt 2 = Just . Some $ In DefaultUniString
    uniAt 3 = Just . Some $ In DefaultUniChar
    uniAt _ = Nothing

    bring _ DefaultUniInteger    = id
    bring _ DefaultUniByteString = id
    bring _ DefaultUniString     = id
    bring _ DefaultUniChar       = id
