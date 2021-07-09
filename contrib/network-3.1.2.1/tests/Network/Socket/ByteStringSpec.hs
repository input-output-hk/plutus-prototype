{-# LANGUAGE OverloadedStrings #-}

module Network.Socket.ByteStringSpec (main, spec) where

import Control.Concurrent.MVar (newEmptyMVar, putMVar, takeMVar)
import Data.Bits
import Data.Maybe
import Control.Monad
import qualified Data.ByteString as S
import qualified Data.ByteString.Char8 as C
import Network.Socket
import Network.Socket.ByteString
import Network.Test.Common

import System.Environment

import Test.Hspec

main :: IO ()
main = hspec spec

spec :: Spec
spec = do
    describe "send" $ do
        it "works well" $ do
            let server sock = recv sock 1024 `shouldReturn` testMsg
                client sock = send sock testMsg
            tcpTest client server

        it "throws when closed" $ do
            let server _ = return ()
                client sock = do
                    close sock
                    send sock testMsg `shouldThrow` anyException
            tcpTest client server

        it "checks -1 correctly on Windows" $ do
            sock <- socket AF_INET Stream defaultProtocol
            send sock "hello world" `shouldThrow` anyException

    describe "sendAll" $ do
        it "works well" $ do
            let server sock = recv sock 1024 `shouldReturn` testMsg
                client sock = sendAll sock testMsg
            tcpTest client server

        it "throws when closed" $ do
            let server _ = return ()
                client sock = do
                    close sock
                    sendAll sock testMsg `shouldThrow` anyException
            tcpTest client server

    describe "sendTo" $ do
        it "works well" $ do
            let server sock = recv sock 1024 `shouldReturn` testMsg
                client sock addr = sendTo sock testMsg addr
            udpTest client server

        it "throws when closed" $ do
            let server _ = return ()
                client sock addr = do
                    close sock
                    sendTo sock testMsg addr `shouldThrow` anyException
            udpTest client server

    describe "sendAllTo" $ do
        it "works well" $ do
            let server sock = recv sock 1024 `shouldReturn` testMsg
                client sock addr = sendAllTo sock testMsg addr
            udpTest client server

        it "throws when closed" $ do
            let server _ = return ()
                client sock addr = do
                    close sock
                    sendAllTo sock testMsg addr `shouldThrow` anyException
            udpTest client server

    describe "sendMany" $ do
        it "works well" $ do
            let server sock = recv sock 1024 `shouldReturn` S.append seg1 seg2
                client sock = sendMany sock [seg1, seg2]

                seg1 = C.pack "This is a "
                seg2 = C.pack "test message."
            tcpTest client server

        it "throws when closed" $ do
            let server _ = return ()
                client sock = do
                    close sock
                    sendMany sock [seg1, seg2] `shouldThrow` anyException

                seg1 = C.pack "This is a "
                seg2 = C.pack "test message."
            tcpTest client server

    describe "sendManyTo" $ do
        it "works well" $ do
            let server sock = recv sock 1024 `shouldReturn` S.append seg1 seg2
                client sock addr = sendManyTo sock [seg1, seg2] addr

                seg1 = C.pack "This is a "
                seg2 = C.pack "test message."
            udpTest client server

        it "throws when closed" $ do
            let server _ = return ()
                client sock addr = do
                    close sock
                    sendManyTo sock [seg1, seg2] addr `shouldThrow` anyException

                seg1 = C.pack "This is a "
                seg2 = C.pack "test message."
            udpTest client server

    describe "recv" $ do
        it "works well" $ do
            let server sock = recv sock 1024 `shouldReturn` testMsg
                client sock = send sock testMsg
            tcpTest client server

        it "throws when closed" $ do
            let server sock = do
                    close sock
                    recv sock 1024 `shouldThrow` anyException
                client sock = send sock testMsg
            tcpTest client server

        it "can treat overflow" $ do
            let server sock = do
                    seg1 <- recv sock (S.length testMsg - 3)
                    seg2 <- recv sock 1024
                    let msg = S.append seg1 seg2
                    msg `shouldBe` testMsg
                client sock = send sock testMsg
            tcpTest client server

        it "returns empty string at EOF" $ do
            let client s = recv s 4096 `shouldReturn` S.empty
                server s = shutdown s ShutdownSend
            tcpTest client server

        it "checks -1 correctly on Windows" $ do
            sock <- socket AF_INET Stream defaultProtocol
            recv sock 1024 `shouldThrow` anyException

    describe "recvFrom" $ do
        it "works well" $ do
            let server sock = do
                    (msg, _) <- recvFrom sock 1024
                    testMsg `shouldBe` msg
                client sock = do
                    addr <- getPeerName sock
                    sendTo sock testMsg addr
            tcpTest client server

        it "throws when closed" $ do
            let server sock = do
                    close sock
                    recvFrom sock 1024 `shouldThrow` anyException
                client sock = do
                    addr <- getPeerName sock
                    sendTo sock testMsg addr
            tcpTest client server

        it "can treat overflow" $ do
            let server sock = do
                    (seg1, _) <- recvFrom sock (S.length testMsg - 3)
                    (seg2, _) <- recvFrom sock 1024
                    let msg = S.append seg1 seg2
                    testMsg `shouldBe` msg
                client sock = send sock testMsg
            tcpTest client server

        it "returns empty string at EOF" $ do
            let server sock = do
                    (seg1, _) <- recvFrom sock (S.length testMsg - 3)
                    seg1 `shouldBe` S.empty
                client sock = shutdown sock ShutdownSend
            tcpTest client server

    describe "sendMsg" $ do
        it "works well" $ do
            let server sock = recv sock 1024 `shouldReturn` S.append seg1 seg2
                client sock addr = sendMsg sock addr [seg1, seg2] [] mempty

                seg1 = C.pack "This is a "
                seg2 = C.pack "test message."
            udpTest client server

        it "throws when closed" $ do
            let server _ = return ()
                client sock addr = do
                    close sock
                    sendMsg sock addr [seg1, seg2] [] mempty `shouldThrow` anyException

                seg1 = C.pack "This is a "
                seg2 = C.pack "test message."
            udpTest client server

    describe "recvMsg" $ do
        it "works well" $ do
            let server sock = do
                    (_, msg, cmsgs, flags) <- recvMsg sock 1024 0 mempty
                    msg `shouldBe` seg
                    cmsgs `shouldBe` []
                    flags `shouldBe` mempty
                client sock addr = sendTo sock seg addr

                seg = C.pack "This is a test message"
            udpTest client server

        it "receives truncated flag" $ do
            let server sock = do
                    (_, _, _, flags) <- recvMsg sock (S.length seg - 2) 0 mempty
                    flags .&. MSG_TRUNC `shouldBe` MSG_TRUNC
                client sock addr = sendTo sock seg addr

                seg = C.pack "This is a test message"
            udpTest client server

        it "peek" $ do
            let server sock = do
                    (_, msgs, _, _flags) <- recvMsg sock 1024 0 MSG_PEEK
                    -- flags .&. MSG_PEEK `shouldBe` MSG_PEEK -- Mac only
                    (_, msgs', _, _) <- recvMsg sock 1024 0 mempty
                    msgs `shouldBe` msgs'
                client sock addr = sendTo sock seg addr

                seg = C.pack "This is a test message"
            udpTest client server

        it "receives control messages for IPv4" $ do
            -- This test behaves strange on AppVeyor and I don't know why so skip
            -- TOS for now.
            isAppVeyor <- isJust <$> lookupEnv "APPVEYOR"

            -- Avoid race condition between the client sending the message and
            -- the server finishing its socket configuration.  Otherwise the
            -- message may be received with default socket options!
            serverReady <- newEmptyMVar

            let server sock = do
                    whenSupported RecvIPv4TTL     $ setSocketOption sock RecvIPv4TTL 1
                    whenSupported RecvIPv4PktInfo $ setSocketOption sock RecvIPv4PktInfo 1
                    whenSupported RecvIPv4TOS     $ setSocketOption sock RecvIPv4TOS 1
                    putMVar serverReady ()

                    (_, _, cmsgs, _) <- recvMsg sock 1024 128 mempty

                    whenSupported RecvIPv4PktInfo $
                      ((lookupCmsg CmsgIdIPv4PktInfo cmsgs >>= decodeCmsg) :: Maybe IPv4PktInfo) `shouldNotBe` Nothing
                    when (not isAppVeyor) $ do
                      whenSupported RecvIPv4TTL $
                        ((lookupCmsg CmsgIdIPv4TTL cmsgs >>= decodeCmsg) :: Maybe IPv4TTL) `shouldNotBe` Nothing
                      whenSupported RecvIPv4TOS $
                        ((lookupCmsg CmsgIdIPv4TOS cmsgs >>= decodeCmsg) :: Maybe IPv4TOS) `shouldNotBe` Nothing
                client sock addr = takeMVar serverReady >> sendTo sock seg addr

                seg = C.pack "This is a test message"
            udpTest client server

        it "receives control messages for IPv6" $ do
            -- Avoid race condition between the client sending the message and
            -- the server finishing its socket configuration.  Otherwise the
            -- message may be received with default socket options!
            serverReady <- newEmptyMVar

            let server sock = do
                    whenSupported RecvIPv6HopLimit $ setSocketOption sock RecvIPv6HopLimit 1
                    whenSupported RecvIPv6TClass   $ setSocketOption sock RecvIPv6TClass 1
                    whenSupported RecvIPv6PktInfo  $ setSocketOption sock RecvIPv6PktInfo 1
                    putMVar serverReady ()

                    (_, _, cmsgs, _) <- recvMsg sock 1024 128 mempty

                    whenSupported RecvIPv6HopLimit $
                      ((lookupCmsg CmsgIdIPv6HopLimit cmsgs >>= decodeCmsg) :: Maybe IPv6HopLimit) `shouldNotBe` Nothing
                    whenSupported RecvIPv6TClass $
                      ((lookupCmsg CmsgIdIPv6TClass cmsgs >>= decodeCmsg) :: Maybe IPv6TClass) `shouldNotBe` Nothing
                    whenSupported RecvIPv6PktInfo $
                      ((lookupCmsg CmsgIdIPv6PktInfo cmsgs >>= decodeCmsg) :: Maybe IPv6PktInfo) `shouldNotBe` Nothing
                client sock addr = takeMVar serverReady >> sendTo sock seg addr

                seg = C.pack "This is a test message"
            udpTest6 client server

        it "receives truncated control messages" $ do
            -- Avoid race condition between the client sending the message and
            -- the server finishing its socket configuration.  Otherwise the
            -- message may be received with default socket options!
            serverReady <- newEmptyMVar

            let server sock = do
                    whenSupported RecvIPv4TTL     $ setSocketOption sock RecvIPv4TTL 1
                    whenSupported RecvIPv4TOS     $ setSocketOption sock RecvIPv4TOS 1
                    whenSupported RecvIPv4PktInfo $ setSocketOption sock RecvIPv4PktInfo 1
                    putMVar serverReady ()

                    (_, _, _, flags) <- recvMsg sock 1024 10 mempty
                    flags .&. MSG_CTRUNC `shouldBe` MSG_CTRUNC

                client sock addr = takeMVar serverReady >> sendTo sock seg addr

                seg = C.pack "This is a test message"
            udpTest client server
