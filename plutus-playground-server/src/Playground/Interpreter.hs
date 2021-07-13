{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE NamedFieldPuns      #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE RecordWildCards     #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell     #-}
{-# LANGUAGE TypeApplications    #-}

module Playground.Interpreter where

import           Control.Exception            (IOException, try)
import           Control.Monad.Catch          (MonadMask)
import           Control.Monad.Error.Class    (MonadError, liftEither, throwError)
import           Control.Monad.Except.Extras  (mapError)
import           Control.Monad.IO.Class       (MonadIO, liftIO)
import qualified Control.Newtype.Generics     as Newtype
import qualified Data.Aeson                   as JSON
import           Data.Bifunctor               (first)
import qualified Data.ByteString.Char8        as BS8
import qualified Data.ByteString.Lazy.Char8   as BSL
import           Data.Proxy                   (Proxy (Proxy))
import           Data.Text                    (Text)
import qualified Data.Text                    as Text
import           Language.Haskell.Interpreter (CompilationError (CompilationError, RawError),
                                               InterpreterError (CompilationErrors),
                                               InterpreterResult (InterpreterResult), SourceCode (SourceCode),
                                               Warning (Warning), avoidUnsafe)
import           Language.Haskell.TH          (Ppr, Q, pprint, runQ)
import           Language.Haskell.TH.Syntax   (liftString)
import           Playground.Types             (CompilationResult (CompilationResult),
                                               Evaluation (program, sourceCode, wallets), EvaluationResult,
                                               PlaygroundError (InterpreterError, JsonDecodingError, OtherError, decodingError, expected, input))
import           Servant.Client               (ClientEnv, ClientM, client, runClientM)
import qualified Text.Regex                   as Regex
import           Webghc.Server                (CompileRequest (CompileRequest))
import qualified Webghc.Server                as Webghc

replaceModuleName :: Text -> Text
replaceModuleName script =
  let scriptString = Text.unpack script
      regex = Regex.mkRegex "module .* where"
   in Text.pack $ Regex.subRegex regex scriptString "module Main where"

ensureMinimumImports :: (MonadError InterpreterError m) => SourceCode -> m ()
ensureMinimumImports script =
  let scriptString = Text.unpack . Newtype.unpack $ script
      regex =
        Regex.mkRegex
          "^import[ \t]+Playground.Contract([ ]*$|[ \t]+\\(.*printSchemas.*\\)|[ \t]+\\(.*printSchemas.*\\))"
      mMatches = Regex.matchRegexAll regex scriptString
   in case mMatches of
        Just _ -> pure ()
        Nothing ->
          let filename = ""
              row = 1
              column = 1
              text =
                [ "You need to import `printSchemas` in order to compile successfully, you can do this with either",
                  "`import Playground.Contract`",
                  "or",
                  "`import Playground.Contract (printSchemas)`"
                ]
              errors = [CompilationError filename row column text]
           in throwError $ CompilationErrors errors

ensureKnownCurrenciesExists :: Text -> Text
ensureKnownCurrenciesExists script =
  let scriptString = Text.unpack script
      regex = Regex.mkRegex "^\\$\\(mkKnownCurrencies \\[.*])"
      mMatches = Regex.matchRegexAll regex scriptString
   in case mMatches of
        Nothing -> script <> "\n$(mkKnownCurrencies [])"
        Just _  -> script

mkCompileScript :: Text -> Text
mkCompileScript script =
  replaceModuleName script
    <> Text.unlines
      [ "",
        "$ensureKnownCurrencies",
        "",
        "main :: IO ()",
        "main = printSchemas (schemas, registeredKnownCurrencies)"
      ]

runghc :: CompileRequest -> ClientM (Either InterpreterError (InterpreterResult String))
runghc = client (Proxy @Webghc.FrontendAPI)

runscript ::
  ( MonadMask m,
    MonadIO m,
    MonadError InterpreterError m
  ) =>
  ClientEnv ->
  Text ->
  m (InterpreterResult String)
runscript clientEnv code = do
  res <- liftIO $ flip runClientM clientEnv $ runghc $ CompileRequest {code, implicitPrelude = False}
  case res of
    Left e          -> throwError (CompilationErrors [RawError (Text.pack (show e))])
    Right (Left e)  -> throwError e
    Right (Right r) -> pure r

checkCode :: MonadError InterpreterError m => SourceCode -> m ()
checkCode source = do
  avoidUnsafe source
  ensureMinimumImports source

getCompilationResult :: MonadError InterpreterError m => InterpreterResult String -> m (InterpreterResult CompilationResult)
getCompilationResult (InterpreterResult warnings result) =
  let eSchema = JSON.eitherDecodeStrict . BS8.pack $ result
   in case eSchema of
        Left err ->
          throwError . CompilationErrors . pure . RawError $
            "unable to decode compilation result: " <> Text.pack err
              <> "\n"
              <> Text.pack result
        Right ([schema], currencies) -> do
          let warnings' =
                Warning
                  "It looks like you have not made any functions available, use `$(mkFunctions ['functionA, 'functionB])` to be able to use `functionA` and `functionB`" :
                warnings
          pure . InterpreterResult warnings' $
            CompilationResult [schema] currencies
        Right (schemas, currencies) ->
          pure . InterpreterResult warnings $
            CompilationResult schemas currencies

compile ::
  ( MonadMask m,
    MonadIO m,
    MonadError InterpreterError m
  ) =>
  ClientEnv ->
  SourceCode ->
  m (InterpreterResult CompilationResult)
compile clientEnv source = do
  -- There are a couple of custom rules required for compilation
  checkCode source
  result <- runscript clientEnv $ mkCompileScript (Newtype.unpack source)
  getCompilationResult result

evaluationToExpr :: (MonadError PlaygroundError m, MonadIO m) => Evaluation -> m Text
evaluationToExpr evaluation = do
  let source = sourceCode evaluation
  mapError InterpreterError $ avoidUnsafe source
  expr <- mkExpr evaluation
  pure $ mkRunScript source (Text.pack expr)

decodeEvaluation :: MonadError PlaygroundError m => InterpreterResult String -> m (InterpreterResult EvaluationResult)
decodeEvaluation (InterpreterResult warnings result) =
  let decodeResult = JSON.eitherDecodeStrict . BS8.pack $ result :: Either String (Either PlaygroundError EvaluationResult)
   in case decodeResult of
        Left err ->
          throwError
            JsonDecodingError
              { expected = "EvaluationResult",
                decodingError = err,
                input = result
              }
        Right eResult ->
          case eResult of
            Left err -> throwError err
            Right result' ->
              pure $ InterpreterResult warnings result'

evaluateSimulation ::
  ( MonadMask m,
    MonadIO m,
    MonadError PlaygroundError m
  ) =>
  ClientEnv ->
  Evaluation ->
  m (InterpreterResult EvaluationResult)
evaluateSimulation clientEnv evaluation = do
  expr <- evaluationToExpr evaluation
  result <- mapError InterpreterError $ runscript clientEnv expr
  decodeEvaluation result

mkRunScript :: SourceCode -> Text -> Text
mkRunScript (SourceCode script) expr =
  replaceModuleName script <> "\n\nmain :: IO ()" <> "\nmain = printJson $ "
    <> expr

mkExpr :: (MonadError PlaygroundError m, MonadIO m) => Evaluation -> m String
mkExpr evaluation = do
  let programJson = liftString . BSL.unpack . JSON.encode $ program evaluation
      simulatorWalletsJson =
        liftString . BSL.unpack . JSON.encode $ wallets evaluation
  printQ [|stage endpoints $(programJson) $(simulatorWalletsJson)|]

printQ :: (MonadError PlaygroundError m, MonadIO m, Ppr a) => Q a -> m String
printQ q = do
  str <- liftIO . fmap toPlaygroundError . try . runQ . fmap pprint $ q
  liftEither str
  where
    toPlaygroundError :: Either IOException a -> Either PlaygroundError a
    toPlaygroundError = first (OtherError . show)

{-{- HLINT ignore getJsonString -}-}
getJsonString :: (MonadError PlaygroundError m) => JSON.Value -> m String
getJsonString (JSON.String s) = pure $ Text.unpack s
getJsonString v =
  throwError
    JsonDecodingError
      { expected = "String",
        input = BSL.unpack $ JSON.encode v,
        decodingError = "Expected a String."
      }
