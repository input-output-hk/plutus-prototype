{-# LANGUAGE DeriveAnyClass     #-}
{-# LANGUAGE NamedFieldPuns     #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings  #-}
{-# LANGUAGE StrictData         #-}

{- | Use this executable to send a number of transactions per second
     to the PAB. The executable will read the PAB configuration to get
     the connection data, and you can specify a rate of transmission
-}
module Main where

import           Control.Concurrent             (ThreadId, forkIO, myThreadId, throwTo)
import           Control.Concurrent.STM         (atomically)
import           Control.Concurrent.STM.TBQueue (TBQueue, newTBQueueIO, readTBQueue, writeTBQueue)
import           Control.Concurrent.STM.TVar    (TVar, modifyTVar', newTVarIO, readTVar)
import           Control.Exception              (AsyncException (..))
import           Control.Lens                   hiding (ix)
import           Control.Monad                  (forever)
import           Control.Monad.IO.Class         (liftIO)
import           Control.RateLimit              (rateLimitExecution)
import qualified Data.Map                       as Map
import           Data.Text                      (Text)
import qualified Data.Text                      as T
import qualified Data.Text.IO                   as T
import           Data.Time.Units                (Microsecond, fromMicroseconds)
import           Data.Yaml                      (decodeFileThrow)
import           GHC.Generics                   (Generic)
import           Options.Applicative            (Parser, ParserInfo, auto, execParser, fullDesc, help, helper, info,
                                                 long, metavar, option, progDesc, short, showDefault, strOption, value,
                                                 (<**>))
import           System.Clock                   (Clock (..), TimeSpec (..), getTime)
import           System.Random.MWC              (GenIO, createSystemRandom)
import           System.Signal                  (installHandler, sigINT)
import           Text.Pretty.Simple             (pPrint)

import           Cardano.Node.Types             (MockServerConfig (..))
import           Cardano.Protocol.Socket.Client (TxSendHandle (..), queueTx, runTxSender)
import qualified Ledger.Ada                     as Ada
import           Ledger.Blockchain              (OnChainTx (..))
import           Ledger.Index                   (UtxoIndex (..), insertBlock)
import           Ledger.Slot                    (Slot (..))
import           Ledger.Tx                      (Tx (..))
import           Plutus.PAB.Types               (Config (..))
import           Wallet.Emulator                (chainState, txPool, walletPubKey)
import           Wallet.Emulator.MultiAgent     (emulatorStateInitialDist)

{- | The `Stats` are used by both the producer and consumer to track the number of
     generated transactions (used to verify if we respect the requested TPS rate)
     and the number of UTxOs (not used at the moment)
-}
data Stats = Stats
  { stStartTime :: TimeSpec
  , stCount     :: Integer
  , stUtxoSize  :: Int
  , stEndTime   :: TimeSpec
  } deriving (Show, Generic)

{- | The `AppEnv` is used by both the producer and the consumer to pass the data
     required for execution
-}
data AppEnv = AppEnv
  { txSendHandle :: TxSendHandle
  , txQueue      :: TBQueue Tx
  , stats        :: TVar Stats
  , utxoIndex    :: UtxoIndex
  }

-- | This builds the default UTxO index, using 10 wallets.
initialUtxoIndex :: Config -> UtxoIndex
initialUtxoIndex config =
  let dist = Map.fromList $
               zip (config & nodeServerConfig & mscInitialTxWallets)
                   (repeat (Ada.adaValueOf 1000_000_000))
      initialTxs =
        view (chainState . txPool) $
        emulatorStateInitialDist $
        Map.mapKeys walletPubKey dist
  in insertBlock (map Valid initialTxs) (UtxoIndex Map.empty)

-- | Starts the producer thread
runProducer :: AppEnv -> IO ThreadId
runProducer AppEnv{txQueue, stats, utxoIndex} = do
  rng <- createSystemRandom
  forkIO $ producer rng utxoIndex
  where
    producer :: GenIO -> UtxoIndex -> IO ()
    producer rng utxo = do
      -- The transaction validator also checks if transactions are within slot
      -- boundaries. We don't currently use boundaries for our generated
      -- transactions, so we chose the random number.
      tx <- generateTx rng (Slot 4) utxo
      let utxo' = insertBlock [Valid tx] utxo
      atomically $ do
        writeTBQueue txQueue tx
        modifyTVar' stats $ \s -> s { stUtxoSize = Map.size $ getIndex utxo' }
      producer rng utxo'

-- | Default consumer will take transactions from the queue and send them
--   as REST requests to the PAB.
consumer :: AppEnv -> IO ()
consumer AppEnv {txSendHandle, txQueue, stats} = do
  tx <- atomically $ readTBQueue txQueue
  atomically $ modifyTVar' stats incrementCount
  _ <- queueTx txSendHandle tx
  pure ()
  where
    incrementCount :: Stats -> Stats
    incrementCount s = s { stCount = stCount s + 1 }

-- | Cleanup procedure called when the application is closed, by using SIGINT (C-c)
completeStats :: ThreadId -> TVar Stats -> IO ()
completeStats parent stats = do
  endTime <- getTime Monotonic
  updatedStats <-
    atomically $ do
      modifyTVar' stats $ \s -> s { stEndTime = endTime }
      readTVar stats
  putStrLn ""
  pPrint updatedStats
  T.putStrLn $ showStats updatedStats
  throwTo parent UserInterrupt

showStats :: Stats -> Text
showStats Stats {stStartTime, stCount, stEndTime} =
  let dt = sec stEndTime - sec stStartTime
      fr = stCount `div` toInteger dt
  in  "Transactions per second: " <> (T.pack $ show fr)

-- | Command line options
data InjectOptions = InjectOptions
  { ioRate         :: Integer
  , ioServerConfig :: String
  } deriving (Show, Generic)

-- | Command line parser
cmdOptions :: Parser InjectOptions
cmdOptions = InjectOptions
  <$> option auto
    (  long "rate"
    <> short 'r'
    <> metavar "RATE"
    <> value 0
    <> showDefault
    <> help "Produce RATE transactions per second." )
  <*> strOption
    (  long "config"
    <> short 'c'
    <> metavar "CONFIG"
    <> help "Read configuration from the CONFIG file" )

prgHelp :: ParserInfo InjectOptions
prgHelp = info (cmdOptions <**> helper)
        ( fullDesc
       <> progDesc "Inject transactions into the SCB at specified RATEs." )

-- | Wrapper that does rate limiting for a consumer
rateLimitedConsumer
  :: InjectOptions
  -> IO (AppEnv -> IO ())
rateLimitedConsumer InjectOptions{ioRate} = do
  let rate :: Microsecond
        = fromMicroseconds $
            if ioRate == 0
            then ioRate
            -- We will need to increase this when we need to generate
            -- more than 1m TPS.
            else 1_000_000 `div` ioRate
  if  rate == 0
  -- Don't wrap the consumer if rate limiting is disabled.
  then pure consumer
  else do
    rateLimitExecution rate consumer

-- | Initial stats.
initializeStats :: IO (TVar Stats)
initializeStats = do
  sTime <- getTime Monotonic
  newTVarIO Stats { stStartTime = sTime
                  , stCount = 0
                  , stUtxoSize = 0
                  , stEndTime = sTime
                  }

-- | SIGINT / C-c will stop the execution.
initializeInterruptHandler :: TVar Stats -> IO ()
initializeInterruptHandler stats = do
  tid <- myThreadId
  installHandler sigINT (const $ completeStats tid stats)

-- | Build a client environment for servant.
initializeClient :: Config -> IO TxSendHandle
initializeClient cfg = do
    let serverSocket = mscSocketPath $ nodeServerConfig cfg
    runTxSender serverSocket

main :: IO ()
main = do
  opts <- execParser prgHelp
  pPrint opts
  config <- liftIO $ decodeFileThrow (ioServerConfig opts)
  env    <-
    AppEnv <$> initializeClient config
           -- Increasing the size beyond this point adds quite a bit of overhead.
           <*> newTBQueueIO 1000
           <*> initializeStats
           <*> pure (initialUtxoIndex config)
  initializeInterruptHandler (stats env)
  _   <- runProducer env
  forever =<< rateLimitedConsumer opts <*> pure env
