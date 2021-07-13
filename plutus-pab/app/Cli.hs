{-# LANGUAGE ApplicativeDo         #-}
{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE DerivingVia           #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE LambdaCase            #-}
{-# LANGUAGE MonoLocalBinds        #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE NamedFieldPuns        #-}
{-# LANGUAGE OverloadedStrings     #-}
{-# LANGUAGE RecordWildCards       #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE TypeApplications      #-}
{-# LANGUAGE TypeOperators         #-}

module Cli (ConfigCommandArgs(..), runConfigCommand, runNoConfigCommand) where

-----------------------------------------------------------------------------------------------------------------------
-- Command interpretation
-----------------------------------------------------------------------------------------------------------------------

import           Command

import           Cardano.BM.Configuration                (Configuration)
import qualified Cardano.BM.Configuration.Model          as CM
import           Cardano.BM.Data.Trace                   (Trace)
import qualified Cardano.ChainIndex.Server               as ChainIndex
import qualified Cardano.Metadata.Server                 as Metadata
import qualified Cardano.Node.Server                     as NodeServer
import qualified Cardano.Wallet.Server                   as WalletServer
import           Cardano.Wallet.Types
import           Control.Concurrent                      (takeMVar)
import           Control.Concurrent.Async                (Async, async, waitAny)
import           Control.Concurrent.Availability         (Availability, starting)
import           Control.Monad                           (void)
import           Control.Monad.Freer                     (Eff, Member, interpret)
import           Control.Monad.Freer.Delay               (DelayEffect, delayThread)
import           Control.Monad.Freer.Extras.Log          (logInfo)
import           Control.Monad.IO.Class                  (liftIO)
import           Data.Foldable                           (traverse_)
import qualified Data.Map                                as Map
import           Data.Proxy                              (Proxy (..))
import qualified Data.Set                                as Set
import qualified Data.Text                               as Text
import           Data.Text.Prettyprint.Doc               (Pretty (..), defaultLayoutOptions, layoutPretty, pretty)
import           Data.Text.Prettyprint.Doc.Render.Text   (renderStrict)
import           Data.Time.Units                         (Second)
import qualified Plutus.PAB.Effects.Contract             as Contract

import           Cardano.Node.Types                      (MockServerConfig (..))
import qualified PSGenerator
import           Plutus.Contract.Resumable               (responses)
import           Plutus.Contract.State                   (State (..))
import qualified Plutus.Contract.State                   as State
import qualified Plutus.PAB.App                          as App
import qualified Plutus.PAB.Core                         as Core
import qualified Plutus.PAB.Db.Beam                      as Beam
import           Plutus.PAB.Effects.Contract.ContractExe (ContractExe)
import qualified Plutus.PAB.Monitoring.Monitoring        as LM
import           Plutus.PAB.Types                        (Config (..), DbConfig (..), chainIndexConfig,
                                                          metadataServerConfig, nodeServerConfig, walletServerConfig)
import qualified Plutus.PAB.Webserver.Server             as PABServer
import           Plutus.PAB.Webserver.Types              (ContractActivationArgs (..))

runNoConfigCommand ::
    Trace IO (LM.AppMsg ContractExe)  -- ^ PAB Tracer logging instance
    -> NoConfigCommand
    -> IO ()
runNoConfigCommand trace = \case

    -- Run database migration
    Migrate{dbPath} ->
        let conf = DbConfig{dbConfigPoolSize=10, dbConfigFile=Text.pack dbPath} in
        App.migrate (LM.convertLog LM.PABMsg trace) conf

    -- Generate PureScript bridge code
    PSGenerator {outputDir} -> PSGenerator.generate outputDir

    -- Get default logging configuration
    WriteDefaultConfig{outputFile} -> LM.defaultConfig >>= flip CM.exportConfiguration outputFile

data ConfigCommandArgs =
    ConfigCommandArgs
        { ccaTrace          :: Trace IO (LM.AppMsg ContractExe)  -- ^ PAB Tracer logging instance
        , ccaLoggingConfig  :: Configuration -- ^ Monitoring configuration
        , ccaPABConfig      :: Config        -- ^ PAB Configuration
        , ccaAvailability   :: Availability  -- ^ Token for signaling service availability
        , ccaStorageBackend :: App.StorageBackend -- ^ Wheter to use the beam-sqlite or in-memory backend
        }

-- | Interpret a 'Command' in 'Eff' using the provided tracer and configurations
--
runConfigCommand ::
    ConfigCommandArgs
    -> ConfigCommand
    -> IO ()

-- Run mock wallet service
runConfigCommand ConfigCommandArgs{ccaTrace, ccaPABConfig = Config {nodeServerConfig, chainIndexConfig, walletServerConfig},ccaAvailability} MockWallet =
    liftIO $ WalletServer.main
        (toWalletLog ccaTrace)
        walletServerConfig
        (mscFeeConfig nodeServerConfig)
        (mscSocketPath nodeServerConfig)
        (mscSlotConfig nodeServerConfig)
        (ChainIndex.ciBaseUrl chainIndexConfig)
        ccaAvailability

-- Run mock node server
runConfigCommand ConfigCommandArgs{ccaTrace, ccaPABConfig = Config {nodeServerConfig},ccaAvailability} (MockNode withoutMockServer) =
    liftIO $ NodeServer.main
        (toMockNodeServerLog ccaTrace)
        nodeServerConfig
        withoutMockServer
        ccaAvailability

-- Run mock metadata server
runConfigCommand ConfigCommandArgs{ccaTrace, ccaPABConfig = Config {metadataServerConfig}, ccaAvailability} Metadata =
    liftIO $ Metadata.main
        (toMetaDataLog ccaTrace)
        metadataServerConfig
        ccaAvailability

-- Run PAB webserver
runConfigCommand ConfigCommandArgs{ccaTrace, ccaPABConfig=config@Config{pabWebserverConfig}, ccaAvailability, ccaStorageBackend} PABWebserver =
        fmap (either (error . show) id)
        $ App.runApp ccaStorageBackend (toPABMsg ccaTrace) config
        $ do
            App.AppEnv{App.walletClientEnv} <- Core.askUserEnv @ContractExe @App.AppEnv
            (mvar, _) <- PABServer.startServer pabWebserverConfig (Left walletClientEnv) ccaAvailability
            liftIO $ takeMVar mvar

-- Fork a list of commands
runConfigCommand c@ConfigCommandArgs{ccaAvailability} (ForkCommands commands) =
    void $ do
        threads <- traverse forkCommand commands
        putStrLn "Started all commands."
        waitAny threads
  where
    forkCommand :: ConfigCommand -> IO (Async ())
    forkCommand subcommand = do
      putStrLn $ "Starting: " <> show subcommand
      asyncId <- async . void . runConfigCommand c $ subcommand
      putStrLn $ "Started: " <> show subcommand
      starting ccaAvailability
      pure asyncId

-- Run the chain-index service
runConfigCommand ConfigCommandArgs{ccaTrace, ccaPABConfig=Config {nodeServerConfig, chainIndexConfig}, ccaAvailability} ChainIndex =
    ChainIndex.main
        (toChainIndexLog ccaTrace)
        chainIndexConfig
        (mscSocketPath nodeServerConfig)
        (mscSlotConfig nodeServerConfig)
        ccaAvailability

-- Install a contract
runConfigCommand ConfigCommandArgs{ccaTrace, ccaPABConfig=Config{dbConfig}} (InstallContract contractExe) =
      do
        connection <- App.dbConnect (LM.convertLog LM.PABMsg ccaTrace) dbConfig
        fmap (either (error . show) id)
            $ Beam.runBeamStoreAction connection (LM.convertLog LM.PABMsg ccaTrace)
            $ Contract.addDefinition @ContractExe contractExe

-- Get the state of a contract
runConfigCommand ConfigCommandArgs{ccaTrace, ccaPABConfig=Config{dbConfig}} (ContractState contractInstanceId) = do
    connection <- App.dbConnect (LM.convertLog LM.PABMsg ccaTrace) dbConfig
    fmap (either (error . show) id)
        $ Beam.runBeamStoreAction connection (LM.convertLog LM.PABMsg ccaTrace)
        $ interpret (LM.handleLogMsgTrace ccaTrace)
        $ do
            s <- Contract.getState @ContractExe contractInstanceId
            let outputState = Contract.serialisableState (Proxy @ContractExe) s
            logInfo @(LM.AppMsg ContractExe) $ LM.PABMsg $ LM.SCoreMsg $ LM.FoundContract $ Just outputState
            drainLog

-- Get all installed contracts
runConfigCommand ConfigCommandArgs{ccaTrace, ccaPABConfig=Config{dbConfig}} ReportInstalledContracts = do
    connection <- App.dbConnect (LM.convertLog LM.PABMsg ccaTrace) dbConfig
    fmap (either (error . show) id)
        $ Beam.runBeamStoreAction connection (LM.convertLog LM.PABMsg ccaTrace)
        $ interpret (LM.handleLogMsgTrace ccaTrace)
        $ do
            installedContracts <- Contract.getDefinitions @ContractExe
            traverse_ (logInfo @(LM.AppMsg ContractExe) . LM.InstalledContract . render . pretty) installedContracts
            drainLog
                where
                    render = renderStrict . layoutPretty defaultLayoutOptions

-- Get all active contracts
runConfigCommand ConfigCommandArgs{ccaTrace, ccaPABConfig=Config{dbConfig}} ReportActiveContracts = do
    connection <- App.dbConnect (LM.convertLog LM.PABMsg ccaTrace) dbConfig
    fmap (either (error . show) id)
        $ Beam.runBeamStoreAction connection (LM.convertLog LM.PABMsg ccaTrace)
        $ interpret (LM.handleLogMsgTrace ccaTrace)
        $ do
            logInfo @(LM.AppMsg ContractExe) LM.ActiveContractsMsg
            instancesById <- Contract.getActiveContracts @ContractExe
            let idsByDefinition = Map.fromListWith (<>) $ fmap (\(inst, ContractActivationArgs{caID}) -> (caID, Set.singleton inst)) $ Map.toList instancesById
            traverse_ (\(e, s) -> logInfo @(LM.AppMsg ContractExe) $ LM.ContractInstances e (Set.toList s)) $ Map.toAscList idsByDefinition
            drainLog

-- Get history of a specific contract
runConfigCommand ConfigCommandArgs{ccaTrace, ccaPABConfig=Config{dbConfig}} (ReportContractHistory contractInstanceId) = do
    connection <- App.dbConnect (LM.convertLog LM.PABMsg ccaTrace) dbConfig
    fmap (either (error . show) id)
        $ Beam.runBeamStoreAction connection (LM.convertLog LM.PABMsg ccaTrace)
        $ interpret (LM.handleLogMsgTrace ccaTrace)
        $ do
            logInfo @(LM.AppMsg ContractExe) LM.ContractHistoryMsg
            s <- Contract.getState @ContractExe contractInstanceId
            let State.ContractResponse{State.newState=State{record}} = Contract.serialisableState (Proxy @ContractExe) s
            traverse_ logStep (responses record)
            drainLog
                where
                    logStep response = logInfo @(LM.AppMsg ContractExe) $ LM.ContractHistoryItem contractInstanceId (snd <$> response)

toPABMsg :: Trace m (LM.AppMsg ContractExe) -> Trace m (LM.PABLogMsg ContractExe)
toPABMsg = LM.convertLog LM.PABMsg

toChainIndexLog :: Trace m (LM.AppMsg ContractExe) -> Trace m LM.ChainIndexServerMsg
toChainIndexLog = LM.convertLog $ LM.PABMsg . LM.SChainIndexServerMsg

toWalletLog :: Trace m (LM.AppMsg ContractExe) -> Trace m WalletMsg
toWalletLog = LM.convertLog $ LM.PABMsg . LM.SWalletMsg

toMetaDataLog :: Trace m (LM.AppMsg ContractExe) -> Trace m LM.MetadataLogMessage
toMetaDataLog = LM.convertLog $ LM.PABMsg . LM.SMetaDataLogMsg

toMockNodeServerLog :: Trace m (LM.AppMsg ContractExe) -> Trace m LM.MockServerLogMsg
toMockNodeServerLog = LM.convertLog $ LM.PABMsg . LM.SMockserverLogMsg

-- | Wait for some time to allow all log messages to be printed to
--   the terminal.
drainLog :: Member DelayEffect effs => Eff effs ()
drainLog = delayThread (1 :: Second)
