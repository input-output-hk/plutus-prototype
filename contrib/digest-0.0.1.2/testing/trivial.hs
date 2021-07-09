import Data.Digest.Adler32
import Data.Digest.CRC32

import Control.Monad            (forM_)
import Data.ByteString          (ByteString)
import Data.ByteString.Char8    (pack)
import Data.Word                (Word32)
import Foreign.ForeignPtr       (mallocForeignPtr)
import System.IO.Unsafe         (unsafePerformIO)

import qualified Data.ByteString.Internal as I

-- | Empty 'ByteString' whose pointer is null
emptyNull :: ByteString
emptyNull = I.PS I.nullForeignPtr 0 0

-- | Empty 'ByteString' whose pointer is not null
emptyNotNull :: ByteString
emptyNotNull = unsafePerformIO $ do
    ptr <- mallocForeignPtr
    return $ I.PS ptr 0 0

testStrings :: [ByteString]
testStrings =
    [ emptyNull
    , emptyNotNull
    , pack "\0"
    , pack "a"
    , pack "hello"
    , pack ['\0'..'\255']
    ]

runTest :: String -> (ByteString -> Word32) -> IO ()
runTest label func = do
    putStrLn label
    forM_ testStrings $ \s ->
        putStrLn $ "    " ++ (show . func) s
    putStrLn ""

main :: IO ()
main = do
    runTest "adler32"                   $ adler32
    runTest "adler32Update 0"           $ adler32Update 0
    runTest "adler32Update 1"           $ adler32Update 1
    runTest "adler32Update 123"         $ adler32Update 123
    runTest "adler32Update 0xFFF0FFF0"  $ adler32Update 0xFFF0FFF0

    runTest "crc32"                     $ crc32
    runTest "crc32Update 0"             $ crc32Update 0
    runTest "crc32Update 1"             $ crc32Update 1
    runTest "crc32Update 123"           $ crc32Update 123
    runTest "crc32Update 0xFFFFFFFF"    $ crc32Update 0xFFFFFFFF
