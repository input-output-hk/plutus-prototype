{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE DerivingStrategies    #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE NamedFieldPuns        #-}
{-# LANGUAGE OverloadedStrings     #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE TypeApplications      #-}
{-# LANGUAGE TypeFamilies          #-}
{-# LANGUAGE TypeOperators         #-}

module PSGenerator
    ( generate
    ) where

import qualified Auth
import           Control.Applicative                        ((<|>))
import           Control.Lens                               (itraverse, set, (&))
import           Control.Monad                              (void)
import           Control.Monad.Catch                        (MonadMask)
import           Control.Monad.Except                       (MonadError, runExceptT)
import           Control.Monad.Except.Extras                (mapError)
import qualified Control.Monad.Freer.Log                    as Log
import           Control.Monad.IO.Class                     (MonadIO)
import qualified Crowdfunding
import qualified CrowdfundingSimulations
import           Data.Aeson                                 (ToJSON, toJSON)
import qualified Data.Aeson                                 as JSON
import qualified Data.Aeson.Encode.Pretty                   as JSON
import qualified Data.ByteString                            as BS
import qualified Data.ByteString.Lazy                       as BSL
import           Data.Monoid                                ()
import           Data.Proxy                                 (Proxy (Proxy))
import           Data.Text                                  (Text)
import qualified Data.Text.Encoding                         as T (decodeUtf8, encodeUtf8)
import           Data.Time.Units                            (Second)
import qualified ErrorHandling
import qualified ErrorHandlingSimulations
import qualified Game
import qualified GameSimulations
import qualified HelloWorld
import qualified HelloWorldSimulations
import qualified Interpreter                                as Webghc
import           Language.Haskell.Interpreter               (CompilationError, InterpreterError,
                                                             InterpreterResult (InterpreterResult),
                                                             SourceCode (SourceCode), Warning, result, warnings)
import           Language.Plutus.Contract.Checkpoint        (CheckpointKey, CheckpointLogMsg)
import           Language.PureScript.Bridge                 (BridgePart, Language (Haskell), SumType, buildBridge,
                                                             equal, genericShow, mkSumType, order, writePSTypesWith)
import           Language.PureScript.Bridge.CodeGenSwitches (ForeignOptions (ForeignOptions), genForeign,
                                                             unwrapSingleConstructors)
import           Language.PureScript.Bridge.TypeParameters  (A)
import           Ledger.Constraints.OffChain                (UnbalancedTx)
import qualified PSGenerator.Common
import qualified Playground.API                             as API
import qualified Playground.Interpreter                     as PI
import           Playground.Types                           (CompilationResult (CompilationResult), ContractCall,
                                                             ContractDemo (ContractDemo), Evaluation (Evaluation),
                                                             EvaluationResult, FunctionSchema, KnownCurrency,
                                                             PlaygroundError (InterpreterError),
                                                             Simulation (Simulation), SimulatorAction, SimulatorWallet,
                                                             contractDemoContext, contractDemoEditorContents,
                                                             contractDemoName, contractDemoSimulations, functionSchema,
                                                             knownCurrencies, program, simulationActions,
                                                             simulationWallets, sourceCode, wallets)
import           Playground.Usecases                        (crowdFunding, errorHandling, game, starter, vesting)
import qualified Playground.Usecases                        as Usecases
import           Schema                                     (FormSchema, formArgumentToJson)
import           Servant                                    ((:<|>))
import           Servant.PureScript                         (HasBridge, Settings, _generateSubscriberAPI, apiModuleName,
                                                             defaultBridge, defaultSettings, languageBridge,
                                                             writeAPIModuleWithSettings)
import qualified Starter
import qualified StarterSimulations
import           System.FilePath                            ((</>))
import qualified Vesting
import qualified VestingSimulations
import           Wallet.API                                 (WalletAPIError)
import           Wallet.Effects                             (AddressChangeRequest)
import qualified Wallet.Emulator.Chain                      as EM
import qualified Wallet.Emulator.ChainIndex                 as EM
import           Wallet.Emulator.ChainIndex.Index           (ChainIndexItem)
import qualified Wallet.Emulator.LogMessages                as EM
import qualified Wallet.Emulator.MultiAgent                 as EM
import qualified Wallet.Emulator.NodeClient                 as EM
import qualified Wallet.Emulator.Wallet                     as EM
import           Wallet.Rollup.Types                        (AnnotatedTx, BeneficialOwner, DereferencedInput,
                                                             SequenceId, TxKey)

myBridge :: BridgePart
myBridge =
    PSGenerator.Common.aesonBridge <|>
    PSGenerator.Common.containersBridge <|>
    PSGenerator.Common.languageBridge <|>
    PSGenerator.Common.ledgerBridge <|>
    PSGenerator.Common.servantBridge <|>
    PSGenerator.Common.miscBridge <|>
    defaultBridge

data MyBridge

myBridgeProxy :: Proxy MyBridge
myBridgeProxy = Proxy

instance HasBridge MyBridge where
    languageBridge _ = buildBridge myBridge

myTypes :: [SumType 'Haskell]
myTypes =
    PSGenerator.Common.ledgerTypes <>
    PSGenerator.Common.playgroundTypes <>
    [ (genericShow <*> (equal <*> mkSumType)) (Proxy @CompilationResult)
    , (genericShow <*> (equal <*> mkSumType)) (Proxy @Warning)
    , (genericShow <*> (equal <*> mkSumType)) (Proxy @SourceCode)
    , (genericShow <*> (equal <*> mkSumType)) (Proxy @EM.Wallet)
    , (genericShow <*> (equal <*> mkSumType)) (Proxy @Simulation)
    , (genericShow <*> (equal <*> mkSumType)) (Proxy @ContractDemo)
    , (genericShow <*> (equal <*> mkSumType)) (Proxy @SimulatorWallet)
    , (genericShow <*> mkSumType) (Proxy @CompilationError)
    , (genericShow <*> mkSumType) (Proxy @Evaluation)
    , (genericShow <*> mkSumType) (Proxy @EvaluationResult)
    , (genericShow <*> mkSumType) (Proxy @ChainIndexItem)
    , (genericShow <*> mkSumType) (Proxy @AddressChangeRequest)
    , (genericShow <*> mkSumType) (Proxy @EM.EmulatorEvent')
    , (genericShow <*> mkSumType) (Proxy @(EM.EmulatorTimeEvent A))
    , (genericShow <*> mkSumType) (Proxy @EM.ChainEvent)
    , (genericShow <*> mkSumType) (Proxy @Log.LogLevel)
    , (genericShow <*> mkSumType) (Proxy @(Log.LogMessage A))
    , (genericShow <*> mkSumType) (Proxy @EM.WalletEvent)
    , (genericShow <*> mkSumType) (Proxy @EM.NodeClientEvent)
    , (genericShow <*> mkSumType) (Proxy @EM.ChainIndexEvent)
    , (genericShow <*> mkSumType) (Proxy @PlaygroundError)
    , (equal <*> (genericShow <*> mkSumType)) (Proxy @WalletAPIError)
    , (order <*> (genericShow <*> mkSumType)) (Proxy @SequenceId)
    , (equal <*> (genericShow <*> mkSumType)) (Proxy @AnnotatedTx)
    , (equal <*> (genericShow <*> mkSumType)) (Proxy @DereferencedInput)
    , (order <*> (genericShow <*> mkSumType)) (Proxy @BeneficialOwner)
    , (equal <*> (genericShow <*> mkSumType)) (Proxy @TxKey)
    , (genericShow <*> mkSumType) (Proxy @InterpreterError)
    , (genericShow <*> (equal <*> mkSumType)) (Proxy @(InterpreterResult A))
    , (genericShow <*> mkSumType) (Proxy @CheckpointLogMsg)
    , (genericShow <*> mkSumType) (Proxy @CheckpointKey)
    , (genericShow <*> mkSumType) (Proxy @EM.RequestHandlerLogMsg)
    , (genericShow <*> mkSumType) (Proxy @EM.TxBalanceMsg)
    , (genericShow <*> mkSumType) (Proxy @UnbalancedTx)
    ]

mySettings :: Settings
mySettings =
    (defaultSettings & set apiModuleName "Playground.Server")
        {_generateSubscriberAPI = False}

multilineString :: Text -> Text -> Text
multilineString name value =
    "\n\n" <> name <> " :: String\n" <> name <> " = \"\"\"" <> value <> "\"\"\""

jsonExport :: ToJSON a => Text -> a -> Text
jsonExport name value =
    multilineString name (T.decodeUtf8 . BSL.toStrict $ JSON.encodePretty value)

sourceCodeExport :: Text -> SourceCode -> Text
sourceCodeExport name (SourceCode value) = multilineString name value

psModule :: Text -> Text -> Text
psModule name body = "module " <> name <> " where" <> body

------------------------------------------------------------
writeUsecases :: FilePath -> IO ()
writeUsecases outputDir = do
    let usecases =
            sourceCodeExport "vesting" vesting <>
            sourceCodeExport "game" game <>
            sourceCodeExport "crowdFunding" crowdFunding <>
            sourceCodeExport "errorHandling" errorHandling <>
            sourceCodeExport "starter" starter <>
            jsonExport "contractDemos" contractDemos
        usecasesModule = psModule "Playground.Usecases" usecases
    BS.writeFile
        (outputDir </> "Playground" </> "Usecases.purs")
        (T.encodeUtf8 usecasesModule)

------------------------------------------------------------
writeTestData :: FilePath -> IO ()
writeTestData outputDir = do
    let ContractDemo { contractDemoContext
                     , contractDemoSimulations
                     , contractDemoEditorContents
                     } = head contractDemos
    BSL.writeFile
        (outputDir </> "compilation_response.json")
        (JSON.encodePretty contractDemoContext)
    void $
        itraverse
            (\index ->
                 writeSimulation
                     (outputDir </> "evaluation_response" <>
                      show index <> ".json")
                     contractDemoEditorContents)
            contractDemoSimulations

writeSimulation :: FilePath -> SourceCode -> Simulation -> IO ()
writeSimulation filename sourceCode simulation = do
    result <- runExceptT $ runSimulation sourceCode simulation
    case result of
        Left err   -> fail $ "Error evaluating simulation: " <> show err
        Right json -> BSL.writeFile filename json

maxInterpretationTime :: Second
maxInterpretationTime = 80

runSimulation ::
       (MonadMask m, MonadError PlaygroundError m, MonadIO m)
    => SourceCode
    -> Simulation
    -> m BSL.ByteString
runSimulation sourceCode Simulation {simulationActions, simulationWallets} = do
    let evaluation =
            Evaluation
                { sourceCode
                , wallets = simulationWallets
                , program =
                      toJSON . encodeToText $ toExpression <$> simulationActions
                }
    expr <- PI.evaluationToExpr evaluation
    result <- mapError InterpreterError $ Webghc.compile maxInterpretationTime False (SourceCode expr)
    interpreterResult <- PI.decodeEvaluation result
    pure $ JSON.encodePretty interpreterResult

encodeToText :: ToJSON a => a -> Text
encodeToText = T.decodeUtf8 . BSL.toStrict . JSON.encode

toExpression :: SimulatorAction -> Maybe (ContractCall Text)
toExpression = traverse (fmap encodeToText . formArgumentToJson)

------------------------------------------------------------
generate :: FilePath -> IO ()
generate outputDir = do
    writeAPIModuleWithSettings
        mySettings
        outputDir
        myBridgeProxy
        (Proxy
             @(API.API
               :<|> Auth.FrontendAPI))
    writePSTypesWith
        (genForeign (ForeignOptions {unwrapSingleConstructors = True}))
        outputDir
        (buildBridge myBridge)
        myTypes
    writeUsecases outputDir
    writeTestData outputDir
    putStrLn $ "Done: " <> outputDir

------------------------------------------------------------
contractDemos :: [ContractDemo]
contractDemos =
    [ mkContractDemo
        "Hello, world"
        Usecases.helloWorld
        HelloWorldSimulations.simulations
        HelloWorld.schemas
        HelloWorld.registeredKnownCurrencies
    , mkContractDemo
          "Starter"
          Usecases.starter
          StarterSimulations.simulations
          Starter.schemas
          Starter.registeredKnownCurrencies
    , mkContractDemo
          "Game"
          Usecases.game
          GameSimulations.simulations
          Game.schemas
          Game.registeredKnownCurrencies
    , mkContractDemo
          "Vesting"
          Usecases.vesting
          VestingSimulations.simulations
          Vesting.schemas
          Vesting.registeredKnownCurrencies
    , mkContractDemo
          "Crowd Funding"
          Usecases.crowdFunding
          CrowdfundingSimulations.simulations
          Crowdfunding.schemas
          Crowdfunding.registeredKnownCurrencies
    , mkContractDemo
          "Error Handling"
          Usecases.errorHandling
          ErrorHandlingSimulations.simulations
          ErrorHandling.schemas
          ErrorHandling.registeredKnownCurrencies
    ]

mkContractDemo ::
       Text
    -> SourceCode
    -> [Simulation]
    -> [FunctionSchema FormSchema]
    -> [KnownCurrency]
    -> ContractDemo
mkContractDemo contractDemoName contractDemoEditorContents contractDemoSimulations functionSchema knownCurrencies =
    ContractDemo
        { contractDemoName
        , contractDemoEditorContents
        , contractDemoSimulations
        , contractDemoContext =
              InterpreterResult
                  { warnings = []
                  , result =
                        CompilationResult
                            {functionSchema, knownCurrencies}
                  }
        }
