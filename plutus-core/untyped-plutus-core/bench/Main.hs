{-# LANGUAGE BangPatterns #-}
module Main where

import           Criterion.Main
import           Data.Semigroup
import           System.Random

import qualified Data.IntMap.Strict               as I
import qualified Data.RAList                      as R
import qualified Data.RandomAccessList.SkewBinary as B
import qualified Data.Unordered.IntMap            as U


main :: IO ()
main = defaultMain
    -- NOTE: there is a faster/better way to create a map using fromAscList
    -- but we want to bench cons-ing because that is what we are using in our machine.
    [ bgroup "create/100" [ bench "ours" $ whnf (extendB B.Nil) 100
                           , bench "ral" $ whnf (extendR R.empty) 100
                           , bench "imap" $ whnf (extendI I.empty) 100
                           , bench "umap" $ whnf (extendU U.empty) 100
                           ]
    , bgroup "create/250" [ bench "ours" $ whnf (extendB B.Nil) 250
                           , bench "ral" $ whnf (extendR R.empty) 250
                           , bench "imap" $ whnf (extendI I.empty) 250
                           , bench "umap" $ whnf (extendU U.empty) 250
                            ]


    , bgroup "query/front/100" [ bench "ours" $ whnf (queryFrontB 100) b100
                                , bench "ral" $ whnf (queryFrontR 100) r100
                                , bench "imap" $ whnf (queryFrontI 100) i100
                                , bench "umap" $ whnf (queryFrontU 100) u100
                                ]
    , bgroup "query/front/250" [ bench "ours" $ whnf (queryFrontB 250) b250
                                , bench "ral" $ whnf (queryFrontR 250) r250
                                , bench "imap" $ whnf (queryFrontI 250) i250
                                , bench "umap" $ whnf (queryFrontU 250) u250
                                ]

    , bgroup "query/back/100" [ bench "ours" $ whnf (queryBackB 100) b100
                               , bench "ral" $ whnf (queryBackR 100) r100
                               , bench "imap" $ whnf (queryBackI 100) i100
                                , bench "umap" $ whnf (queryBackU 100) u100
                               ]
    , bgroup "query/back/250" [ bench "ours" $ whnf (queryBackB 250) b250
                               , bench "ral" $ whnf (queryBackR 250) r250
                               , bench "imap" $ whnf (queryBackI 250) i250
                               , bench "umap" $ whnf (queryBackU 250) u250
                               ]


    , bgroup "query/rand/100" [ bench "ours" $ whnf (uncurry queryRandB) (rand100Word, b100)
                               , bench "ral" $ whnf (uncurry queryRandR) (rand100Int, r100)
                               , bench "imap" $ whnf (uncurry queryRandI) (rand100Int, i100)
                               , bench "umap" $ whnf (uncurry queryRandU) (rand100Int, u100)
                               ]
    , bgroup "query/rand/250" [ bench "ours" $ whnf (uncurry queryRandB) (rand250Word, b250)
                               , bench "ral" $ whnf (uncurry queryRandR) (rand250Int, r250)
                               , bench "imap" $ whnf (uncurry queryRandI) (rand250Int, i250)
                               , bench "umap" $ whnf (uncurry queryRandU) (rand250Int, u250)
                               ]

    , bgroup "create100/front100/cons100/back100/cons100/rand100"
            [ bench "ours" $ whnf (uncurry $ mixB 100 100 100 100) (rand100Word, b100)
            , bench "ral" $ whnf (uncurry $ mixR 100 100 100 100) (rand100Int, r100)
            , bench "imap" $ whnf (uncurry $ mixI 100 100 100 100) (rand100Int, i100)
            , bench "umap" $ whnf (uncurry $ mixU 100 100 100 100) (rand100Int, u100)
            ]
    , bgroup "create250/front100/cons100/back100/cons100/rand250"
            [ bench "ours" $ whnf (uncurry $ mixB 100 100 100 100) (rand250Word, b250)
            , bench "ral" $ whnf (uncurry $ mixR 100 100 100 100) (rand250Int, r250)
            , bench "imap" $ whnf (uncurry $ mixI 100 100 100 100) (rand250Int, i250)
            , bench "umap" $ whnf (uncurry $ mixU 100 100 100 100) (rand100Int, u250)
            ]


    ]
  where
        -- the Words in these lists are smaller than maxBound :: Int
        -- so they will not overflow when unsafe coerced to Int
        b100 = extendB B.Nil 100
        r100 = extendR R.empty 100
        i100 = extendI I.empty 100
        u100 = extendU U.empty 100
        b250 = extendB B.Nil 250
        r250 = extendR R.empty 250
        i250 = extendI I.empty 250
        u250 = extendU U.empty 250
        -- if the range is the same, they should produce the same numbers for word and int
        rand100Word = take 100 $ randomRs (0,100-1) g
        rand250Word = take 250 $ randomRs (0,250-1) g
        rand100Int = take 100 $ randomRs (0,100-1) g
        rand250Int = take 250 $ randomRs (0,250-1) g
        -- note: fixed rand-seed to make benchmarks deterministic
        g = mkStdGen 59950

--- EXTEND

applyN :: Integral b => (a -> a) -> a -> b -> a
applyN f init n = appEndo (stimes n $ Endo f) init

extendB :: B.RAList () -> Word -> B.RAList ()
extendB = applyN $ B.Cons ()

extendR :: R.RAList () -> Int -> R.RAList ()
extendR = applyN $ R.cons ()


extendI :: I.IntMap () -> Int -> I.IntMap ()
extendI f n | n == 0 = f
            | otherwise = let n' = n -1
                  in I.insert n' () $ extendI f n'

extendU :: U.UnorderedIntMap () -> Int -> U.UnorderedIntMap ()
extendU f n | n == 0 = f
            | otherwise = let n' = n -1
                  in U.insert n' () $ extendU f n'

-- QUERY FRONT

queryFrontB :: Word -> B.RAList () -> ()
queryFrontB 0 _ = ()
queryFrontB !i d = B.index d i' `seq` queryFrontB i' d
  where i' = i-1

queryFrontR :: Int -> R.RAList () -> ()
queryFrontR 0 _ = ()
queryFrontR !i d = d R.! i' `seq` queryFrontR i' d
  where i' = i-1

queryFrontI :: Int -> I.IntMap () -> ()
queryFrontI 0 _ = ()
queryFrontI !i d = d I.! i' `seq` queryFrontI i' d
  where i' = i-1

queryFrontU :: Int -> U.UnorderedIntMap () -> ()
queryFrontU 0 _ = ()
queryFrontU !i d = d U.! i' `seq` queryFrontU i' d
  where i' = i-1

-- QUERY BACK

queryBackB :: Word -> B.RAList () -> ()
queryBackB size = go 0
 where
   go !i d | i == size = ()
           | otherwise = B.index d i `seq` go (i+1) d

queryBackR :: Int -> R.RAList () -> ()
queryBackR size = go 0
 where
   go !i d | i == size = ()
           | otherwise = d R.! i `seq` go (i+1) d

queryBackI :: Int -> I.IntMap () -> ()
queryBackI size = go 0
 where
   go !i d | i == size = ()
           | otherwise = d I.! i `seq` go (i+1) d

queryBackU :: Int -> U.UnorderedIntMap () -> ()
queryBackU size = go 0
 where
   go !i d | i == size = ()
           | otherwise = d U.! i `seq` go (i+1) d

-- QUERY RAND

queryRandB :: [Word] -> B.RAList () -> ()
queryRandB [] _     = ()
queryRandB (i:is) d = B.index d i `seq` queryRandB is d

queryRandR :: [Int] -> R.RAList () -> ()
queryRandR [] _     = ()
queryRandR (i:is) d = d R.! i `seq` queryRandR is d

queryRandI :: [Int] -> I.IntMap () -> ()
queryRandI [] _     = ()
queryRandI (i:is) d = d I.! i `seq` queryRandI is d

queryRandU :: [Int] -> U.UnorderedIntMap () -> ()
queryRandU [] _     = ()
queryRandU (i:is) d = d U.! i `seq` queryRandU is d

-- MIX

mixB :: Word -> Word -> Word -> Word -> [Word] -> B.RAList () -> ()
mixB front cons1 back cons2 rand d =
    queryFrontB front d
    `seq`
    let d1 = extendB d cons1
    in queryBackB back d1
    `seq`
    let d2 = extendB d1 cons2
    in queryRandB rand d2


mixR :: Int -> Int -> Int -> Int -> [Int] -> R.RAList () -> ()
mixR front cons1 back cons2 rand d =
    queryFrontR front d
    `seq`
    let d1 = extendR d cons1
    in queryBackR back d1
    `seq`
    let d2 = extendR d1 cons2
    in queryRandR rand d2

mixI :: Int -> Int -> Int -> Int -> [Int] -> I.IntMap () -> ()
mixI front cons1 back cons2 rand d =
    queryFrontI front d
    `seq`
    let d1 = extendI d cons1
    in queryBackI back d1
    `seq`
    let d2 = extendI d1 cons2
    in queryRandI rand d2

mixU :: Int -> Int -> Int -> Int -> [Int] -> U.UnorderedIntMap () -> ()
mixU front cons1 back cons2 rand d =
    queryFrontU front d
    `seq`
    let d1 = extendU d cons1
    in queryBackU back d1
    `seq`
    let d2 = extendU d1 cons2
    in queryRandU rand d2





