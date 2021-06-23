{-# LANGUAGE NoImplicitPrelude #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}

module Plutus.Benchmark.Knights where

import           Data.Char
import           Plutus.Benchmark.Knights.ChessSetList
import           Plutus.Benchmark.Knights.KnightHeuristic
import           Plutus.Benchmark.Knights.Queue

import           PlutusCore.Default
import qualified PlutusCore.Pretty                        as PLC
import qualified PlutusTx                                 as Tx
import           PlutusTx.Prelude                         as Tx
import qualified Prelude                                  as Haskell
import           UntypedPlutusCore


{-# INLINABLE zipConst #-}
zipConst :: a -> [b] -> [(a,b)]
zipConst _ []     = []
zipConst a (b:bs) = (a,b) : zipConst a bs

{-# INLINABLE grow #-}
grow :: (Integer,ChessSet) -> [(Integer,ChessSet)]
grow (x,y) = zipConst (x+1) (descendents y)

{-# INLINABLE isFinished #-}
isFinished :: (Integer,ChessSet) -> Bool
isFinished (_,y) = tourFinished y

{-# INLINABLE interval #-}
interval :: Integer -> Integer -> [Integer]
interval a b =
    if a > b then []
    else a:(interval (a+1) b)


{-# INLINABLE repl #-}
repl :: Integer -> Integer -> [Integer]
repl n a =
    if n == 0 then []
    else a:(repl (n-1) a)

-- % Original version used infinite lists.
{-# INLINABLE mkStarts #-}
mkStarts :: Integer -> [(Integer, ChessSet)]
mkStarts sze =
    let l = [startTour (x,y) sze | x <- interval 1 sze, y <- interval 1 sze]
        numStarts = Tx.length l  -- = sze*sze
    in Tx.zip (repl numStarts (1-numStarts)) l

{-# INLINABLE root #-}
root :: Integer -> Queue (Integer, ChessSet)
root sze = addAllFront (mkStarts sze) createQueue

{-% Original version
root sze = addAllFront
             (Tx.zip [-(sze*sze)+1,-(sze*sze)+1..]
                  (zipWith
                     startTour
                      [(x,y) | x <- [1..sze], y <- [1..sze]]
                     (take' (sze*sze) [sze,sze..])))
             createQueue
%-}

type Solution = (Integer, ChessSet)

{-# INLINABLE depthSearch #-}
-- % Added a depth parameter to stop things getting out of hand in the strict world.
depthSearch :: (Eq a) => Integer -> Queue a -> (a -> [a]) -> (a -> Bool) -> Queue a
depthSearch depth q growFn finFn
   | depth == 0             = []
   | emptyQueue q           = []
   | finFn (inquireFront q) = (inquireFront q):
                              (depthSearch (depth-1) (removeFront q) growFn finFn)
   | otherwise              = depthSearch (depth-1)
                                 (addAllFront (growFn (inquireFront q))
                                              (removeFront q))
                                 growFn
                                 finFn

-- % Only for textual output of PLC scripts
unindent :: PLC.Doc ann -> [Haskell.String]
unindent d = map (Haskell.dropWhile isSpace) $ (Haskell.lines . Haskell.show $ d)


-- % Haskell entry point for testing
{-# INLINABLE runKnights #-}
runKnights :: Integer -> Integer -> [Solution]
runKnights depth boardSize = depthSearch depth (root boardSize) grow isFinished

{-# INLINABLE mkKnightsTerm #-}
mkKnightsTerm :: Integer -> Integer -> Term DeBruijn DefaultUni DefaultFun ()
mkKnightsTerm depth boardSize =
  let (Program _ _ code) = Tx.getPlc $
                             $$(Tx.compile [|| runKnights ||])
                             `Tx.applyCode` Tx.liftCode depth
                             `Tx.applyCode` Tx.liftCode boardSize
  in code

Tx.makeLift ''ChessSet
