{-# LANGUAGE BangPatterns    #-}
{-# LANGUAGE LambdaCase      #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE TypeFamilies    #-}
{-# LANGUAGE ViewPatterns    #-}
module Data.RandomAccessList.SkewBinary ( RAList(Cons,Nil)
                 , index
                 , Data.RandomAccessList.SkewBinary.null
                 , Data.RandomAccessList.SkewBinary.head
                 , Data.RandomAccessList.SkewBinary.tail
                 , uncons
                 ) where

import           Data.Bits  (unsafeShiftR)
import qualified Data.List  as List (unfoldr)
import           Data.Maybe
import           GHC.Exts

{- Note [Optimizing RAList for performance]
After benchmarking using plutus-core:env-bench and plutus-benchmark:nofib,
it seems that the best options are:

- no sub-tree size caching
- strict on the spines
-}

-- | A complete binary tree.
-- Note: the size of the tree is not stored/cached,
-- unless it appears as a root tree in 'RAList', which the size is stored inside the Cons.
data Tree a = Leaf a
            | Node a !(Tree a) !(Tree a)
            deriving (Eq, Show)

-- | A strict list of complete binary trees accompanied by their size.
-- The trees appear in >=-size order.
-- Note: this list is strict in its spine, unlike the Prelude list
data RAList a = BHead
               {-# UNPACK #-} !Word -- ^ the size of the head tree
               !(Tree a) -- ^ the head tree
               !(RAList a) -- ^ the tail trees
             | Nil
             -- the derived Eq instance is correct,
             -- because binary skew numbers have unique representation
             -- and hence all trees of the same size will have the same structure
             deriving (Eq, Show)


instance IsList (RAList a) where
  type Item (RAList a) = a
  fromList = foldr cons Nil
  toList = List.unfoldr uncons

{-# INLINABLE null #-}
null :: RAList a -> Bool
null Nil = True
null _   = False

-- /O(1)/
-- destructor
pattern Cons :: a -> RAList a -> RAList a
pattern Cons x xs <- (uncons -> Just (x, xs)) where
  -- constructor
  Cons x xs = cons x xs

{-# complete Cons, Nil #-}
{-# complete BHead, Nil #-}

-- O(1) worst-case
cons :: a -> RAList a -> RAList a
cons x = \case
    (BHead w1 t1 (BHead w2 t2 ts')) | w1 == w2 -> BHead (2*w1+1) (Node x t1 t2) ts'
    ts                                         -> BHead 1 (Leaf x) ts

-- /O(1)/
uncons :: RAList a -> Maybe (a, RAList a)
uncons = \case
    BHead _ (Leaf x) ts -> Just (x, ts)
    BHead treeSize (Node x t1 t2) ts ->
        -- unsafeShiftR 1 is faster than `div w 2`
        let halfSize = unsafeShiftR treeSize 1
            -- split the node in two)
        in Just (x, BHead halfSize t1 $ BHead halfSize t2 ts)
    Nil -> Nothing

{-# INLINABLE head #-}
-- O(1) worst-case
head :: RAList a -> a
head = fst . fromMaybe (error "empty RAList") . uncons

{-# INLINABLE tail #-}
-- O(1) worst-case
tail :: RAList a -> RAList a
tail = snd . fromMaybe (error "empty RAList") . uncons

-- 0-based
-- O(log n)
index :: RAList a -> Word -> a
index (BHead w0 t ts) !i0
  | i0 >= w0 = index ts (i0 - w0)
  | otherwise = go w0 i0 t
  where
    go _ _ (Leaf x) = x
    go _ 0 (Node x _ _) = x
    go w i (Node _ l r) =
      let halfSize = unsafeShiftR w 1
      in if i <= halfSize
         then go halfSize (i-1) l
         else go halfSize (i-1-halfSize) r
index Nil _ = error "skew list out of bounds"

-- TODO: safeIndex
