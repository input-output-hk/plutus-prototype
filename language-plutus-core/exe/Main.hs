{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings     #-}
{-# LANGUAGE ScopedTypeVariables   #-}

module Main (main) where

import           Control.Exception                                          (toException)
import           Control.Monad
import           Control.Monad.Trans.Except                                 (runExceptT)
import           Data.Bifunctor                                             (first, second)
import           Data.Foldable                                              (traverse_)
import qualified Language.PlutusCore                                        as PLC
import qualified Language.PlutusCore.CBOR                                   ()
import qualified Language.PlutusCore.Evaluation.Machine.Cek                 as PLC
import qualified Language.PlutusCore.Evaluation.Machine.Ck                  as PLC
import qualified Language.PlutusCore.Evaluation.Machine.ExBudgetingDefaults as PLC
import qualified Language.PlutusCore.Generators                             as PLC
import qualified Language.PlutusCore.Generators.Interesting                 as PLC
import qualified Language.PlutusCore.Generators.Test                        as PLC
import qualified Language.PlutusCore.Pretty                                 as PLC
import qualified Language.PlutusCore.StdLib.Data.Bool                       as PLC
import qualified Language.PlutusCore.StdLib.Data.ChurchNat                  as PLC
import qualified Language.PlutusCore.StdLib.Data.Integer                    as PLC
import qualified Language.PlutusCore.StdLib.Data.Unit                       as PLC

import qualified Data.ByteString.Lazy                                       as BSL
import qualified Data.ByteString.Lazy.Char8                                 as BSL8
import qualified Data.Text                                                  as T
import           Data.Text.Encoding                                         (encodeUtf8)
import qualified Data.Text.IO                                               as T
import           Data.Text.Prettyprint.Doc
import           System.Exit

import           Codec.Serialise
import           Options.Applicative


type PlainProgram   = PLC.Program PLC.TyName PLC.Name PLC.DefaultUni ()
type ParsedProgram  = PLC.Program PLC.TyName PLC.Name PLC.DefaultUni PLC.AlexPosn
type PlcParserError = PLC.Error PLC.DefaultUni PLC.AlexPosn


---------------- Option parsers ----------------

data Input = FileInput FilePath | StdInput

input :: Parser Input
input = fileInput <|> stdInput

fileInput :: Parser Input
fileInput = FileInput <$> strOption
  (  long "file"
  <> short 'f'
  <> long "input"
  <> short 'i'
  <> metavar "FILENAME"
  <> help "Input file" )

stdInput :: Parser Input
stdInput = flag' StdInput
  (  long "stdin"
  <> help "Read from stdin" )


data Output = FileOutput FilePath | StdOutput

output :: Parser Output
output = fileOutput <|> stdOutput

fileOutput :: Parser Output
fileOutput = FileOutput <$> strOption
  (  long "output"
  <> short 'o'
  <> metavar "FILENAME"
  <> help "Output file" )

stdOutput :: Parser Output
stdOutput = flag' StdOutput
  (  long "stdout"
  <> help "Write to stdout" )


data Format = Plc | Cbor  -- Input/output format for programs

format :: Parser Format
format = flag Plc Cbor
  ( long "cbor"
  <> long "CBOR"
  <> short 'c'
  <> help "Input CBOR (default: input PLC)"
  )


data NormalizationMode = Required | NotRequired deriving (Show, Read)
data TypecheckOptions = TypecheckOptions Input Format
data EvalMode = CK | CEK deriving (Show, Read)
data EvalOptions = EvalOptions Input EvalMode Format
data PrintMode = Classic | Debug deriving (Show, Read)
data PrintOptions = PrintOptions Input PrintMode
data PlcToCborOptions = PlcToCborOptions Input Output
data CborToPlcOptions = CborToPlcOptions Input Output PrintMode
type ExampleName = T.Text
data ExampleMode = ExampleSingle ExampleName | ExampleAvailable
newtype ExampleOptions = ExampleOptions ExampleMode

-- Main commands
data Command = Typecheck TypecheckOptions
             | Eval EvalOptions
             | Example ExampleOptions
             | Print PrintOptions
             | PlcToCbor PlcToCborOptions
             | CborToPlc CborToPlcOptions

plutus :: ParserInfo Command
plutus = info (plutusOpts <**> helper) (progDesc "Plutus Core tool")

plutusOpts :: Parser Command
plutusOpts = hsubparser (
    command "typecheck" (info (Typecheck <$> typecheckOpts) (progDesc "Typecheck a Plutus Core program"))
    <> command "evaluate" (info (Eval <$> evalOpts) (progDesc "Evaluate a Plutus Core program"))
    <> command "example" (info (Example <$> exampleOpts) (progDesc "Show a Plutus Core program example. Usage: first request the list of available examples (optional step), then request a particular example by the name of a type/term. Note that evaluating a generated example may result in 'Failure'"))
    <> command "print" (info (Print <$> printOpts) (progDesc "Parse a program then prettyprint it"))
    <> command "plc-to-cbor" (info (PlcToCbor <$> plcToCborOpts) (progDesc "Convert a PLC source file to CBOR"))
    <> command "cbor-to-plc" (info (CborToPlc <$> cborToPlcOpts) (progDesc "Convert a CBOR file to PLC source"))
  )

typecheckOpts :: Parser TypecheckOptions
typecheckOpts = TypecheckOptions <$> input <*> format

evalMode :: Parser EvalMode
evalMode = option auto
  (  long "mode"
  <> short 'm'
  <> metavar "MODE"
  <> value CEK
  <> showDefault
  <> help "Evaluation mode (CK or CEK)" )

evalOpts :: Parser EvalOptions
evalOpts = EvalOptions <$> input <*> evalMode <*> format

printMode :: Parser PrintMode
printMode = option auto
  (  long "print-mode"
  <> metavar "MODE"
  <> value Classic
  <> showDefault
  <> help "Print mode: Classic -> plcPrettyClassicDef, Debug -> plcPrettyClassicDebug" )

printOpts :: Parser PrintOptions
printOpts = PrintOptions <$> input <*> printMode

plcToCborOpts :: Parser PlcToCborOptions
plcToCborOpts = PlcToCborOptions <$> input <*> output

cborToPlcOpts :: Parser CborToPlcOptions
cborToPlcOpts = CborToPlcOptions <$> input <*> output <*> printMode

exampleMode :: Parser ExampleMode
exampleMode = exampleAvailable <|> exampleSingle

exampleAvailable :: Parser ExampleMode
exampleAvailable = flag' ExampleAvailable
  (  long "available"
  <> short 'a'
  <> help "Show available examples")

exampleName :: Parser ExampleName
exampleName = strOption
  (  long "single"
  <> metavar "NAME"
  <> short 's'
  <> help "Show a single example")

exampleSingle :: Parser ExampleMode
exampleSingle = ExampleSingle <$> exampleName

exampleOpts :: Parser ExampleOptions
exampleOpts = ExampleOptions <$> exampleMode


---------------- Reading programs from files ----------------

-- Read a PLC source file
getPlcInput :: Input -> IO String
getPlcInput (FileInput file) = readFile file
getPlcInput StdInput         = getContents

-- Read and parse a PLC source file
parsePlcFile :: Input -> IO ParsedProgram
parsePlcFile inp = do
    contents <- getPlcInput inp
    let bsContents = (BSL.fromStrict . encodeUtf8 . T.pack) contents
    case PLC.runQuoteT $ runExceptT (PLC.parseScoped bsContents) of
        Left (errCheck :: PlcParserError) -> do
            T.putStrLn $ PLC.prettyPlcDefText errCheck
            exitFailure
        Right (Left (errEval :: PlcParserError)) -> do
            print errEval
            exitFailure
        Right (Right (p :: ParsedProgram)) ->
            return p

-- Read a PLC AST from a CBOR file
getCborInput :: Input -> IO BSL.ByteString
getCborInput StdInput         = BSL.getContents
getCborInput (FileInput file) = BSL.readFile file

-- Read either a PLC file or a CBOR file, depending on 'fmt'
getProg :: Input -> Format -> IO ParsedProgram
getProg inp fmt =
    case fmt of
      Plc  -> parsePlcFile inp
      Cbor -> do
               p <- getCborInput inp
               return $ fakeAlexPosn <$ (deserialise p :: PlainProgram)  -- FIXME: may cause error
                   where fakeAlexPosn = PLC.AlexPn 0 0 0


---------------- Typechecking ----------------

runTypecheck :: TypecheckOptions -> IO ()
runTypecheck (TypecheckOptions inp fmt) = do
    prog <- getProg inp fmt
    let cfg = PLC.defConfig
    case PLC.runQuoteT $ PLC.typecheckPipeline cfg prog of
      Left (e :: PlcParserError) -> do
            T.putStrLn $ PLC.prettyPlcDefText e
            exitFailure
      Right ty -> do
            T.putStrLn $ PLC.prettyPlcDefText ty
            exitSuccess


---------------- Evaluation ----------------

runEval :: EvalOptions -> IO ()
runEval (EvalOptions inp mode fmt) = do
  prog <- getProg inp fmt
  let evalFn = case mode of
                 CK  -> first toException . PLC.extractEvaluationResult . PLC.evaluateCk
                 CEK -> first toException . PLC.extractEvaluationResult . PLC.evaluateCek mempty PLC.defaultCostModel
  case evalFn . void . PLC.toTerm $ prog of
    Left errEval -> do
      print errEval
      exitFailure
    Right v -> do
      T.putStrLn $ PLC.prettyPlcDefText v
      exitSuccess


---------------- Parse and print a PLC source file ----------------

runPrint :: PrintOptions -> IO ()
runPrint (PrintOptions inp mode) =
  let printMethod = case mode of
            Classic -> PLC.prettyPlcClassicDef
            Debug   -> PLC.prettyPlcClassicDebug
  in do
    p <- parsePlcFile inp
    putStrLn . show . printMethod $ p


---------------- Convert a PLC source file to CBOR ----------------

runPlcToCbor :: PlcToCborOptions -> IO ()
runPlcToCbor (PlcToCborOptions inp outp) = do
  p <- parsePlcFile inp
  let cbor = serialise (() <$ p)
  case outp of
    FileOutput file -> BSL.writeFile file cbor
    StdOutput       -> BSL8.putStrLn cbor   -- BSL.putStrLn causes deprecation warnings


---------------- Convert a CBOR file to PLC source ----------------

runCborToPlc :: CborToPlcOptions -> IO ()
runCborToPlc (CborToPlcOptions inp outp mode) = do
  cbor <- getCborInput inp
  let plc = deserialise cbor :: PlainProgram
      printMethod = case mode of
            Classic -> PLC.prettyPlcClassicDef
            Debug   -> PLC.prettyPlcClassicDebug
  case outp of
    FileOutput file -> writeFile file . show . printMethod $ plc
    StdOutput       -> putStrLn . show . printMethod $ plc


---------------- Examples ----------------

data TypeExample = TypeExample (PLC.Kind ()) (PLC.Type PLC.TyName PLC.DefaultUni ())
data TermExample = TermExample
    (PLC.Type PLC.TyName PLC.DefaultUni ())
    (PLC.Term PLC.TyName PLC.Name PLC.DefaultUni ())
data SomeExample = SomeTypeExample TypeExample | SomeTermExample TermExample

prettySignature :: ExampleName -> SomeExample -> Doc ann
prettySignature name (SomeTypeExample (TypeExample kind _)) =
    pretty name <+> "::" <+> PLC.prettyPlcDef kind
prettySignature name (SomeTermExample (TermExample ty _)) =
    pretty name <+> ":"  <+> PLC.prettyPlcDef ty

prettyExample :: SomeExample -> Doc ann
prettyExample (SomeTypeExample (TypeExample _ ty))   = PLC.prettyPlcDef ty
prettyExample (SomeTermExample (TermExample _ term)) =
    PLC.prettyPlcDef $ PLC.Program () (PLC.defaultVersion ()) term

toTermExample :: PLC.Term PLC.TyName PLC.Name PLC.DefaultUni () -> TermExample
toTermExample term = TermExample ty term where
    program = PLC.Program () (PLC.defaultVersion ()) term
    ty = case PLC.runQuote . runExceptT $ PLC.typecheckPipeline PLC.defConfig program of
        Left (err :: PLC.Error PLC.DefaultUni ()) -> error $ PLC.prettyPlcDefString err
        Right vTy                                 -> PLC.unNormalized vTy

getInteresting :: IO [(ExampleName, PLC.Term PLC.TyName PLC.Name PLC.DefaultUni ())]
getInteresting =
    sequence $ PLC.fromInterestingTermGens $ \name gen -> do
        PLC.TermOf term _ <- PLC.getSampleTermValue gen
        pure (T.pack name, term)

simpleExamples :: [(ExampleName, SomeExample)]
simpleExamples =
    [ ("succInteger", SomeTermExample $ toTermExample PLC.succInteger)
    , ("unit"       , SomeTypeExample $ TypeExample (PLC.Type ()) PLC.unit)
    , ("unitval"    , SomeTermExample $ toTermExample PLC.unitval)
    , ("bool"       , SomeTypeExample $ TypeExample (PLC.Type ()) PLC.bool)
    , ("true"       , SomeTermExample $ toTermExample PLC.true)
    , ("false"      , SomeTermExample $ toTermExample PLC.false)
    , ("churchNat"  , SomeTypeExample $ TypeExample (PLC.Type ()) PLC.churchNat)
    , ("churchZero" , SomeTermExample $ toTermExample PLC.churchZero)
    , ("churchSucc" , SomeTermExample $ toTermExample PLC.churchSucc)
    ]

getAvailableExamples :: IO [(ExampleName, SomeExample)]
getAvailableExamples = do
    interesting <- getInteresting
    pure $ simpleExamples ++ map (second $ SomeTermExample . toTermExample) interesting

-- The implementation is a little hacky: we generate interesting examples when the list of examples
-- is requsted and at each lookup of a particular example. I.e. each time we generate distinct
-- terms. But types of those terms must not change across requests, so we're safe.
runExample :: ExampleOptions -> IO ()
runExample (ExampleOptions ExampleAvailable)     = do
    examples <- getAvailableExamples
    traverse_ (T.putStrLn . PLC.docText . uncurry prettySignature) examples
runExample (ExampleOptions (ExampleSingle name)) = do
    examples <- getAvailableExamples
    T.putStrLn $ case lookup name examples of
        Nothing -> "Unknown name: " <> name
        Just ex -> PLC.docText $ prettyExample ex


---------------- Driver ----------------

main :: IO ()
main = do
    options <- customExecParser (prefs showHelpOnEmpty) plutus
    case options of
        Typecheck tos  -> runTypecheck tos
        Eval eos       -> runEval eos
        Example eos    -> runExample eos
        Print dos      -> runPrint dos
        PlcToCbor opts -> runPlcToCbor opts
        CborToPlc opts -> runCborToPlc opts


