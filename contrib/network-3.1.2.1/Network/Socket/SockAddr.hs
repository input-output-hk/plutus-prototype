{-# LANGUAGE CPP #-}
module Network.Socket.SockAddr (
      getPeerName
    , getSocketName
    , connect
    , bind
    , accept
    , sendBufTo
    , recvBufFrom
    , sendBufMsg
    , recvBufMsg
    ) where

import Control.Exception (try, throwIO, IOException)
import System.Directory (removeFile)
import System.IO.Error (isAlreadyInUseError, isDoesNotExistError)

import qualified Network.Socket.Buffer as G
import qualified Network.Socket.Name as G
import qualified Network.Socket.Syscall as G
import Network.Socket.Flag
import Network.Socket.Imports
#if !defined(mingw32_HOST_OS)
import Network.Socket.Posix.Cmsg
#else
import Network.Socket.Win32.Cmsg
#endif
import Network.Socket.Types

-- | Getting peer's 'SockAddr'.
getPeerName :: Socket -> IO SockAddr
getPeerName = G.getPeerName

-- | Getting my 'SockAddr'.
getSocketName :: Socket -> IO SockAddr
getSocketName = G.getSocketName

-- | Connect to a remote socket at address.
connect :: Socket -> SockAddr -> IO ()
connect = G.connect

-- | Bind the socket to an address. The socket must not already be
-- bound.  The 'Family' passed to @bind@ must be the
-- same as that passed to 'socket'.  If the special port number
-- 'defaultPort' is passed then the system assigns the next available
-- use port.
bind :: Socket -> SockAddr -> IO ()
bind s a = case a of
  SockAddrUnix p -> do
    -- gracefully handle the fact that UNIX systems don't clean up closed UNIX
    -- domain sockets, inspired by https://stackoverflow.com/a/13719866
    res <- try (G.bind s a)
    case res of
      Right () -> return ()
      Left e | not (isAlreadyInUseError e) -> throwIO (e :: IOException)
      Left e | otherwise -> do
        -- socket might be in use, try to connect
        res2 <- try (G.connect s a)
        case res2 of
          Right () -> close s >> throwIO e
          Left e2 | not (isDoesNotExistError e2) -> throwIO (e2 :: IOException)
          _ -> do
            -- socket not actually in use, remove it and retry bind
            void (try $ removeFile p :: IO (Either IOError ()))
            G.bind s a
  _ -> G.bind s a

-- | Accept a connection.  The socket must be bound to an address and
-- listening for connections.  The return value is a pair @(conn,
-- address)@ where @conn@ is a new socket object usable to send and
-- receive data on the connection, and @address@ is the address bound
-- to the socket on the other end of the connection.
-- On Unix, FD_CLOEXEC is set to the new 'Socket'.
accept :: Socket -> IO (Socket, SockAddr)
accept = G.accept

-- | Send data to the socket.  The recipient can be specified
-- explicitly, so the socket need not be in a connected state.
-- Returns the number of bytes sent.  Applications are responsible for
-- ensuring that all data has been sent.
sendBufTo :: Socket -> Ptr a -> Int -> SockAddr -> IO Int
sendBufTo = G.sendBufTo

-- | Receive data from the socket, writing it into buffer instead of
-- creating a new string.  The socket need not be in a connected
-- state. Returns @(nbytes, address)@ where @nbytes@ is the number of
-- bytes received and @address@ is a 'SockAddr' representing the
-- address of the sending socket.
--
-- If the first return value is zero, it means EOF.
--
-- For 'Stream' sockets, the second return value would be invalid.
--
-- NOTE: blocking on Windows unless you compile with -threaded (see
-- GHC ticket #1129)
recvBufFrom :: Socket -> Ptr a -> Int -> IO (Int, SockAddr)
recvBufFrom = G.recvBufFrom

-- | Send data to the socket using sendmsg(2).
sendBufMsg :: Socket            -- ^ Socket
           -> SockAddr          -- ^ Destination address
           -> [(Ptr Word8,Int)] -- ^ Data to be sent
           -> [Cmsg]            -- ^ Control messages
           -> MsgFlag           -- ^ Message flags
           -> IO Int            -- ^ The length actually sent
sendBufMsg = G.sendBufMsg

-- | Receive data from the socket using recvmsg(2).
recvBufMsg :: Socket            -- ^ Socket
        -> [(Ptr Word8,Int)] -- ^ A list of a pair of buffer and its size.
                             --   If the total length is not large enough,
                             --   'MSG_TRUNC' is returned
        -> Int               -- ^ The buffer size for control messages.
                             --   If the length is not large enough,
                             --   'MSG_CTRUNC' is returned
        -> MsgFlag           -- ^ Message flags
        -> IO (SockAddr,Int,[Cmsg],MsgFlag) -- ^ Source address, received data, control messages and message flags
recvBufMsg = G.recvBufMsg
