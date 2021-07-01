{-# LANGUAGE LambdaCase #-}
-- We don't normally do this to avoid being sensitive to GHC's optimzations,
-- but here we're precisely testing how much difference that makes.
{-# OPTIONS_GHC -fexpose-all-unfoldings #-}
{-# OPTIONS_GHC -O2 #-}
{-# OPTIONS_GHC -fno-strictness #-}
module Opt where

import           Prelude          hiding (tail)

import qualified PlutusTx.Prelude as P

{- HLINT ignore -}

fibOpt :: Integer -> Integer
fibOpt n =
    if n P.== 0
    then 0
    else if n P.== 1
    then 1
    else fibOpt (n P.- 1) P.+ fibOpt (n P.- 2)

fromToOpt :: Integer -> Integer -> [Integer]
fromToOpt f t =
    if f P.== t then [f]
    else f:(fromToOpt (f P.+ 1) t)

foldrOpt :: (a -> b -> b) -> b -> [a] -> b
foldrOpt f z = go
    where go []    = z
          go (h:t) = h `f` go t

tailOpt :: [a] -> Maybe a
tailOpt = \case
    []     -> Nothing
    (x:[]) -> Just x
    (_:xs) -> tailOpt xs
