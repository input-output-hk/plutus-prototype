{-# LANGUAGE DeriveAnyClass        #-}
{-# LANGUAGE DeriveGeneric         #-}
{-# LANGUAGE DerivingStrategies    #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE NoImplicitPrelude     #-}
{-# LANGUAGE TemplateHaskell       #-}
{-# OPTIONS_GHC -fno-omit-interface-pragmas #-}
{-# OPTIONS_GHC -fplugin-opt PlutusTx.Plugin:debug-context #-}
{-# OPTIONS_GHC -fno-strictness #-}
{-# OPTIONS_GHC -fno-ignore-interface-pragmas #-}
module PlutusTx.Ratio(
    Ratio
    , Rational
    , (%)
    , fromInteger
    , numerator
    , denominator
    , round
    , truncate
    , properFraction
    , recip
    , half
    , fromGHC
    , toGHC
    -- * Misc.
    , divMod
    , quotRem
    , gcd
    , abs
    , reduce
    ) where

import qualified PlutusTx.Bool     as P
import qualified PlutusTx.Eq       as P
import qualified PlutusTx.IsData   as P
import qualified PlutusTx.Lift     as P
import qualified PlutusTx.Numeric  as P
import qualified PlutusTx.Ord      as P

import qualified PlutusTx.Builtins as Builtins

import           Data.Aeson        (FromJSON, ToJSON)
import           GHC.Generics      (Generic)
import qualified GHC.Real          as Ratio
import           Prelude           (Bool (True), Eq, Integer, Integral, Ord (..), Show (..), showParen, showString, (*))
import qualified Prelude           as Haskell

data Ratio a = a :% a
    deriving stock (Eq,Generic)
    deriving anyclass (ToJSON, FromJSON)

instance  Show a => Show (Ratio a) where
    -- Adapted from Data.Ratio in the base library
    showsPrec p r = showParen (p > ratioPrec) Haskell.$
                    showString "(" Haskell..
                    showsPrec ratioPrec1 (numerator r) Haskell..
                    showString " % " Haskell..
                    showsPrec ratioPrec1 (denominator r) Haskell..
                    showString ")"
       where ratioPrec = 7  -- This refers to the operator precedence level of %
             ratioPrec1 = ratioPrec Haskell.+ 1

{- HLINT ignore -}

{- Note [Ratio]

The implementation of 'Ratio' and related functions (most importantly
'round' and Num/Ord instances) is the same as that found in 'GHC.Real',
specialised to `Integer`.

An important invariant is that the denominator is always positive. This is
enforced by

* Construction of 'Rational' numbers with '%' (the constructor of 'Ratio' is
  not exposed)
* Using `reduce` after every 'Num' operation

The 'StdLib.Spec' module has some property tests that check the behaviour of
'round', 'truncate', '>=', etc. against that of their counterparts in
'GHC.Real'.

-}

{- NOTE [Integer division operations]

Plutus Core provides built-in functions 'divideInteger', 'modInteger',
'quotientInteger' and 'remainderInteger' which are implemented as the Haskell
functions 'div', 'mod', 'quot', and 'rem' respectively.

The operations 'div' and 'mod' go together, as do 'quot' and 'rem': * DO NOT use
'div' with 'rem' or 'quot' with 'mod' *.  For most purposes users shoud probably
use 'div' and 'mod': see below for details.

For any integers a and b with b nonzero we have

  a * (a  `div` b) + a `mod` b = a
  a * (a `quot` b) + a `rem` b = a

(all operations give a "divide by zero" error if b = 0).  The analagous
identities for div/rem and quot/mod don't hold in general, and this can
lead to problems if you use the wrong combination of operations.

For positive divisors b, div truncates downwards and mod always returns a
non-negative result (0 <= a `mod` b <= b-1), which is consistent with standard
mathematical practice.  The `quot` operation truncates towards zero and `rem`
will give a negative remainder if a<0 and b>0.  If a<0 and b<0 then `mod` willl
also yield a negative result.  Results for different combinations of signs are
shown below.

-------------------------------
|   n  d | div mod | quot rem |
|-----------------------------|
|  41  5 |  8   1  |   8   1  |
| -41  5 | -9   4  |  -8  -1  |
|  41 -5 | -9  -4  |  -8   1  |
| -41 -5 |  8  -1  |   8  -1  |
-------------------------------

For many purposes (in particular if you're doing modular arithmetic),
a positive remainder is what you want.  Using 'div' and 'mod' achieves
this for positive values of b (but not for b negative, although doing
artimetic modulo a negative number would be unusual).

There is another possibility (Euclidean division) which is arguably more
mathematically correct than both div/mod and quot/rem. Given integers a and b
with b != 0, this returns numbers q and r with a = q*b+r and 0 <= r < |b|.  For
the numbers above this gives

-------------------
|   n  d |  q   r |
|-----------------|
|  41  5 |  8   1 |
| -41  5 | -9   4 |
|  41 -5 | -8   1 |
| -41 -5 |  9   4 |
-------------------

We get a positive remainder in all cases, but note for instance that the pairs
(41,5) and (-41,-5) give different results, which might be unexpected.

For a discussion of the pros and cons of various versions of integer division,
see Raymond T. Boute, "The Euclidean definition of the functions div and mod",
ACM Transactions on Programming Languages and Systems, April 1992.  (PDF at
https://core.ac.uk/download/pdf/187613369.pdf)
-}


type Rational = Ratio Integer

instance  (Integral a)  => Ord (Ratio a)  where
    (x:%y) <= (x':%y')  =  x * y' <= x' * y
    (x:%y) <  (x':%y')  =  x * y' <  x' * y

instance P.Eq a => P.Eq (Ratio a) where
    {-# INLINABLE (==) #-}
    (n1 :% d1) == (n2 :% d2) = n1 P.== n2 P.&& d1 P.== d2

instance P.AdditiveSemigroup (Ratio Integer) where
    {-# INLINABLE (+) #-}
    (x :% y) + (x' :% y') = reduce ((x P.* y') P.+ (x' P.* y)) (y P.* y')

instance P.AdditiveMonoid (Ratio Integer) where
    {-# INLINABLE zero #-}
    zero = P.zero :% P.one

instance P.AdditiveGroup (Ratio Integer) where
    {-# INLINABLE (-) #-}
    (x :% y) - (x' :% y') = reduce ((x P.* y') P.- (x' P.* y)) (y P.* y')

instance P.MultiplicativeSemigroup (Ratio Integer) where
    {-# INLINABLE (*) #-}
    (x :% y) * (x' :% y') = reduce (x P.* x') (y P.* y')

instance P.MultiplicativeMonoid (Ratio Integer) where
    {-# INLINABLE one #-}
    one = 1 :% 1

instance P.Ord (Ratio Integer) where
    {-# INLINABLE (<=) #-}
    (x :% y) <= (x' :% y') = x P.* y' P.<= (x' P.* y)

infixl 7 %
{-# INLINABLE (%) #-}
-- | Forms the ratio of two integral numbers.
(%) :: Integer -> Integer -> Ratio Integer
x % y = reduce (x P.* signum y) (abs y)

-- | Reciprocal fraction
recip :: Ratio Integer -> Ratio Integer
recip (x :% y) = (y :% x)

-- | Convert an 'Interger' to a 'Rational'
fromInteger :: Integer -> Ratio Integer
fromInteger n = n :% 1

-- | Convert a 'Data.Ratio.Rational' to a
--   Plutus-compatible 'PlutusTx.Ratio.Rational'
fromGHC :: Ratio.Rational -> Ratio Integer
fromGHC (n Ratio.:% d) = n :% d

-- | Convert a 'PlutusTx.Ratio.Rational' to a
--   'Data.Ratio.Rational'
toGHC :: Rational -> Ratio.Rational
toGHC (n :% d) = n Ratio.:% d

{-# INLINABLE numerator #-}
-- | Extract the numerator of the ratio in reduced form: the numerator and denominator have no common factor and the denominator is positive.
numerator :: Ratio a -> a
numerator (n :% _) = n

{-# INLINABLE denominator #-}
-- | Extract the denominator of the ratio in reduced form: the numerator and denominator have no common factor and the denominator is positive.
denominator :: Ratio a -> a
denominator (_ :% d) = d

{-# INLINABLE gcd #-}
-- From GHC.Real
-- | @'gcd' x y@ is the non-negative factor of both @x@ and @y@ of which
-- every common factor of @x@ and @y@ is also a factor; for example
-- @'gcd' 4 2 = 2@, @'gcd' (-4) 6 = 2@, @'gcd' 0 4@ = @4@. @'gcd' 0 0@ = @0@.
gcd :: Integer -> Integer -> Integer
gcd a b = gcd' (abs a) (abs b) where
    gcd' a' b'
        | b' P.== P.zero = a'
        | True           = gcd' b' (a' `Builtins.remainderInteger` b')

{-# INLINABLE truncate #-}
-- | truncate @x@ returns the integer nearest @x@ between zero and @x@
truncate :: Ratio Integer -> Integer
truncate r = let (m, _ :: Rational) = properFraction r in m

{-# INLINABLE properFraction #-}
-- From GHC.Real
-- | The function 'properFraction' takes a real fractional number @x@
-- and returns a pair @(n,f)@ such that @x = n+f@, and:
--
-- * @n@ is an integral number with the same sign as @x@; and
--
-- * @f@ is a fraction with the same type and sign as @x@,
--   and with absolute value less than @1@.
--
-- The default definitions of the 'ceiling', 'floor', 'truncate'
-- and 'round' functions are in terms of 'properFraction'.
properFraction :: Ratio Integer -> (Integer, Ratio Integer)
properFraction (n :% d) = (q, r :% d) where (q, r) = quotRem n d

{-# INLINABLE divMod #-}
-- TODO. This is doing twice as much work as it needs to: the Plutus Core
-- builtins 'divideInteger' and 'modInteger' are implemented as the Haskell
-- 'div' and 'mod' operations, which in turn are impemented as fst . divMod and
-- snd . divMod, so we're calling Haskell's 'divMod' twice and throwing away
-- useful information.  We could fix his by exposing 'divMod' as a PLC builtin,
-- but that would require us to implement pairs as built-in types along with
-- built-in introduction and elimination functions.  This would be non-trivial.
-- | Simultaneous div and mod.
divMod :: Integer -> Integer -> (Integer, Integer)
divMod x y = ( x `Builtins.divideInteger` y, x `Builtins.modInteger` y)

{-# INLINABLE quotRem #-}
-- TODO.  Provide a Plutus Core built-in function for this: see the comment for
-- 'divMod'.
-- | Simultaneous quot and rem.
quotRem :: Integer -> Integer -> (Integer, Integer)
quotRem x y = ( x `Builtins.quotientInteger` y, x `Builtins.remainderInteger` y)

{-# INLINABLE half #-}
-- | 0.5
half :: Ratio Integer
half = 1 :% 2

{-# INLINABLE reduce #-}
-- | From GHC.Real
-- | 'reduce' is a subsidiary function used only in this module.
-- It normalises a ratio by dividing both numerator and denominator by
-- their greatest common divisor.
reduce :: Integer -> Integer -> Ratio Integer
reduce x y
    | y P.== 0 = Builtins.error ()
    | True     =
        let d = gcd x y in
        (x `Builtins.quotientInteger` d) :% (y `Builtins.quotientInteger` d)

{-# INLINABLE abs #-}
abs :: (P.Ord n, P.AdditiveGroup n) => n -> n
abs x = if x P.< P.zero then P.negate x else x

{-# INLINABLE signumR #-}
signumR :: Rational -> Rational
signumR (n :% d) = signum (n P.* d) :% 1

{-# INLINABLE signum #-}
signum :: Integer -> Integer
signum r =
    if r P.== 0
    then P.zero
    else if r P.> 0
         then P.one
         else P.negate P.one

{-# INLINABLE even #-}
even :: Integer -> Bool
even x = (x `Builtins.remainderInteger` 2) P.== P.zero

{-# INLINABLE round #-}
-- | From GHC.Real
-- | @round x@ returns the nearest integer to @x@; the even integer if @x@ is equidistant between two integers
round :: Ratio Integer -> Integer
round x
    | sig P.== P.negate P.one = n
    | sig P.== P.zero         = if even n then n else m
    | sig P.== P.one          = m
    | True                    = Builtins.error()
    where (n, r) = properFraction x
          m      = if r P.< P.zero then n P.- P.one else n P.+ P.one
          sig    = signumR (abs r P.- half)

P.makeLift ''Ratio
P.makeIsDataIndexed ''Ratio [('(:%),0)]
