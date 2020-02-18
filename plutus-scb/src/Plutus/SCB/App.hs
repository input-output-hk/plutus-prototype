{-# LANGUAGE DerivingStrategies    #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings     #-}
{-# LANGUAGE RecordWildCards       #-}

module Plutus.SCB.App where

import qualified Cardano.Node.Client        as NodeClient
import qualified Cardano.Wallet.Client      as WalletClient
import           Control.Monad              (void)
import           Control.Monad.Except       (ExceptT (ExceptT), MonadError, runExceptT, throwError)
import           Control.Monad.IO.Class     (MonadIO, liftIO)
import           Control.Monad.Logger       (LogLevel (LevelDebug), LoggingT, MonadLogger, filterLogger, logInfoN,
                                             runStdoutLoggingT)
import           Control.Monad.Reader       (MonadReader, ReaderT (ReaderT), asks, runReaderT)
import           Data.Aeson                 (FromJSON, ToJSON, eitherDecode)
import qualified Data.Aeson.Encode.Pretty   as JSON
import qualified Data.ByteString.Lazy.Char8 as BSL8
import qualified Data.Text                  as Text
import           Database.Persist.Sqlite    (retryOnBusy, runSqlPool)
import           Eventful                   (commandStoredAggregate, getLatestStreamProjection,
                                             serializedEventStoreWriter, serializedGlobalEventStoreReader,
                                             serializedVersionedEventStoreReader)
import           Eventful.Store.Sql         (jsonStringSerializer, sqlEventStoreReader, sqlGlobalEventStoreReader)
import           Eventful.Store.Sqlite      (initializeSqliteEventStore, sqliteEventStoreWriter)
import           Network.HTTP.Client        (defaultManagerSettings, newManager)
import           Plutus.SCB.Core            (Connection (Connection), ContractCommand (InitContract, UpdateContract),
                                             MonadContract, MonadEventStore, addProcessBus, dbConnect, invokeContract,
                                             refreshProjection, runCommand, toUUID)
import           Plutus.SCB.Types           (DbConfig,
                                             SCBError (ContractCommandError, NodeClientError, WalletClientError))
import           Servant.Client             (ClientEnv, ClientM, ServantError, mkClientEnv, parseBaseUrl, runClientM)
import           System.Exit                (ExitCode (ExitFailure, ExitSuccess))
import           System.Process             (readProcessWithExitCode)
import           Wallet.API                 (NodeAPI, WalletAPI, WalletDiagnostics, logMsg, ownPubKey, sign, slot,
                                             startWatching, submitTxn, updatePaymentWithChange, watchedAddresses)

------------------------------------------------------------
data Env =
    Env
        { dbConnection    :: Connection
        , walletClientEnv :: ClientEnv
        , nodeClientEnv   :: ClientEnv
        }

newtype App a =
    App
        { unApp :: ExceptT SCBError (ReaderT Env (LoggingT IO)) a
        }
    deriving newtype ( Functor
                     , Applicative
                     , Monad
                     , MonadLogger
                     , MonadIO
                     , MonadReader Env
                     , MonadError SCBError
                     )

instance NodeAPI App where
    submitTxn = void . runNodeClientM . NodeClient.addTx
    slot = runNodeClientM NodeClient.getCurrentSlot

instance WalletAPI App where
    ownPubKey = runWalletClientM WalletClient.getOwnPubKey
    sign bs = runWalletClientM $ WalletClient.sign bs
    updatePaymentWithChange _ _ = error "UNIMPLEMENTED: updatePaymentWithChange"
    watchedAddresses = runWalletClientM WalletClient.getWatchedAddresses
    startWatching = void . runWalletClientM . WalletClient.startWatching

runAppClientM ::
       (Env -> ClientEnv) -> (ServantError -> SCBError) -> ClientM a -> App a
runAppClientM f wrapErr action =
    App $ do
        env <- asks f
        result <- liftIO $ runClientM action env
        case result of
            Left err    -> throwError $ wrapErr err
            Right value -> pure value

runWalletClientM :: ClientM a -> App a
runWalletClientM = runAppClientM walletClientEnv WalletClientError

runNodeClientM :: ClientM a -> App a
runNodeClientM = runAppClientM nodeClientEnv NodeClientError

runApp :: DbConfig -> App a -> IO (Either SCBError a)
runApp dbConfig (App action) =
    runStdoutLoggingT . filterLogger (\_ level -> level > LevelDebug) $ do
        walletClientEnv <- mkEnv "http://localhost:8081"
        nodeClientEnv <- mkEnv "http://localhost:8082"
        dbConnection <- runReaderT dbConnect dbConfig
        runReaderT (runExceptT action) $ Env {..}
  where
    mkEnv baseUrl = do
        nodeManager <- liftIO $ newManager defaultManagerSettings
        nodeBaseUrl <- parseBaseUrl baseUrl
        pure $ mkClientEnv nodeManager nodeBaseUrl

instance (FromJSON event, ToJSON event) => MonadEventStore event App where
    refreshProjection projection =
        App $ do
            (Connection (sqlConfig, connectionPool)) <- asks dbConnection
            let reader =
                    serializedGlobalEventStoreReader jsonStringSerializer $
                    sqlGlobalEventStoreReader sqlConfig
            ExceptT . fmap Right . flip runSqlPool connectionPool $
                getLatestStreamProjection reader projection
    runCommand aggregate source input =
        App $ do
            (Connection (sqlConfig, connectionPool)) <- asks dbConnection
            let reader =
                    serializedVersionedEventStoreReader jsonStringSerializer $
                    sqlEventStoreReader sqlConfig
            let writer =
                    addProcessBus
                        (serializedEventStoreWriter jsonStringSerializer $
                         sqliteEventStoreWriter sqlConfig)
                        reader
            ExceptT $
                fmap Right . retryOnBusy . flip runSqlPool connectionPool $
                commandStoredAggregate
                    writer
                    reader
                    aggregate
                    (toUUID source)
                    input

instance MonadContract App where
    invokeContract contractCommand =
        App $ do
            (exitCode, stdout, stderr) <-
                liftIO $
                case contractCommand of
                    InitContract contractPath ->
                        readProcessWithExitCode contractPath ["init"] ""
                    UpdateContract contractPath payload ->
                        readProcessWithExitCode
                            contractPath
                            ["update"]
                            (BSL8.unpack (JSON.encodePretty payload))
            case exitCode of
                ExitFailure code ->
                    pure . Left $ ContractCommandError code (Text.pack stderr)
                ExitSuccess ->
                    case eitherDecode (BSL8.pack stdout) of
                        Right value -> pure $ Right value
                        Left err ->
                            pure . Left $ ContractCommandError 0 (Text.pack err)

instance WalletDiagnostics App where
    logMsg = App . logInfoN

-- | Initialize/update the database to hold events.
migrate :: App ()
migrate =
    App $ do
        logInfoN "Migrating"
        Connection (sqlConfig, connectionPool) <- asks dbConnection
        ExceptT . fmap Right . flip runSqlPool connectionPool $
            initializeSqliteEventStore sqlConfig connectionPool
