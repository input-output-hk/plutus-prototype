{-# OPTIONS_GHC -funbox-strict-fields #-}

-- | Support module for the POSIX writev system call.
module Network.Socket.Posix.IOVec
    ( IOVec(..)
    , withIOVec
    ) where

import Foreign.Marshal.Array (allocaArray)

import Network.Socket.Imports

#include <sys/types.h>
#include <sys/uio.h>

data IOVec = IOVec
    { iovBase :: !(Ptr Word8)
    , iovLen  :: !CSize
    }

instance Storable IOVec where
  sizeOf    _ = (#const sizeof(struct iovec))
  alignment _ = alignment (0 :: CInt)

  peek p = do
    base <- (#peek struct iovec, iov_base) p
    len  <- (#peek struct iovec, iov_len)  p
    return $ IOVec base len

  poke p iov = do
    (#poke struct iovec, iov_base) p (iovBase iov)
    (#poke struct iovec, iov_len)  p (iovLen  iov)

-- | @withIOVec cs f@ executes the computation @f@, passing as argument a pair
-- consisting of a pointer to a temporarily allocated array of pointers to
-- IOVec made from @cs@ and the number of pointers (@length cs@).
-- /Unix only/.
withIOVec :: [(Ptr Word8, Int)] -> ((Ptr IOVec, Int) -> IO a) -> IO a
withIOVec [] f = f (nullPtr, 0)
withIOVec cs f =
    allocaArray csLen $ \aPtr -> do
        zipWithM_ pokeIov (ptrs aPtr) cs
        f (aPtr, csLen)
  where
    csLen = length cs
    ptrs = iterate (`plusPtr` sizeOf (IOVec nullPtr 0))
    pokeIov ptr (sPtr, sLen) = poke ptr $ IOVec sPtr (fromIntegral sLen)
