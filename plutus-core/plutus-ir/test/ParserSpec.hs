{-# LANGUAGE FlexibleContexts  #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications  #-}

module ParserSpec (parsing) where

import           PlutusPrelude

import           Common

import           Data.Char
import qualified Data.Text               as T

import qualified PlutusCore.Default      as PLC

import           PlutusIR
import           PlutusIR.Generators.AST
import           PlutusIR.Parser

import           Hedgehog                hiding (Var)
import qualified Hedgehog.Gen            as Gen
import qualified Hedgehog.Range          as Range

import           Test.Tasty
import           Test.Tasty.Hedgehog

newtype PrettyProg = PrettyProg { prog :: Program TyName Name PLC.DefaultUni PLC.DefaultFun SourcePos }
instance Show PrettyProg where
    show = display . prog

whitespace :: MonadGen m => m String
whitespace = flip replicate ' ' <$> Gen.integral (Range.linear 1 4)

lineComment :: MonadGen m => m String
lineComment = (Gen.string (Range.linear 0 20) $ Gen.filterT (/= '\n') Gen.latin1)
              >>= (\s -> return $ " --" ++ s ++ "\n")

blockComment :: MonadGen m => m String
blockComment = (Gen.string (Range.linear 0 20) $ Gen.element notBraces)
               >>= (\s -> return $ "{- " ++ s ++ " -}")
    where notBraces :: String
          notBraces = filter (\c -> c /= '{' && c /= '}') ['\0' .. '\255']

comment :: MonadGen m => m String
comment = Gen.choice [Gen.constant "", lineComment, blockComment]

separators :: String
separators = ['!', '(', ')', '[', ']', '{', '}']

separator :: Char -> Bool
separator c = c `elem` separators || isSpace c

aroundSeparators :: MonadGen m => m String -> String -> m String
aroundSeparators _ [] = return []
aroundSeparators splice [s] = (s:) <$> splice
aroundSeparators splice (a:b:l)
    | separator b = do
          s1 <- splice
          s2 <- splice
          rest <- aroundSeparators splice l
          return $ a : s1 ++ b : s2 ++ rest
    | otherwise = (a :) <$> aroundSeparators splice (b:l)

genScrambledWith :: MonadGen m => m String -> m (String, String)
genScrambledWith splice = do
    original <- display <$> runAstGen genProgram
    scrambled <- aroundSeparators splice original
    return (original, scrambled)

propRoundTrip :: Property
propRoundTrip = property $ do
    code <- display <$> forAllWith display (runAstGen genProgram)
    let backward = fmap (display . prog)
        forward = fmap PrettyProg . parse program "test"
    tripping code forward backward

propIgnores :: Gen String -> Property
propIgnores splice = property $ do
    (original, scrambled) <- forAll (genScrambledWith splice)
    let displayProgram :: Program TyName Name PLC.DefaultUni PLC.DefaultFun SourcePos -> String
        displayProgram = display
        parse1 = displayProgram <$> (parse program "test" $ T.pack original)
        parse2 = displayProgram <$> (parse program "test" $ T.pack scrambled)
    parse1 === parse2

parsing :: TestNested
parsing = return $ testGroup "parsing"
    [ testProperty "parser round-trip" propRoundTrip
    , testProperty "parser ignores whitespace" (propIgnores whitespace)
    , testProperty "parser ignores comments" (propIgnores comment)
    ]
