{-# LANGUAGE DefaultSignatures    #-}
{-# LANGUAGE FlexibleInstances    #-}
{-# LANGUAGE OverloadedStrings    #-}
{-# LANGUAGE TypeApplications     #-}
{-# LANGUAGE TypeOperators        #-}
{-# LANGUAGE TypeSynonymInstances #-}

module Language.PlutusCore.Parsable
    (
     Parsable(..)
    )
where

import           PlutusPrelude

import           Language.PlutusCore.Core.Type
import           Language.PlutusCore.Lexer
import           Language.PlutusCore.Name
import           Language.PlutusCore.Universe

import           Data.Bits                     (shiftL, (.|.))
import           Data.ByteString.Lazy          (ByteString)
import qualified Data.ByteString.Lazy          as BSL (pack, tail, unpack)
import           Data.Char                     (isHexDigit, ord)
import qualified Data.Text                     as T
import           Text.Read                     (readMaybe)


class Parsable a
  where
  parseConstant :: T.Text -> Maybe a
  default parseConstant :: Read a => T.Text -> Maybe a
  parseConstant = readMaybe @ a . T.unpack

instance Parsable Bool
instance Parsable Char
instance Parsable Integer
instance Parsable String
instance Parsable ()

instance Parsable ByteString
  where parseConstant = parseByteStringConstant

--- Parsing bytestrings ---

parseByteStringConstant :: T.Text -> Maybe ByteString
parseByteStringConstant lit = do
      case T.unpack lit of
	'#':body -> asBSLiteral body
        _        -> Nothing

-- | Convert a list to a list of pairs, failing if the input list has an odd number of elements
pairs :: [a] -> Maybe [(a,a)]
pairs []         = Just []
pairs (a:b:rest) = fmap ((:) (a,b)) (pairs rest)
pairs _          = Nothing

hexDigitToWord8 :: Char -> Maybe Word8
hexDigitToWord8 c =
    let x = ord8 c
    in    if '0' <= c && c <= '9'  then  Just $ x - ord8 '0'
    else  if 'a' <= c && c <= 'f'  then  Just $ x - ord8 'a' + 10
    else  if 'A' <= c && c <= 'F'  then  Just $ x - ord8 'A' + 10
    else  Nothing

    where ord8 :: Char -> Word8
	  ord8 = fromIntegral . Data.Char.ord

-- | Convert a String into a ByteString, failing if the string has odd length
-- or any of its characters are not hex digits
asBSLiteral :: String -> Maybe ByteString
asBSLiteral s =
    mapM hexDigitToWord8 s >>= pairs      -- convert s into a list of pairs of Word8 values in [0..0xF]
    <&> map (\(a,b) -> shiftL a 4 .|. b)  -- convert pairs of values in [0..0xF] to values in [0..xFF]
    <&> BSL.pack

