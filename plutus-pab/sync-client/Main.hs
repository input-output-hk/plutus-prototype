module Main where

import           Options.Applicative

import           Cardano.Protocol.Socket.Client       (runChainSync)
import           Ledger                               (Slot)
import           Ouroboros.Consensus.Cardano.Block    (CardanoBlock, HardForkBlock (..))
import           Ouroboros.Consensus.Shelley.Protocol (StandardCrypto (..))

-- | We only need to know the location of the socket.
--   We can get the protocol versions from Cardano.Protocol.Socket.Type
data Configuration = Configuration
  { cSocketPath :: String
  } deriving (Show)

-- | A simple callback that reads the incoming data, from the node.
processBlock
  :: CardanoBlock StandardCrypto
  -> Slot
  -> IO ()
processBlock _ _ = print "Received block"

cfgParser :: Parser Configuration
cfgParser = Configuration
  <$> argument str (metavar "SOCKET")

main :: IO ()
main = do
  cfg <- execParser $ info (cfgParser <**> helper)
                        ( fullDesc
                        <> progDesc "Connect and stream blocks from the node client"
                        )
  print "Runtime configuration:"
  print "---------------------"
  print cfg
  -- _ <- runChainSync (cSocketPath cfg) undefined processBlock
  pure ()
