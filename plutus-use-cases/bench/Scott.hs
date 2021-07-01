{-# LANGUAGE RankNTypes          #-}
{-# LANGUAGE ScopedTypeVariables #-}
module Scott where

import           Prelude hiding (replicate, tail)

import           IFix

{- HLINT ignore -}

newtype ScottListF f a = ScottListF (forall r . r -> (a -> f a -> r) -> r)
type ScottList a = IFix ScottListF a

nil :: ScottList a
nil = Wrap $ ScottListF $ \z _c -> z

cons :: a -> ScottList a -> ScottList a
cons h t = Wrap $ ScottListF $ \_z c -> c h t

matchList :: ScottList a -> r -> (a -> ScottList a -> r) -> r
matchList (Wrap (ScottListF f)) = f

fromTo :: Integer -> Integer -> ScottList Integer
fromTo f t =
    if f == t then f `cons` nil
    else f `cons` fromTo (f + 1) t

replicate :: Integer -> a -> ScottList a
replicate n a = if n == 0 then nil else a `cons` replicate (n-1) a
