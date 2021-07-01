{-# OPTIONS_GHC -fno-omit-interface-pragmas #-}
module PlutusTx.Either (Either(..), isLeft, isRight, either) where

import           Prelude (Bool (..), Either (..))


{- HLINT ignore -}

{-# INLINABLE isLeft #-}
-- | Return `True` if the given value is a `Left`-value, `False` otherwise.
isLeft :: Either a b -> Bool
isLeft (Left _)  = True
isLeft (Right _) = False

{-# INLINABLE isRight #-}
-- | Return `True` if the given value is a `Right`-value, `False` otherwise.
isRight :: Either a b -> Bool
isRight (Left _)  = False
isRight (Right _) = True

{-# INLINABLE either #-}
-- | Plutus Tx version of 'Prelude.either'
either :: (a -> c) -> (b -> c) -> Either a b -> c
either f _ (Left x)  = f x
either _ g (Right y) = g y
