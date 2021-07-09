{-# OPTIONS_GHC -funbox-strict-fields #-}
{-# LANGUAGE CPP #-}

-- | Support module for the Windows 'WSASendMsg' system call.
module Network.Socket.Win32.MsgHdr
    ( MsgHdr(..)
    ) where

#include "HsNet.h"

import Network.Socket.Imports
import Network.Socket.Internal (zeroMemory)
import Network.Socket.Win32.WSABuf

type DWORD = Word32
type ULONG = Word32

-- The size of BufferLen is different on pre-vista compilers.
-- But since those platforms are out of support anyway we ignore that.
data MsgHdr sa = MsgHdr
    { msgName      :: !(Ptr sa)
    , msgNameLen   :: !CInt
    , msgBuffer    :: !(Ptr WSABuf)
    , msgBufferLen :: !DWORD
    , msgCtrl      :: !(Ptr Word8)
    , msgCtrlLen   :: !ULONG
    , msgFlags     :: !DWORD
    } deriving Show

instance Storable (MsgHdr sa) where
  sizeOf    _ = #{size WSAMSG}
  alignment _ = #alignment WSAMSG

  peek p = do
    name       <- (#peek WSAMSG, name)          p
    nameLen    <- (#peek WSAMSG, namelen)       p
    buffer     <- (#peek WSAMSG, lpBuffers)     p
    bufferLen  <- (#peek WSAMSG, dwBufferCount) p
    ctrl       <- (#peek WSAMSG, Control.buf)   p
    ctrlLen    <- (#peek WSAMSG, Control.len)   p
    flags      <- (#peek WSAMSG, dwFlags)       p
    return $ MsgHdr name nameLen buffer bufferLen ctrl ctrlLen flags

  poke p mh = do
    -- We need to zero the msg_control, msg_controllen, and msg_flags
    -- fields, but they only exist on some platforms (e.g. not on
    -- Solaris).  Instead of using CPP, we zero the entire struct.
    zeroMemory p (#const sizeof(WSAMSG))
    (#poke WSAMSG, name)           p (msgName       mh)
    (#poke WSAMSG, namelen)        p (msgNameLen    mh)
    (#poke WSAMSG, lpBuffers)      p (msgBuffer     mh)
    (#poke WSAMSG, dwBufferCount)  p (msgBufferLen  mh)
    (#poke WSAMSG, Control.buf)    p (msgCtrl       mh)
    (#poke WSAMSG, Control.len)    p (msgCtrlLen    mh)
    (#poke WSAMSG, dwFlags)        p (msgFlags      mh)
