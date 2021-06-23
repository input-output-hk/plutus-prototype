{-# LANGUAGE LambdaCase       #-}
{-# LANGUAGE TypeApplications #-}

module Main where

import           Prelude                                  ((<>))
import qualified Prelude                                  as Haskell

import           Control.Monad                            ()
import qualified Data.ByteString.Lazy                     as BSL
import           Data.Char                                (isSpace)
import           Options.Applicative                      as Opt hiding (action)
import           System.Exit                              (exitFailure)
import           System.IO
import           Text.PrettyPrint.ANSI.Leijen             (Doc, indent, line, string, text, vsep)

import qualified Plutus.Benchmark.Clausify                as Clausify
import qualified Plutus.Benchmark.Knights                 as Knights
import qualified Plutus.Benchmark.LastPiece               as LastPiece
import qualified Plutus.Benchmark.Prime                   as Prime
import qualified Plutus.Benchmark.Queens                  as Queens

import           PlutusCore                               (Name (..))
import qualified PlutusCore                               as PLC
import           PlutusCore.CBOR                          ()
import           PlutusCore.Default
import qualified PlutusCore.Pretty                        as PLC
import           PlutusTx.Prelude                         as Plutus hiding (fmap, mappend, (<$), (<$>), (<*>), (<>))
import qualified UntypedPlutusCore                        as UPLC
import           UntypedPlutusCore.Evaluation.Machine.Cek

failWithMsg :: Haskell.String -> IO a
failWithMsg s = hPutStrLn stderr s >> exitFailure


-- | A program together with its arguments
data ProgAndArgs =
    Clausify  Clausify.StaticFormula
  | Queens    Haskell.Integer Queens.Algorithm
  | Knights   Haskell.Integer Haskell.Integer
  | LastPiece
  | Prime     Prime.PrimeID
  | Primetest Integer

-- | The actions this program can perform
data Options
    = RunPLC           ProgAndArgs
    | RunHaskell       ProgAndArgs
    | DumpPLC          ProgAndArgs
    | DumpCBORdeBruijn ProgAndArgs


-- Clausify options --

knownFormulae :: Haskell.String
knownFormulae = "one of F1, F2, F3, F4, F5, F6, F7"

clausifyFormulaReader :: Haskell.String -> Either Haskell.String Clausify.StaticFormula
clausifyFormulaReader "F1" = Right Clausify.F1
clausifyFormulaReader "F2" = Right Clausify.F2
clausifyFormulaReader "F3" = Right Clausify.F3
clausifyFormulaReader "F4" = Right Clausify.F4
clausifyFormulaReader "F5" = Right Clausify.F5
clausifyFormulaReader "F6" = Right Clausify.F6
clausifyFormulaReader "F7" = Right Clausify.F7
clausifyFormulaReader f    = Left $ "Cannot parse `" <> f <> "`. Expected " ++ knownFormulae ++ "."

clausifyOptions :: Parser ProgAndArgs
clausifyOptions =
  Clausify <$> argument (eitherReader clausifyFormulaReader)
                          (metavar "FORMULA" <>
                           help ("Formula to use for benchmarking: " ++ knownFormulae ++ "."))


-- Knights options --

knightsOptions :: Parser ProgAndArgs
knightsOptions =
  Knights <$> argument auto (metavar "DEPTH" <>
                               help "Maximum search depth.")
          <*> argument auto (metavar "BOARD-SIZE" <>
                               help "Board size (NxN)")


-- Lastpiece options --

lastpieceOptions :: Parser ProgAndArgs
lastpieceOptions = Haskell.pure LastPiece


-- Primes options --

knownPrimes :: Haskell.String
knownPrimes = "P05, P08, P10, P20, P30, P40, P50, P60, P100, P150, or P200 (a prime with the indicated number of digits)"

primeIdReader :: Haskell.String -> Either Haskell.String Prime.PrimeID
primeIdReader "P05"  = Right Prime.P5
primeIdReader "P08"  = Right Prime.P8
primeIdReader "P10"  = Right Prime.P10
primeIdReader "P20"  = Right Prime.P20
primeIdReader "P30"  = Right Prime.P30
primeIdReader "P40"  = Right Prime.P40
primeIdReader "P50"  = Right Prime.P50
primeIdReader "P60"  = Right Prime.P60
primeIdReader "P100" = Right Prime.P100
primeIdReader "P150" = Right Prime.P150
primeIdReader "P200" = Right Prime.P200
primeIdReader f      = Left $ "Cannot parse `" <> f <> "`. Possible values are " ++ knownPrimes ++"."

-- | Apply the primality test to one of the built-in primes
primeOptions :: Parser ProgAndArgs
primeOptions =
  Prime <$> (argument (eitherReader primeIdReader)
             (metavar "ID" <> help ("Identifier for known prime: " ++ knownPrimes)))


-- Primetest options --

-- | Apply the primality test to a given integer instead of one of the built-in large primes
primetestOptions :: Parser ProgAndArgs
primetestOptions =
  Primetest <$> (argument auto (metavar "N" <> help "a positive integer"))


-- Queens options --

knownAlgorithms :: Haskell.String
knownAlgorithms = "bt, bm, bjbt1, bjbt2, fc"

queensAlgorithmReader :: Haskell.String -> Either Haskell.String Queens.Algorithm
queensAlgorithmReader "bt"    = Right Queens.Bt
queensAlgorithmReader "bm"    = Right Queens.Bm
queensAlgorithmReader "bjbt1" = Right Queens.Bjbt1
queensAlgorithmReader "bjbt2" = Right Queens.Bjbt2
queensAlgorithmReader "fc"    = Right Queens.Fc
queensAlgorithmReader alg     = Left $ "Unknown algorithm: " <> alg <> ". Options are " ++ knownAlgorithms

queensOptions :: Parser ProgAndArgs
queensOptions =
  Queens <$> argument auto (metavar "BOARD-SIZE" <>
                              help "Size of the playing board NxN")
         <*> (argument (eitherReader queensAlgorithmReader)
                        (metavar "ALGORITHM" <>
                         help ("Algorithm to use for constraint solving. One of: " ++ knownAlgorithms)))

-- Main parsers --

progAndArgs :: Parser ProgAndArgs
progAndArgs = hsubparser
  (  command "clausify"  (info clausifyOptions      (progDesc "Run the Clausify benchmark."))
  <> command "queens"    (info queensOptions        (progDesc "Run the Queens benchmark."))
  <> command "knights"   (info knightsOptions       (progDesc "Run the Knights benchmark"))
  <> command "lastpiece" (info lastpieceOptions     (progDesc "Run the Lastpiece benchmark"))
  <> command "prime"     (info primeOptions         (progDesc "Run the Prime benchmark on a known prime (see help)"))
  <> command "primetest" (info primetestOptions (progDesc "Run the Prime benchmark on a positive integer N")) )


options :: Parser Options
options = hsubparser
  (  command "run"
     (info (RunPLC <$> progAndArgs)
      (progDesc "same as runPLC"))
  <> command "runPLC"
     (info (RunPLC <$> progAndArgs)
      (progDesc "compile the program to Plutus Core and evaluate it using the CEK machine"))
  <> command "runHaskell"
     (info (RunHaskell <$> progAndArgs)
      (progDesc "run the program directly as Haskell"))
  <> command "dumpPLC"
     (info (DumpPLC <$> progAndArgs)
      (progDesc "print the program (applied to arguments) as Plutus Core source on standard output"))
  <> command "dumpCBOR"
     (info (DumpCBORdeBruijn <$> progAndArgs)
      (progDesc "same as dumpCBORdeBruijn, but easier to type"))
  <> command "dumpCBORdeBruijn"
     (info (DumpCBORdeBruijn <$> progAndArgs)
      (progDesc "dump the AST as CBOR, with names replaced by de Bruijn indices"))
  )


---------------- Evaluation ----------------

evaluateWithCek :: UPLC.Term UPLC.DeBruijn DefaultUni DefaultFun () -> EvaluationResult (UPLC.Term UPLC.DeBruijn DefaultUni DefaultFun ())
evaluateWithCek = unsafeEvaluateCekNoEmit PLC.defaultCekParameters

writeCBORnamed :: UPLC.Program Name DefaultUni DefaultFun () -> IO ()
writeCBORnamed prog = BSL.putStr $ UPLC.serialiseOmittingUnits prog

writeCBORdeBruijn :: UPLC.Program UPLC.DeBruijn DefaultUni DefaultFun () -> IO ()
writeCBORdeBruijn = BSL.putStr . UPLC.serialiseOmittingUnits

description :: Haskell.String
description = "This program provides operations on a number of Plutus programs "
              ++ "ported from the nofib Haskell test suite.  "
              ++ "The programs are written in Haskell and can be run directly "
              ++ "or compiled into Plutus Core and run on the CEK machine.  "
              ++ "Compiled programs can also be output in a number of formats."

knownProgs :: [Doc]
knownProgs = map text ["clausify", "knights", "lastpiece", "prime", "primetest", "queens"]

-- Extra information about the available programs.  We need a Doc because if you
-- just make it a string it removes newlines and other formatting.  There's some
-- manual formatting in here because the text doesn't wrap as expected, presumably
-- due to what optparse-applicative is doing internally.
footerInfo :: Doc
footerInfo = text "Every command takes the name of a program and a (possbily empty) list of arguments."
           <> line <> line
           <> text "The available programs are: "
           <> line
           <> indent 2 (vsep knownProgs)
           <> line <> line
           <> string ("See 'nofib-exe run <programe-name> --help' for information about the arguments\n"
                   ++ "for a particular program.")
           <> line <> line
           <> string ("The 'dump' commands construct a Plutus Core term applying the program to its\n"
                   ++ "arguments and prints the result to the terminal in the specified format.\n"
                   ++ "You'll probably want to redirect the output to a file.")

main :: IO ()
main = do
  execParser (info (helper <*> options) (fullDesc <> progDesc description <> footerDoc (Just footerInfo))) >>= \case
    RunPLC pa ->  print . PLC.prettyPlcClassicDebug <$> evaluateWithCek . getDBrTerm $ pa
    RunHaskell pa ->
        case pa of
          Clausify formula        -> print $ Clausify.runClausify formula
          Knights depth boardSize -> print $ Knights.runKnights depth boardSize
          LastPiece               -> print $ LastPiece.runLastPiece
          Queens boardSize alg    -> print $ Queens.runQueens boardSize alg
          Prime input             -> print $ Prime.runFixedPrimalityTest input
          Primetest n             -> if n<0 then Haskell.error "Positive number expected"
                                     else print $ Prime.runPrimalityTest n
    DumpPLC pa -> Haskell.mapM_ putStrLn $ unindent . PLC.prettyPlcClassicDebug . mkProg . getDBrTerm $ pa
        where unindent d = map (dropWhile isSpace) $ (Haskell.lines . Haskell.show $ d)
    DumpCBORdeBruijn pa-> writeCBORdeBruijn . mkProg . getDBrTerm $ pa
    -- Write the output to stdout and let the user deal with redirecting it.
    where getDBrTerm :: ProgAndArgs -> UPLC.Term UPLC.DeBruijn DefaultUni DefaultFun ()
          getDBrTerm =
              \case
               Clausify formula        -> Clausify.mkClausifyTerm formula
               Queens boardSize alg    -> Queens.mkQueensTerm boardSize alg
               Knights depth boardSize -> Knights.mkKnightsTerm depth boardSize
               LastPiece               -> LastPiece.mkLastPieceTerm
               Prime input             -> Prime.mkPrimalityBenchTerm input
               Primetest n             -> if n<0 then Haskell.error "Positive number expected"
                                          else Prime.mkPrimalityTestTerm n

          mkProg :: UPLC.Term name uni fun () -> UPLC.Program name uni fun ()
          mkProg = UPLC.Program () (UPLC.Version () 1 0 0)
