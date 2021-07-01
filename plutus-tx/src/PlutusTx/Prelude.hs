-- Need some extra imports from the Prelude for doctests, annoyingly
{-# OPTIONS_GHC -Wno-unused-imports #-}
{-# OPTIONS_GHC -fno-omit-interface-pragmas #-}
{-# OPTIONS_GHC -fmax-simplifier-iterations=0 #-}

module PlutusTx.Prelude (
    -- $prelude
    -- * Classes
    module Eq,
    module Ord,
    module Semigroup,
    module Monoid,
    module Numeric,
    module Functor,
    module Applicative,
    module Lattice,
    module Foldable,
    module Traversable,
    -- * Monad
    (>>=),
    (=<<),
    (>>),
    return,
    -- * Standard functions
    ($),
    (.),
    otherwise,
    until,
    flip,
    -- * String and tracing functions
    trace,
    traceIfTrue,
    traceIfFalse,
    traceError,
    module String,
    -- * Error
    error,
    check,
    -- * Booleans
    module Bool,
    -- * Integer numbers
    Integer,
    divide,
    modulo,
    quotient,
    remainder,
    even,
    -- * Tuples
    fst,
    snd,
    -- * Maybe
    module Maybe,
    -- * Either
    module Either,
    -- * Lists
    module List,
    dropWhile,
    zipWith,
    -- * ByteStrings
    module ByteString,
    -- * Rational numbers
    Rational,
    (%),
    fromInteger,
    round,
    divMod,
    quotRem,
    ) where

import           Data.String          (IsString (..))
import           PlutusTx.Applicative as Applicative
import           PlutusTx.Bool        as Bool
import qualified PlutusTx.Builtins    as Builtins
import           PlutusTx.ByteString  as ByteString
import           PlutusTx.Either      as Either
import           PlutusTx.Eq          as Eq
import           PlutusTx.Foldable    as Foldable
import           PlutusTx.Functor     as Functor
import           PlutusTx.Lattice     as Lattice
import           PlutusTx.List        as List hiding (foldr)
import           PlutusTx.Maybe       as Maybe
import           PlutusTx.Monoid      as Monoid
import           PlutusTx.Numeric     as Numeric
import           PlutusTx.Ord         as Ord
import           PlutusTx.Ratio       as Ratio
import           PlutusTx.Semigroup   as Semigroup
import           PlutusTx.String      as String
import           PlutusTx.Traversable as Traversable
import           Prelude              as Prelude hiding (Applicative (..), Eq (..), Foldable (..), Functor (..),
                                                  Monoid (..), Num (..), Ord (..), Rational, Semigroup (..),
                                                  Traversable (..), all, and, any, concat, concatMap, const, divMod,
                                                  either, elem, error, filter, fst, head, id, length, map, mapM_, max,
                                                  maybe, min, not, notElem, null, or, quotRem, reverse, round, sequence,
                                                  snd, take, zip, (!!), ($), (&&), (++), (<$>), (||))
import qualified Prelude              as Haskell

-- this module does lots of weird stuff deliberately
{-# ANN module ("HLint: ignore"::Haskell.String) #-}

-- $prelude
-- The PlutusTx Prelude is a replacement for the Haskell Prelude that works
-- better with Plutus Tx. You should use it if you're writing code that
-- will be compiled with the Plutus Tx compiler.
-- @
--     {-# LANGUAGE NoImplicitPrelude #-}
--     import PlutusTx.Prelude
-- @

-- $setup
-- >>> :set -XNoImplicitPrelude
-- >>> import PlutusTx.Prelude

{-# INLINABLE error #-}
-- | Terminate the evaluation of the script with an error message.
error :: () -> a
error = Builtins.error

{-# INLINABLE check #-}
-- | Checks a 'Bool' and aborts if it is false.
check :: Bool -> ()
check b = if b then () else error ()

{-# INLINABLE trace #-}
-- | Emit the given string as a trace message before evaluating the argument.
trace :: Builtins.String -> a -> a
-- The builtin trace is just a side-effecting function that returns unit, so
-- we have to be careful to make sure it actually gets evaluated, and not
-- thrown away by GHC or the PIR compiler.
trace str a = case Builtins.trace str of () -> a

{-# INLINABLE traceError #-}
-- | Log a message and then terminate the evaluation with an error.
traceError :: Builtins.String -> a
traceError str = error (trace str ())

{-# INLINABLE traceIfFalse #-}
-- | Emit the given 'String' only if the argument evaluates to 'False'.
traceIfFalse :: Builtins.String -> Bool -> Bool
traceIfFalse str a = if a then True else trace str False

{-# INLINABLE traceIfTrue #-}
-- | Emit the given 'String' only if the argument evaluates to 'True'.
traceIfTrue :: Builtins.String -> Bool -> Bool
traceIfTrue str a = if a then trace str True else False

{-# INLINABLE divide #-}
-- | Integer division, rounding downwards
--
--   >>> divide (-41) 5
--   -9
--
divide :: Integer -> Integer -> Integer
divide = Builtins.divideInteger

{-# INLINABLE modulo #-}
-- | Integer remainder, always positive for a positive divisor
--
--   >>> modulo (-41) 5
--   4
--
modulo :: Integer -> Integer -> Integer
modulo = Builtins.modInteger

{-# INLINABLE quotient #-}
-- | Integer division, rouding towards zero
--
--   >>> quotient (-41) 5
--   -8
--

quotient :: Integer -> Integer -> Integer
quotient = Builtins.quotientInteger

{-# INLINABLE remainder #-}
-- | Integer remainder, same sign as dividend
--
--   >>> remainder (-41) 5
--   -1
--
remainder :: Integer -> Integer -> Integer
remainder = Builtins.remainderInteger

{-# INLINABLE fst #-}
-- | Plutus Tx version of 'Data.Tuple.fst'
fst :: (a, b) -> a
fst (a, _) = a

{-# INLINABLE snd #-}
-- | Plutus Tx version of 'Data.Tuple.snd'
snd :: (a, b) -> b
snd (_, b) = b

infixr 0 $
-- Normal $ is levity-polymorphic, which we can't handle.
{-# INLINABLE ($) #-}
-- | Plutus Tx version of 'Data.Function.($)'.
($) :: (a -> b) -> a -> b
f $ a = f a
