{-% nofib/spectral/constraints converted to Plutus.
    Renamed to avoid conflict with existing package. %-}
{-# LANGUAGE DeriveAnyClass    #-}
{-# LANGUAGE DeriveGeneric     #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# OPTIONS_GHC -fno-warn-incomplete-patterns #-}
{-# OPTIONS_GHC -fno-warn-name-shadowing      #-}
{-# OPTIONS_GHC -fno-warn-orphans             #-}
{-# OPTIONS_GHC -fno-warn-unused-matches      #-}

module Plutus.Benchmark.Queens where

{- Andrew Tolmach and Thomas Nordin's contraint solver

	See Proceedings of WAAAPL '99
-}

import           Control.DeepSeq    (NFData)
import           Control.Monad      (forM_)
import           Data.Char          (isSpace)
import           GHC.Generics
import qualified Prelude            as Haskell
import           System.Environment

import           PlutusCore.Default
import qualified PlutusCore.Pretty  as PLC
import qualified PlutusTx           as Tx
import           PlutusTx.Prelude   as TxPrelude
import           UntypedPlutusCore


-----------------------------
-- The main program
-----------------------------

{-% This program computes the number of mutually non-attacking arrangements
    of n queens on an n x n chessboard.  It's quite sophisticated: there's a
    generic constraint solver that takes an algorithm as a parameter.  There are
    five different algorithms, and the original behaviour was to try each of
    these on a board if size NxN, where N is a parameter supplied by the user.
    The Haskell version can run all five algorithms one after the other hundreds
    of times on an 8x8 board in a few seconds.

    Compiling into Plutus, I tried to run all five algorithms one after the other
    (in a single run of the program) on a 5x5 board on the CEK machine on an 8 GB
    machine.  The program was just able to complete in about 23s, but with some
    swapping.

    The resource consumption isn't so bad for the individual algorithms.  Here
    are figures for the time and memory usage for one run of the Plutus version
    of each algorithm on a 5x5 board on the same machine:

    bt:    2.9s, 1.2 GB
    bm:    2.5s, 830 MB
    bjbt:  2.7s, 933 MB
    bjbt': 3.0s, 1.1 GB
    fc:    7.5s, 3.2 GB

%-}


-- The different algorithms implemented in this file. The program iterates the
-- solver over this list of algortihms.

allAlgorithms :: [Labeler]
allAlgorithms = [bt, bm, bjbt, bjbt', fc]

data Algorithm = Bt
               | Bm
               | Bjbt1
               | Bjbt2
               | Fc
               deriving (Haskell.Show, Haskell.Read)

{-# INLINABLE lookupAlgorithm #-}
lookupAlgorithm :: Algorithm -> Labeler
lookupAlgorithm Bt    = bt
lookupAlgorithm Bm    = bm
lookupAlgorithm Bjbt1 = bjbt
lookupAlgorithm Bjbt2 = bjbt'  -- bjbt' problematic on command line
lookupAlgorithm Fc    = fc

{-# INLINABLE nqueens #-}
nqueens :: Integer -> Labeler -> [State]
nqueens n algorithm = (search algorithm (queens n))

-- % Haskell entry point for testing
{-# INLINABLE runQueens #-}
runQueens :: Integer -> Algorithm -> [State]
runQueens n alg = nqueens n (lookupAlgorithm alg)

-- % Compile a Plutus Core term which runs nqueens on given arguments
mkQueensTerm :: Integer -> Algorithm -> Term DeBruijn DefaultUni DefaultFun ()
mkQueensTerm sz alg =
  let (Program _ _ code) =
        Tx.getPlc $
              $$(Tx.compile [|| runQueens ||])
              `Tx.applyCode` Tx.liftCode sz
              `Tx.applyCode` Tx.liftCode alg
  in code


main2 :: Haskell.IO ()  -- Haskell version
main2 = do
  args <- getArgs
  case args of
    [] -> Haskell.putStrLn "Integer parameter expected"
    arg:_ -> do
              let n = Haskell.read arg :: Integer
                  try algorithm = Haskell.print (nqueens n algorithm)
              forM_ [1..240::Integer] $ const $ do
                Haskell.sequence_ (map try allAlgorithms)

-- % Only for textual output of PLC scripts
unindent :: PLC.Doc ann -> [Haskell.String]
unindent d = map (dropWhile isSpace) $ (Haskell.lines . Haskell.show $ d)


-----------------------------------------------------------
-- % Various standard things reimplemented for Plutus
-----------------------------------------------------------

-- % Replacement for `iterate`, which generates an infinite list
{-# INLINABLE iterateN #-}
iterateN :: Integer -> (a -> a) -> a -> [a]
iterateN k f x =
    if k == 0 then []
    else x : iterateN (k-1) f (f x)

-- % Replacement for [a..b]
{-# INLINABLE interval #-}
interval :: Integer -> Integer -> [Integer]
interval a b =
    if a > b then []
    else a : (interval (a+1) b)

{-# INLINABLE abs #-}
abs :: Integer -> Integer
abs n = if n<0 then 0-n else n

-- % Things needed for `union`

{-# INLINABLE deleteBy #-}
deleteBy :: (a -> a -> Bool) -> a -> [a] -> [a]
deleteBy _  _ []     = []
deleteBy eq x (y:ys) = if x `eq` y then ys else y : deleteBy eq x ys

{-# INLINABLE unionBy #-}
unionBy :: (a -> a -> Bool) -> [a] -> [a] -> [a]
unionBy eq xs ys =  xs ++ foldl (flip (deleteBy eq)) (TxPrelude.nubBy eq ys) xs

{-# INLINABLE union #-}
union :: (Eq a) => [a] -> [a] -> [a]
union                   = unionBy (==)

-- % Things needed for `sortBy`
instance TxPrelude.Eq Ordering where
    LT == LT = True
    EQ == EQ = True
    GT == GT = True
    _ == _   = False

{-# INLINABLE sortBy #-}
-- % Stolen from Data.List
sortBy :: (a -> a -> Ordering) -> [a] -> [a]
sortBy cmp = mergeAll . sequences
  where
    sequences (a:b:xs)
      | (a `cmp` b) == GT = descending b [a]  xs
      | otherwise       = ascending  b (a:) xs
    sequences xs = [xs]

    descending a as (b:bs)
      | (a `cmp` b) == GT = descending b (a:as) bs
    descending a as bs  = (a:as): sequences bs

    ascending a as (b:bs)
      | (a `cmp` b) /= GT = ascending b (\ys -> as (a:ys)) bs
    ascending a as bs   = case as [a]  -- Original used let !x = ...
                          of x -> x : sequences bs

    mergeAll [x] = x
    mergeAll xs  = mergeAll (mergePairs xs)

    mergePairs (a:b:xs) = case merge a b -- Original used let !x = ...
                          of x ->  x : mergePairs xs
    mergePairs xs       = xs

    merge as@(a:as') bs@(b:bs')
      | a `cmp` b == GT = b:merge as  bs'
      | otherwise       = a:merge as' bs
    merge [] bs         = bs
    merge as []         = as


-----------------------------
-- Figure 1. CSPs in Haskell.
-----------------------------

type Var = Integer
type Value = Integer

data Assign = Var := Value
    deriving (Haskell.Show, Haskell.Eq, Haskell.Ord, Generic, NFData)
instance TxPrelude.Eq Assign
    where (a := b) == (a' := b') = a==a' && b==b'
instance TxPrelude.Ord Assign
    where (a := b) < (a' := b') = (a<a') || (a==a' && b < b')

type Relation = Assign -> Assign -> Bool

data CSP = CSP { vars, vals :: Integer, rel :: Relation }

type State = [Assign]

{-# INLINABLE level #-}
level :: Assign -> Var
level (var := val) = var

{-# INLINABLE value #-}
value :: Assign -> Value
value (var := val) = val

{-# INLINABLE maxLevel #-}
maxLevel :: State -> Var
maxLevel []               = 0
maxLevel ((var := val):_) = var

{-# INLINABLE complete #-}
complete :: CSP -> State -> Bool
complete CSP{vars=vars} s = maxLevel s == vars

{-# INLINABLE generate #-}
generate :: CSP -> [State]
generate CSP{vals=vals,vars=vars} = g vars
  where g 0   = [[]]
        g var = [ (var := val):st | val <- interval 1 vals, st <- g (var-1) ]

{-# INLINABLE inconsistencies #-}
inconsistencies :: CSP -> State -> [(Var,Var)]
inconsistencies CSP{rel=rel} as =  [ (level a, level b) | a <- as, b <- reverse as, a > b, not (rel a b) ]

{-# INLINABLE consistent #-}
consistent :: CSP -> State -> Bool
consistent csp = null . (inconsistencies csp)

{-# INLINABLE test #-}
test :: CSP -> [State] -> [State]
test csp = filter (consistent csp)

{-# INLINABLE solver #-}
solver :: CSP -> [State]
solver csp  = test csp candidates
  where candidates = generate csp

{-# INLINABLE queens #-}
queens :: Integer -> CSP
queens n = CSP {vars = n, vals = n, rel = safe}
  where safe (i := m) (j := n) = (m /= n) && abs (i - j) /= abs (m - n)

-------------------------------
-- Figure 2.  Trees in Haskell.
-------------------------------

data Tree a = Node a [Tree a]

label :: Tree a -> a
label (Node lab _) = lab

type Transform a b = Tree a -> Tree b

{-# INLINABLE mapTree  #-}
mapTree  :: (a -> b) -> Transform a b
mapTree f (Node a cs) = Node (f a) (map (mapTree f) cs)

{-# INLINABLE foldTree #-}
foldTree :: (a -> [b] -> b) -> Tree a -> b
foldTree f (Node a cs) = f a (map (foldTree f) cs)

{-# INLINABLE filterTree #-}
filterTree :: (a -> Bool) -> Transform a a
filterTree p = foldTree f
  where f a cs = Node a (filter (p . label) cs)

{-# INLINABLE prune #-}
prune :: (a -> Bool) -> Transform a a
prune p = filterTree (not . p)

{-# INLINABLE leaves #-}
leaves :: Tree a -> [a]
leaves (Node leaf []) = [leaf]
leaves (Node _ cs)    = concat (map leaves cs)

{-# INLINABLE initTree #-}
initTree :: (a -> [a]) -> a -> Tree a
initTree f a = Node a (map (initTree f) (f a))

--------------------------------------------------
-- Figure 3.  Simple backtracking solver for CSPs.
--------------------------------------------------

{-# INLINABLE mkTree #-}
mkTree :: CSP -> Tree State
mkTree CSP{vars=vars,vals=vals} = initTree next []
  where next ss = [ ((maxLevel ss + 1) := j):ss | maxLevel ss < vars, j <- vallist ]  -- Removed [1..vals]
        vallist = interval 1 vals

{-# INLINABLE earliestInconsistency #-}
earliestInconsistency :: CSP -> State -> Maybe (Var,Var)
earliestInconsistency CSP{rel=rel} [] = Nothing
earliestInconsistency CSP{rel=rel} (a:as) =
        case filter (not . rel a) (reverse as) of
          []    -> Nothing
          (b:_) -> Just (level a, level b)

{-# INLINABLE labelInconsistencies #-}
labelInconsistencies :: CSP -> Transform State (State,Maybe (Var,Var))
labelInconsistencies csp = mapTree f
    where f s = (s,earliestInconsistency csp s)

{-# INLINABLE btsolver0 #-}
btsolver0 :: CSP -> [State]
btsolver0 csp =
  (filter (complete csp) . leaves . (mapTree fst) . prune ((/= Nothing) . snd)
                                            . (labelInconsistencies csp) .  mkTree) csp

-----------------------------------------------
-- Figure 6. Conflict-directed solving of CSPs.
-----------------------------------------------

data ConflictSet = Known [Var] | Unknown
instance TxPrelude.Eq ConflictSet where
    Known v == Known w = v == w
    Unknown == Unknown = True
    _ == _             = False

{-# INLINABLE knownConflict #-}
knownConflict :: ConflictSet -> Bool
knownConflict (Known (a:as)) = True
knownConflict _              = False

{-# INLINABLE knownSolution #-}
knownSolution :: ConflictSet -> Bool
knownSolution (Known []) = True
knownSolution _          = False

{-# INLINABLE checkComplete #-}
checkComplete :: CSP -> State -> ConflictSet
checkComplete csp s = if complete csp s then Known [] else Unknown

type Labeler = CSP -> Transform State (State, ConflictSet)

{-# INLINABLE search #-}
search :: Labeler -> CSP -> [State]
search labeler csp =
  (map fst . filter (knownSolution . snd) . leaves . prune (knownConflict . snd) . labeler csp . mkTree) csp

{-# INLINABLE bt #-}
bt :: Labeler
bt csp = mapTree f
      where f s = (s,
                   case earliestInconsistency csp s of
                     Nothing    -> checkComplete csp s
                     Just (a,b) -> Known [a,b])

{-# INLINABLE btsolver #-}
btsolver :: CSP -> [State]
btsolver = search bt

-------------------------------------
-- Figure 7. Randomization heuristic.
-------------------------------------

{-# INLINABLE hrandom #-}
hrandom :: Integer -> Transform a a
hrandom seed (Node a cs) = Node a (randomList seed' (zipWith hrandom (randoms (length cs) seed') cs))
  where seed' = random seed

{-# INLINABLE btr #-}
btr :: Integer -> Labeler
btr seed csp = bt csp . hrandom seed

---------------------------------------------
-- Support for random numbers (not in paper).
---------------------------------------------

{-# INLINABLE random2 #-}
random2 :: Integer -> Integer
random2 n = if test > 0 then test else test + 2147483647
  where test = 16807 * lo - 2836 * hi
        hi   = n `Haskell.div` 127773
        lo   = n `Haskell.rem` 127773

{-# INLINABLE randoms #-}
randoms :: Integer -> Integer -> [Integer]
randoms k = iterateN k random2

{-# INLINABLE random #-}
random :: Integer -> Integer
random n = (a * n + c) -- mod m
  where a = 994108973
        c = a

{-# INLINABLE randomList #-}
randomList :: Integer -> [a] -> [a]
randomList i as = map snd (sortBy (\(a,b) (c,d) -> compare a c) (zip (randoms (length as) i) as))

-------------------------
-- Figure 8. Backmarking.
-------------------------

type Table = [Row]       -- indexed by Var
type Row = [ConflictSet] -- indexed by Value

{-# INLINABLE bm #-}
bm :: Labeler
bm csp = mapTree fst . lookupCache csp . cacheChecks csp (emptyTable csp)

{-# INLINABLE emptyTable #-}
emptyTable :: CSP -> Table
emptyTable CSP{vars=vars,vals=vals} = []:[[Unknown | m <- interval 1 vals] | n <- interval 1 vars]

{-# INLINABLE cacheChecks #-}
cacheChecks :: CSP -> Table -> Transform State (State, Table)
cacheChecks csp tbl (Node s cs) =
  Node (s, tbl) (map (cacheChecks csp (fillTable s csp (tail tbl))) cs)

{-# INLINABLE fillTable #-}
fillTable :: State -> CSP -> Table -> Table
fillTable [] csp tbl = tbl
fillTable ((var' := val'):as) CSP{vars=vars,vals=vals,rel=rel} tbl =
    zipWith (zipWith f) tbl [[(var,val) | val <- interval 1 vals] | var <- interval (var'+1) vars]
          where f cs (var,val) = if cs == Unknown && not (rel (var' := val') (var := val)) then
                                   Known [var',var]
                                 else cs

{-# INLINABLE lookupCache #-}
lookupCache :: CSP -> Transform (State, Table) ((State, ConflictSet), Table)
lookupCache csp t = mapTree f t
  where f ([], tbl)      = (([], Unknown), tbl)
        f (s@(a:_), tbl) = ((s, cs), tbl)
             where cs = if tableEntry == Unknown then checkComplete csp s else tableEntry
                   tableEntry = (head tbl)!!(value a-1)

--------------------------------------------
-- Figure 10. Conflict-directed backjumping.
--------------------------------------------

{-# INLINABLE bjbt #-}
bjbt :: Labeler
bjbt csp = bj csp . bt csp

{-# INLINABLE bjbt' #-}
bjbt' :: Labeler
bjbt' csp = bj' csp . bt csp

{-# INLINABLE bj #-}
bj :: CSP -> Transform (State, ConflictSet) (State, ConflictSet)
bj csp = foldTree f
  where f (a, Known cs) chs = Node (a,Known cs) chs
        f (a, Unknown)  chs = Node (a,Known cs') chs
          where cs' = combine (map label chs) []

{-# INLINABLE combine #-}
combine :: [(State, ConflictSet)] -> [Var] -> [Var]
combine []                 acc = acc
combine ((s, Known cs):css) acc =
  if maxLevel s `notElem` cs then cs else combine css (cs `union` acc)

{-# INLINABLE bj' #-}
bj' :: CSP -> Transform (State, ConflictSet) (State, ConflictSet)
bj' csp = foldTree f
  where f (a, Known cs) chs = Node (a,Known cs) chs
        f (a, Unknown) chs = if knownConflict cs' then Node (a,cs') [] else Node (a,cs') chs
           where cs' = Known (combine (map label chs) [])

-------------------------------
-- Figure 11. Forward checking.
-------------------------------

{-# INLINABLE fc #-}
fc :: Labeler
fc csp = domainWipeOut csp . lookupCache csp . cacheChecks csp (emptyTable csp)

{-# INLINABLE collect #-}
collect :: [ConflictSet] -> [Var]
collect []             = []
collect (Known cs:css) = cs `union` (collect css)

{-# INLINABLE domainWipeOut #-}
domainWipeOut :: CSP -> Transform ((State, ConflictSet), Table) (State, ConflictSet)
domainWipeOut CSP{vars=vars} t = mapTree f t
  where f ((as, cs), tbl) = (as, cs')
          where wipedDomains = ([vs | vs <- tbl, all (knownConflict) vs])
                cs' = if null wipedDomains then cs else Known (collect (head wipedDomains))

Tx.makeLift ''Algorithm
Tx.makeLift ''Assign
