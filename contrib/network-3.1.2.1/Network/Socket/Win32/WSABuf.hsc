{-# OPTIONS_GHC -funbox-strict-fields #-}

-- | Support module for the Windows winsock system calls.
module Network.Socket.Win32.WSABuf
    ( WSABuf(..)
    , withWSABuf
    ) where

#include "HsNet.h"

import Foreign.Marshal.Array (allocaArray)

import Network.Socket.Imports

type ULONG = Word32

data WSABuf = WSABuf
    { wsaBufPtr :: !(Ptr Word8)
    , wsaBufLen :: !ULONG
    }

instance Storable WSABuf where
  sizeOf    _ = #{size WSABUF}
  alignment _ = #alignment WSABUF

  peek p = do
    base <- (#peek WSABUF, buf) p
    len  <- (#peek WSABUF, len)  p
    return $ WSABuf base len

  poke p iov = do
    (#poke WSABUF, buf) p (wsaBufPtr iov)
    (#poke WSABUF, len) p (wsaBufLen iov)

-- | @withWSABuf cs f@ executes the computation @f@, passing as argument a pair
-- consisting of a pointer to a temporarily allocated array of pointers to
-- WSABBUF made from @cs@ and the number of pointers (@length cs@).
-- /Windows only/.
withWSABuf :: [(Ptr Word8, Int)] -> ((Ptr WSABuf, Int) -> IO a) -> IO a
withWSABuf [] f = f (nullPtr, 0)
withWSABuf cs f =
    allocaArray csLen $ \aPtr -> do
        zipWithM_ pokeWsaBuf (ptrs aPtr) cs
        f (aPtr, csLen)
  where
    csLen = length cs
    ptrs = iterate (`plusPtr` sizeOf (WSABuf nullPtr 0))
    pokeWsaBuf ptr (sPtr, sLen) = poke ptr $ WSABuf sPtr (fromIntegral sLen)
