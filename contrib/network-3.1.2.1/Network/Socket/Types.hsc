{-# LANGUAGE CPP #-}
{-# LANGUAGE MagicHash, UnboxedTuples #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}

#include "HsNet.h"
##include "HsNetDef.h"

module Network.Socket.Types (
    -- * Socket type
      Socket
    , withFdSocket
    , unsafeFdSocket
    , touchSocket
    , socketToFd
    , fdSocket
    , mkSocket
    , invalidateSocket
    , close
    , close'
    , c_close
    -- * Types of socket
    , SocketType(GeneralSocketType, UnsupportedSocketType, NoSocketType
                , Stream, Datagram, Raw, RDM, SeqPacket)
    , isSupportedSocketType
    , packSocketType
    , unpackSocketType

    -- * Family
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

    -- * Socket address typeclass
    , SocketAddress(..)
    , withSocketAddress
    , withNewSocketAddress

    -- * Socket address type
    , SockAddr(..)
    , isSupportedSockAddr
    , HostAddress
    , hostAddressToTuple
    , tupleToHostAddress
    , HostAddress6
    , hostAddress6ToTuple
    , tupleToHostAddress6
    , FlowInfo
    , ScopeID
    , peekSockAddr
    , pokeSockAddr
    , withSockAddr

    -- * Unsorted
    , ProtocolNumber
    , defaultProtocol
    , PortNumber
    , defaultPort

    -- * Low-level helpers
    , zeroMemory
    , htonl
    , ntohl
    , In6Addr(..)
    ) where

import Data.IORef (IORef, newIORef, readIORef, atomicModifyIORef', mkWeakIORef)
import Foreign.C.Error (throwErrno)
import Foreign.Marshal.Alloc
import GHC.Conc (closeFdWith)
import System.Posix.Types (Fd)
import Control.DeepSeq (NFData (..))
import GHC.Exts (touch##)
import GHC.IORef (IORef (..))
import GHC.STRef (STRef (..))
import GHC.IO (IO (..))

import qualified Text.Read as P

#if defined(DOMAIN_SOCKET_SUPPORT)
import Foreign.Marshal.Array
#endif

import Network.Socket.Imports

----- readshow module import
import Network.Socket.ReadShow


-----------------------------------------------------------------------------

-- | Basic type for a socket.
data Socket = Socket !(IORef CInt) !CInt {- for Show -}

instance Show Socket where
    show (Socket _ ofd) = "<socket: " ++ show ofd ++ ">"

instance Eq Socket where
    Socket ref1 _ == Socket ref2 _ = ref1 == ref2

{-# DEPRECATED fdSocket "Use withFdSocket or unsafeFdSocket instead" #-}
-- | Currently, this is an alias of `unsafeFdSocket`.
fdSocket :: Socket -> IO CInt
fdSocket = unsafeFdSocket

-- | Getting a file descriptor from a socket.
--
--   If a 'Socket' is shared with multiple threads and
--   one uses 'unsafeFdSocket', unexpected issues may happen.
--   Consider the following scenario:
--
--   1) Thread A acquires a 'Fd' from 'Socket' by 'unsafeFdSocket'.
--
--   2) Thread B close the 'Socket'.
--
--   3) Thread C opens a new 'Socket'. Unfortunately it gets the same 'Fd'
--      number which thread A is holding.
--
--   In this case, it is safer for Thread A to clone 'Fd' by
--   'System.Posix.IO.dup'. But this would still suffer from
--   a race condition between 'unsafeFdSocket' and 'close'.
--
--   If you use this function, you need to guarantee that the 'Socket' does not
--   get garbage-collected until after you finish using the file descriptor.
--   'touchSocket' can be used for this purpose.
--
--   A safer option is to use 'withFdSocket' instead.
unsafeFdSocket :: Socket -> IO CInt
unsafeFdSocket (Socket ref _) = readIORef ref

-- | Ensure that the given 'Socket' stays alive (i.e. not garbage-collected)
--   at the given place in the sequence of IO actions. This function can be
--   used in conjunction with 'unsafeFdSocket' to guarantee that the file
--   descriptor is not prematurely freed.
--
-- > fd <- unsafeFdSocket sock
-- > -- using fd with blocking operations such as accept(2)
-- > touchSocket sock
touchSocket :: Socket -> IO ()
touchSocket (Socket ref _) = touch ref

touch :: IORef a -> IO ()
touch (IORef (STRef mutVar)) =
  -- Thanks to a GHC issue, this touch# may not be quite guaranteed
  -- to work. There's talk of replacing the touch# primop with one
  -- that works better with the optimizer. But this seems to be the
  -- "right" way to do it for now.
  IO $ \s -> (## touch## mutVar s, () ##)

-- | Get a file descriptor from a 'Socket'. The socket will never
-- be closed automatically before @withFdSocket@ completes, but
-- it may still be closed by an explicit call to 'close' or `close'`,
-- either before or during the call.
--
-- The file descriptor must not be used after @withFdSocket@ returns, because
-- the 'Socket' may have been garbage-collected, invalidating the file
-- descriptor.
--
-- Since: 3.1.0.0
withFdSocket :: Socket -> (CInt -> IO r) -> IO r
withFdSocket (Socket ref _) f = do
  fd <- readIORef ref
  -- Should we throw an exception if the socket is already invalid?
  -- That will catch some mistakes but certainly not all.

  r <- f fd

  touch ref
  return r

-- | Socket is closed and a duplicated file descriptor is returned.
--   The duplicated descriptor is no longer subject to the possibility
--   of unexpectedly being closed if the socket is finalized. It is
--   now the caller's responsibility to ultimately close the
--   duplicated file descriptor.
socketToFd :: Socket -> IO CInt
socketToFd s = do
#if defined(mingw32_HOST_OS)
    fd <- unsafeFdSocket s
    fd2 <- c_wsaDuplicate fd
    -- FIXME: throw error no if -1
    close s
    return fd2

foreign import ccall unsafe "wsaDuplicate"
   c_wsaDuplicate :: CInt -> IO CInt
#else
    fd <- unsafeFdSocket s
    -- FIXME: throw error no if -1
    fd2 <- c_dup fd
    close s
    return fd2

foreign import ccall unsafe "dup"
   c_dup :: CInt -> IO CInt
#endif

-- | Creating a socket from a file descriptor.
mkSocket :: CInt -> IO Socket
mkSocket fd = do
    ref <- newIORef fd
    let s = Socket ref fd
    void $ mkWeakIORef ref $ close s
    return s

invalidSocket :: CInt
#if defined(mingw32_HOST_OS)
invalidSocket = #const INVALID_SOCKET
#else
invalidSocket = -1
#endif

invalidateSocket ::
      Socket
   -> (CInt -> IO a)
   -> (CInt -> IO a)
   -> IO a
invalidateSocket (Socket ref _) errorAction normalAction = do
    oldfd <- atomicModifyIORef' ref $ \cur -> (invalidSocket, cur)
    if oldfd == invalidSocket then errorAction oldfd else normalAction oldfd

-----------------------------------------------------------------------------

-- | Close the socket. This function does not throw exceptions even if
--   the underlying system call returns errors.
--
--   If multiple threads use the same socket and one uses 'unsafeFdSocket' and
--   the other use 'close', unexpected behavior may happen.
--   For more information, please refer to the documentation of 'unsafeFdSocket'.
close :: Socket -> IO ()
close s = invalidateSocket s (\_ -> return ()) $ \oldfd -> do
    -- closeFdWith avoids the deadlock of IO manager.
    closeFdWith closeFd (toFd oldfd)
  where
    toFd :: CInt -> Fd
    toFd = fromIntegral
    -- closeFd ignores the return value of c_close and
    -- does not throw exceptions
    closeFd :: Fd -> IO ()
    closeFd = void . c_close . fromIntegral

-- | Close the socket. This function throws exceptions if
--   the underlying system call returns errors.
close' :: Socket -> IO ()
close' s = invalidateSocket s (\_ -> return ()) $ \oldfd -> do
    -- closeFdWith avoids the deadlock of IO manager.
    closeFdWith closeFd (toFd oldfd)
  where
    toFd :: CInt -> Fd
    toFd = fromIntegral
    closeFd :: Fd -> IO ()
    closeFd fd = do
        ret <- c_close $ fromIntegral fd
        when (ret == -1) $ throwErrno "Network.Socket.close'"

#if defined(mingw32_HOST_OS)
foreign import CALLCONV unsafe "closesocket"
  c_close :: CInt -> IO CInt
#else
foreign import ccall unsafe "close"
  c_close :: CInt -> IO CInt
#endif

-----------------------------------------------------------------------------

-- | Protocol number.
type ProtocolNumber = CInt

-- | This is the default protocol for a given service.
--
-- >>> defaultProtocol
-- 0
defaultProtocol :: ProtocolNumber
defaultProtocol = 0

-----------------------------------------------------------------------------
-- Socket types

-- There are a few possible ways to do this.  The first is convert the
-- structs used in the C library into an equivalent Haskell type. An
-- other possible implementation is to keep all the internals in the C
-- code and use an Int## and a status flag. The second method is used
-- here since a lot of the C structures are not required to be
-- manipulated.

-- Originally the status was non-mutable so we had to return a new
-- socket each time we changed the status.  This version now uses
-- mutable variables to avoid the need to do this.  The result is a
-- cleaner interface and better security since the application
-- programmer now can't circumvent the status information to perform
-- invalid operations on sockets.

-- | Socket Types.
--
-- Some of the defined patterns may be unsupported on some systems:
-- see 'isSupportedSocketType'.
newtype SocketType = SocketType { packSocketType :: CInt }
        deriving (Eq, Ord)

unpackSocketType :: CInt -> SocketType
unpackSocketType = SocketType
{-# INLINE unpackSocketType #-}

-- | Is the @SOCK_xxxxx@ constant corresponding to the given SocketType known
-- on this system?  'GeneralSocketType' values, not equal to any of the named
-- patterns or 'UnsupportedSocketType', will return 'True' even when not
-- known on this system.
isSupportedSocketType :: SocketType -> Bool
isSupportedSocketType = (/= UnsupportedSocketType)

-- | Pattern for a general socket type.
pattern GeneralSocketType    :: CInt -> SocketType
pattern GeneralSocketType n  =  SocketType n
#if __GLASGOW_HASKELL__ >= 806
{-# COMPLETE GeneralSocketType #-}
#endif
-- The actual constructor is not exported, which keeps the internal
-- representation private, but for all purposes other than 'coerce' the
-- above pattern is just as good.

-- | Unsupported socket type, equal to any other types not supported on this
-- system.
pattern UnsupportedSocketType :: SocketType
pattern UnsupportedSocketType  = SocketType (-1)

-- | Used in getAddrInfo hints, for example.
pattern NoSocketType        :: SocketType
pattern NoSocketType         = SocketType 0

pattern Stream              :: SocketType
#ifdef SOCK_STREAM
pattern Stream               = SocketType (#const SOCK_STREAM)
#else
pattern Stream               = (-1)
#endif

pattern Datagram            :: SocketType
#ifdef SOCK_DGRAM
pattern Datagram             = SocketType (#const SOCK_DGRAM)
#else
pattern Datagram             = (-1)
#endif

pattern Raw                 :: SocketType
#ifdef SOCK_RAW
pattern Raw                  = SocketType (#const SOCK_RAW)
#else
pattern Raw                  = (-1)
#endif

pattern RDM                 :: SocketType
#ifdef SOCK_RDM
pattern RDM                  = SocketType (#const SOCK_RDM)
#else
pattern RDM                  = (-1)
#endif

pattern SeqPacket           :: SocketType
#ifdef SOCK_SEQPACKET
pattern SeqPacket            = SocketType (#const SOCK_SEQPACKET)
#else
pattern SeqPacket            = (-1)
#endif

------------------------------------------------------------------------
-- Protocol Families.


-- | Address families.  The @AF_xxxxx@ constants are widely used as synonyms
-- for the corresponding @PF_xxxxx@ protocol family values, to which they are
-- numerically equal in mainstream socket API implementations.
--
-- Stictly correct usage would be to pass the @PF_xxxxx@ constants as the first
-- argument when creating a 'Socket', while the @AF_xxxxx@ constants should be
-- used as @addrFamily@ values with 'getAddrInfo'.  For now only the @AF_xxxxx@
-- constants are provided.
--
-- Some of the defined patterns may be unsupported on some systems:
-- see 'isSupportedFamily'.
newtype Family = Family { packFamily :: CInt } deriving (Eq, Ord)


-- | Does one of the AF_ constants correspond to a known address family on this
-- system.  'GeneralFamily' values, not equal to any of the named @AF_xxxxx@
-- patterns or 'UnsupportedFamily', will return 'True' even when not known on
-- this system.
isSupportedFamily :: Family -> Bool
isSupportedFamily f = case f of
    UnsupportedFamily -> False
    GeneralFamily _   -> True

-- | Convert 'CInt' to 'Family'.
unpackFamily :: CInt -> Family
unpackFamily = Family
{-# INLINE unpackFamily #-}

-- | Pattern for a general protocol family (a.k.a. address family).
--
-- @since 3.2.0.0
pattern GeneralFamily      :: CInt -> Family
pattern GeneralFamily n     = Family n
#if __GLASGOW_HASKELL__ >= 806
{-# COMPLETE GeneralFamily #-}
#endif
-- The actual constructor is not exported, which keeps the internal
-- representation private, but for all purposes other than 'coerce' the
-- above pattern is just as good.

-- | Unsupported address family, equal to any other families that are not
-- supported on the system.
--
-- @since 3.2.0.0
pattern UnsupportedFamily  :: Family
pattern UnsupportedFamily   = Family (-1)

-- | unspecified
pattern AF_UNSPEC          :: Family
pattern AF_UNSPEC           = Family (#const AF_UNSPEC)

-- | UNIX-domain
pattern AF_UNIX            :: Family
#ifdef AF_UNIX
pattern AF_UNIX             = Family (#const AF_UNIX)
#else
pattern AF_UNIX             = Family (-1)
#endif

-- | Internet Protocol version 4
pattern AF_INET            :: Family
#ifdef AF_INET
pattern AF_INET             = Family (#const AF_INET)
#else
pattern AF_INET             = Family (-1)
#endif

-- | Internet Protocol version 6
pattern AF_INET6           :: Family
#ifdef AF_INET6
pattern AF_INET6            = Family (#const AF_INET6)
#else
pattern AF_INET6            = Family (-1)
#endif

-- | Arpanet imp addresses
pattern AF_IMPLINK         :: Family
#ifdef AF_IMPLINK
pattern AF_IMPLINK          = Family (#const AF_IMPLINK)
#else
pattern AF_IMPLINK          = Family (-1)
#endif

-- | pup protocols: e.g. BSP
pattern AF_PUP             :: Family
#ifdef AF_PUP
pattern AF_PUP              = Family (#const AF_PUP)
#else
pattern AF_PUP              = Family (-1)
#endif

-- | mit CHAOS protocols
pattern AF_CHAOS           :: Family
#ifdef AF_CHAOS
pattern AF_CHAOS            = Family (#const AF_CHAOS)
#else
pattern AF_CHAOS            = Family (-1)
#endif

-- | XEROX NS protocols
pattern AF_NS              :: Family
#ifdef AF_NS
pattern AF_NS               = Family (#const AF_NS)
#else
pattern AF_NS               = Family (-1)
#endif

-- | nbs protocols
pattern AF_NBS             :: Family
#ifdef AF_NBS
pattern AF_NBS              = Family (#const AF_NBS)
#else
pattern AF_NBS              = Family (-1)
#endif

-- | european computer manufacturers
pattern AF_ECMA            :: Family
#ifdef AF_ECMA
pattern AF_ECMA             = Family (#const AF_ECMA)
#else
pattern AF_ECMA             = Family (-1)
#endif

-- | datakit protocols
pattern AF_DATAKIT         :: Family
#ifdef AF_DATAKIT
pattern AF_DATAKIT          = Family (#const AF_DATAKIT)
#else
pattern AF_DATAKIT          = Family (-1)
#endif

-- | CCITT protocols, X.25 etc
pattern AF_CCITT           :: Family
#ifdef AF_CCITT
pattern AF_CCITT            = Family (#const AF_CCITT)
#else
pattern AF_CCITT            = Family (-1)
#endif

-- | IBM SNA
pattern AF_SNA             :: Family
#ifdef AF_SNA
pattern AF_SNA              = Family (#const AF_SNA)
#else
pattern AF_SNA              = Family (-1)
#endif

-- | DECnet
pattern AF_DECnet          :: Family
#ifdef AF_DECnet
pattern AF_DECnet           = Family (#const AF_DECnet)
#else
pattern AF_DECnet           = Family (-1)
#endif

-- | Direct data link interface
pattern AF_DLI             :: Family
#ifdef AF_DLI
pattern AF_DLI              = Family (#const AF_DLI)
#else
pattern AF_DLI              = Family (-1)
#endif

-- | LAT
pattern AF_LAT             :: Family
#ifdef AF_LAT
pattern AF_LAT              = Family (#const AF_LAT)
#else
pattern AF_LAT              = Family (-1)
#endif

-- | NSC Hyperchannel
pattern AF_HYLINK          :: Family
#ifdef AF_HYLINK
pattern AF_HYLINK           = Family (#const AF_HYLINK)
#else
pattern AF_HYLINK           = Family (-1)
#endif

-- | Apple Talk
pattern AF_APPLETALK       :: Family
#ifdef AF_APPLETALK
pattern AF_APPLETALK        = Family (#const AF_APPLETALK)
#else
pattern AF_APPLETALK        = Family (-1)
#endif

-- | Internal Routing Protocol (aka AF_NETLINK)
pattern AF_ROUTE           :: Family
#ifdef AF_ROUTE
pattern AF_ROUTE            = Family (#const AF_ROUTE)
#else
pattern AF_ROUTE            = Family (-1)
#endif

-- | NetBios-style addresses
pattern AF_NETBIOS         :: Family
#ifdef AF_NETBIOS
pattern AF_NETBIOS          = Family (#const AF_NETBIOS)
#else
pattern AF_NETBIOS          = Family (-1)
#endif

-- | Network Interface Tap
pattern AF_NIT             :: Family
#ifdef AF_NIT
pattern AF_NIT              = Family (#const AF_NIT)
#else
pattern AF_NIT              = Family (-1)
#endif

-- | IEEE 802.2, also ISO 8802
pattern AF_802             :: Family
#ifdef AF_802
pattern AF_802              = Family (#const AF_802)
#else
pattern AF_802              = Family (-1)
#endif

-- | ISO protocols
pattern AF_ISO             :: Family
#ifdef AF_ISO
pattern AF_ISO              = Family (#const AF_ISO)
#else
pattern AF_ISO              = Family (-1)
#endif

-- | umbrella of all families used by OSI
pattern AF_OSI             :: Family
#ifdef AF_OSI
pattern AF_OSI              = Family (#const AF_OSI)
#else
pattern AF_OSI              = Family (-1)
#endif

-- | DNA Network Management
pattern AF_NETMAN          :: Family
#ifdef AF_NETMAN
pattern AF_NETMAN           = Family (#const AF_NETMAN)
#else
pattern AF_NETMAN           = Family (-1)
#endif

-- | CCITT X.25
pattern AF_X25             :: Family
#ifdef AF_X25
pattern AF_X25              = Family (#const AF_X25)
#else
pattern AF_X25              = Family (-1)
#endif

-- | AX25
pattern AF_AX25            :: Family
#ifdef AF_AX25
pattern AF_AX25             = Family (#const AF_AX25)
#else
pattern AF_AX25             = Family (-1)
#endif

-- | AFI
pattern AF_OSINET          :: Family
#ifdef AF_OSINET
pattern AF_OSINET           = Family (#const AF_OSINET)
#else
pattern AF_OSINET           = Family (-1)
#endif

-- | US Government OSI
pattern AF_GOSSIP          :: Family
#ifdef AF_GOSSIP
pattern AF_GOSSIP           = Family (#const AF_GOSSIP)
#else
pattern AF_GOSSIP           = Family (-1)
#endif

-- | Novell Internet Protocol
pattern AF_IPX             :: Family
#ifdef AF_IPX
pattern AF_IPX              = Family (#const AF_IPX)
#else
pattern AF_IPX              = Family (-1)
#endif

-- | eXpress Transfer Protocol (no AF)
pattern Pseudo_AF_XTP      :: Family
#ifdef Pseudo_AF_XTP
pattern Pseudo_AF_XTP       = Family (#const Pseudo_AF_XTP)
#else
pattern Pseudo_AF_XTP       = Family (-1)
#endif

-- | Common Trace Facility
pattern AF_CTF             :: Family
#ifdef AF_CTF
pattern AF_CTF              = Family (#const AF_CTF)
#else
pattern AF_CTF              = Family (-1)
#endif

-- | Wide Area Network protocols
pattern AF_WAN             :: Family
#ifdef AF_WAN
pattern AF_WAN              = Family (#const AF_WAN)
#else
pattern AF_WAN              = Family (-1)
#endif

-- | SGI Data Link for DLPI
pattern AF_SDL             :: Family
#ifdef AF_SDL
pattern AF_SDL              = Family (#const AF_SDL)
#else
pattern AF_SDL              = Family (-1)
#endif

-- | Netware
pattern AF_NETWARE         :: Family
#ifdef AF_NETWARE
pattern AF_NETWARE          = Family (#const AF_NETWARE)
#else
pattern AF_NETWARE          = Family (-1)
#endif

-- | NDD
pattern AF_NDD             :: Family
#ifdef AF_NDD
pattern AF_NDD              = Family (#const AF_NDD)
#else
pattern AF_NDD              = Family (-1)
#endif

-- | Debugging use only
pattern AF_INTF            :: Family
#ifdef AF_INTF
pattern AF_INTF             = Family (#const AF_INTF)
#else
pattern AF_INTF             = Family (-1)
#endif

-- | connection-oriented IP, aka ST II
pattern AF_COIP            :: Family
#ifdef AF_COIP
pattern AF_COIP             = Family (#const AF_COIP)
#else
pattern AF_COIP             = Family (-1)
#endif

-- | Computer Network Technology
pattern AF_CNT             :: Family
#ifdef AF_CNT
pattern AF_CNT              = Family (#const AF_CNT)
#else
pattern AF_CNT              = Family (-1)
#endif

-- | Help Identify RTIP packets
pattern Pseudo_AF_RTIP     :: Family
#ifdef Pseudo_AF_RTIP
pattern Pseudo_AF_RTIP      = Family (#const Pseudo_AF_RTIP)
#else
pattern Pseudo_AF_RTIP      = Family (-1)
#endif

-- | Help Identify PIP packets
pattern Pseudo_AF_PIP      :: Family
#ifdef Pseudo_AF_PIP
pattern Pseudo_AF_PIP       = Family (#const Pseudo_AF_PIP)
#else
pattern Pseudo_AF_PIP       = Family (-1)
#endif

-- | Simple Internet Protocol
pattern AF_SIP             :: Family
#ifdef AF_SIP
pattern AF_SIP              = Family (#const AF_SIP)
#else
pattern AF_SIP              = Family (-1)
#endif

-- | Integrated Services Digital Network
pattern AF_ISDN            :: Family
#ifdef AF_ISDN
pattern AF_ISDN             = Family (#const AF_ISDN)
#else
pattern AF_ISDN             = Family (-1)
#endif

-- | Internal key-management function
pattern Pseudo_AF_KEY      :: Family
#ifdef Pseudo_AF_KEY
pattern Pseudo_AF_KEY       = Family (#const Pseudo_AF_KEY)
#else
pattern Pseudo_AF_KEY       = Family (-1)
#endif

-- | native ATM access
pattern AF_NATM            :: Family
#ifdef AF_NATM
pattern AF_NATM             = Family (#const AF_NATM)
#else
pattern AF_NATM             = Family (-1)
#endif

-- | ARP (RFC 826)
pattern AF_ARP             :: Family
#ifdef AF_ARP
pattern AF_ARP              = Family (#const AF_ARP)
#else
pattern AF_ARP              = Family (-1)
#endif

-- | Used by BPF to not rewrite hdrs in iface output
pattern Pseudo_AF_HDRCMPLT :: Family
#ifdef Pseudo_AF_HDRCMPLT
pattern Pseudo_AF_HDRCMPLT  = Family (#const Pseudo_AF_HDRCMPLT)
#else
pattern Pseudo_AF_HDRCMPLT  = Family (-1)
#endif

-- | ENCAP
pattern AF_ENCAP           :: Family
#ifdef AF_ENCAP
pattern AF_ENCAP            = Family (#const AF_ENCAP)
#else
pattern AF_ENCAP            = Family (-1)
#endif

-- | Link layer interface
pattern AF_LINK            :: Family
#ifdef AF_LINK
pattern AF_LINK             = Family (#const AF_LINK)
#else
pattern AF_LINK             = Family (-1)
#endif

-- | Link layer interface
pattern AF_RAW             :: Family
#ifdef AF_RAW
pattern AF_RAW              = Family (#const AF_RAW)
#else
pattern AF_RAW              = Family (-1)
#endif

-- | raw interface
pattern AF_RIF             :: Family
#ifdef AF_RIF
pattern AF_RIF              = Family (#const AF_RIF)
#else
pattern AF_RIF              = Family (-1)
#endif

-- | Amateur radio NetROM
pattern AF_NETROM          :: Family
#ifdef AF_NETROM
pattern AF_NETROM           = Family (#const AF_NETROM)
#else
pattern AF_NETROM           = Family (-1)
#endif

-- | multiprotocol bridge
pattern AF_BRIDGE          :: Family
#ifdef AF_BRIDGE
pattern AF_BRIDGE           = Family (#const AF_BRIDGE)
#else
pattern AF_BRIDGE           = Family (-1)
#endif

-- | ATM PVCs
pattern AF_ATMPVC          :: Family
#ifdef AF_ATMPVC
pattern AF_ATMPVC           = Family (#const AF_ATMPVC)
#else
pattern AF_ATMPVC           = Family (-1)
#endif

-- | Amateur Radio X.25 PLP
pattern AF_ROSE            :: Family
#ifdef AF_ROSE
pattern AF_ROSE             = Family (#const AF_ROSE)
#else
pattern AF_ROSE             = Family (-1)
#endif

-- | Netbeui 802.2LLC
pattern AF_NETBEUI         :: Family
#ifdef AF_NETBEUI
pattern AF_NETBEUI          = Family (#const AF_NETBEUI)
#else
pattern AF_NETBEUI          = Family (-1)
#endif

-- | Security callback pseudo AF
pattern AF_SECURITY        :: Family
#ifdef AF_SECURITY
pattern AF_SECURITY         = Family (#const AF_SECURITY)
#else
pattern AF_SECURITY         = Family (-1)
#endif

-- | Packet family
pattern AF_PACKET          :: Family
#ifdef AF_PACKET
pattern AF_PACKET           = Family (#const AF_PACKET)
#else
pattern AF_PACKET           = Family (-1)
#endif

-- | Ash
pattern AF_ASH             :: Family
#ifdef AF_ASH
pattern AF_ASH              = Family (#const AF_ASH)
#else
pattern AF_ASH              = Family (-1)
#endif

-- | Acorn Econet
pattern AF_ECONET          :: Family
#ifdef AF_ECONET
pattern AF_ECONET           = Family (#const AF_ECONET)
#else
pattern AF_ECONET           = Family (-1)
#endif

-- | ATM SVCs
pattern AF_ATMSVC          :: Family
#ifdef AF_ATMSVC
pattern AF_ATMSVC           = Family (#const AF_ATMSVC)
#else
pattern AF_ATMSVC           = Family (-1)
#endif

-- | IRDA sockets
pattern AF_IRDA            :: Family
#ifdef AF_IRDA
pattern AF_IRDA             = Family (#const AF_IRDA)
#else
pattern AF_IRDA             = Family (-1)
#endif

-- | PPPoX sockets
pattern AF_PPPOX           :: Family
#ifdef AF_PPPOX
pattern AF_PPPOX            = Family (#const AF_PPPOX)
#else
pattern AF_PPPOX            = Family (-1)
#endif

-- | Wanpipe API sockets
pattern AF_WANPIPE         :: Family
#ifdef AF_WANPIPE
pattern AF_WANPIPE          = Family (#const AF_WANPIPE)
#else
pattern AF_WANPIPE          = Family (-1)
#endif

-- | bluetooth sockets
pattern AF_BLUETOOTH       :: Family
#ifdef AF_BLUETOOTH
pattern AF_BLUETOOTH        = Family (#const AF_BLUETOOTH)
#else
pattern AF_BLUETOOTH        = Family (-1)
#endif

-- | Controller Area Network
pattern AF_CAN             :: Family
#ifdef AF_CAN
pattern AF_CAN              = Family (#const AF_CAN)
#else
pattern AF_CAN              = Family (-1)
#endif

------------------------------------------------------------------------
-- Port Numbers

-- | Port number.
--   Use the @Num@ instance (i.e. use a literal) to create a
--   @PortNumber@ value.
--
-- >>> 1 :: PortNumber
-- 1
-- >>> read "1" :: PortNumber
-- 1
-- >>> show (12345 :: PortNumber)
-- "12345"
-- >>> 50000 < (51000 :: PortNumber)
-- True
-- >>> 50000 < (52000 :: PortNumber)
-- True
-- >>> 50000 + (10000 :: PortNumber)
-- 60000
newtype PortNumber = PortNum Word16 deriving (Eq, Ord, Num, Enum, Bounded, Real, Integral)

foreign import CALLCONV unsafe "ntohs" ntohs :: Word16 -> Word16
foreign import CALLCONV unsafe "htons" htons :: Word16 -> Word16
-- | Converts the from host byte order to network byte order.
foreign import CALLCONV unsafe "htonl" htonl :: Word32 -> Word32
-- | Converts the from network byte order to host byte order.
foreign import CALLCONV unsafe "ntohl" ntohl :: Word32 -> Word32
{-# DEPRECATED htonl "Use getAddrInfo instead" #-}
{-# DEPRECATED ntohl "Use getAddrInfo instead" #-}

instance Storable PortNumber where
   sizeOf    _ = sizeOf    (0 :: Word16)
   alignment _ = alignment (0 :: Word16)
   poke p (PortNum po) = poke (castPtr p) (htons po)
   peek p = PortNum . ntohs <$> peek (castPtr p)

-- | Default port number.
--
-- >>> defaultPort
-- 0
defaultPort :: PortNumber
defaultPort = 0

------------------------------------------------------------------------

-- | The core typeclass to unify socket addresses.
class SocketAddress sa where
    sizeOfSocketAddress :: sa -> Int
    peekSocketAddress :: Ptr sa -> IO sa
    pokeSocketAddress  :: Ptr a -> sa -> IO ()

-- sizeof(struct sockaddr_storage) which has enough space to contain
-- sockaddr_in, sockaddr_in6 and sockaddr_un.
sockaddrStorageLen :: Int
sockaddrStorageLen = 128

withSocketAddress :: SocketAddress sa => sa -> (Ptr sa -> Int -> IO a) -> IO a
withSocketAddress addr f = do
    let sz = sizeOfSocketAddress addr
    if sz == 0 then
        f nullPtr 0
      else
        allocaBytes sz $ \p -> pokeSocketAddress p addr >> f (castPtr p) sz

withNewSocketAddress :: SocketAddress sa => (Ptr sa -> Int -> IO a) -> IO a
withNewSocketAddress f = allocaBytes sockaddrStorageLen $ \ptr -> do
    zeroMemory ptr $ fromIntegral sockaddrStorageLen
    f ptr sockaddrStorageLen

------------------------------------------------------------------------
-- Socket addresses

-- The scheme used for addressing sockets is somewhat quirky. The
-- calls in the BSD socket API that need to know the socket address
-- all operate in terms of struct sockaddr, a `virtual' type of
-- socket address.

-- The Internet family of sockets are addressed as struct sockaddr_in,
-- so when calling functions that operate on struct sockaddr, we have
-- to type cast the Internet socket address into a struct sockaddr.
-- Instances of the structure for different families might *not* be
-- the same size. Same casting is required of other families of
-- sockets such as Xerox NS. Similarly for UNIX-domain sockets.

-- To represent these socket addresses in Haskell-land, we do what BSD
-- didn't do, and use a union/algebraic type for the different
-- families. Currently only UNIX-domain sockets and the Internet
-- families are supported.

-- | Flow information.
type FlowInfo = Word32
-- | Scope identifier.
type ScopeID = Word32

-- | Socket addresses.
--  The existence of a constructor does not necessarily imply that
--  that socket address type is supported on your system: see
-- 'isSupportedSockAddr'.
data SockAddr
  = SockAddrInet
        !PortNumber      -- sin_port
        !HostAddress     -- sin_addr  (ditto)
  | SockAddrInet6
        !PortNumber      -- sin6_port
        !FlowInfo        -- sin6_flowinfo (ditto)
        !HostAddress6    -- sin6_addr (ditto)
        !ScopeID         -- sin6_scope_id (ditto)
  -- | The path must have fewer than 104 characters. All of these characters must have code points less than 256.
  | SockAddrUnix
        String           -- sun_path
  deriving (Eq, Ord)

instance NFData SockAddr where
  rnf (SockAddrInet _ _) = ()
  rnf (SockAddrInet6 _ _ _ _) = ()
  rnf (SockAddrUnix str) = rnf str

-- | Is the socket address type supported on this system?
isSupportedSockAddr :: SockAddr -> Bool
isSupportedSockAddr addr = case addr of
  SockAddrInet{}  -> True
  SockAddrInet6{} -> True
#if defined(DOMAIN_SOCKET_SUPPORT)
  SockAddrUnix{}  -> True
#else
  SockAddrUnix{}  -> False
#endif

instance SocketAddress SockAddr where
    sizeOfSocketAddress = sizeOfSockAddr
    peekSocketAddress   = peekSockAddr
    pokeSocketAddress   = pokeSockAddr

#if defined(mingw32_HOST_OS)
type CSaFamily = (#type unsigned short)
#elif defined(darwin_HOST_OS)
type CSaFamily = (#type u_char)
#else
type CSaFamily = (#type sa_family_t)
#endif

-- | Computes the storage requirements (in bytes) of the given
-- 'SockAddr'.  This function differs from 'Foreign.Storable.sizeOf'
-- in that the value of the argument /is/ used.
sizeOfSockAddr :: SockAddr -> Int
#if defined(DOMAIN_SOCKET_SUPPORT)
# ifdef linux_HOST_OS
-- http://man7.org/linux/man-pages/man7/unix.7.html says:
-- "an abstract socket address is distinguished (from a
-- pathname socket) by the fact that sun_path[0] is a null byte
-- ('\0').  The socket's address in this namespace is given by the
-- additional bytes in sun_path that are covered by the specified
-- length of the address structure.  (Null bytes in the name have no
-- special significance.)  The name has no connection with filesystem
-- pathnames.  When the address of an abstract socket is returned,
-- the returned addrlen is greater than sizeof(sa_family_t) (i.e.,
-- greater than 2), and the name of the socket is contained in the
-- first (addrlen - sizeof(sa_family_t)) bytes of sun_path."
sizeOfSockAddr (SockAddrUnix path) =
    case path of
        '\0':_ -> (#const sizeof(sa_family_t)) + length path
        _      -> #const sizeof(struct sockaddr_un)
# else
sizeOfSockAddr SockAddrUnix{}  = #const sizeof(struct sockaddr_un)
# endif
#else
sizeOfSockAddr SockAddrUnix{}  = error "sizeOfSockAddr: not supported"
#endif
sizeOfSockAddr SockAddrInet{}  = #const sizeof(struct sockaddr_in)
sizeOfSockAddr SockAddrInet6{} = #const sizeof(struct sockaddr_in6)

-- | Use a 'SockAddr' with a function requiring a pointer to a
-- 'SockAddr' and the length of that 'SockAddr'.
withSockAddr :: SockAddr -> (Ptr SockAddr -> Int -> IO a) -> IO a
withSockAddr addr f = do
    let sz = sizeOfSockAddr addr
    allocaBytes sz $ \p -> pokeSockAddr p addr >> f (castPtr p) sz

-- We cannot bind sun_paths longer than than the space in the sockaddr_un
-- structure, and attempting to do so could overflow the allocated storage
-- space.  This constant holds the maximum allowable path length.
--
#if defined(DOMAIN_SOCKET_SUPPORT)
unixPathMax :: Int
unixPathMax = #const sizeof(((struct sockaddr_un *)NULL)->sun_path)
#endif

-- We can't write an instance of 'Storable' for 'SockAddr' because
-- @sockaddr@ is a sum type of variable size but
-- 'Foreign.Storable.sizeOf' is required to be constant.

-- Note that on Darwin, the sockaddr structure must be zeroed before
-- use.

-- | Write the given 'SockAddr' to the given memory location.
pokeSockAddr :: Ptr a -> SockAddr -> IO ()
#if defined(DOMAIN_SOCKET_SUPPORT)
pokeSockAddr p sa@(SockAddrUnix path) = do
    when (length path > unixPathMax) $ error "pokeSockAddr: path is too long"
    zeroMemory p $ fromIntegral $ sizeOfSockAddr sa
# if defined(HAVE_STRUCT_SOCKADDR_SA_LEN)
    (#poke struct sockaddr_un, sun_len) p ((#const sizeof(struct sockaddr_un)) :: Word8)
# endif
    (#poke struct sockaddr_un, sun_family) p ((#const AF_UNIX) :: CSaFamily)
    let pathC = map castCharToCChar path
    -- the buffer is already filled with nulls.
    pokeArray ((#ptr struct sockaddr_un, sun_path) p) pathC
#else
pokeSockAddr _ SockAddrUnix{} = error "pokeSockAddr: not supported"
#endif
pokeSockAddr p (SockAddrInet port addr) = do
    zeroMemory p (#const sizeof(struct sockaddr_in))
#if defined(HAVE_STRUCT_SOCKADDR_SA_LEN)
    (#poke struct sockaddr_in, sin_len) p ((#const sizeof(struct sockaddr_in)) :: Word8)
#endif
    (#poke struct sockaddr_in, sin_family) p ((#const AF_INET) :: CSaFamily)
    (#poke struct sockaddr_in, sin_port) p port
    (#poke struct sockaddr_in, sin_addr) p addr
pokeSockAddr p (SockAddrInet6 port flow addr scope) = do
    zeroMemory p (#const sizeof(struct sockaddr_in6))
# if defined(HAVE_STRUCT_SOCKADDR_SA_LEN)
    (#poke struct sockaddr_in6, sin6_len) p ((#const sizeof(struct sockaddr_in6)) :: Word8)
# endif
    (#poke struct sockaddr_in6, sin6_family) p ((#const AF_INET6) :: CSaFamily)
    (#poke struct sockaddr_in6, sin6_port) p port
    (#poke struct sockaddr_in6, sin6_flowinfo) p flow
    (#poke struct sockaddr_in6, sin6_addr) p (In6Addr addr)
    (#poke struct sockaddr_in6, sin6_scope_id) p scope

-- | Read a 'SockAddr' from the given memory location.
peekSockAddr :: Ptr SockAddr -> IO SockAddr
peekSockAddr p = do
  family <- (#peek struct sockaddr, sa_family) p
  case family :: CSaFamily of
#if defined(DOMAIN_SOCKET_SUPPORT)
    (#const AF_UNIX) -> do
        str <- peekCAString ((#ptr struct sockaddr_un, sun_path) p)
        return (SockAddrUnix str)
#endif
    (#const AF_INET) -> do
        addr <- (#peek struct sockaddr_in, sin_addr) p
        port <- (#peek struct sockaddr_in, sin_port) p
        return (SockAddrInet port addr)
    (#const AF_INET6) -> do
        port <- (#peek struct sockaddr_in6, sin6_port) p
        flow <- (#peek struct sockaddr_in6, sin6_flowinfo) p
        In6Addr addr <- (#peek struct sockaddr_in6, sin6_addr) p
        scope <- (#peek struct sockaddr_in6, sin6_scope_id) p
        return (SockAddrInet6 port flow addr scope)
    _ -> ioError $ userError $
      "Network.Socket.Types.peekSockAddr: address family '" ++
      show family ++ "' not supported."

------------------------------------------------------------------------

-- | The raw network byte order number is read using host byte order.
-- Therefore on little-endian architectures the byte order is swapped. For
-- example @127.0.0.1@ is represented as @0x0100007f@ on little-endian hosts
-- and as @0x7f000001@ on big-endian hosts.
--
-- For direct manipulation prefer 'hostAddressToTuple' and
-- 'tupleToHostAddress'.
type HostAddress = Word32

-- | Converts 'HostAddress' to representation-independent IPv4 quadruple.
-- For example for @127.0.0.1@ the function will return @(0x7f, 0, 0, 1)@
-- regardless of host endianness.
--
{- -- prop> tow == hostAddressToTuple (tupleToHostAddress tow) -}
hostAddressToTuple :: HostAddress -> (Word8, Word8, Word8, Word8)
hostAddressToTuple ha' =
    let ha = htonl ha'
        byte i = fromIntegral (ha `shiftR` i) :: Word8
    in (byte 24, byte 16, byte 8, byte 0)

-- | Converts IPv4 quadruple to 'HostAddress'.
tupleToHostAddress :: (Word8, Word8, Word8, Word8) -> HostAddress
tupleToHostAddress (b3, b2, b1, b0) =
    let x `sl` i = fromIntegral x `shiftL` i :: Word32
    in ntohl $ (b3 `sl` 24) .|. (b2 `sl` 16) .|. (b1 `sl` 8) .|. (b0 `sl` 0)

-- | Independent of endianness. For example @::1@ is stored as @(0, 0, 0, 1)@.
--
-- For direct manipulation prefer 'hostAddress6ToTuple' and
-- 'tupleToHostAddress6'.
type HostAddress6 = (Word32, Word32, Word32, Word32)

-- | Converts 'HostAddress6' to representation-independent IPv6 octuple.
--
{- -- prop> (w1,w2,w3,w4,w5,w6,w7,w8) == hostAddress6ToTuple (tupleToHostAddress6 (w1,w2,w3,w4,w5,w6,w7,w8)) -}
hostAddress6ToTuple :: HostAddress6 -> (Word16, Word16, Word16, Word16,
                                        Word16, Word16, Word16, Word16)
hostAddress6ToTuple (w3, w2, w1, w0) =
    let high, low :: Word32 -> Word16
        high w = fromIntegral (w `shiftR` 16)
        low w = fromIntegral w
    in (high w3, low w3, high w2, low w2, high w1, low w1, high w0, low w0)

-- | Converts IPv6 octuple to 'HostAddress6'.
tupleToHostAddress6 :: (Word16, Word16, Word16, Word16,
                        Word16, Word16, Word16, Word16) -> HostAddress6
tupleToHostAddress6 (w7, w6, w5, w4, w3, w2, w1, w0) =
    let add :: Word16 -> Word16 -> Word32
        high `add` low = (fromIntegral high `shiftL` 16) .|. (fromIntegral low)
    in (w7 `add` w6, w5 `add` w4, w3 `add` w2, w1 `add` w0)

-- The peek32 and poke32 functions work around the fact that the RFCs
-- don't require 32-bit-wide address fields to be present.  We can
-- only portably rely on an 8-bit field, s6_addr.

s6_addr_offset :: Int
s6_addr_offset = (#offset struct in6_addr, s6_addr)

peek32 :: Ptr a -> Int -> IO Word32
peek32 p i0 = do
    let i' = i0 * 4
        peekByte n = peekByteOff p (s6_addr_offset + i' + n) :: IO Word8
        a `sl` i = fromIntegral a `shiftL` i
    a0 <- peekByte 0
    a1 <- peekByte 1
    a2 <- peekByte 2
    a3 <- peekByte 3
    return ((a0 `sl` 24) .|. (a1 `sl` 16) .|. (a2 `sl` 8) .|. (a3 `sl` 0))

poke32 :: Ptr a -> Int -> Word32 -> IO ()
poke32 p i0 a = do
    let i' = i0 * 4
        pokeByte n = pokeByteOff p (s6_addr_offset + i' + n)
        x `sr` i = fromIntegral (x `shiftR` i) :: Word8
    pokeByte 0 (a `sr` 24)
    pokeByte 1 (a `sr` 16)
    pokeByte 2 (a `sr`  8)
    pokeByte 3 (a `sr`  0)

-- | Private newtype proxy for the Storable instance. To avoid orphan instances.
newtype In6Addr = In6Addr HostAddress6

#if __GLASGOW_HASKELL__ < 800
#let alignment t = "%lu", (unsigned long)offsetof(struct {char x__; t (y__); }, y__)
#endif

instance Storable In6Addr where
    sizeOf    _ = #const sizeof(struct in6_addr)
    alignment _ = #alignment struct in6_addr

    peek p = do
        a <- peek32 p 0
        b <- peek32 p 1
        c <- peek32 p 2
        d <- peek32 p 3
        return $ In6Addr (a, b, c, d)

    poke p (In6Addr (a, b, c, d)) = do
        poke32 p 0 a
        poke32 p 1 b
        poke32 p 2 c
        poke32 p 3 d

------------------------------------------------------------------------
-- Read and Show instance for pattern-based integral newtypes

socktypeBijection :: Bijection SocketType String
socktypeBijection =
    [ (UnsupportedSocketType, "UnsupportedSocketType")
    , (Stream, "Stream")
    , (Datagram, "Datagram") 
    , (Raw, "Raw")
    , (RDM, "RDM")
    , (SeqPacket, "SeqPacket")
    , (NoSocketType, "NoSocketType")
    ]

instance Show SocketType where
    showsPrec = bijectiveShow socktypeBijection def
      where
        gst = "GeneralSocketType"
        def = defShow gst packSocketType _showInt

instance Read SocketType where
    readPrec = bijectiveRead socktypeBijection def
      where
        gst = "GeneralSocketType"
        def = defRead gst unpackSocketType _readInt

familyBijection :: Bijection Family String
familyBijection =
    [ (UnsupportedFamily, "UnsupportedFamily")
    , (AF_UNSPEC, "AF_UNSPEC")
    , (AF_UNIX, "AF_UNIX")
    , (AF_INET, "AF_INET")
    , (AF_INET6, "AF_INET6")
    , (AF_IMPLINK, "AF_IMPLINK")
    , (AF_PUP, "AF_PUP")
    , (AF_CHAOS, "AF_CHAOS")
    , (AF_NS, "AF_NS")
    , (AF_NBS, "AF_NBS")
    , (AF_ECMA, "AF_ECMA")
    , (AF_DATAKIT, "AF_DATAKIT")
    , (AF_CCITT, "AF_CCITT")
    , (AF_SNA, "AF_SNA")
    , (AF_DECnet, "AF_DECnet")
    , (AF_DLI, "AF_DLI")
    , (AF_LAT, "AF_LAT")
    , (AF_HYLINK, "AF_HYLINK")
    , (AF_APPLETALK, "AF_APPLETALK")
    , (AF_ROUTE, "AF_ROUTE")
    , (AF_NETBIOS, "AF_NETBIOS")
    , (AF_NIT, "AF_NIT")
    , (AF_802, "AF_802")
    , (AF_ISO, "AF_ISO")
    , (AF_OSI, "AF_OSI")
    , (AF_NETMAN, "AF_NETMAN")
    , (AF_X25, "AF_X25")
    , (AF_AX25, "AF_AX25")
    , (AF_OSINET, "AF_OSINET")
    , (AF_GOSSIP, "AF_GOSSIP")
    , (AF_IPX, "AF_IPX")
    , (Pseudo_AF_XTP, "Pseudo_AF_XTP")
    , (AF_CTF, "AF_CTF")
    , (AF_WAN, "AF_WAN")
    , (AF_SDL, "AF_SDL")
    , (AF_NETWARE, "AF_NETWARE")
    , (AF_NDD, "AF_NDD")
    , (AF_INTF, "AF_INTF")
    , (AF_COIP, "AF_COIP")
    , (AF_CNT, "AF_CNT")
    , (Pseudo_AF_RTIP, "Pseudo_AF_RTIP")
    , (Pseudo_AF_PIP, "Pseudo_AF_PIP")
    , (AF_SIP, "AF_SIP")
    , (AF_ISDN, "AF_ISDN")
    , (Pseudo_AF_KEY, "Pseudo_AF_KEY")
    , (AF_NATM, "AF_NATM")
    , (AF_ARP, "AF_ARP")
    , (Pseudo_AF_HDRCMPLT, "Pseudo_AF_HDRCMPLT")
    , (AF_ENCAP, "AF_ENCAP")
    , (AF_LINK, "AF_LINK")
    , (AF_RAW, "AF_RAW")
    , (AF_RIF, "AF_RIF")
    , (AF_NETROM, "AF_NETROM")
    , (AF_BRIDGE, "AF_BRIDGE")
    , (AF_ATMPVC, "AF_ATMPVC")
    , (AF_ROSE, "AF_ROSE")
    , (AF_NETBEUI, "AF_NETBEUI")
    , (AF_SECURITY, "AF_SECURITY")
    , (AF_PACKET, "AF_PACKET")
    , (AF_ASH, "AF_ASH")
    , (AF_ECONET, "AF_ECONET")
    , (AF_ATMSVC, "AF_ATMSVC")
    , (AF_IRDA, "AF_IRDA")
    , (AF_PPPOX, "AF_PPPOX")
    , (AF_WANPIPE, "AF_WANPIPE")
    , (AF_BLUETOOTH, "AF_BLUETOOTH")
    , (AF_CAN, "AF_CAN")
    ]

instance Show Family where
    showsPrec = bijectiveShow familyBijection def
      where
        gf = "GeneralFamily"
        def = defShow gf packFamily _showInt

instance Read Family where
    readPrec = bijectiveRead familyBijection def
      where
        gf = "GeneralFamily"
        def = defRead gf unpackFamily _readInt

-- Print "n" instead of "PortNum n".
instance Show PortNumber where
  showsPrec p (PortNum pn) = showsPrec p pn

-- Read "n" instead of "PortNum n".
instance Read PortNumber where
  readPrec = safeInt

------------------------------------------------------------------------
-- Helper functions

foreign import ccall unsafe "string.h" memset :: Ptr a -> CInt -> CSize -> IO ()

-- | Zero a structure.
zeroMemory :: Ptr a -> CSize -> IO ()
zeroMemory dest nbytes = memset dest 0 (fromIntegral nbytes)
