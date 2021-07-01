{-# LANGUAGE DataKinds #-}
{-# LANGUAGE PolyKinds #-}
-- This ensures that we don't put *anything* about these functions into the interface
-- file, otherwise GHC can be clever about the ones that are always error, even though
-- they're NOINLINE!
{-# OPTIONS_GHC -O0 #-}
-- | Primitive names and functions for working with Plutus Core builtins.
module PlutusTx.Builtins (
                                -- * Bytestrings
                                  module PlutusTx.ByteString
                                -- * Strings
                                , module PlutusTx.String
                                -- * Integer builtins
                                , addInteger
                                , subtractInteger
                                , multiplyInteger
                                , divideInteger
                                , modInteger
                                , quotientInteger
                                , remainderInteger
                                , greaterThanInteger
                                , greaterThanEqInteger
                                , lessThanInteger
                                , lessThanEqInteger
                                , equalsInteger
                                -- * Error
                                , error
                                -- * Data
                                , Data (..)
                                -- * Tracing
                                , trace
                                ) where

import           Prelude             hiding (String, error)

import           PlutusTx.ByteString
import           PlutusTx.Data
import           PlutusTx.String
import           PlutusTx.Utils      (mustBeReplaced)

{-# NOINLINE addInteger #-}
-- | Add two 'Integer's.
addInteger :: Integer -> Integer -> Integer
addInteger = (+)

{-# NOINLINE subtractInteger #-}
-- | Subtract two 'Integer's.
subtractInteger :: Integer -> Integer -> Integer
subtractInteger = (-)

{-# NOINLINE multiplyInteger #-}
-- | Multiply two 'Integer's.
multiplyInteger :: Integer -> Integer -> Integer
multiplyInteger = (*)

{-# NOINLINE divideInteger #-}
-- | Divide two integers.
divideInteger :: Integer -> Integer -> Integer
divideInteger = div

{-# NOINLINE modInteger #-}
-- | Integer modulo operation.
modInteger :: Integer -> Integer -> Integer
modInteger = mod

{-# NOINLINE quotientInteger #-}
-- | Quotient of two integers.
quotientInteger :: Integer -> Integer -> Integer
quotientInteger = quot

{-# NOINLINE remainderInteger #-}
-- | Take the remainder of dividing two 'Integer's.
remainderInteger :: Integer -> Integer -> Integer
remainderInteger = rem

{-# NOINLINE greaterThanInteger #-}
-- | Check whether one 'Integer' is greater than another.
greaterThanInteger :: Integer -> Integer -> Bool
greaterThanInteger = (>)

{-# NOINLINE greaterThanEqInteger #-}
-- | Check whether one 'Integer' is greater than or equal to another.
greaterThanEqInteger :: Integer -> Integer -> Bool
greaterThanEqInteger = (>=)

{-# NOINLINE lessThanInteger #-}
-- | Check whether one 'Integer' is less than another.
lessThanInteger :: Integer -> Integer -> Bool
lessThanInteger = (<)

{-# NOINLINE lessThanEqInteger #-}
-- | Check whether one 'Integer' is less than or equal to another.
lessThanEqInteger :: Integer -> Integer -> Bool
lessThanEqInteger = (<=)

{-# NOINLINE equalsInteger #-}
-- | Check if two 'Integer's are equal.
equalsInteger :: Integer -> Integer -> Bool
equalsInteger = (==)

{- Note [Delaying error]
The Plutus Core 'error' builtin is of type 'forall a . a', but the
one we expose here is of type 'forall a . () -> a'.

This is because it's hard to get the evaluation order right with
the non-delayed version - it's easy to end up with it getting thrown
unconditionally, or before some other effect (e.g. tracing). On the other
hand, it's much easier to work with the delayed version.

But why not just define that in the library? i.e.

    error = \_ -> Builtins.error

The answer is that GHC is eager to inline and reduce this function, which
does the Wrong Thing. We can't stop GHC doing this (at the moment), but
for most of our functions it's not a *semantic* problem. Here, however,
it is a problem. So we just expose the delayed version as the builtin.
-}

{-# NOINLINE error #-}
-- | Aborts evaluation with an error.
error :: () -> a
error = mustBeReplaced "error"

{-# NOINLINE trace #-}
-- | Logs the given 'String' to the evaluation log.
trace :: String -> ()
trace _ = () --mustBeReplaced "trace"
