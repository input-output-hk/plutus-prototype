{-# OPTIONS_GHC -fno-omit-interface-pragmas #-}
module PlutusTx.Eq (Eq(..), (/=)) where

import qualified Data.ByteString   as BS
import           PlutusTx.Bool
import qualified PlutusTx.Builtins as Builtins
import           PlutusTx.Data

import           Prelude           hiding (Eq (..), not, (&&))
import qualified Prelude           as Haskell

{-# ANN module ("HLint: ignore"::String) #-}

infix 4 ==, /=

-- Copied from the GHC definition
-- | The 'Eq' class defines equality ('==').
class Eq a where
    (==) :: a -> a -> Bool

    -- (/=) deliberately omitted, to make this a one-method class which has a
    -- simpler representation

{-# INLINABLE (/=) #-}
(/=) :: Eq a => a -> a -> Bool
x /= y = not (x == y)

instance Eq Integer where
    {-# INLINABLE (==) #-}
    (==) = Builtins.equalsInteger

instance Eq Builtins.ByteString where
    {-# INLINABLE (==) #-}
    (==) = Builtins.equalsByteString

instance Eq Builtins.String where
    {-# INLINABLE (==) #-}
    (==) = Builtins.equalsString

instance Eq BS.ByteString where
    {-# INLINABLE (==) #-}
    (==) = (Haskell.==)

instance Eq a => Eq [a] where
    {-# INLINABLE (==) #-}
    [] == []         = True
    (x:xs) == (y:ys) = x == y && xs == ys
    _ == _           = False

instance Eq Bool where
    {-# INLINABLE (==) #-}
    True == True   = True
    False == False = True
    _ == _         = False

instance Eq a => Eq (Maybe a) where
    {-# INLINABLE (==) #-}
    (Just a1) == (Just a2) = a1 == a2
    Nothing == Nothing     = True
    _ == _                 = False

instance (Eq a, Eq b) => Eq (Either a b) where
    {-# INLINABLE (==) #-}
    (Left a1) == (Left a2)   = a1 == a2
    (Right b1) == (Right b2) = b1 == b2
    _ == _                   = False

instance Eq () where
    {-# INLINABLE (==) #-}
    _ == _ = True

instance (Eq a, Eq b) => Eq (a, b) where
    {-# INLINABLE (==) #-}
    (a, b) == (a', b') = a == a' && b == b'

instance Eq Data where
    {-# INLINABLE (==) #-}
    Constr i ds == Constr i' ds' = i == i' && ds == ds'
    Constr _ _  == _             = False
    Map ds == Map ds'            = ds == ds'
    Map _  == _                  = False
    I i == I i'                  = i == i'
    I _ == _                     = False
    B b == B b'                  = b == b'
    B _ == _                     = False
    List ls == List ls'          = ls == ls'
    List _  == _                 = False
