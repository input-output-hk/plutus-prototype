{-# LANGUAGE BangPatterns              #-}
{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE LambdaCase                #-}
{-# LANGUAGE MultiParamTypeClasses     #-}
{-# LANGUAGE OverloadedStrings         #-}
{-# LANGUAGE TypeApplications          #-}

module Main (main) where

import qualified PlutusCore                               as PLC
import qualified PlutusCore.CBOR                          as PLC
import qualified PlutusCore.Evaluation.Machine.Ck         as Ck
import           PlutusCore.Evaluation.Machine.ExBudget   (ExBudget (..), ExRestrictingBudget (..))
import           PlutusCore.Evaluation.Machine.ExMemory   (ExCPU (..), ExMemory (..))
import qualified PlutusCore.Generators                    as Gen
import qualified PlutusCore.Generators.Interesting        as Gen
import qualified PlutusCore.Generators.Test               as Gen
import qualified PlutusCore.Pretty                        as PP
import qualified PlutusCore.StdLib.Data.Bool              as StdLib
import qualified PlutusCore.StdLib.Data.ChurchNat         as StdLib
import qualified PlutusCore.StdLib.Data.Integer           as StdLib
import qualified PlutusCore.StdLib.Data.Unit              as StdLib
import qualified UntypedPlutusCore                        as UPLC
import qualified UntypedPlutusCore.Evaluation.Machine.Cek as Cek


import           Codec.Serialise
import           Control.DeepSeq                          (NFData, rnf)
import           Control.Monad
import           Control.Monad.Trans.Except               (runExcept, runExceptT)
import           Data.Bifunctor                           (second)
import qualified Data.ByteString.Lazy                     as BSL
import           Data.Foldable                            (asum, traverse_)
import           Data.Function                            ((&))
import           Data.Functor                             ((<&>))
import qualified Data.HashMap.Monoidal                    as H
import           Data.List                                (nub)
import qualified Data.List                                as List
import           Data.List.Split                          (splitOn)
import qualified Data.Text                                as T
import           Data.Text.Encoding                       (encodeUtf8)
import qualified Data.Text.IO                             as T
import           Data.Text.Prettyprint.Doc                (Doc, pretty, (<+>))
import           Data.Traversable                         (for)
import           Flat
import           Options.Applicative
import           System.CPUTime                           (getCPUTime)
import           System.Exit                              (exitFailure, exitSuccess)
import           System.Mem                               (performGC)
import           Text.Printf                              (printf)
import           Text.Read                                (readMaybe)

{- Note [Annotation types] This program now reads and writes CBOR-serialised PLC
   ASTs.  In all cases we require the annotation type to be ().  There are two
   reasons for this.  Firstly, ASTs serialised for transmission to the chain
   will always have unit annotations because we can save space by omitting
   annotations in the CBOR (using the OmitUnitAnnotations class from CBOR.hs),
   so it makes sense for the program to deal with these.  Secondly, the
   annotation type has to be specified when we're deserialising CBOR (in order
   to check that the AST has the correct type), so it's difficult to deal with
   CBOR with arbitrary annotation types: fixing the annotation type to be () is
   the simplest thing to do and fits our use case.
 -}


-- | Our internal representation of programs is as ASTs over the Name type.
type TypedProgram a = PLC.Program PLC.TyName PLC.Name PLC.DefaultUni PLC.DefaultFun a
type UntypedProgram a = UPLC.Program PLC.Name PLC.DefaultUni PLC.DefaultFun a

data Program a =
      TypedProgram (TypedProgram a)
    | UntypedProgram (UntypedProgramDeBruijn a)
    deriving (Functor)

instance (PP.PrettyBy PP.PrettyConfigPlc (Program a)) where
    prettyBy cfg (TypedProgram p)   = PP.prettyBy cfg p
    prettyBy cfg (UntypedProgram p) = PP.prettyBy cfg p

-- | Untyped AST with names consisting solely of De Bruijn indices. This is
-- currently only used for intermediate values during CBOR/Flat
-- serialisation/deserialisation.  We may wish to add TypedProgramDeBruijn as
-- well if we modify the CEK machine to run directly on de Bruijnified ASTs, but
-- support for this is lacking elsewhere at the moment.
type UntypedProgramDeBruijn a = UPLC.Program UPLC.DeBruijn PLC.DefaultUni PLC.DefaultFun a

type PlcParserError = PLC.Error PLC.DefaultUni PLC.DefaultFun PLC.AlexPosn


---------------- Types for commands and arguments ----------------

data Input       = FileInput FilePath | StdInput
data Output      = FileOutput FilePath | StdOutput
data Language    = TypedPLC | UntypedPLC
data TimingMode  = NoTiming | Timing Integer deriving (Eq)  -- Report program execution time?
data CekModel    = Default | Unit   -- Which cost model should we use for CEK machine steps?
data PrintMode   = Classic | Debug | Readable | ReadableDebug deriving (Show, Read)
type ExampleName = T.Text
data ExampleMode = ExampleSingle ExampleName | ExampleAvailable
data EvalMode    = CK | CEK deriving (Show, Read)
data BudgetMode  = Silent
                 | forall cost. (Eq cost, NFData cost, PrintBudgetState cost) =>
                     Verbose (Cek.ExBudgetMode cost PLC.DefaultUni PLC.DefaultFun)
data AstNameType = Named | DeBruijn  -- Do we use Names or de Bruijn indices when (de)serialising ASTs?
type Files       = [FilePath]

data Format = Plc | Cbor AstNameType | Flat AstNameType -- Input/output format for programs
instance Show Format where
    show Plc             = "plc"
    show (Cbor Named)    = "cbor-named"
    show (Cbor DeBruijn) = "cbor-deBruijn"
    show (Flat Named)    = "flat-named"
    show (Flat DeBruijn) = "flat-deBruijn"

data TypecheckOptions = TypecheckOptions Input Format
data ConvertOptions   = ConvertOptions Language Input Format Output Format PrintMode
data PrintOptions     = PrintOptions Language Input PrintMode
data ExampleOptions   = ExampleOptions Language ExampleMode
data EraseOptions     = EraseOptions Input Format Output Format PrintMode
data EvalOptions      = EvalOptions Language Input Format EvalMode PrintMode BudgetMode TimingMode CekModel
data ApplyOptions     = ApplyOptions Language Files Format Output Format PrintMode

-- Main commands
data Command = Apply     ApplyOptions
             | Typecheck TypecheckOptions
             | Convert   ConvertOptions
             | Print     PrintOptions
             | Example   ExampleOptions
             | Erase     EraseOptions
             | Eval      EvalOptions


---------------- Option parsers ----------------

typedPLC :: Parser Language
typedPLC = flag UntypedPLC TypedPLC (long "typed" <> help "Use typed Plutus Core")

untypedPLC :: Parser Language
untypedPLC = flag UntypedPLC UntypedPLC (long "untyped" <> help "Use untyped Plutus Core (default)")
-- ^ NB: default is always UntypedPLC

languagemode :: Parser Language
languagemode = typedPLC <|> untypedPLC

-- | Parser for an input stream. If none is specified, default to stdin: this makes use in pipelines easier
input :: Parser Input
input = fileInput <|> stdInput <|> pure StdInput

fileInput :: Parser Input
fileInput = FileInput <$> strOption
  (  long "input"
  <> short 'i'
  <> metavar "FILENAME"
  <> help "Input file" )

stdInput :: Parser Input
stdInput = flag' StdInput
  (  long "stdin"
  <> help "Read from stdin (default)" )

-- | Parser for an output stream. If none is specified, default to stdout: this makes use in pipelines easier
output :: Parser Output
output = fileOutput <|> stdOutput <|> pure StdOutput

fileOutput :: Parser Output
fileOutput = FileOutput <$> strOption
  (  long "output"
  <> short 'o'
  <> metavar "FILENAME"
  <> help "Output file" )

stdOutput :: Parser Output
stdOutput = flag' StdOutput
  (  long "stdout"
  <> help "Write to stdout (default)" )

formatHelp :: String
formatHelp = "plc, cbor (de Bruijn indices), cbor-named (names), flat (de Bruijn indices), or flat-named (names)"

formatReader :: String -> Maybe Format
formatReader =
    \case
         "plc"           -> Just Plc
         "cbor-named"    -> Just (Cbor Named)
         "cbor"          -> Just (Cbor DeBruijn)
         "cbor-deBruijn" -> Just (Cbor DeBruijn)
         "flat-named"    -> Just (Flat Named)
         "flat"          -> Just (Flat DeBruijn)
         "flat-deBruijn" -> Just (Flat DeBruijn)
         _               -> Nothing

inputformat :: Parser Format
inputformat = option (maybeReader formatReader)
  (  long "if"
  <> long "input-format"
  <> metavar "FORMAT"
  <> value Plc
  <> showDefault
  <> help ("Input format: " ++ formatHelp))

outputformat :: Parser Format
outputformat = option (maybeReader formatReader)
  (  long "of"
  <> long "output-format"
  <> metavar "FORMAT"
  <> value Plc
  <> showDefault
  <> help ("Output format: " ++ formatHelp))


-- Reader for budget.  The --restricting option requires two integer arguments
-- and the easiest way to do this is to supply a colon-separated pair of
-- integers.
exbudgetReader :: ReadM ExBudget
exbudgetReader = do
  s <- str
  case splitOn ":" s of
    [a,b] -> case (readMaybe a, readMaybe b) of
               (Just cpu, Just mem) -> pure $ ExBudget (ExCPU cpu) (ExMemory mem)
               _                    -> readerError badfmt
    _     -> readerError badfmt
    where badfmt = "Invalid budget (expected eg 10000:50000)"

restrictingbudgetEnormous :: Parser BudgetMode
restrictingbudgetEnormous = flag' (Verbose Cek.restrictingEnormous)
                            (  long "restricting-enormous"
                            <> short 'r'
                            <> help "Run the machine in restricting mode with an enormous budget" )

restrictingbudget :: Parser BudgetMode
restrictingbudget = Verbose . Cek.restricting . ExRestrictingBudget
                    <$> option exbudgetReader
                            (  long "restricting"
                            <> short 'R'
                            <> metavar "ExCPU:ExMemory"
                            <> help "Run the machine in restricting mode with the given limits" )

countingbudget :: Parser BudgetMode
countingbudget = flag' (Verbose Cek.counting)
                 (  long "counting"
                 <> short 'c'
                 <> help "Run machine in counting mode and report results" )

tallyingbudget :: Parser BudgetMode
tallyingbudget = flag' (Verbose Cek.tallying)
                 (  long "tallying"
                 <> short 't'
                 <> help "Run machine in tallying mode and report results" )

budgetmode :: Parser BudgetMode
budgetmode = asum
    [ restrictingbudgetEnormous
    , restrictingbudget
    , countingbudget
    , tallyingbudget
    , pure Silent
    ]

-- -x -> run 100 times and print the mean time
timing1 :: Parser TimingMode
timing1 = flag NoTiming (Timing 100)
  (  short 'x'
  <> help "Report mean execution time of program over 100 repetitions"
  )

-- -X N -> run N times and print the mean time
timing2 :: Parser TimingMode
timing2 = Timing <$> option auto
  (  long "time-execution"
  <> short 'X'
  <> metavar "N"
  <> help "Report mean execution time of program over N repetitions. Use a large value of N if possible to get accurate results."
  )

-- We really do need two separate parsers here.
-- See https://github.com/pcapriotti/optparse-applicative/issues/194#issuecomment-205103230
timingmode :: Parser TimingMode
timingmode = timing1 <|> timing2

cekmodel :: Parser CekModel
cekmodel = flag Default Unit
           (  short '1'
           <> long "unit-cek-model"
           <> help "Use unit AST node costs for CEK cost model (tallying mode only)"
           )

files :: Parser Files
files = some (argument str (metavar "[FILES...]"))

applyOpts :: Parser ApplyOptions
applyOpts = ApplyOptions <$> languagemode <*> files <*> inputformat <*> output <*> outputformat <*> printmode

typecheckOpts :: Parser TypecheckOptions
typecheckOpts = TypecheckOptions <$> input <*> inputformat

printmode :: Parser PrintMode
printmode = option auto
  (  long "print-mode"
  <> metavar "MODE"
  <> value Classic
  <> showDefault
  <> help ("Print mode for plc output (ignored elsewhere): Classic -> plcPrettyClassicDef, Debug -> plcPrettyClassicDebug, "
        ++ "Readable -> prettyPlcReadableDef, ReadableDebug -> prettyPlcReadableDebug" ))

printOpts :: Parser PrintOptions
printOpts = PrintOptions <$> languagemode <*> input <*> printmode

convertOpts :: Parser ConvertOptions
convertOpts = ConvertOptions <$> languagemode <*> input <*> inputformat <*> output <*> outputformat <*> printmode

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
exampleOpts = ExampleOptions <$> languagemode <*> exampleMode

eraseOpts :: Parser EraseOptions
eraseOpts = EraseOptions <$> input <*> inputformat <*> output <*> outputformat <*> printmode

evalmode :: Parser EvalMode
evalmode = option auto
  (  long "mode"
  <> short 'm'
  <> metavar "MODE"
  <> value CEK
  <> showDefault
  <> help "Evaluation mode (CK or CEK)" )

evalOpts :: Parser EvalOptions
evalOpts = EvalOptions <$> languagemode <*> input <*> inputformat <*> evalmode <*> printmode <*> budgetmode <*> timingmode <*> cekmodel

helpText :: String
helpText =
       "This program provides a number of utilities for dealing with Plutus Core "
    ++ "programs, including typechecking, evaluation, and conversion between a "
    ++ "number of different formats.  The program also provides a number of example "
    ++ "typed Plutus Core programs.  Some commands read or write Plutus Core abstract "
    ++ "syntax trees serialised in CBOR or Flat format: ASTs are always written with "
    ++ "unit annotations, and any CBOR/Flat-encoded AST supplied as input must also be "
    ++ "equipped with unit annotations.  Attempting to read a serialised AST with any "
    ++ "non-unit annotation type will cause an error."

plutus :: ParserInfo Command
plutus = info (plutusOpts <**> helper) (fullDesc <> header "Plutus Core tool" <> progDesc helpText)

plutusOpts :: Parser Command
plutusOpts = hsubparser (
       command "apply"
           (info (Apply <$> applyOpts)
            (progDesc $ "Given a list of input scripts f g1 g2 ... gn, output a script consisting of (... ((f g1) g2) ... gn); "
            ++ "for example, 'plc apply --if cbor Validator.cbor Datum.cbor Redeemer.cbor Context.cbor --of cbor -o Script.cbor'"))
    <> command "print"
           (info (Print <$> printOpts)
            (progDesc "Parse a program then prettyprint it."))
    <> command "convert"
           (info (Convert <$> convertOpts)
            (progDesc "Convert PLC programs between various formats"))
    <> command "example"
           (info (Example <$> exampleOpts)
            (progDesc $ "Show a typed or untyped Plutus Core program example. "
                     ++ "Usage: first request the list of available examples (optional step), "
                     ++ "then request a particular example by the name of a term (or also a "
                     ++ "type if --typed is specified). "
                     ++ "Note that evaluating a generated example may result in 'Failure'."))
    <> command "typecheck"
           (info (Typecheck <$> typecheckOpts)
            (progDesc "Typecheck a typed Plutus Core program."))
    <> command "erase"
           (info (Erase <$> eraseOpts)
            (progDesc "Convert a typed Plutus Core program to an untyped one."))
    <> command "evaluate"
           (info (Eval <$> evalOpts)
            (progDesc "Evaluate a Plutus Core program."))
  )


---------------- Name conversions ----------------

-- We don't support de Bruijn names for typed programs because we really only
-- want serialisation for on-chain programs (and some of the functionality we'd
-- need isn't available anyway).
typedDeBruijnNotSupportedError :: IO a
typedDeBruijnNotSupportedError =
    errorWithoutStackTrace "De-Bruijn-named ASTs are not supported for typed Plutus Core"

-- | Convert an untyped program to one where the 'name' type is de Bruijn indices.
toDeBruijn :: UntypedProgram a -> IO (UntypedProgramDeBruijn a)
toDeBruijn prog =
  case runExcept @UPLC.FreeVariableError (UPLC.deBruijnProgram prog) of
    Left e  -> errorWithoutStackTrace $ show e
    Right p -> pure p


---------------- Reading programs from files ----------------

-- Read a PLC source program
getPlcInput :: Input -> IO String
getPlcInput (FileInput file) = readFile file
getPlcInput StdInput         = getContents

-- Read and parse a PLC source program
parsePlcInput :: Language -> Input -> IO (Program PLC.AlexPosn)
parsePlcInput language inp = do
    bsContents <- BSL.fromStrict . encodeUtf8 . T.pack <$> getPlcInput inp
    case language of
      TypedPLC   -> handleResult TypedProgram   $ PLC.runQuoteT $ runExceptT (PLC.parseScoped bsContents)
      UntypedPLC -> handleResult UntypedProgram $ PLC.runQuoteT $ runExceptT (UPLC.parseScoped bsContents)
      where handleResult wrapper =
                \case
                  Left errCheck        -> failWith errCheck
                  Right (Left errEval) -> failWith errEval
                  Right (Right p)      -> return $ wrapper p
            failWith (err :: PlcParserError) =  errorWithoutStackTrace $ PP.displayPlcDef err

-- Read a binary-encoded file (eg, CBOR- or Flat-encoded PLC)
getBinaryInput :: Input -> IO BSL.ByteString
getBinaryInput StdInput         = BSL.getContents
getBinaryInput (FileInput file) = BSL.readFile file

-- Read and deserialise a CBOR-encoded AST
-- There's no (un-)deBruijnifier for typed PLC, so we don't handle that case.
loadASTfromCBOR :: Language -> AstNameType -> Input -> IO (Program ())
loadASTfromCBOR language cborMode inp =
    case (language, cborMode) of
         (TypedPLC,   Named)    -> getBinaryInput inp <&> PLC.deserialiseRestoringUnitsOrFail >>= handleResult TypedProgram
         (UntypedPLC, Named)    -> getBinaryInput inp <&> UPLC.deserialiseRestoringUnitsOrFail >>= mapM toDeBruijn >>= handleResult UntypedProgram
         (TypedPLC,   DeBruijn) -> typedDeBruijnNotSupportedError
         (UntypedPLC, DeBruijn) -> getBinaryInput inp <&> UPLC.deserialiseRestoringUnitsOrFail >>=
                                   handleResult UntypedProgram
    where handleResult wrapper =
              \case
               Left (DeserialiseFailure offset msg) ->
                   errorWithoutStackTrace $ "CBOR deserialisation failure at offset " ++ Prelude.show offset ++ ": " ++ msg
               Right r -> return $ wrapper r

-- Read and deserialise a Flat-encoded AST
loadASTfromFlat :: Language -> AstNameType -> Input -> IO (Program ())
loadASTfromFlat language flatMode inp =
    case (language, flatMode) of
         (TypedPLC,   Named)    -> getBinaryInput inp <&> unflat >>= handleResult TypedProgram
         (UntypedPLC, Named)    -> getBinaryInput inp <&> unflat >>= handleResult UntypedProgram
         (TypedPLC,   DeBruijn) -> typedDeBruijnNotSupportedError
         (UntypedPLC, DeBruijn) -> getBinaryInput inp <&> unflat >>= handleResult UntypedProgram
    where handleResult wrapper =
              \case
               Left e  -> errorWithoutStackTrace $ "Flat deserialisation failure: " ++ show e
               Right r -> return $ wrapper r


-- Read either a PLC file or a CBOR file, depending on 'fmt'
getProgram :: Language -> Format -> Input  -> IO (Program PLC.AlexPosn)
getProgram language fmt inp =
    case fmt of
      Plc  -> parsePlcInput language inp
      Cbor cborMode -> do
               prog <- loadASTfromCBOR language cborMode inp
               return $ PLC.AlexPn 0 0 0 <$ prog  -- No source locations in CBOR, so we have to make them up.
      Flat flatMode -> do
               prog <- loadASTfromFlat language flatMode inp
               return $ PLC.AlexPn 0 0 0 <$ prog  -- No source locations in CBOR, so we have to make them up.


---------------- Serialise a program using CBOR ----------------

serialiseProgramCBOR :: Program () -> BSL.ByteString
serialiseProgramCBOR (TypedProgram p)   = PLC.serialiseOmittingUnits p
serialiseProgramCBOR (UntypedProgram p) = UPLC.serialiseOmittingUnits p

-- | Convert names to de Bruijn indices and then serialise
serialiseDbProgramCBOR :: Program () -> IO (BSL.ByteString)
serialiseDbProgramCBOR (TypedProgram _)   = typedDeBruijnNotSupportedError
serialiseDbProgramCBOR (UntypedProgram p) = pure $ UPLC.serialiseOmittingUnits p

writeCBOR :: Output -> AstNameType -> Program a -> IO ()
writeCBOR outp cborMode prog = do
  cbor <- case cborMode of
            Named    -> pure $ serialiseProgramCBOR (() <$ prog) -- Change annotations to (): see Note [Annotation types].
            DeBruijn -> serialiseDbProgramCBOR (() <$ prog)
  case outp of
    FileOutput file -> BSL.writeFile file cbor
    StdOutput       -> BSL.putStr cbor

---------------- Serialise a program using Flat ----------------

serialiseProgramFlat :: Flat a => Program a -> BSL.ByteString
serialiseProgramFlat (TypedProgram p)   = BSL.fromStrict $ flat p
serialiseProgramFlat (UntypedProgram p) = BSL.fromStrict $ flat p

-- | Convert names to de Bruijn indices and then serialise
serialiseDbProgramFlat :: Flat a => Program a -> IO (BSL.ByteString)
serialiseDbProgramFlat (TypedProgram _)   = typedDeBruijnNotSupportedError
serialiseDbProgramFlat (UntypedProgram p) = pure . BSL.fromStrict . flat $ p

writeFlat :: Output -> AstNameType -> Program a -> IO ()
writeFlat outp flatMode prog = do
  flatProg <- case flatMode of
            Named    -> pure $ serialiseProgramFlat (() <$ prog) -- Change annotations to (): see Note [Annotation types].
            DeBruijn -> serialiseDbProgramFlat (() <$ prog)
  case outp of
    FileOutput file -> BSL.writeFile file flatProg
    StdOutput       -> BSL.putStr flatProg


---------------- Write an AST as PLC source ----------------

getPrintMethod :: PP.PrettyPlc a => PrintMode -> (a -> Doc ann)
getPrintMethod = \case
      Classic       -> PP.prettyPlcClassicDef
      Debug         -> PP.prettyPlcClassicDebug
      Readable      -> PP.prettyPlcReadableDef
      ReadableDebug -> PP.prettyPlcReadableDebug

writePlc :: Output -> PrintMode -> Program a -> IO ()
writePlc outp mode prog = do
  let printMethod = getPrintMethod mode
  case outp of
        FileOutput file -> writeFile file . Prelude.show . printMethod $ prog
        StdOutput       -> print . printMethod $ prog

writeProgram :: Output -> Format -> PrintMode -> Program a -> IO ()
writeProgram outp Plc mode prog          = writePlc outp mode prog
writeProgram outp (Cbor cborMode) _ prog = writeCBOR outp cborMode prog
writeProgram outp (Flat flatMode) _ prog = writeFlat outp flatMode prog


---------------- Conversions ----------------

-- | Convert between textual and CBOR representations.  This subsumes the
-- `print` command: for example, `plc convert -i prog.plc --typed --fmt Readable`
-- will read a typed plc file and print it in the Readable format.  Having
-- the separate `print` option may be more user-friendly though.
runConvert :: ConvertOptions -> IO ()
runConvert (ConvertOptions lang inp ifmt outp ofmt mode) = do
    program <- getProgram lang ifmt inp
    writeProgram outp ofmt mode program


---------------- Parse and print a PLC source file ----------------

runPrint :: PrintOptions -> IO ()
runPrint (PrintOptions language inp mode) =
    parsePlcInput language inp >>= print . (getPrintMethod mode)


---------------- Erasure ----------------

-- | Input a program, erase the types, then output it
runErase :: EraseOptions -> IO ()
runErase (EraseOptions inp ifmt outp ofmt mode) = do
  TypedProgram typedProg <- getProgram TypedPLC ifmt inp
  let untypedNameProg = () <$ UPLC.eraseProgram typedProg
  untypedProg <- UntypedProgram <$> toDeBruijn untypedNameProg
  case ofmt of
    Plc           -> writePlc outp mode untypedProg
    Cbor cborMode -> writeCBOR outp cborMode untypedProg
    Flat flatMode -> writeFlat outp flatMode untypedProg



---------------- Script application ----------------

-- | Apply one script to a list of others.
runApply :: ApplyOptions -> IO ()
runApply (ApplyOptions language inputfiles ifmt outp ofmt mode) = do
  scripts <- mapM (getProgram language ifmt) (map FileInput inputfiles)
  let appliedScript =
          case language of  -- Annoyingly, we've got a list which could in principle contain both typed and untyped programs
            TypedPLC ->
                case map (\case TypedProgram p -> () <$ p;  _ -> error "unexpected program type mismatch") scripts of
                  []          -> errorWithoutStackTrace "No input files"
                  progAndargs -> TypedProgram $ foldl1 PLC.applyProgram progAndargs
            UntypedPLC ->
                case map (\case UntypedProgram p -> () <$ p; _ -> error "unexpected program type mismatch") scripts of
                  []          -> errorWithoutStackTrace "No input files"
                  progAndArgs -> UntypedProgram $ foldl1 UPLC.applyProgram progAndArgs
  writeProgram outp ofmt mode appliedScript


---------------- Examples ----------------

data TypeExample = TypeExample (PLC.Kind ()) (PLC.Type PLC.TyName PLC.DefaultUni ())
data TypedTermExample = TypedTermExample
    (PLC.Type PLC.TyName PLC.DefaultUni ())
    (PLC.Term PLC.TyName PLC.Name PLC.DefaultUni PLC.DefaultFun ())
data SomeTypedExample = SomeTypeExample TypeExample | SomeTypedTermExample TypedTermExample

data UntypedTermExample = UntypedTermExample
    (UPLC.Term PLC.Name PLC.DefaultUni PLC.DefaultFun ())
data SomeUntypedExample = SomeUntypedTermExample UntypedTermExample

data SomeExample = SomeTypedExample SomeTypedExample | SomeUntypedExample SomeUntypedExample

prettySignature :: ExampleName -> SomeExample -> Doc ann
prettySignature name (SomeTypedExample (SomeTypeExample (TypeExample kind _))) =
    pretty name <+> "::" <+> PP.prettyPlcDef kind
prettySignature name (SomeTypedExample (SomeTypedTermExample (TypedTermExample ty _))) =
    pretty name <+> ":"  <+> PP.prettyPlcDef ty
prettySignature name (SomeUntypedExample _) =
    pretty name

prettyExample :: SomeExample -> Doc ann
prettyExample =
    \case
         SomeTypedExample (SomeTypeExample (TypeExample _ ty)) -> PP.prettyPlcDef ty
         SomeTypedExample (SomeTypedTermExample (TypedTermExample _ term))
             -> PP.prettyPlcDef $ PLC.Program () (PLC.defaultVersion ()) term
         SomeUntypedExample (SomeUntypedTermExample (UntypedTermExample term)) ->
             PP.prettyPlcDef $ UPLC.Program () (PLC.defaultVersion ()) term

toTypedTermExample :: PLC.Term PLC.TyName PLC.Name PLC.DefaultUni PLC.DefaultFun () -> TypedTermExample
toTypedTermExample term = TypedTermExample ty term where
    program = PLC.Program () (PLC.defaultVersion ()) term
    errOrTy = PLC.runQuote . runExceptT $ do
        tcConfig <- PLC.getDefTypeCheckConfig ()
        PLC.typecheckPipeline tcConfig program
    ty = case errOrTy of
        Left (err :: PLC.Error PLC.DefaultUni PLC.DefaultFun ()) -> errorWithoutStackTrace $ PP.displayPlcDef err
        Right vTy                                                -> PLC.unNormalized vTy

getInteresting :: IO [(ExampleName, PLC.Term PLC.TyName PLC.Name PLC.DefaultUni PLC.DefaultFun ())]
getInteresting =
    sequence $ Gen.fromInterestingTermGens $ \name gen -> do
        Gen.TermOf term _ <- Gen.getSampleTermValue gen
        pure (T.pack name, term)

simpleExamples :: [(ExampleName, SomeTypedExample)]
simpleExamples =
    [ ("succInteger", SomeTypedTermExample $ toTypedTermExample StdLib.succInteger)
    , ("unit"       , SomeTypeExample      $ TypeExample (PLC.Type ()) StdLib.unit)
    , ("unitval"    , SomeTypedTermExample $ toTypedTermExample StdLib.unitval)
    , ("bool"       , SomeTypeExample      $ TypeExample (PLC.Type ()) StdLib.bool)
    , ("true"       , SomeTypedTermExample $ toTypedTermExample StdLib.true)
    , ("false"      , SomeTypedTermExample $ toTypedTermExample StdLib.false)
    , ("churchNat"  , SomeTypeExample      $ TypeExample (PLC.Type ()) StdLib.churchNat)
    , ("churchZero" , SomeTypedTermExample $ toTypedTermExample StdLib.churchZero)
    , ("churchSucc" , SomeTypedTermExample $ toTypedTermExample StdLib.churchSucc)
    ]


-- TODO: This supplies both typed and untyped examples.  Currently the untyped
-- examples are obtained by erasing typed ones, but it might be useful to have
-- some untyped ones that can't be obtained by erasure.
getAvailableExamples :: Language -> IO [(ExampleName, SomeExample)]
getAvailableExamples language = do
    interesting <- getInteresting
    let examples = simpleExamples ++ map (second $ SomeTypedTermExample . toTypedTermExample) interesting
    case language of
      TypedPLC   -> pure $ map (fmap SomeTypedExample) examples
      UntypedPLC -> pure $ mapMaybeSnd convert examples
                    where convert =
                              \case
                               SomeTypeExample _ -> Nothing
                               SomeTypedTermExample (TypedTermExample _ e) ->
                                   Just . SomeUntypedExample . SomeUntypedTermExample . UntypedTermExample $ UPLC.erase e
                          mapMaybeSnd _ []     = []
                          mapMaybeSnd f ((a,b):r) =
                              case f b of
                                Nothing -> mapMaybeSnd f r
                                Just b' -> (a,b') : mapMaybeSnd f r

-- The implementation is a little hacky: we generate interesting examples when the list of examples
-- is requested and at each lookup of a particular example. I.e. each time we generate distinct
-- terms. But types of those terms must not change across requests, so we're safe.

runPrintExample :: ExampleOptions -> IO ()
runPrintExample (ExampleOptions language ExampleAvailable) = do
    examples <- getAvailableExamples language
    traverse_ (T.putStrLn . PP.render . uncurry prettySignature) examples
runPrintExample (ExampleOptions language (ExampleSingle name)) = do
    examples <- getAvailableExamples language
    T.putStrLn $ case lookup name examples of
        Nothing -> "Unknown name: " <> name
        Just ex -> PP.render $ prettyExample ex


---------------- Typechecking ----------------

runTypecheck :: TypecheckOptions -> IO ()
runTypecheck (TypecheckOptions inp fmt) = do
  TypedProgram prog <- getProgram TypedPLC fmt inp
  case PLC.runQuoteT $ do
    tcConfig <- PLC.getDefTypeCheckConfig ()
    PLC.typecheckPipeline tcConfig (void prog)
    of
      Left (e :: PLC.Error PLC.DefaultUni PLC.DefaultFun ()) ->
        errorWithoutStackTrace $ PP.displayPlcDef e
      Right ty                                               ->
        T.putStrLn (PP.displayPlcDef ty) >> exitSuccess


---------------- Timing ----------------

-- Convert a time in picoseconds into a readble format with appropriate units
formatTime_picoseconds :: Double -> String
formatTime_picoseconds t
    | t >= 1e12 = printf "%.3f s"  (t/1e12)
    | t >= 1e9  = printf "%.3f ms" (t/1e9)
    | t >= 1e6  = printf "%.3f μs" (t/1e6)
    | t >= 1e3  = printf "%.3f ns" (t/1e3)
    | otherwise = printf "%f ps"   t

{-| Apply an evaluator to a program a number of times and report the mean execution
time.  The first measurement is often significantly larger than the rest
(perhaps due to warm-up effects), and this can distort the mean.  To avoid this
we measure the evaluation time (n+1) times and discard the first result. -}
timeEval :: NFData a => Integer -> (t -> a) -> t -> IO [a]
timeEval n evaluate prog
    | n <= 0 = errorWithoutStackTrace "Error: the number of repetitions should be at least 1"
    | otherwise = do
  (results, times) <- unzip . tail <$> for (replicate (fromIntegral (n+1)) prog) (timeOnce evaluate)
  let mean = (fromIntegral $ sum times) / (fromIntegral n) :: Double
      runs :: String = if n==1 then "run" else "runs"
  printf "Mean evaluation time (%d %s): %s\n" n runs (formatTime_picoseconds mean)
  pure results
    where timeOnce eval prg = do
            start <- performGC >> getCPUTime
            let result = eval prg
                !_ = rnf result
            end <- getCPUTime
            pure $ (result, end - start)


---------------- Printing budgets and costs ----------------

printBudgetStateBudget :: UPLC.Term UPLC.DeBruijn PLC.DefaultUni PLC.DefaultFun () -> CekModel -> ExBudget -> IO ()
printBudgetStateBudget _ model b =
    case model of
      Unit -> pure ()
      _ ->  let ExCPU cpu = _exBudgetCPU b
                ExMemory mem = _exBudgetMemory b
            in do
              putStrLn $ "CPU budget:    " ++ show cpu
              putStrLn $ "Memory budget: " ++ show mem

printBudgetStateTally :: (Eq fun, Cek.Hashable fun, Show fun)
       => UPLC.Term UPLC.DeBruijn PLC.DefaultUni PLC.DefaultFun () -> CekModel ->  Cek.CekExTally fun -> IO ()
printBudgetStateTally term model (Cek.CekExTally costs) = do
  putStrLn $ "Const      " ++ pbudget (Cek.BStep Cek.BConst)
  putStrLn $ "Var        " ++ pbudget (Cek.BStep Cek.BVar)
  putStrLn $ "LamAbs     " ++ pbudget (Cek.BStep Cek.BLamAbs)
  putStrLn $ "Apply      " ++ pbudget (Cek.BStep Cek.BApply)
  putStrLn $ "Delay      " ++ pbudget (Cek.BStep Cek.BDelay)
  putStrLn $ "Force      " ++ pbudget (Cek.BStep Cek.BForce)
  putStrLn $ "Builtin    " ++ pbudget (Cek.BStep Cek.BBuiltin)
  putStrLn ""
  putStrLn $ "startup    " ++ pbudget Cek.BStartup
  putStrLn $ "compute    " ++ printf "%-20s" (budgetToString totalComputeCost)
  putStrLn $ "AST nodes  " ++ printf "%15d" (UPLC.termSize term)
  putStrLn ""
  putStrLn $ "BuiltinApp " ++ budgetToString builtinCosts
  case model of
    Default ->
        do
  -- 1e9*(0.200  + 0.0000725 * totalComputeSteps + builtinExeTimes/1000)  putStrLn ""
          putStrLn ""
          traverse_ (\(b,cost) -> putStrLn $ printf "%-20s %s" (show b) (budgetToString cost :: String)) builtinsAndCosts
          putStrLn ""
          putStrLn $ "Total budget spent: " ++ printf (budgetToString totalCost)
          putStrLn $ "Predicted execution time: " ++ (formatTime_picoseconds totalTime)
    Unit -> pure ()
  where
        getSpent k =
            case H.lookup k costs of
              Just v  -> v
              Nothing -> ExBudget 0 0
        allNodeTags = fmap Cek.BStep [Cek.BConst, Cek.BVar, Cek.BLamAbs, Cek.BApply, Cek.BDelay, Cek.BForce, Cek.BBuiltin]
        totalComputeCost = mconcat $ map getSpent allNodeTags  -- For unitCekCosts this will be the total number of compute steps
        budgetToString (ExBudget (ExCPU cpu) (ExMemory mem)) =
            printf "%15s  %15s" (show cpu) (show mem) :: String -- Not %d: doesn't work when CostingInteger is SatInt.
        pbudget = budgetToString . getSpent
        f l e = case e of {(Cek.BBuiltinApp b, cost)  -> (b,cost):l; _ -> l}
        builtinsAndCosts = List.foldl f [] (H.toList costs)
        builtinCosts = mconcat (map snd builtinsAndCosts)
        -- ^ Total builtin evaluation time (according to the models) in picoseconds (units depend on BuiltinCostModel.costMultiplier)
        getCPU b = let ExCPU b' = _exBudgetCPU b in fromIntegral b'::Double
        totalCost = getSpent Cek.BStartup <> totalComputeCost <> builtinCosts
        totalTime = (getCPU $ getSpent Cek.BStartup) + getCPU totalComputeCost + getCPU builtinCosts

class PrintBudgetState cost where
    printBudgetState :: UPLC.Term PLC.DeBruijn PLC.DefaultUni PLC.DefaultFun () -> CekModel -> cost -> IO ()
    -- TODO: Tidy this up.  We're passing in the term and the CEK cost model
    -- here, but we only need them in tallying mode (where we need the term so
    -- we can print out the AST size and we need the model type to decide how
    -- much information we're going to print out).

instance PrintBudgetState Cek.CountingSt where
    printBudgetState term model (Cek.CountingSt budget) = printBudgetStateBudget term model budget

instance (Eq fun, Cek.Hashable fun, Show fun) => PrintBudgetState (Cek.TallyingSt fun) where
    printBudgetState term model (Cek.TallyingSt tally budget) = do
        printBudgetStateBudget term model budget
        putStrLn ""
        printBudgetStateTally term model tally

instance PrintBudgetState Cek.RestrictingSt where
    printBudgetState term model (Cek.RestrictingSt (ExRestrictingBudget budget)) =
        printBudgetStateBudget term model budget


---------------- Evaluation ----------------

runEval :: EvalOptions -> IO ()
runEval (EvalOptions language inp ifmt evalMode printMode budgetMode timingMode cekModel) =
    case language of

      TypedPLC ->
        case evalMode of
            CEK -> errorWithoutStackTrace "There is no CEK machine for Typed Plutus Core"
            CK  -> do
                    let !_ = case budgetMode of
                               Silent    -> ()
                               Verbose _ -> errorWithoutStackTrace "There is no budgeting for typed Plutus Core"
                    TypedProgram prog <- getProgram TypedPLC ifmt inp
                    let evaluate = Ck.evaluateCkNoEmit PLC.defaultBuiltinsRuntime
                        term = void . PLC.toTerm $ prog
                        !_ = rnf term
                        -- Force evaluation of body to ensure that we're not timing parsing/deserialisation.
                        -- The parser apparently returns a fully-evaluated AST, but let's be on the safe side.
                    case timingMode of
                      NoTiming -> evaluate term & handleResult
                      Timing n -> timeEval n evaluate term >>= handleTimingResults term

      UntypedPLC ->
          case evalMode of
            CK  -> errorWithoutStackTrace "There is no CK machine for Untyped Plutus Core"
            CEK -> do
                  UntypedProgram prog <- getProgram UntypedPLC ifmt inp
                  let term = void . UPLC.toTerm $ prog
                      !_ = rnf term
                      cekparams = case cekModel of
                                Default -> PLC.defaultCekParameters  -- AST nodes are charged according to the default cost model
                                Unit    -> PLC.unitCekParameters     -- AST nodes are charged one unit each, so we can see how many times each node
                                                                     -- type is encountered.  This is useful for calibrating the budgeting code.
                  case budgetMode of
                    Silent -> do
                          let evaluate = Cek.evaluateCekNoEmit cekparams
                          case timingMode of
                            NoTiming -> evaluate term & handleResult
                            Timing n -> timeEval n evaluate term >>= handleTimingResults term
                    Verbose bm -> do
                          let evaluate = Cek.runCekNoEmit cekparams bm
                          case timingMode of
                            NoTiming -> do
                                    let (result, budget) = evaluate term
                                    printBudgetState term cekModel budget
                                    handleResultSilently result  -- We just want to see the budget information
                            Timing n -> timeEval n evaluate term >>= handleTimingResultsWithBudget term

    where handleResult result =
              case result of
                Right v  -> (print $ getPrintMethod printMode v) >> exitSuccess
                Left err -> print err *> exitFailure
          handleResultSilently = \case
                Right _  -> exitSuccess
                Left err -> print err >> exitFailure
          handleTimingResults _ results =
              case nub results of
                [Right _]  -> exitSuccess -- We don't want to see the result here
                [Left err] -> print err >> exitFailure
                _          -> error "Timing evaluations returned inconsistent results" -- Should never happen
          handleTimingResultsWithBudget term results =
              case nub results of
                [(Right _, budget)] -> do
                    putStrLn ""
                    printBudgetState term cekModel budget
                    exitSuccess
                [(Left err,   budget)] -> do
                    putStrLn ""
                    print err
                    printBudgetState term cekModel budget
                    exitFailure
                _                                   -> error "Timing evaluations returned inconsistent results"


---------------- Driver ----------------

main :: IO ()
main = do
    options <- customExecParser (prefs showHelpOnEmpty) plutus
    case options of
        Apply     opts -> runApply        opts
        Typecheck opts -> runTypecheck    opts
        Eval      opts -> runEval         opts
        Example   opts -> runPrintExample opts
        Erase     opts -> runErase        opts
        Print     opts -> runPrint        opts
        Convert   opts -> runConvert      opts
