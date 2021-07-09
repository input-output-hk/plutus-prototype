{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE PatternGuards #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE RankNTypes #-}


module Network.Socket.ReadShow where

import Text.Read ((<++))
import qualified Text.Read as P
import qualified Text.Read.Lex as P
import Control.Monad (mzero)

-- type alias for individual correspondences of a (possibly partial) bijection
type Pair a b = (a, b)

-- | helper function for equality on first tuple element
{-# INLINE eqFst #-}
eqFst :: Eq a => a -> (a, b) -> Bool
eqFst x = \(x',_) -> x' == x

-- | helper function for equality on snd tuple element
{-# INLINE eqSnd #-}
eqSnd :: Eq b => b -> (a, b) -> Bool
eqSnd y = \(_,y') -> y' == y


-- | Unified automorphic involution over @Either a b@ that converts between
--   LHS and RHS elements of a list of @Pair a b@ mappings and is the identity
--   function if no matching pair is found
--
--   If list contains duplicate matches, short-circuits to the first matching @Pair@
lookBetween :: (Eq a, Eq b) => [Pair a b] -> Either a b -> Either a b
lookBetween ps = \case
  Left  x | (_,y):_ <- filter (eqFst x) ps -> Right y
  Right y | (x,_):_ <- filter (eqSnd y) ps -> Left  x
  z -> z

-- Type alias for partial bijections between two types, consisting of a list
-- of individual correspondences that are checked in order and short-circuit
-- on first match
--
-- Depending on how this is used, may not actually be a true bijection over
-- the partial types, as no overlap-checking is currently implemented. If
-- overlaps are unavoidable, the canonical short-circuit pair should appear
-- first to avoid round-trip inconsistencies.
type Bijection a b = [Pair a b]

-- | Helper function for prefixing an optional constructor name before arbitrary values,
-- which only enforces high precedence on subsequent output if the constructor name is not
-- blank and space-separates for non-blank constructor names
namePrefix :: Int -> String -> (Int -> b -> ShowS) -> b -> ShowS
namePrefix i name f x
    | null name = f i x
    | otherwise = showParen (i > app_prec) $ showString name . showChar ' ' . f (app_prec+1) x
{-# INLINE namePrefix #-}

-- | Helper function for defining bijective Show instances that represents
-- a common use-case where a constructor (or constructor-like pattern) name
-- (optionally) precedes an internal value with a separate show function
defShow :: Eq a => String -> (a -> b) -> (Int -> b -> ShowS) -> (Int -> a -> ShowS)
defShow name unwrap shoPrec = \i x -> namePrefix i name shoPrec (unwrap x)
{-# INLINE defShow #-}

-- Helper function for stripping an optional constructor-name prefix before parsing
-- an arbitrary value, which only consumes an extra token and increases precedence
-- if the provided name prefix is non-blank
expectPrefix :: String -> P.ReadPrec a -> P.ReadPrec a
expectPrefix name pars
    | null name = pars
    | otherwise = do
        P.lift $ P.expect $ P.Ident name
        P.step pars
{-# INLINE expectPrefix #-}

-- | Helper function for defining bijective Read instances that represent a
-- common use case where a constructor (or constructor-like pattern) name
-- (optionally) precedes an internal value with a separate parse function
defRead :: Eq a => String -> (b -> a) -> P.ReadPrec b -> P.ReadPrec a
defRead name wrap redPrec = expectPrefix name $ wrap <$> redPrec
{-# INLINE defRead #-}

-- | Alias for showsPrec that pairs well with `_readInt`
_showInt :: (Show a) => Int -> a -> ShowS
_showInt = showsPrec
{-# INLINE _showInt #-}

-- | More descriptive alias for `safeInt`
_readInt :: (Bounded a, Integral a) => P.ReadPrec a
_readInt = safeInt
{-# INLINE _readInt #-}

-- | show two elements of a tuple separated by a space character
-- inverse function to readIntInt when used on integer-like values
showIntInt :: (Show a, Show b) => Int -> (a, b) -> ShowS
showIntInt i (x, y) = _showInt i x . showChar ' ' . _showInt i y
{-# INLINE showIntInt #-}

-- | consume and return two integer-like values from two consecutive lexical tokens
readIntInt :: (Bounded a, Integral a, Bounded b, Integral b) => P.ReadPrec (a, b)
readIntInt = do
  x <- _readInt
  y <- _readInt
  return (x, y)
{-# INLINE readIntInt #-}

bijectiveShow :: (Eq a) => Bijection a String -> (Int -> a -> ShowS) -> (Int -> a -> ShowS)
bijectiveShow bi def = \i x ->
    case lookBetween bi (Left x) of
        Right y -> showString y
        _ -> def i x

bijectiveRead :: (Eq a) => Bijection a String -> P.ReadPrec a -> P.ReadPrec a
bijectiveRead bi def = P.parens $ bijective <++ def
  where
    bijective = do
      (P.Ident y) <- P.lexP
      case lookBetween bi (Right y) of
          Left x -> return x
          _ -> mzero

app_prec :: Int
app_prec = 10
{-# INLINE app_prec #-}

-- Parse integral values with type-specific overflow and underflow bounds-checks
safeInt :: forall a. (Bounded a, Integral a) => P.ReadPrec a
safeInt = do
    i <- signed
    if (i >= fromIntegral (minBound :: a) && i <= fromIntegral (maxBound :: a))
    then return $ fromIntegral i
    else mzero
  where
    signed :: P.ReadPrec Integer
    signed = P.readPrec
