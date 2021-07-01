{-# LANGUAGE DataKinds         #-}
{-# LANGUAGE DeriveAnyClass    #-}
{-# LANGUAGE DeriveGeneric     #-}
{-# LANGUAGE DerivingVia       #-}
{-# LANGUAGE FlexibleContexts  #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs             #-}
{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PolyKinds         #-}
{-# LANGUAGE RoleAnnotations   #-}
{-# LANGUAGE StrictData        #-}
{-# LANGUAGE TemplateHaskell   #-}
{-# LANGUAGE TypeApplications  #-}

-- | Maintainer's note: There are some types in this module where we'd
-- like to have two different ways to encode JSON data; the 'native'
-- aeson one and a 3rd-party defined one. We can do this by adding a
-- phantom type parameter which specifies the encoding, and then having
-- different typeclass instances for different choices of that parameter.
--
-- Since it's a phantom type, the underlying data representation is
-- the same in every case, so you are allowed to use
-- 'Data.Coerce.coerce' to freely switch between encodings.

module Cardano.Metadata.Types (
      Subject (..)
    , AnnotatedSignature (..)
    , SubjectProperties (..)
    , Property (..)
    , PropertyKey (..)
    , MetadataError (..)
    , Query (..)
    , QueryResult (..)
    , HashFunction (..)

    -- * Encoding (aeson or external)
    , JSONEncoding (..)

    -- * Configuration
    , MetadataConfig (..)

    -- * Logging
    , MetadataLogMessage (..)

    -- * Effects
    , MetadataEffect (..)
    , batchQuery
    , getProperty
    , getProperties
    , toPropertyKey
    , toSubject
    ) where

import           Cardano.BM.Data.Tracer            (ToObject (..))
import           Cardano.BM.Data.Tracer.Extras     (Tagged (..), mkObjectStr)
import           Control.Applicative               (Alternative, (<|>))
import           Control.Monad.Freer.TH            (makeEffect)
import           Data.Aeson                        (FromJSON, FromJSONKey, ToJSON, ToJSONKey, parseJSON, toJSON,
                                                    withObject, withText, (.:), (.=))
import qualified Data.Aeson                        as JSON
import           Data.Aeson.Extras                 (decodeByteString, encodeByteString)
import           Data.Aeson.Types                  (Parser)
import qualified Data.ByteString                   as BS
import           Data.List.NonEmpty                (NonEmpty)
import           Data.Set                          (Set)
import           Data.Text                         (Text)
import qualified Data.Text                         as Text
import           Data.Text.Encoding                (encodeUtf8)
import           Data.Text.Prettyprint.Doc         (Pretty, pretty, viaShow, (<+>))
import           GHC.Generics                      (Generic)
import           Ledger.Bytes                      (LedgerBytes)
import qualified Ledger.Bytes                      as LedgerBytes
import           Ledger.Crypto                     (PubKey (PubKey), PubKeyHash, Signature (Signature), getPubKey,
                                                    getPubKeyHash, getSignature)
import           Plutus.PAB.Arbitrary              ()
import           Plutus.PAB.Instances              ()
import qualified PlutusTx.ByteString               as PlutusTx
import           Servant.API                       (FromHttpApiData, ToHttpApiData)
import           Servant.Client                    (BaseUrl, ClientError)
import           Test.QuickCheck.Arbitrary.Generic (Arbitrary, arbitrary, genericArbitrary)

newtype MetadataUrl = MetadataUrl BaseUrl
    deriving (Show, Eq)

newtype MetadataConfig =
    MetadataConfig
        { mdBaseUrl :: BaseUrl
        }
    deriving (Show, Eq, Generic)
    deriving anyclass (FromJSON)

------------------------------------------------------------
newtype Subject =
    Subject Text
    deriving (Show, Eq, Ord, Generic)
    deriving newtype ( ToJSON
                     , FromJSON
                     , FromHttpApiData
                     , ToHttpApiData
                     , Pretty
                     , ToJSONKey
                     , FromJSONKey
                     )

instance Arbitrary Subject where
    arbitrary = genericArbitrary

class ToSubject a where
    toSubject :: a -> Subject

instance ToSubject BS.ByteString where
    toSubject x = Subject $ encodeByteString x

instance ToSubject PlutusTx.ByteString where
    toSubject x = Subject $ encodeByteString $ PlutusTx.toHaskellByteString x

instance ToSubject LedgerBytes where
    toSubject = toSubject . LedgerBytes.bytes

instance ToSubject PubKey where
    toSubject = toSubject . getPubKey

instance ToSubject PubKeyHash where
    toSubject = toSubject . getPubKeyHash

------------------------------------------------------------
newtype PropertyKey =
    PropertyKey Text
    deriving (Show, Eq, Ord, Generic)
    deriving newtype (ToJSON, FromJSON, FromHttpApiData, ToHttpApiData, Pretty)

data SubjectProperties (encoding :: k) =
    SubjectProperties Subject [Property encoding]
    deriving (Show, Eq, Generic)

instance Arbitrary (SubjectProperties encoding) where
    arbitrary = genericArbitrary

deriving anyclass instance
         ToJSON (SubjectProperties 'AesonEncoding)

deriving anyclass instance
         FromJSON (SubjectProperties 'AesonEncoding)

instance FromJSON (SubjectProperties 'ExternalEncoding) where
    parseJSON =
        withObject "SubjectProperties" $ \o -> do
            subject <- o .: "subject"
            SubjectProperties subject <$>
                (accumulateSuccesses :: [Parser a] -> Parser [a])
                    [ parseName o
                    , parseDescription o
                    , parsePreimage o
                    , parseOwner o
                    ]

-- | Collect alternatives, ignoring failures.
-- For example, accumulate the results of every parser that succeeds,
-- ignoring the ones that failed. Useful when the same data can be
-- parsed more than one way.
accumulateSuccesses ::
       ( Alternative f
       , Applicative m
       , Monoid (m a)
       , Monoid (f (m a))
       , Foldable g
       )
    => g (f a)
    -> f (m a)
accumulateSuccesses = foldMap (\f -> (pure <$> f) <|> pure mempty)

parseName :: JSON.Object -> Parser (Property 'ExternalEncoding)
parseName =
    parseAtKey
        "name"
        (\subObject -> do
             value <- subObject .: "value"
             signatures :: NonEmpty (AnnotatedSignature 'ExternalEncoding) <-
                 subObject .: "anSignatures"
             pure $ Name value signatures)

parseDescription ::
       JSON.Object -> Parser (Property 'ExternalEncoding)
parseDescription =
    parseAtKey
        "description"
        (\description -> do
             value <- description .: "value"
             signatures <- description .: "anSignatures"
             pure $ Description value signatures)

parsePreimage :: JSON.Object -> Parser (Property 'ExternalEncoding)
parsePreimage =
    parseAtKey
        "preImage"
        (\preImage -> do
             hash <- preImage .: "hashFn"
             hex <- preImage .: "value"
             pure $ Preimage hash hex)

parseOwner :: JSON.Object -> Parser (Property 'ExternalEncoding)
parseOwner subObject = do
    sig <- subObject .: "owner"
    pure $ Other "owner" (JSON.Object subObject) (pure sig)

parseAtKey :: Text -> (JSON.Object -> Parser a) -> JSON.Object -> Parser a
parseAtKey key parser o = do
    subValue <- o .: key
    withObject (Text.unpack key) parser subValue

data HashFunction
    = SHA256
    | Blake2B256
    deriving (Show, Eq, Ord, Generic, Enum, Bounded)

instance FromJSON HashFunction where
    parseJSON =
        withText "HashFunction" $ \case
            "SHA256"      -> pure SHA256
            "blake2b-256" -> pure Blake2B256
            other         -> fail $ "Unknown HashFunction '" <> Text.unpack other <> "'"

instance ToJSON HashFunction where
    toJSON SHA256     = JSON.String "SHA256"
    toJSON Blake2B256 = JSON.String "blake2b-256"

instance Arbitrary HashFunction where
    arbitrary = genericArbitrary

data AnnotatedSignature (encoding :: k) =
    AnnotatedSignature PubKey Signature
    deriving (Show, Eq, Ord, Generic)

deriving anyclass instance
         ToJSON (AnnotatedSignature 'AesonEncoding)

deriving anyclass instance
         FromJSON (AnnotatedSignature 'AesonEncoding)

instance Arbitrary (AnnotatedSignature encoding) where
    arbitrary = genericArbitrary

instance FromJSON (AnnotatedSignature 'ExternalEncoding) where
    parseJSON =
        withObject "AnnotatedSignature" $ \o -> do
            sigRaw <- o .: "signature"
            sigBytes <- decodeByteString sigRaw
            let sig = Signature $ PlutusTx.fromHaskellByteString sigBytes
            pubKeyRaw :: Text <- o .: "publicKey"
            case PubKey <$> LedgerBytes.fromHex (encodeUtf8 pubKeyRaw) of
                Right pubKey -> pure $ AnnotatedSignature pubKey sig
                Left err     -> fail (show (err, pubKeyRaw))

instance ToJSON (AnnotatedSignature 'ExternalEncoding) where
    toJSON (AnnotatedSignature pubKey sig) =
        JSON.object
            [ "signature" .= encodeByteString (PlutusTx.toHaskellByteString $ getSignature sig)
            , "publicKey" .= getPubKey pubKey
            ]

data JSONEncoding
    = ExternalEncoding
    | AesonEncoding

data Property (encoding :: k)
    = Preimage HashFunction LedgerBytes
    | Name Text (NonEmpty (AnnotatedSignature encoding))
    | Description Text (NonEmpty (AnnotatedSignature encoding))
    | Other Text JSON.Value (NonEmpty (AnnotatedSignature encoding))
    deriving (Show, Eq, Generic)

instance Arbitrary (Property encoding) where
    arbitrary = genericArbitrary

deriving anyclass instance
         ToJSON (Property 'AesonEncoding)

deriving anyclass instance
         FromJSON (Property 'AesonEncoding)

instance ToJSON (Property 'ExternalEncoding) where
    toJSON (Preimage hash bytes) =
        JSON.object
            ["preImage" .= JSON.object ["hashFn" .= hash, "value" .= bytes]]
    toJSON (Name value signatures) =
        JSON.object
            [ "name" .=
              JSON.object ["value" .= value, "anSignatures" .= signatures]
            ]
    toJSON (Description value signatures) =
        JSON.object
            [ "description" .=
              JSON.object ["value" .= value, "anSignatures" .= signatures]
            ]
    toJSON (Other name value signatures) =
        JSON.object
            [ name.=
              JSON.object ["value" .= value, "anSignatures" .= signatures]
            ]

instance FromJSON (Property 'ExternalEncoding) where
    parseJSON =
        withObject "Property" $ \o ->
            parseName o <|> parseDescription o <|> parsePreimage o <|>
            parseOwner o

toPropertyKey :: Property encoding -> PropertyKey
toPropertyKey (Preimage _ _)    = PropertyKey "preimage"
toPropertyKey (Name _ _)        = PropertyKey "name"
toPropertyKey (Description _ _) = PropertyKey "description"
toPropertyKey (Other name _ _)  = PropertyKey name

data Query =
    QuerySubjects
        { subjects      :: Set Subject
        , propertyNames :: Maybe (Set PropertyKey)
        }
    deriving (Show, Eq, Generic)
    deriving anyclass (ToJSON, FromJSON)

instance Pretty Query where
    pretty = viaShow

newtype QueryResult (encoding :: k) =
    QueryResult
        { results :: [SubjectProperties encoding]
        }
    deriving (Show, Eq, Generic)

deriving newtype instance FromJSON (QueryResult 'AesonEncoding)
deriving newtype instance ToJSON (QueryResult 'AesonEncoding)

instance FromJSON (QueryResult 'ExternalEncoding) where
    parseJSON =
        withObject "QueryResult" $ \o -> QueryResult <$> o .: "subjects"

------------------------------------------------------------
data MetadataEffect r where
    GetProperties
        :: Subject -> MetadataEffect (SubjectProperties 'AesonEncoding)
    GetProperty
        :: Subject
        -> PropertyKey
        -> MetadataEffect (Property 'AesonEncoding)
    BatchQuery :: Query -> MetadataEffect (QueryResult 'AesonEncoding)

makeEffect ''MetadataEffect

------------------------------------------------------------
data MetadataError
    = MetadataClientError ClientError
    | SubjectNotFound Subject
    | SubjectPropertyNotFound Subject PropertyKey
    deriving (Show, Eq, Generic)
    deriving anyclass (ToJSON, FromJSON)

data MetadataLogMessage
    = FetchingSubject Subject
    | FetchingProperty Subject PropertyKey
    | Querying Query
    | StartingMetadataServer Int
    deriving stock (Show, Generic)
    deriving anyclass (ToJSON, FromJSON)

instance ToObject MetadataLogMessage where
    toObject _ = \case
        StartingMetadataServer p -> mkObjectStr "Starting Metadata Server" (Tagged @"port" p)
        FetchingSubject s        -> mkObjectStr "Fetching subject" (Tagged @"subject" s)
        FetchingProperty s p     -> mkObjectStr "Fetching property" (Tagged @"subject" s, Tagged @"property" p)
        Querying q               -> mkObjectStr "Running query" (Tagged @"query" q)

instance Pretty MetadataLogMessage where
    pretty =
        \case
            StartingMetadataServer p -> "Starting Metadata Server:" <+> pretty p
            FetchingSubject subject -> "Fetching subject:" <+> pretty subject
            FetchingProperty subject propertyKey ->
                "Fetching property:" <+>
                pretty subject <> "/" <> pretty propertyKey
            Querying query ->
                "Running query:" <+>
                pretty query
