{-# OPTIONS_GHC -funbox-strict-fields #-}

#include "HsNet.h"

module Network.Socket.Win32.CmsgHdr (
    Cmsg(..)
  , withCmsgs
  , parseCmsgs
  ) where

import Foreign.Marshal.Alloc (allocaBytes)
import Foreign.ForeignPtr
import qualified Data.ByteString as B
import Data.ByteString.Internal

import Network.Socket.Imports
import Network.Socket.Win32.Cmsg
import Network.Socket.Win32.MsgHdr
import Network.Socket.Types

data CmsgHdr = CmsgHdr {
    cmsgHdrLen   :: !CUInt
  , cmsgHdrLevel :: !CInt
  , cmsgHdrType  :: !CInt
  } deriving (Eq, Show)

instance Storable CmsgHdr where
  sizeOf    _ = #{size WSACMSGHDR}
  alignment _ = #alignment WSACMSGHDR

  peek p = do
    len <- (#peek WSACMSGHDR, cmsg_len)   p
    lvl <- (#peek WSACMSGHDR, cmsg_level) p
    typ <- (#peek WSACMSGHDR, cmsg_type)  p
    return $ CmsgHdr len lvl typ

  poke p (CmsgHdr len lvl typ) = do
    zeroMemory p (#size WSACMSGHDR)
    (#poke WSACMSGHDR, cmsg_len)   p len
    (#poke WSACMSGHDR, cmsg_level) p lvl
    (#poke WSACMSGHDR, cmsg_type)  p typ

withCmsgs :: [Cmsg] -> (Ptr CmsgHdr -> Int -> IO a) -> IO a
withCmsgs cmsgs0 action
  | total == 0 = action nullPtr 0
  | otherwise  = allocaBytes total $ \ctrlPtr -> do
        loop ctrlPtr cmsgs0 spaces
        action ctrlPtr total
  where
    loop ctrlPtr (cmsg:cmsgs) (s:ss) = do
        toCmsgHdr cmsg ctrlPtr
        let nextPtr = ctrlPtr `plusPtr` s
        loop nextPtr cmsgs ss
    loop _ _ _ = return ()
    cmsg_space = fromIntegral . c_cmsg_space . fromIntegral
    spaces = map (cmsg_space . B.length . cmsgData) cmsgs0
    total = sum spaces

toCmsgHdr :: Cmsg -> Ptr CmsgHdr -> IO ()
toCmsgHdr (Cmsg (CmsgId lvl typ) (PS fptr off len)) ctrlPtr = do
    poke ctrlPtr $ CmsgHdr (c_cmsg_len (fromIntegral len)) lvl typ
    withForeignPtr fptr $ \src0 -> do
        let src = src0 `plusPtr` off
        dst <- c_cmsg_data ctrlPtr
        memcpy dst src len

parseCmsgs :: SocketAddress sa => Ptr (MsgHdr sa) -> IO [Cmsg]
parseCmsgs msgptr = do
    ptr <- c_cmsg_firsthdr msgptr
    loop ptr id
  where
    loop ptr build
      | ptr == nullPtr = return $ build []
      | otherwise = do
            val <- fromCmsgHdr ptr
            case val of
              Nothing -> return $ build []
              Just cmsg -> do
                nextPtr <- c_cmsg_nxthdr msgptr ptr
                loop nextPtr (build . (cmsg :))

fromCmsgHdr :: Ptr CmsgHdr -> IO (Maybe Cmsg)
fromCmsgHdr ptr = do
    CmsgHdr len lvl typ <- peek ptr
    src <- c_cmsg_data ptr
    let siz = fromIntegral len - (src `minusPtr` ptr)
    if siz < 0
      then return Nothing
      else Just . Cmsg (CmsgId lvl typ) <$> create (fromIntegral siz) (\dst -> memcpy dst src siz)

foreign import ccall unsafe "cmsg_firsthdr"
  c_cmsg_firsthdr :: Ptr (MsgHdr sa) -> IO (Ptr CmsgHdr)

foreign import ccall unsafe "cmsg_nxthdr"
  c_cmsg_nxthdr :: Ptr (MsgHdr sa) -> Ptr CmsgHdr -> IO (Ptr CmsgHdr)

foreign import ccall unsafe "cmsg_data"
  c_cmsg_data :: Ptr CmsgHdr -> IO (Ptr Word8)

foreign import ccall unsafe "cmsg_space"
  c_cmsg_space :: CUInt -> CUInt

foreign import ccall unsafe "cmsg_len"
  c_cmsg_len :: CUInt -> CUInt
