{-# OPTIONS_GHC -funbox-strict-fields #-}

-- | Support module for the POSIX 'sendmsg' system call.
module Network.Socket.Posix.MsgHdr
    ( MsgHdr(..)
    ) where

#include <sys/types.h>
#include <sys/socket.h>

import Network.Socket.Imports
import Network.Socket.Internal (zeroMemory)

import Network.Socket.Posix.IOVec (IOVec)

data MsgHdr sa = MsgHdr
    { msgName    :: !(Ptr sa)
    , msgNameLen :: !CUInt
    , msgIov     :: !(Ptr IOVec)
    , msgIovLen  :: !CSize
    , msgCtrl    :: !(Ptr Word8)
    , msgCtrlLen :: !CInt
    , msgFlags   :: !CInt
    }

instance Storable (MsgHdr sa) where
  sizeOf    _ = (#const sizeof(struct msghdr))
  alignment _ = alignment (0 :: CInt)

  peek p = do
    name       <- (#peek struct msghdr, msg_name)       p
    nameLen    <- (#peek struct msghdr, msg_namelen)    p
    iov        <- (#peek struct msghdr, msg_iov)        p
    iovLen     <- (#peek struct msghdr, msg_iovlen)     p
    ctrl       <- (#peek struct msghdr, msg_control)    p
    ctrlLen    <- (#peek struct msghdr, msg_controllen) p
    flags      <- (#peek struct msghdr, msg_flags)      p
    return $ MsgHdr name nameLen iov iovLen ctrl ctrlLen flags

  poke p mh = do
    -- We need to zero the msg_control, msg_controllen, and msg_flags
    -- fields, but they only exist on some platforms (e.g. not on
    -- Solaris).  Instead of using CPP, we zero the entire struct.
    zeroMemory p (#const sizeof(struct msghdr))
    (#poke struct msghdr, msg_name)       p (msgName       mh)
    (#poke struct msghdr, msg_namelen)    p (msgNameLen    mh)
    (#poke struct msghdr, msg_iov)        p (msgIov        mh)
    (#poke struct msghdr, msg_iovlen)     p (msgIovLen     mh)
    (#poke struct msghdr, msg_control)    p (msgCtrl       mh)
    (#poke struct msghdr, msg_controllen) p (msgCtrlLen    mh)
    (#poke struct msghdr, msg_flags)      p (msgFlags      mh)
