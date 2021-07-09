{-# LANGUAGE CPP #-}

#include "HsNetDef.h"

-----------------------------------------------------------------------------
-- |
-- Module      :  Network.Socket
-- Copyright   :  (c) The University of Glasgow 2001
-- License     :  BSD-style (see the file libraries/network/LICENSE)
--
-- Maintainer  :  libraries@haskell.org
-- Stability   :  provisional
-- Portability :  portable
--
-- This is the main module of the network package supposed to be
-- used with either "Network.Socket.ByteString" or
-- "Network.Socket.ByteString.Lazy" for sending/receiving.
--
-- Here are two minimal example programs using the TCP/IP protocol:
--
-- * a server that echoes all data that it receives back
-- * a client using it
--
-- > -- Echo server program
-- > module Main (main) where
-- >
-- > import Control.Concurrent (forkFinally)
-- > import qualified Control.Exception as E
-- > import Control.Monad (unless, forever, void)
-- > import qualified Data.ByteString as S
-- > import Network.Socket
-- > import Network.Socket.ByteString (recv, sendAll)
-- >
-- > main :: IO ()
-- > main = runTCPServer Nothing "3000" talk
-- >   where
-- >     talk s = do
-- >         msg <- recv s 1024
-- >         unless (S.null msg) $ do
-- >           sendAll s msg
-- >           talk s
-- >
-- > -- from the "network-run" package.
-- > runTCPServer :: Maybe HostName -> ServiceName -> (Socket -> IO a) -> IO a
-- > runTCPServer mhost port server = withSocketsDo $ do
-- >     addr <- resolve
-- >     E.bracket (open addr) close loop
-- >   where
-- >     resolve = do
-- >         let hints = defaultHints {
-- >                 addrFlags = [AI_PASSIVE]
-- >               , addrSocketType = Stream
-- >               }
-- >         head <$> getAddrInfo (Just hints) mhost (Just port)
-- >     open addr = E.bracketOnError (openSocket addr) close $ \sock -> do
-- >         setSocketOption sock ReuseAddr 1
-- >         withFdSocket sock setCloseOnExecIfNeeded
-- >         bind sock $ addrAddress addr
-- >         listen sock 1024
-- >         return sock
-- >     loop sock = forever $ E.bracketOnError (accept sock) (close . fst)
-- >         $ \(conn, _peer) -> void $
-- >             -- 'forkFinally' alone is unlikely to fail thus leaking @conn@,
-- >             -- but 'E.bracketOnError' above will be necessary if some
-- >             -- non-atomic setups (e.g. spawning a subprocess to handle
-- >             -- @conn@) before proper cleanup of @conn@ is your case
-- >             forkFinally (server conn) (const $ gracefulClose conn 5000)
--
-- > {-# LANGUAGE OverloadedStrings #-}
-- > -- Echo client program
-- > module Main (main) where
-- >
-- > import qualified Control.Exception as E
-- > import qualified Data.ByteString.Char8 as C
-- > import Network.Socket
-- > import Network.Socket.ByteString (recv, sendAll)
-- >
-- > main :: IO ()
-- > main = runTCPClient "127.0.0.1" "3000" $ \s -> do
-- >     sendAll s "Hello, world!"
-- >     msg <- recv s 1024
-- >     putStr "Received: "
-- >     C.putStrLn msg
-- >
-- > -- from the "network-run" package.
-- > runTCPClient :: HostName -> ServiceName -> (Socket -> IO a) -> IO a
-- > runTCPClient host port client = withSocketsDo $ do
-- >     addr <- resolve
-- >     E.bracket (open addr) close client
-- >   where
-- >     resolve = do
-- >         let hints = defaultHints { addrSocketType = Stream }
-- >         head <$> getAddrInfo (Just hints) (Just host) (Just port)
-- >     open addr = E.bracketOnError (openSocket addr) close $ \sock -> do
-- >         connect sock $ addrAddress addr
-- >         return sock
--
-- The proper programming model is that one 'Socket' is handled by
-- a single thread. If multiple threads use one 'Socket' concurrently,
-- unexpected things would happen. There is one exception for multiple
-- threads vs a single 'Socket': one thread reads data from a 'Socket'
-- only and the other thread writes data to the 'Socket' only.
-----------------------------------------------------------------------------

-- In order to process this file, you need to have CALLCONV defined.

module Network.Socket
    (
    -- * Initialisation
      withSocketsDo

    -- * Address information
    , getAddrInfo
    -- ** Types
    , HostName
    , ServiceName
    , AddrInfo(..)
    , defaultHints
    -- ** Flags
    , AddrInfoFlag(..)
    , addrInfoFlagImplemented

    -- * Socket operations
    , connect
    , bind
    , listen
    , accept
    -- ** Closing
    , close
    , close'
    , gracefulClose
    , shutdown
    , ShutdownCmd(..)

    -- * Socket options
    , SocketOption(SockOpt
                  ,UnsupportedSocketOption
                  ,Debug,ReuseAddr,SoDomain,Type,SoProtocol,SoError,DontRoute
                  ,Broadcast,SendBuffer,RecvBuffer,KeepAlive,OOBInline
                  ,TimeToLive,MaxSegment,NoDelay,Cork,Linger,ReusePort
                  ,RecvLowWater,SendLowWater,RecvTimeOut,SendTimeOut
                  ,UseLoopBack,UserTimeout,IPv6Only
                  ,RecvIPv4TTL,RecvIPv4TOS,RecvIPv4PktInfo
                  ,RecvIPv6HopLimit,RecvIPv6TClass,RecvIPv6PktInfo)
    , isSupportedSocketOption
    , whenSupported
    , getSocketOption
    , setSocketOption
    , getSockOpt
    , setSockOpt

    -- * Socket
    , Socket
    , socket
    , openSocket
    , withFdSocket
    , unsafeFdSocket
    , touchSocket
    , socketToFd
    , fdSocket
    , mkSocket
    , socketToHandle
    -- ** Types of Socket
    , SocketType(GeneralSocketType, UnsupportedSocketType, NoSocketType
                , Stream, Datagram, Raw, RDM, SeqPacket)
    , isSupportedSocketType
    , getSocketType
    -- ** Family
    , Family(GeneralFamily, UnsupportedFamily
            ,AF_UNSPEC,AF_UNIX,AF_INET,AF_INET6,AF_IMPLINK,AF_PUP,AF_CHAOS
            ,AF_NS,AF_NBS,AF_ECMA,AF_DATAKIT,AF_CCITT,AF_SNA,AF_DECnet
            ,AF_DLI,AF_LAT,AF_HYLINK,AF_APPLETALK,AF_ROUTE,AF_NETBIOS
            ,AF_NIT,AF_802,AF_ISO,AF_OSI,AF_NETMAN,AF_X25,AF_AX25,AF_OSINET
            ,AF_GOSSIP,AF_IPX,Pseudo_AF_XTP,AF_CTF,AF_WAN,AF_SDL,AF_NETWARE
            ,AF_NDD,AF_INTF,AF_COIP,AF_CNT,Pseudo_AF_RTIP,Pseudo_AF_PIP
            ,AF_SIP,AF_ISDN,Pseudo_AF_KEY,AF_NATM,AF_ARP,Pseudo_AF_HDRCMPLT
            ,AF_ENCAP,AF_LINK,AF_RAW,AF_RIF,AF_NETROM,AF_BRIDGE,AF_ATMPVC
            ,AF_ROSE,AF_NETBEUI,AF_SECURITY,AF_PACKET,AF_ASH,AF_ECONET
            ,AF_ATMSVC,AF_IRDA,AF_PPPOX,AF_WANPIPE,AF_BLUETOOTH,AF_CAN)
    , isSupportedFamily
    , packFamily
    , unpackFamily
    -- ** Protocol number
    , ProtocolNumber
    , defaultProtocol
    -- * Basic socket address type
    , SockAddr(..)
    , isSupportedSockAddr
    , getPeerName
    , getSocketName
    -- ** Host address
    , HostAddress
    , hostAddressToTuple
    , tupleToHostAddress
    -- ** Host address6
    , HostAddress6
    , hostAddress6ToTuple
    , tupleToHostAddress6
    -- ** Flow Info
    , FlowInfo
    -- ** Scope ID
    , ScopeID
    , ifNameToIndex
    , ifIndexToName
    -- ** Port number
    , PortNumber
    , defaultPort
    , socketPortSafe
    , socketPort

    -- * UNIX-domain socket
    , isUnixDomainSocketAvailable
    , socketPair
    , sendFd
    , recvFd
    , getPeerCredential

    -- * Name information
    , getNameInfo
    , NameInfoFlag(..)

    -- * Low level
    -- ** socket operations
    , setCloseOnExecIfNeeded
    , getCloseOnExec
    , setNonBlockIfNeeded
    , getNonBlock
    -- ** Sending and receiving data
    , sendBuf
    , recvBuf
    , sendBufTo
    , recvBufFrom
    -- ** Advanced IO
    , sendBufMsg
    , recvBufMsg
    , MsgFlag(MSG_OOB,MSG_DONTROUTE,MSG_PEEK,MSG_EOR,MSG_TRUNC,MSG_CTRUNC,MSG_WAITALL)
    -- ** Control message (ancillary data)
    , Cmsg(..)
    , CmsgId(CmsgId
            ,CmsgIdIPv4TTL
            ,CmsgIdIPv6HopLimit
            ,CmsgIdIPv4TOS
            ,CmsgIdIPv6TClass
            ,CmsgIdIPv4PktInfo
            ,CmsgIdIPv6PktInfo
            ,CmsgIdFd
            ,UnsupportedCmsgId)
    -- ** APIs for control message
    , lookupCmsg
    , filterCmsg
    , decodeCmsg
    , encodeCmsg
    -- ** Class and types for control message
    , ControlMessage(..)
    , IPv4TTL(..)
    , IPv6HopLimit(..)
    , IPv4TOS(..)
    , IPv6TClass(..)
    , IPv4PktInfo(..)
    , IPv6PktInfo(..)
    -- * Special constants
    , maxListenQueue
    ) where

import Network.Socket.Buffer hiding (sendBufTo, recvBufFrom, sendBufMsg, recvBufMsg)
import Network.Socket.Cbits
import Network.Socket.Fcntl
import Network.Socket.Flag
import Network.Socket.Handle
import Network.Socket.If
import Network.Socket.Info
import Network.Socket.Internal
import Network.Socket.Name hiding (getPeerName, getSocketName)
import Network.Socket.Options
import Network.Socket.Shutdown
import Network.Socket.SockAddr
import Network.Socket.Syscall hiding (connect, bind, accept)
import Network.Socket.Types
import Network.Socket.Unix
#if !defined(mingw32_HOST_OS)
import Network.Socket.Posix.Cmsg
#else
import Network.Socket.Win32.Cmsg
#endif
