{-# LANGUAGE DerivingVia           #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE NamedFieldPuns        #-}
{-# LANGUAGE OverloadedStrings     #-}
{-# LANGUAGE RecordWildCards       #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE ViewPatterns          #-}

module Wallet.Rollup.Render(
    showBlockchain
    , showBlockchainFold
    ) where

import           Control.Lens.Combinators              (itraverse)
import           Control.Monad.Except                  (MonadError, throwError)
import           Control.Monad.Reader
import           Crypto.Hash                           (Digest, SHA256)
import qualified Data.Aeson.Extras                     as JSON
import           Data.Foldable                         (fold)
import           Data.List                             (intersperse)
import           Data.Map                              (Map)
import qualified Data.Map                              as Map
import           Data.Set                              (Set)
import qualified Data.Set                              as Set
import           Data.Text                             (Text)
import qualified Data.Text                             as Text
import           Data.Text.Prettyprint.Doc             (Doc, Pretty, defaultLayoutOptions, fill, indent, layoutPretty,
                                                        line, parens, pretty, viaShow, vsep, (<+>))
import           Data.Text.Prettyprint.Doc.Render.Text (renderStrict)
import           Ledger                                (Address, Blockchain, PubKey, PubKeyHash, Signature, Tx (Tx),
                                                        TxId, TxIn (TxIn),
                                                        TxInType (ConsumePublicKeyAddress, ConsumeScriptAddress),
                                                        TxOut (TxOut), TxOutRef (TxOutRef, txOutRefId, txOutRefIdx),
                                                        Value, txFee, txMint, txOutValue, txOutputs, txSignatures)
import           Ledger.Ada                            (Ada (Lovelace))
import qualified Ledger.Ada                            as Ada
import           Ledger.Scripts                        (Datum (getDatum), Script, Validator,
                                                        ValidatorHash (ValidatorHash), unValidatorScript)
import           Ledger.Value                          (CurrencySymbol (CurrencySymbol), TokenName (TokenName))
import qualified Ledger.Value                          as Value
import qualified PlutusTx                              as PlutusTx
import qualified PlutusTx.AssocMap                     as AssocMap
import qualified PlutusTx.Prelude                      as PlutusTx
import           Wallet.Emulator.Folds                 (EmulatorEventFold)
import qualified Wallet.Emulator.Folds                 as Folds
import           Wallet.Emulator.Types                 (Wallet (Wallet))
import           Wallet.Rollup                         (doAnnotateBlockchain)
import           Wallet.Rollup.Types                   (AnnotatedTx (AnnotatedTx),
                                                        BeneficialOwner (OwnedByPubKey, OwnedByScript),
                                                        DereferencedInput (DereferencedInput, InputNotFound, originalInput, refersTo),
                                                        SequenceId (SequenceId, slotIndex, txIndex), balances,
                                                        dereferencedInputs, toBeneficialOwner, tx, txId, valid)

showBlockchainFold :: [(PubKeyHash, Wallet)] -> EmulatorEventFold (Either Text Text)
showBlockchainFold walletKeys =
    let r txns =
            (renderStrict . layoutPretty defaultLayoutOptions)
            <$> runReaderT (render txns) (Map.fromList walletKeys)
    in fmap r Folds.annotatedBlockchain

showBlockchain :: [(PubKeyHash, Wallet)] -> Blockchain -> Either Text Text
showBlockchain walletKeys blockchain =
    flip runReaderT (Map.fromList walletKeys) $ do
        annotatedBlockchain <- doAnnotateBlockchain blockchain
        doc <- render $ reverse annotatedBlockchain
        pure . renderStrict . layoutPretty defaultLayoutOptions $ doc

type RenderM = ReaderT (Map PubKeyHash Wallet) (Either Text)

class Render a where
    render :: a -> RenderM (Doc ann)

newtype RenderPretty a =
    RenderPretty a

instance Pretty a => Render (RenderPretty a) where
    render (RenderPretty a) = pure $ pretty a

instance Render [[AnnotatedTx]] where
    render blockchain =
        vsep . intersperse mempty . fold <$>
        itraverse
            (\slotIndex ->
                 itraverse
                     (\txIndex tx -> do
                          i <- render SequenceId {..}
                          v <- render tx
                          pure $ vsep ["====" <+> i <+> "====", v]))
            blockchain

instance Render AnnotatedTx where
    render AnnotatedTx { txId
                       , tx = Tx {txOutputs, txMint, txFee, txSignatures}
                       , dereferencedInputs
                       , balances
                       , valid = True
                       } =
        vsep <$>
        sequence
            [ heading "TxId:" txId
            , heading "Fee:" txFee
            , heading "Mint:" txMint
            , heading "Signatures" txSignatures
            , pure "Inputs:"
            , indent 2 <$> numbered "----" "Input" dereferencedInputs
            , pure line
            , pure "Outputs:"
            , indent 2 <$> numbered "----" "Output" txOutputs
            , pure line
            , pure "Balances Carried Forward:"
            , indented balances
            ]
    render AnnotatedTx { txId
                       , tx = Tx { txFee }
                       , valid = False
                       } =
        vsep <$>
        sequence
            [ pure "Invalid transaction"
            , heading "TxId:" txId
            , heading "Fee:" txFee
            ]

heading :: Render a => Doc ann -> a -> ReaderT (Map PubKeyHash Wallet) (Either Text) (Doc ann)
heading t x = do
    r <- indented x
    pure $ fill 10 t <> r

instance Render SequenceId where
    render SequenceId {..} =
        pure $
        "Slot #" <> viaShow slotIndex <> "," <+> "Tx #" <> viaShow txIndex

instance Render CurrencySymbol where
    render (CurrencySymbol cs) | cs == PlutusTx.emptyByteString = pure "Ada"
    render (CurrencySymbol other) = render other

instance Render TokenName where
    render (TokenName tn) | tn == PlutusTx.emptyByteString = pure "Lovelace"
    render t             = pure $ pretty $ Value.toString t

instance Render PlutusTx.ByteString where
    render = pure . pretty . JSON.encodeByteString . PlutusTx.toHaskellByteString

deriving via RenderPretty PlutusTx.Data instance
         Render PlutusTx.Data

deriving newtype instance Render Value

instance (Render k, Render v) => Render (AssocMap.Map k v) where
    render m
        | null (AssocMap.toList m) = pure "-"
        | otherwise =
            vsep <$>
            traverse
                (\(k, v) -> do
                     rk <- render k
                     rv <- render v
                     pure $ fill 8 (rk <> ":") <> indent 2 rv)
                (AssocMap.toList m)

instance Render (Map BeneficialOwner Value) where
    render xs
        | Map.null xs = pure "-"
        | otherwise = do
            entries <-
                traverse
                    (\(k, v) -> do
                         rk <- render k
                         rv <- render v
                         pure $ vsep [rk, "Value:", indent 2 rv])
                    (Map.toList xs)
            pure $ vsep $ intersperse mempty entries

instance Render (Map PubKey Signature) where
    render xs
        | Map.null xs = pure "-"
        | otherwise = do
            entries <-
                traverse
                    (\(k, v) -> do
                         rk <- render k
                         rv <- render v
                         pure $ vsep [rk, indent 2 rv])
                    (Map.toList xs)
            pure $ vsep $ intersperse mempty entries

deriving via RenderPretty Text instance Render Text

deriving via RenderPretty String instance Render String

deriving via RenderPretty Integer instance Render Integer

deriving via RenderPretty Address instance Render Address

instance Render Wallet where
    render (Wallet n) = pure $ "Wallet" <+> viaShow n

instance Render BeneficialOwner where
    render (OwnedByScript address) = ("Script:" <+>) <$> render address
    render (OwnedByPubKey pkh) = do
        walletKeys <- ask
        wallet <- lookupWallet pkh walletKeys
        w <- render wallet
        p <- render pkh
        pure $ p <+> parens w

instance Render Ada where
    render ada@(Lovelace l)
        | Ada.isZero ada = pure "-"
        | otherwise = pure (pretty l)

instance Render (Digest SHA256) where
    render = render . abbreviate 40 . JSON.encodeSerialise

deriving via RenderPretty TxId instance Render TxId

instance Render PubKey where
    render pubKey =
        pure $
        let v = Text.pack (show (pretty pubKey))
         in "PubKey:" <+> pretty (abbreviate 40 v)

instance Render PubKeyHash where
    render pkh =
        pure $
        let v = Text.pack (show (pretty pkh))
         in "PubKeyHash:" <+> pretty (abbreviate 40 v)

instance Render Signature where
    render sig =
        pure $
        let v = JSON.encodeSerialise sig
         in "Signature:" <+> pretty (abbreviate 40 v)

instance Render Script where
    render script =
        pure $
        let v = JSON.encodeSerialise script
         in "Script:" <+> pretty (abbreviate 40 v)

instance Render Validator where
    render = render . unValidatorScript

deriving newtype instance Render ValidatorHash

instance Render Datum where
    render = render . getDatum

instance Render a => Render (Set a) where
    render xs = vsep <$> traverse render (Set.toList xs)

instance Render DereferencedInput where
    render (InputNotFound txKey) = pure $ "Input not found:" <+> pretty txKey
    render DereferencedInput {originalInput, refersTo} =
        vsep <$>
        sequence
            [render refersTo, pure "Source:", indent 2 <$> render originalInput]

instance Render TxIn where
    render (TxIn txInRef (Just txInType)) =
        vsep <$> sequence [render txInRef, render txInType]
    render (TxIn txInRef Nothing) = render txInRef

instance Render TxInType where
    render (ConsumeScriptAddress validator _ _) = render validator
    render ConsumePublicKeyAddress              = pure mempty

instance Render TxOutRef where
    render TxOutRef {txOutRefId, txOutRefIdx} =
        vsep <$>
        sequence [heading' "Tx:" txOutRefId, heading' "Output #" txOutRefIdx]
      where
        heading' t x = do
            r <- render x
            pure $ fill 8 t <> r

instance Render TxOut where
    render txOut@TxOut {txOutValue} =
        vsep <$>
        sequence
            [ mappend "Destination:" . indent 2 <$>
              render (toBeneficialOwner txOut)
            , pure "Value:"
            , indent 2 <$> render txOutValue
            ]

------------------------------------------------------------
indented :: Render a => a -> RenderM (Doc ann)
indented x = indent 2 <$> render x

numbered :: Render a => Doc ann -> Doc ann -> [a] -> RenderM (Doc ann)
numbered separator title xs =
    vsep . intersperse mempty <$> itraverse numberedEntry xs
  where
    numberedEntry index x = do
        v <- render x
        pure $ vsep [separator <+> title <+> viaShow index <+> separator, v]

------------------------------------------------------------
lookupWallet ::
       MonadError Text m => PubKeyHash -> Map PubKeyHash Wallet -> m Wallet
lookupWallet pkh (Map.lookup pkh -> Just wallet) = pure wallet
lookupWallet pkh _ =
    throwError $
    "Could not find referenced PubKeyHash: " <> Text.pack (show pkh)

abbreviate :: Int -> Text -> Text
abbreviate n t =
    let prefix = Text.take n t
     in if prefix == t
            then t
            else prefix <> "..."
