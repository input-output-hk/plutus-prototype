{-# LANGUAGE CPP #-}

-- |
-- Module      : Network.Socket.ByteString.Internal
-- Copyright   : (c) Johan Tibell 2007-2010
-- License     : BSD-style
--
-- Maintainer  : johan.tibell@gmail.com
-- Stability   : stable
-- Portability : portable
--
module Network.Socket.ByteString.Internal
    (
      mkInvalidRecvArgError
#if !defined(mingw32_HOST_OS)
    , c_writev
#else
    , c_wsasend
#endif
    , c_sendmsg
    , c_recvmsg
    ) where

#include "HsNetDef.h"

import GHC.IO.Exception (IOErrorType(..))
import System.IO.Error (ioeSetErrorString, mkIOError)

#if !defined(mingw32_HOST_OS)
import System.Posix.Types (CSsize(..))

import Network.Socket.Imports
import Network.Socket.Posix.IOVec (IOVec)
import Network.Socket.Posix.MsgHdr (MsgHdr)
import Network.Socket.Types
#else
import Data.Word
import Foreign.C.Types
import Foreign.Ptr

import Network.Socket.Win32.WSABuf (WSABuf)
import Network.Socket.Win32.MsgHdr (MsgHdr)
import Network.Socket.Types

type DWORD   = Word32
type LPDWORD = Ptr DWORD
#endif

mkInvalidRecvArgError :: String -> IOError
mkInvalidRecvArgError loc = ioeSetErrorString (mkIOError
                                    InvalidArgument
                                    loc Nothing Nothing) "non-positive length"

#if !defined(mingw32_HOST_OS)
foreign import ccall unsafe "writev"
  c_writev :: CInt -> Ptr IOVec -> CInt -> IO CSsize

foreign import ccall unsafe "sendmsg"
  c_sendmsg :: CInt -> Ptr (MsgHdr SockAddr) -> CInt -> IO CSsize

foreign import ccall unsafe "recvmsg"
  c_recvmsg :: CInt -> Ptr (MsgHdr SockAddr) -> CInt -> IO CSsize
#else
  -- fixme Handle for SOCKET, see #426
foreign import CALLCONV SAFE_ON_WIN "WSASend"
  c_wsasend :: CInt -> Ptr WSABuf -> DWORD -> LPDWORD -> DWORD -> Ptr () -> Ptr () -> IO CInt
foreign import CALLCONV SAFE_ON_WIN "WSASendMsg"
  c_sendmsg :: CInt -> Ptr (MsgHdr SockAddr) -> DWORD -> LPDWORD -> Ptr () -> Ptr ()  -> IO CInt
foreign import CALLCONV SAFE_ON_WIN "WSARecvMsg"
  c_recvmsg :: CInt -> Ptr (MsgHdr SockAddr) -> LPDWORD -> Ptr () -> Ptr () -> IO CInt
#endif
