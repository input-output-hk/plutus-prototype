{-# LANGUAGE DeriveAnyClass        #-}
{-# LANGUAGE DeriveGeneric         #-}
{-# LANGUAGE DerivingStrategies    #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE LambdaCase            #-}
{-# LANGUAGE MonoLocalBinds        #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE NoImplicitPrelude     #-}
{-# LANGUAGE TemplateHaskell       #-}
{-# LANGUAGE TupleSections         #-}
{-# LANGUAGE UndecidableInstances  #-}
{-# OPTIONS_GHC -Wno-name-shadowing #-}
-- Prevent unboxing, which the plugin can't deal with
{-# OPTIONS_GHC -fno-strictness #-}
{-# OPTIONS_GHC -fno-specialise #-}
{-# OPTIONS_GHC -fno-omit-interface-pragmas #-}

-- | A map represented as an "association list" of key-value pairs.
module PlutusTx.AssocMap (
    Map
    , singleton
    , empty
    , null
    , fromList
    , toList
    , keys
    , elems
    , lookup
    , member
    , insert
    , delete
    , union
    , unionWith
    , filter
    , mapWithKey
    , mapMaybe
    , mapMaybeWithKey
    , all
    , mapThese
    ) where

import           Control.DeepSeq  (NFData)
import           GHC.Generics     (Generic)
import           PlutusTx.IsData
import           PlutusTx.Lift    (makeLift)
import           PlutusTx.Prelude hiding (all, filter, mapMaybe, null, toList)
import qualified PlutusTx.Prelude as P
import           PlutusTx.These
import qualified Prelude          as Haskell

{-HLINT ignore "Use newtype instead of data"-}

-- | A 'Map' of key-value pairs.
newtype Map k v = Map { unMap :: [(k, v)] }
    deriving stock (Generic, Haskell.Eq, Haskell.Show)
    deriving newtype (Eq, Ord, IsData, NFData)

instance Functor (Map k) where
    {-# INLINABLE fmap #-}
    fmap f (Map mp) =
        let
            go []          = []
            go ((c, i):xs) = (c, f i) : go xs
        in Map (go mp)

instance Foldable (Map k) where
    {-# INLINABLE foldMap #-}
    foldMap f (Map mp) =
        let
            go []          = mempty
            go ((_, i):xs) = f i <> go xs
        in go mp

instance Traversable (Map k) where
    {-# INLINABLE traverse #-}
    traverse f (Map mp) =
        let
            go []          = pure []
            go ((c, i):xs) = (\i' xs' -> (c, i') : xs') <$> f i <*> go xs
        in Map <$> go mp

-- This is the "better" instance for Maps that various people
-- have suggested, which merges conflicting entries with
-- the underlying semigroup for values.
instance (Eq k, Semigroup v) => Semigroup (Map k v) where
    (<>) = unionWith (<>)

instance (Eq k, Semigroup v) => Monoid (Map k v) where
    mempty = empty

{-# INLINABLE fromList #-}
fromList :: [(k, v)] -> Map k v
fromList = Map

{-# INLINABLE toList #-}
toList :: Map k v -> [(k, v)]
toList (Map l) = l

{-# INLINABLE lookup #-}
-- | Find an entry in a 'Map'.
lookup :: forall k v . (Eq k) => k -> Map k v -> Maybe v
lookup c (Map xs) =
    let
        go :: [(k, v)] -> Maybe v
        go []            = Nothing
        go ((c', i):xs') = if c' == c then Just i else go xs'
    in go xs


{-# INLINABLE member #-}
-- | Is the key a member of the map?
member :: forall k v . (Eq k) => k -> Map k v -> Bool
member k m = isJust (lookup k m)

{-# INLINABLE insert #-}
insert :: forall k v . Eq k => k -> v -> Map k v -> Map k v
insert k v m = unionWith (\_ b -> b) m (fromList [(k, v)])

{-# INLINABLE delete #-}
delete :: forall k v . (Eq k) => k -> Map k v -> Map k v
delete key (Map ls) = Map (go ls)
  where
    go [] = []
    go ((k, v) : rest) | k == key = rest
                       | otherwise = (k, v) : go rest

{-# INLINABLE keys #-}
-- | The keys of a 'Map'.
keys :: Map k v -> [k]
keys (Map xs) = P.fmap (\(k, _ :: v) -> k) xs

{-# INLINABLE union #-}
-- | Combine two 'Map's.
union :: forall k v r . (Eq k) => Map k v -> Map k r -> Map k (These v r)
union (Map ls) (Map rs) =
    let
        f :: v -> Maybe r -> These v r
        f a b' = case b' of
            Nothing -> This a
            Just b  -> These a b

        ls' :: [(k, These v r)]
        ls' = P.fmap (\(c, i) -> (c, f i (lookup c (Map rs)))) ls

        rs' :: [(k, r)]
        rs' = P.filter (\(c, _) -> not (any (\(c', _) -> c' == c) ls)) rs

        rs'' :: [(k, These v r)]
        rs'' = P.fmap (\(c, b) -> (c, That b)) rs'

    in Map (ls' ++ rs'')

{-# INLINABLE unionWith #-}
-- | Combine two 'Map's with the given combination function.
unionWith :: forall k a . (Eq k) => (a -> a -> a) -> Map k a -> Map k a -> Map k a
unionWith merge (Map ls) (Map rs) =
    let
        f :: a -> Maybe a -> a
        f a b' = case b' of
            Nothing -> a
            Just b  -> merge a b

        ls' :: [(k, a)]
        ls' = P.fmap (\(c, i) -> (c, f i (lookup c (Map rs)))) ls

        rs' :: [(k, a)]
        rs' = P.filter (\(c, _) -> not (any (\(c', _) -> c' == c) ls)) rs

    in Map (ls' ++ rs')

{-# INLINABLE all #-}
-- | See 'Data.Map.all'
all :: (v -> Bool) -> Map k v -> Bool
all p (Map mps) =
    let go xs = case xs of
            []              -> True
            (_ :: k, x):xs' -> p x && go xs'
    in go mps

-- | A version of 'Data.Map.Lazy.mapEither' that works with 'These'.
mapThese :: (v -> These a b) -> Map k v -> (Map k a, Map k b)
mapThese f mps = (Map mpl, Map mpr)  where
    (mpl, mpr) = P.foldr f' ([], []) mps'
    Map mps'  = fmap f mps
    f' (k, v) (as, bs) = case v of
        This a    -> ((k, a):as, bs)
        That b    -> (as, (k, b):bs)
        These a b -> ((k, a):as, (k, b):bs)

-- | A singleton map.
singleton :: k -> v -> Map k v
singleton c i = Map [(c, i)]

{-# INLINABLE empty #-}
-- | An empty 'Map'.
empty :: Map k v
empty = Map ([] :: [(k, v)])

{-# INLINABLE null #-}
-- | Is the map empty?
null :: Map k v -> Bool
null = P.null . unMap

{-# INLINABLE filter #-}
-- | Filter all values that satisfy the predicate.
filter :: (v -> Bool) -> Map k v -> Map k v
filter f (Map m) = Map $ P.filter (f . snd) m

{-# INLINABLE elems #-}
-- | Return all elements of the map in the ascending order of their keys.
elems :: Map k v -> [v]
elems (Map xs) = P.fmap (\(_ :: k, v) -> v) xs

{-# INLINABLE mapWithKey #-}
-- | Map a function over all values in the map.
mapWithKey :: (k -> a -> b) -> Map k a -> Map k b
mapWithKey f (Map xs) = Map $ fmap (\(k, v) -> (k, f k v)) xs

{-# INLINABLE mapMaybe #-}
-- | Map keys\/values and collect the 'Just' results.
mapMaybe :: (a -> Maybe b) -> Map k a -> Map k b
mapMaybe f (Map xs) = Map $ P.mapMaybe (\(k, v) -> (k, ) <$> f v) xs

{-# INLINABLE mapMaybeWithKey #-}
-- | Map keys\/values and collect the 'Just' results.
mapMaybeWithKey :: (k -> a -> Maybe b) -> Map k a -> Map k b
mapMaybeWithKey f (Map xs) = Map $ P.mapMaybe (\(k, v) -> (k, ) <$> f k v) xs

makeLift ''Map
