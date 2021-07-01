{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeOperators         #-}
-- For the 'IsString' instance
{-# OPTIONS_GHC -Wno-orphans #-}
{-# OPTIONS_GHC -fno-omit-interface-pragmas #-}

module PlutusTx.ByteString.Instances (stringToBuiltinByteString) where

import qualified Data.String                  as Haskell (IsString (..), String)
import           PlutusTx.ByteString.Internal as Plutus
import qualified PlutusTx.String              as String

import qualified GHC.Magic                    as Magic

{- Same noinline hack as with `String` type. -}
instance Haskell.IsString ByteString where
    -- Try and make sure the dictionary selector goes away, it's simpler to match on
    -- the application of 'stringToBuiltinByteString'
    {-# INLINE fromString #-}
    -- See Note [noinline hack]
    fromString = Magic.noinline stringToBuiltinByteString

{-# INLINABLE stringToBuiltinByteString #-}
stringToBuiltinByteString :: Haskell.String -> ByteString
stringToBuiltinByteString = encodeUtf8 . String.stringToBuiltinString
