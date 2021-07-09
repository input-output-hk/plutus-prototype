{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE OverloadedStrings #-}

#include "HsNet.h"

-- |
-- Module      : Network.Socket.ByteString.IO
-- Copyright   : (c) Johan Tibell 2007-2010
-- License     : BSD-style
--
-- Maintainer  : johan.tibell@gmail.com
-- Stability   : stable
-- Portability : portable
--
module Network.Socket.ByteString.IO
    (
    -- * Send data to a socket
      send
    , sendAll
    , sendTo
    , sendAllTo

    -- ** Vectored I/O
    -- $vectored
    , sendMany
    , sendManyTo

    -- * Receive data from a socket
    , recv
    , recvFrom
    , waitWhen0

    -- * Advanced send and recv
    , sendMsg
    , recvMsg
    , MsgFlag(..)
    , Cmsg(..)
    ) where

import Control.Concurrent (threadWaitWrite, rtsSupportsBoundThreads)
import Data.ByteString (ByteString)
import qualified Data.ByteString as B
import Data.ByteString.Internal (createAndTrim)
import Data.ByteString.Unsafe (unsafeUseAsCStringLen)
import Foreign.Marshal.Alloc (allocaBytes)

import Network.Socket.Buffer
import Network.Socket.ByteString.Internal
import Network.Socket.Imports
import Network.Socket.Types

import Data.ByteString.Internal (create, ByteString(..))
import Foreign.ForeignPtr (withForeignPtr)
import Foreign.Marshal.Utils (with)
import Network.Socket.Internal

import Network.Socket.Flag

#if !defined(mingw32_HOST_OS)
import Network.Socket.Posix.Cmsg
import Network.Socket.Posix.IOVec
import Network.Socket.Posix.MsgHdr (MsgHdr(..))
#else
import Foreign.Marshal.Alloc (alloca)
import Network.Socket.Win32.Cmsg
import Network.Socket.Win32.WSABuf
import Network.Socket.Win32.MsgHdr (MsgHdr(..))
#endif

-- ----------------------------------------------------------------------------
-- Sending

-- | Send data to the socket.  The socket must be connected to a
-- remote socket.  Returns the number of bytes sent. Applications are
-- responsible for ensuring that all data has been sent.
send :: Socket     -- ^ Connected socket
     -> ByteString  -- ^ Data to send
     -> IO Int      -- ^ Number of bytes sent
send s xs = unsafeUseAsCStringLen xs $ \(str, len) ->
    sendBuf s (castPtr str) len

waitWhen0 :: Int -> Socket -> IO ()
waitWhen0 0 s = when rtsSupportsBoundThreads $
    withFdSocket s $ \fd -> threadWaitWrite $ fromIntegral fd
waitWhen0 _ _ = return ()

-- | Send data to the socket.  The socket must be connected to a
-- remote socket.  Unlike 'send', this function continues to send data
-- until either all data has been sent or an error occurs.  On error,
-- an exception is raised, and there is no way to determine how much
-- data, if any, was successfully sent.
sendAll :: Socket     -- ^ Connected socket
        -> ByteString  -- ^ Data to send
        -> IO ()
sendAll _ "" = return ()
sendAll s bs = do
    sent <- send s bs
    waitWhen0 sent s
    when (sent >= 0) $ sendAll s $ B.drop sent bs

-- | Send data to the socket.  The recipient can be specified
-- explicitly, so the socket need not be in a connected state.
-- Returns the number of bytes sent. Applications are responsible for
-- ensuring that all data has been sent.
sendTo :: SocketAddress sa =>
          Socket     -- ^ Socket
       -> ByteString  -- ^ Data to send
       -> sa    -- ^ Recipient address
       -> IO Int      -- ^ Number of bytes sent
sendTo s xs sa =
    unsafeUseAsCStringLen xs $ \(str, len) -> sendBufTo s str len sa

-- | Send data to the socket. The recipient can be specified
-- explicitly, so the socket need not be in a connected state.  Unlike
-- 'sendTo', this function continues to send data until either all
-- data has been sent or an error occurs.  On error, an exception is
-- raised, and there is no way to determine how much data, if any, was
-- successfully sent.
sendAllTo :: SocketAddress sa =>
             Socket     -- ^ Socket
          -> ByteString  -- ^ Data to send
          -> sa    -- ^ Recipient address
          -> IO ()
sendAllTo _ "" _  = return ()
sendAllTo s xs sa = do
    sent <- sendTo s xs sa
    waitWhen0 sent s
    when (sent >= 0) $ sendAllTo s (B.drop sent xs) sa

-- | Send data to the socket.  The socket must be in a connected
-- state.  The data is sent as if the parts have been concatenated.
-- This function continues to send data until either all data has been
-- sent or an error occurs.  On error, an exception is raised, and
-- there is no way to determine how much data, if any, was
-- successfully sent.
sendMany :: Socket       -- ^ Connected socket
         -> [ByteString]  -- ^ Data to send
         -> IO ()
sendMany _ [] = return ()
sendMany s cs = do
    sent <- sendManyInner
    waitWhen0 sent s
    when (sent >= 0) $ sendMany s $ remainingChunks sent cs
  where
    sendManyInner =
#if !defined(mingw32_HOST_OS)
      fmap fromIntegral . withIOVecfromBS cs $ \(iovsPtr, iovsLen) ->
          withFdSocket s $ \fd -> do
              let len =  fromIntegral $ min iovsLen (#const IOV_MAX)
              throwSocketErrorWaitWrite s "Network.Socket.ByteString.sendMany" $
                  c_writev fd iovsPtr len
#else
      fmap fromIntegral . withWSABuffromBS cs $ \(wsabsPtr, wsabsLen) ->
          withFdSocket s $ \fd -> do
              let len =  fromIntegral wsabsLen
              alloca $ \send_ptr -> do
                _ <- throwSocketErrorWaitWrite s "Network.Socket.ByteString.sendMany" $
                       c_wsasend fd wsabsPtr len send_ptr  0 nullPtr nullPtr
                peek send_ptr
#endif

-- | Send data to the socket.  The recipient can be specified
-- explicitly, so the socket need not be in a connected state.  The
-- data is sent as if the parts have been concatenated.  This function
-- continues to send data until either all data has been sent or an
-- error occurs.  On error, an exception is raised, and there is no
-- way to determine how much data, if any, was successfully sent.
sendManyTo :: Socket       -- ^ Socket
           -> [ByteString]  -- ^ Data to send
           -> SockAddr      -- ^ Recipient address
           -> IO ()
sendManyTo _ [] _    = return ()
sendManyTo s cs addr = do
    sent <- fromIntegral <$> sendManyToInner
    waitWhen0 sent s
    when (sent >= 0) $ sendManyTo s (remainingChunks sent cs) addr
  where
    sendManyToInner =
      withSockAddr addr $ \addrPtr addrSize ->
#if !defined(mingw32_HOST_OS)
        withIOVecfromBS cs $ \(iovsPtr, iovsLen) -> do
          let msgHdr = MsgHdr {
                  msgName    = addrPtr
                , msgNameLen = fromIntegral addrSize
                , msgIov     = iovsPtr
                , msgIovLen  = fromIntegral iovsLen
                , msgCtrl    = nullPtr
                , msgCtrlLen = 0
                , msgFlags   = 0
                }
          withFdSocket s $ \fd ->
              with msgHdr $ \msgHdrPtr ->
                throwSocketErrorWaitWrite s "Network.Socket.ByteString.sendManyTo" $
                  c_sendmsg fd msgHdrPtr 0
#else
        withWSABuffromBS cs $ \(wsabsPtr, wsabsLen) -> do
          let msgHdr = MsgHdr {
                  msgName      = addrPtr
                , msgNameLen   = fromIntegral addrSize
                , msgBuffer    = wsabsPtr
                , msgBufferLen = fromIntegral wsabsLen
                , msgCtrl      = nullPtr
                , msgCtrlLen   = 0
                , msgFlags     = 0
                }
          withFdSocket s $ \fd ->
              with msgHdr $ \msgHdrPtr ->
                alloca $ \send_ptr -> do
                  _ <- throwSocketErrorWaitWrite s "Network.Socket.ByteString.sendManyTo" $
                          c_sendmsg fd msgHdrPtr 0 send_ptr nullPtr nullPtr
                  peek send_ptr
#endif

-- ----------------------------------------------------------------------------
-- Receiving

-- | Receive data from the socket.  The socket must be in a connected
-- state.  This function may return fewer bytes than specified.  If
-- the message is longer than the specified length, it may be
-- discarded depending on the type of socket.  This function may block
-- until a message arrives.
--
-- Considering hardware and network realities, the maximum number of bytes to
-- receive should be a small power of 2, e.g., 4096.
--
-- For TCP sockets, a zero length return value means the peer has
-- closed its half side of the connection.
recv :: Socket        -- ^ Connected socket
     -> Int            -- ^ Maximum number of bytes to receive
     -> IO ByteString  -- ^ Data received
recv s nbytes
    | nbytes < 0 = ioError (mkInvalidRecvArgError "Network.Socket.ByteString.recv")
    | otherwise  = createAndTrim nbytes $ \ptr -> recvBuf s ptr nbytes

-- | Receive data from the socket.  The socket need not be in a
-- connected state.  Returns @(bytes, address)@ where @bytes@ is a
-- 'ByteString' representing the data received and @address@ is a
-- 'SockAddr' representing the address of the sending socket.
--
-- If the first return value is zero, it means EOF.
recvFrom :: SocketAddress sa =>
            Socket                     -- ^ Socket
         -> Int                        -- ^ Maximum number of bytes to receive
         -> IO (ByteString, sa)  -- ^ Data received and sender address
recvFrom sock nbytes =
    allocaBytes nbytes $ \ptr -> do
        (len, sockaddr) <- recvBufFrom sock ptr nbytes
        str <- B.packCStringLen (ptr, len)
        return (str, sockaddr)

-- ----------------------------------------------------------------------------
-- Not exported


-- | Suppose we try to transmit a list of chunks @cs@ via a gathering write
-- operation and find that @n@ bytes were sent. Then @remainingChunks n cs@ is
-- list of chunks remaining to be sent.
remainingChunks :: Int -> [ByteString] -> [ByteString]
remainingChunks _ [] = []
remainingChunks i (x:xs)
    | i < len        = B.drop i x : xs
    | otherwise      = let i' = i - len in i' `seq` remainingChunks i' xs
  where
    len = B.length x

#if !defined(mingw32_HOST_OS)
-- | @withIOVecfromBS cs f@ executes the computation @f@, passing as argument a pair
-- consisting of a pointer to a temporarily allocated array of pointers to
-- IOVec made from @cs@ and the number of pointers (@length cs@).
-- /Unix only/.
withIOVecfromBS :: [ByteString] -> ((Ptr IOVec, Int) -> IO a) -> IO a
withIOVecfromBS cs f = withBufSizs cs $ \bufsizs -> withIOVec bufsizs f
#else
-- | @withWSABuffromBS cs f@ executes the computation @f@, passing as argument a pair
-- consisting of a pointer to a temporarily allocated array of pointers to
-- WSABuf made from @cs@ and the number of pointers (@length cs@).
-- /Windows only/.
withWSABuffromBS :: [ByteString] -> ((Ptr WSABuf, Int) -> IO a) -> IO a
withWSABuffromBS cs f = withBufSizs cs $ \bufsizs -> withWSABuf bufsizs f
#endif

withBufSizs :: [ByteString] -> ([(Ptr Word8, Int)] -> IO a) -> IO a
withBufSizs bss0 f = loop bss0 id
  where
    loop []                    !build = f $ build []
    loop (PS fptr off len:bss) !build = withForeignPtr fptr $ \ptr -> do
        let !ptr' = ptr `plusPtr` off
        loop bss (build . ((ptr',len) :))

-- | Send data to the socket using sendmsg(2).
sendMsg :: Socket       -- ^ Socket
        -> SockAddr     -- ^ Destination address
        -> [ByteString] -- ^ Data to be sent
        -> [Cmsg]       -- ^ Control messages
        -> MsgFlag      -- ^ Message flags
        -> IO Int       -- ^ The length actually sent
sendMsg _ _    []  _ _ = return 0
sendMsg s addr bss cmsgs flags = withBufSizs bss $ \bufsizs ->
    sendBufMsg s addr bufsizs cmsgs flags

-- | Receive data from the socket using recvmsg(2).
recvMsg :: Socket  -- ^ Socket
        -> Int     -- ^ The maximum length of data to be received
                   --   If the total length is not large enough,
                   --   'MSG_TRUNC' is returned
        -> Int     -- ^ The buffer size for control messages.
                   --   If the length is not large enough,
                   --   'MSG_CTRUNC' is returned
        -> MsgFlag -- ^ Message flags
        -> IO (SockAddr, ByteString, [Cmsg], MsgFlag) -- ^ Source address, received data, control messages and message flags
recvMsg s siz clen flags = do
    bs@(PS fptr _ _) <- create siz $ \ptr -> zeroMemory ptr (fromIntegral siz)
    withForeignPtr fptr $ \ptr -> do
        (addr,len,cmsgs,flags') <- recvBufMsg s [(ptr,siz)] clen flags
        let bs' | len < siz = PS fptr 0 len
                | otherwise = bs
        return (addr, bs', cmsgs, flags')
