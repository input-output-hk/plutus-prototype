{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE CPP #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}

module Network.Socket.Posix.Cmsg where

#include "HsNet.h"

#include <sys/types.h>
#include <sys/socket.h>

import Data.ByteString.Internal
import Foreign.ForeignPtr
import System.IO.Unsafe (unsafeDupablePerformIO)
import System.Posix.Types (Fd(..))

import Network.Socket.Imports
import Network.Socket.Types
import Network.Socket.ReadShow

import qualified Text.Read as P

-- | Control message (ancillary data) including a pair of level and type.
data Cmsg = Cmsg {
    cmsgId   :: !CmsgId
  , cmsgData :: !ByteString
  } deriving (Eq, Show)

----------------------------------------------------------------

-- | Identifier of control message (ancillary data).
data CmsgId = CmsgId {
    cmsgLevel :: !CInt
  , cmsgType  :: !CInt
  } deriving (Eq)

-- | Unsupported identifier
pattern UnsupportedCmsgId :: CmsgId
pattern UnsupportedCmsgId = CmsgId (-1) (-1)

-- | The identifier for 'IPv4TTL'.
pattern CmsgIdIPv4TTL :: CmsgId
#if defined(darwin_HOST_OS) || defined(freebsd_HOST_OS)
pattern CmsgIdIPv4TTL = CmsgId (#const IPPROTO_IP) (#const IP_RECVTTL)
#else
pattern CmsgIdIPv4TTL = CmsgId (#const IPPROTO_IP) (#const IP_TTL)
#endif

-- | The identifier for 'IPv6HopLimit'.
pattern CmsgIdIPv6HopLimit :: CmsgId
pattern CmsgIdIPv6HopLimit = CmsgId (#const IPPROTO_IPV6) (#const IPV6_HOPLIMIT)

-- | The identifier for 'IPv4TOS'.
pattern CmsgIdIPv4TOS :: CmsgId
#if defined(darwin_HOST_OS) || defined(freebsd_HOST_OS)
pattern CmsgIdIPv4TOS = CmsgId (#const IPPROTO_IP) (#const IP_RECVTOS)
#else
pattern CmsgIdIPv4TOS = CmsgId (#const IPPROTO_IP) (#const IP_TOS)
#endif

-- | The identifier for 'IPv6TClass'.
pattern CmsgIdIPv6TClass :: CmsgId
pattern CmsgIdIPv6TClass = CmsgId (#const IPPROTO_IPV6) (#const IPV6_TCLASS)

-- | The identifier for 'IPv4PktInfo'.
pattern CmsgIdIPv4PktInfo :: CmsgId
#if defined(IP_PKTINFO)
pattern CmsgIdIPv4PktInfo = CmsgId (#const IPPROTO_IP) (#const IP_PKTINFO)
#else
pattern CmsgIdIPv4PktInfo = CmsgId (-1) (-1)
#endif

-- | The identifier for 'IPv6PktInfo'.
pattern CmsgIdIPv6PktInfo :: CmsgId
#if defined(IPV6_PKTINFO)
pattern CmsgIdIPv6PktInfo = CmsgId (#const IPPROTO_IPV6) (#const IPV6_PKTINFO)
#else
pattern CmsgIdIPv6PktInfo = CmsgId (-1) (-1)
#endif

-- | The identifier for 'Fd'.
pattern CmsgIdFd :: CmsgId
pattern CmsgIdFd = CmsgId (#const SOL_SOCKET) (#const SCM_RIGHTS)

----------------------------------------------------------------

-- | Locate a control message of the given type in a list of control
--   messages. The following shows an example usage:
--
-- > (lookupCmsg CmsgIdIPv4TOS cmsgs >>= decodeCmsg) :: Maybe IPv4TOS
lookupCmsg :: CmsgId -> [Cmsg] -> Maybe Cmsg
lookupCmsg cid cmsgs = find (\cmsg -> cmsgId cmsg == cid) cmsgs

-- | Filtering control message.
filterCmsg :: CmsgId -> [Cmsg] -> [Cmsg]
filterCmsg cid cmsgs = filter (\cmsg -> cmsgId cmsg == cid) cmsgs

----------------------------------------------------------------

-- | Control message type class.
--   Each control message type has a numeric 'CmsgId' and a 'Storable'
--   data representation.
class Storable a => ControlMessage a where
    controlMessageId :: CmsgId

encodeCmsg :: forall a . ControlMessage a => a -> Cmsg
encodeCmsg x = unsafeDupablePerformIO $ do
    bs <- create siz $ \p0 -> do
        let p = castPtr p0
        poke p x
    let cmsid = controlMessageId @a
    return $ Cmsg cmsid bs
  where
    siz = sizeOf x

decodeCmsg :: forall a . (ControlMessage a, Storable a) => Cmsg -> Maybe a
decodeCmsg (Cmsg cmsid (PS fptr off len))
  | cid /= cmsid = Nothing
  | len < siz    = Nothing
  | otherwise    = unsafeDupablePerformIO $ withForeignPtr fptr $ \p0 -> do
        let p = castPtr (p0 `plusPtr` off)
        Just <$> peek p
  where
    cid = controlMessageId @a
    siz = sizeOf (undefined :: a)

----------------------------------------------------------------

-- | Time to live of IPv4.
#if defined(darwin_HOST_OS) || defined(freebsd_HOST_OS)
newtype IPv4TTL = IPv4TTL CChar deriving (Eq, Show, Storable)
#else
newtype IPv4TTL = IPv4TTL CInt deriving (Eq, Show, Storable)
#endif

instance ControlMessage IPv4TTL where
    controlMessageId = CmsgIdIPv4TTL

----------------------------------------------------------------

-- | Hop limit of IPv6.
newtype IPv6HopLimit = IPv6HopLimit CInt deriving (Eq, Show, Storable)

instance ControlMessage IPv6HopLimit where
    controlMessageId = CmsgIdIPv6HopLimit

----------------------------------------------------------------

-- | TOS of IPv4.
newtype IPv4TOS = IPv4TOS CChar deriving (Eq, Show, Storable)

instance ControlMessage IPv4TOS where
    controlMessageId = CmsgIdIPv4TOS

----------------------------------------------------------------

-- | Traffic class of IPv6.
newtype IPv6TClass = IPv6TClass CInt deriving (Eq, Show, Storable)

instance ControlMessage IPv6TClass where
    controlMessageId = CmsgIdIPv6TClass

----------------------------------------------------------------

-- | Network interface ID and local IPv4 address.
data IPv4PktInfo = IPv4PktInfo Int HostAddress HostAddress deriving (Eq)

instance Show IPv4PktInfo where
    show (IPv4PktInfo n sa ha) = "IPv4PktInfo " ++ show n ++ " " ++ show (hostAddressToTuple sa) ++ " " ++ show (hostAddressToTuple ha)

instance ControlMessage IPv4PktInfo where
    controlMessageId = CmsgIdIPv4PktInfo

instance Storable IPv4PktInfo where
#if defined (IP_PKTINFO)
    sizeOf    _ = (#size struct in_pktinfo)
    alignment _ = alignment (0 :: CInt)
    poke p (IPv4PktInfo n sa ha) = do
        (#poke struct in_pktinfo, ipi_ifindex)  p (fromIntegral n :: CInt)
        (#poke struct in_pktinfo, ipi_spec_dst) p sa
        (#poke struct in_pktinfo, ipi_addr)     p ha
    peek p = do
        n  <- (#peek struct in_pktinfo, ipi_ifindex)  p
        sa <- (#peek struct in_pktinfo, ipi_spec_dst) p
        ha <- (#peek struct in_pktinfo, ipi_addr)     p
        return $ IPv4PktInfo n sa ha
#else
    sizeOf    _ = 0
    alignment _ = 1
    poke _ _ = error "Unsupported control message type"
    peek _   = error "Unsupported control message type"
#endif

----------------------------------------------------------------

-- | Network interface ID and local IPv4 address.
data IPv6PktInfo = IPv6PktInfo Int HostAddress6 deriving (Eq)

instance Show IPv6PktInfo where
    show (IPv6PktInfo n ha6) = "IPv6PktInfo " ++ show n ++ " " ++ show (hostAddress6ToTuple ha6)

instance ControlMessage IPv6PktInfo where
    controlMessageId = CmsgIdIPv6PktInfo

instance Storable IPv6PktInfo where
#if defined (IPV6_PKTINFO)
    sizeOf    _ = (#size struct in6_pktinfo)
    alignment _ = alignment (0 :: CInt)
    poke p (IPv6PktInfo n ha6) = do
        (#poke struct in6_pktinfo, ipi6_ifindex) p (fromIntegral n :: CInt)
        (#poke struct in6_pktinfo, ipi6_addr)    p (In6Addr ha6)
    peek p = do
        In6Addr ha6 <- (#peek struct in6_pktinfo, ipi6_addr)    p
        n :: CInt   <- (#peek struct in6_pktinfo, ipi6_ifindex) p
        return $ IPv6PktInfo (fromIntegral n) ha6
#else
    sizeOf    _ = 0
    alignment _ = 1
    poke _ _ = error "Unsupported control message type"
    peek _   = error "Unsupported control message type"
#endif

----------------------------------------------------------------

instance ControlMessage Fd where
    controlMessageId = CmsgIdFd

cmsgIdBijection :: Bijection CmsgId String
cmsgIdBijection =
    [ (UnsupportedCmsgId, "UnsupportedCmsgId")
    , (CmsgIdIPv4TTL, "CmsgIdIPv4TTL")
    , (CmsgIdIPv6HopLimit, "CmsgIdIPv6HopLimit")
    , (CmsgIdIPv4TOS, "CmsgIdIPv4TOS")
    , (CmsgIdIPv6TClass, "CmsgIdIPv6TClass")
    , (CmsgIdIPv4PktInfo, "CmsgIdIPv4PktInfo")
    , (CmsgIdIPv6PktInfo, "CmsgIdIPv6PktInfo")
    , (CmsgIdFd, "CmsgIdFd")
    ]

instance Show CmsgId where
    showsPrec = bijectiveShow cmsgIdBijection def
      where
        defname = "CmsgId"
        unId = \(CmsgId l t) -> (l,t)
        def = defShow defname unId showIntInt

instance Read CmsgId where
    readPrec = bijectiveRead cmsgIdBijection def
      where
        defname = "CmsgId"
        def = defRead defname (uncurry CmsgId) readIntInt
