{-# OPTIONS_GHC -fno-omit-interface-pragmas #-}
module PlutusTx.List (
    map,
    filter,
    listToMaybe,
    uniqueElement,
    findIndices,
    findIndex,
    foldr,
    reverse,
    zip,
    (++),
    (!!),
    head,
    take,
    tail,
    nub,
    nubBy
    ) where

import           PlutusTx.Bool     ((||))
import qualified PlutusTx.Builtins as Builtins
import           PlutusTx.Eq       (Eq, (==))
import           Prelude           hiding (Eq (..), all, any, elem, filter, foldl, foldr, head, length, map, null,
                                    reverse, tail, take, zip, (!!), (&&), (++), (||))

{- HLINT ignore -}

{-# INLINABLE map #-}
-- | Plutus Tx version of 'Data.List.map'.
--
--   >>> map (\i -> i + 1) [1, 2, 3]
--   [2,3,4]
--
map :: (a -> b) -> [a] -> [b]
map f l = case l of
    []   -> []
    x:xs -> f x : map f xs

{-# INLINABLE foldr #-}
-- | Plutus Tx version of 'Data.List.foldr'.
--
--   >>> foldr (\i s -> s + i) 0 [1, 2, 3, 4]
--   10
--
foldr :: (a -> b -> b) -> b -> [a] -> b
foldr f acc l = case l of
    []   -> acc
    x:xs -> f x (foldr f acc xs)

{-# INLINABLE (++) #-}
-- | Plutus Tx version of '(Data.List.++)'.
--
--   >>> [0, 1, 2] ++ [1, 2, 3, 4]
--   [0,1,2,1,2,3,4]
--
infixr 5 ++
(++) :: [a] -> [a] -> [a]
(++) l r = foldr (:) r l

{-# INLINABLE filter #-}
-- | Plutus Tx version of 'Data.List.filter'.
--
--   >>> filter (> 1) [1, 2, 3, 4]
--   [2,3,4]
--
filter :: (a -> Bool) -> [a] -> [a]
filter p = foldr (\e xs -> if p e then e:xs else xs) []

{-# INLINABLE listToMaybe #-}
-- | Plutus Tx version of 'Data.List.listToMaybe'.
listToMaybe :: [a] -> Maybe a
listToMaybe []    = Nothing
listToMaybe (x:_) = Just x

{-# INLINABLE uniqueElement #-}
-- | Return the element in the list, if there is precisely one.
uniqueElement :: [a] -> Maybe a
uniqueElement [x] = Just x
uniqueElement _   = Nothing

{-# INLINABLE findIndices #-}
-- | Plutus Tx version of 'Data.List.findIndices'.
findIndices :: (a -> Bool) -> [a] -> [Integer]
findIndices p = go 0
    where
        go i l = case l of
            []     -> []
            (x:xs) -> let indices = go (Builtins.addInteger i 1) xs in if p x then i:indices else indices

{-# INLINABLE findIndex #-}
-- | Plutus Tx version of 'Data.List.findIndex'.
findIndex :: (a -> Bool) -> [a] -> Maybe Integer
findIndex p l = listToMaybe (findIndices p l)

{-# INLINABLE (!!) #-}
-- | Plutus Tx version of '(GHC.List.!!)'.
--
--   >>> [10, 11, 12] !! 2
--   12
--
infixl 9 !!
(!!) :: [a] -> Integer -> a
[]       !! _ = Builtins.error ()
(x : xs) !! i = if Builtins.equalsInteger i 0
    then x
    else xs !! Builtins.subtractInteger i 1


{-# INLINABLE reverse #-}
-- | Plutus Tx version of 'Data.List.reverse'.
reverse :: [a] -> [a]
reverse l = rev l []
  where
    rev []      a = a
    rev (x:xs) a  = rev xs (x:a)


{-# INLINABLE zip #-}
-- | Plutus Tx version of 'Data.List.zip'.
zip :: [a] -> [b] -> [(a,b)]
zip []     _bs    = []
zip _as    []     = []
zip (a:as) (b:bs) = (a,b) : zip as bs

{-# INLINABLE head #-}
-- | Plutus Tx version of 'Data.List.head'.
head :: [a] -> a
head []      = Builtins.error ()
head (x : _) = x

{-# INLINABLE tail #-}
-- | Plutus Tx version of 'Data.List.tail'.
tail :: [a] -> [a]
tail (_:as) =  as
tail []     =  Builtins.error ()

{-# INLINABLE take #-}
-- | Plutus Tx version of 'Data.List.take'.
take :: Integer -> [a] -> [a]
take n _      | n <= 0 =  []
take _ []              =  []
take n (x:xs)          =  x : take (n-1) xs

{-# INLINABLE nub #-}
-- | Plutus Tx version of 'Data.List.nub'.
nub :: (Eq a) => [a] -> [a]
nub =  nubBy (==)

{-# INLINABLE elem_by #-}
-- | Plutus Tx version of 'Data.List.elem_by'.
elem_by :: (a -> a -> Bool) -> a -> [a] -> Bool
elem_by _  _ []     =  False
elem_by eq y (x:xs) =  x `eq` y || elem_by eq y xs

{-# INLINABLE nubBy #-}
-- | Plutus Tx version of 'Data.List.nubBy'.
nubBy :: (a -> a -> Bool) -> [a] -> [a]
nubBy eq l              = nubBy' l []
  where
    nubBy' [] _         = []
    nubBy' (y:ys) xs
       | elem_by eq y xs = nubBy' ys xs
       | otherwise       = y : nubBy' ys (y:xs)
