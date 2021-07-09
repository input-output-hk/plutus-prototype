
module System.Console.Terminal.Posix
  ( size, fdSize, hSize
  ) where

import System.Console.Terminal.Common
import Control.Exception (catch)
import Data.Typeable (cast)
import Foreign
import Foreign.C.Error
import Foreign.C.Types
import GHC.IO.FD (FD(FD, fdFD))
import GHC.IO.Handle.Internals (withHandle_)
import GHC.IO.Handle.Types (Handle, Handle__(Handle__, haDevice))
#if defined(__GLASGOW_HASKELL__) && (__GLASGOW_HASKELL__ < 706)
import Prelude hiding (catch)
#endif
import System.Posix.Types (Fd(Fd))

#include <sys/ioctl.h>
#include <unistd.h>

-- Interesting part of @struct winsize@
data CWin = CWin CUShort CUShort

instance Storable CWin where
  sizeOf _ = (#size struct winsize)
  alignment _ = (#alignment struct winsize)
  peek ptr = do
    row <- (#peek struct winsize, ws_row) ptr
    col <- (#peek struct winsize, ws_col) ptr
    return $ CWin row col
  poke ptr (CWin row col) = do
    (#poke struct winsize, ws_row) ptr row
    (#poke struct winsize, ws_col) ptr col


fdSize :: Integral n => Fd -> IO (Maybe (Window n))
fdSize (Fd fd) = with (CWin 0 0) $ \ws -> do
  throwErrnoIfMinus1 "ioctl" $
    ioctl fd (#const TIOCGWINSZ) ws
  CWin row col <- peek ws
  return . Just $ Window (fromIntegral row) (fromIntegral col)
 `catch`
  handler
 where
  handler :: IOError -> IO (Maybe (Window h))
  handler _ = return Nothing

foreign import ccall "sys/ioctl.h ioctl"
  ioctl :: CInt -> CInt -> Ptr CWin -> IO CInt

size :: Integral n => IO (Maybe (Window n))
size = fdSize (Fd (#const STDOUT_FILENO))

hSize :: Integral n => Handle -> IO (Maybe (Window n))
hSize h = withHandle_ "hSize" h $ \Handle__ { haDevice = dev } ->
  case cast dev of
    Nothing -> return Nothing
    Just FD { fdFD = fd } -> fdSize (Fd fd)
