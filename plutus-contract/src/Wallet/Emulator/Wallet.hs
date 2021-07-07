{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE DeriveAnyClass        #-}
{-# LANGUAGE DerivingStrategies    #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE GADTs                 #-}
{-# LANGUAGE LambdaCase            #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE NamedFieldPuns        #-}
{-# LANGUAGE OverloadedStrings     #-}
{-# LANGUAGE Rank2Types            #-}
{-# LANGUAGE TemplateHaskell       #-}
{-# LANGUAGE TypeApplications      #-}
{-# LANGUAGE TypeOperators         #-}
{-# LANGUAGE UndecidableInstances  #-}
{-# OPTIONS_GHC -Wno-orphans  #-}
module Wallet.Emulator.Wallet where

import           Control.Lens                   as Lens
import           Control.Monad                  (foldM)
import           Control.Monad.Freer
import           Control.Monad.Freer.Error
import           Control.Monad.Freer.Extras.Log (LogMsg, logDebug, logInfo, logWarn)
import           Control.Monad.Freer.State
import           Control.Monad.Freer.TH         (makeEffect)
import           Control.Newtype.Generics       (Newtype)
import           Data.Aeson                     (FromJSON, ToJSON, ToJSONKey)
import           Data.Bifunctor
import           Data.Foldable
import           Data.Hashable                  (Hashable)
import qualified Data.Map                       as Map
import           Data.Maybe
import           Data.Semigroup                 (Sum (..))
import qualified Data.Set                       as Set
import           Data.String                    (IsString (..))
import qualified Data.Text                      as T
import           Data.Text.Prettyprint.Doc
import           GHC.Generics                   (Generic)
import           Ledger
import qualified Ledger.Ada                     as Ada
import qualified Ledger.AddressMap              as AM
import           Ledger.Constraints.OffChain    (UnbalancedTx (..))
import qualified Ledger.Constraints.OffChain    as U
import           Ledger.Credential              (Credential (..))
import qualified Ledger.Crypto                  as Crypto
import qualified Ledger.Tx                      as Tx
import qualified Ledger.Value                   as Value
import           Plutus.Contract.Checkpoint     (CheckpointLogMsg)
import qualified PlutusTx.Prelude               as PlutusTx
import           Prelude                        as P
import           Servant.API                    (FromHttpApiData (..), ToHttpApiData (..))
import qualified Wallet.API                     as WAPI
import           Wallet.Effects                 (ChainIndexEffect, NodeClientEffect, WalletEffect (..),
                                                 watchedAddresses)
import qualified Wallet.Effects                 as W
import           Wallet.Emulator.Chain          (ChainState (..))
import           Wallet.Emulator.ChainIndex     (ChainIndexState, idxWatchedAddresses)
import           Wallet.Emulator.LogMessages    (RequestHandlerLogMsg, TxBalanceMsg (..))
import           Wallet.Emulator.NodeClient     (NodeClientState, emptyNodeClientState)

newtype SigningProcess = SigningProcess {
    unSigningProcess :: forall effs. (Member (Error WAPI.WalletAPIError) effs) => [PubKeyHash] -> Tx -> Eff effs Tx
}

instance Show SigningProcess where
    show = const "SigningProcess <...>"

-- | A wallet in the emulator model.
newtype Wallet = Wallet { getWallet :: Integer }
    deriving (Eq, Ord, Generic)
    deriving newtype (ToHttpApiData, FromHttpApiData, Hashable)
    deriving anyclass (Newtype, ToJSON, FromJSON, ToJSONKey)

instance Show Wallet where
    showsPrec p (Wallet i) = showParen (p > 9) $ showString "Wallet " . shows i

instance Pretty Wallet where
    pretty (Wallet i) = "W" <> pretty i

-- | Get a wallet's public key.
walletPubKey :: Wallet -> PubKey
walletPubKey = toPublicKey . walletPrivKey

-- | Get a wallet's private key by looking it up in the list of
--   private keys in 'Ledger.Crypto.knownPrivateKeys'
walletPrivKey :: Wallet -> PrivateKey
walletPrivKey (Wallet i) = cycle Crypto.knownPrivateKeys !! fromIntegral (i - 1)

-- | Get a wallet's address.
walletAddress :: Wallet -> Address
walletAddress = pubKeyAddress . walletPubKey

-- | Sign a 'Tx' using the wallet's privat key.
signWithWallet :: Wallet -> Tx -> Tx
signWithWallet wlt = addSignature (walletPrivKey wlt)

-- | Whether the wallet is one of the known emulated wallets
isEmulatorWallet :: Wallet -> Bool
isEmulatorWallet (Wallet i) = 0 <= i && i < fromIntegral (length Crypto.knownPrivateKeys)

data WalletEvent =
    GenericLog T.Text
    | CheckpointLog CheckpointLogMsg
    | RequestHandlerLog RequestHandlerLogMsg
    | TxBalanceLog TxBalanceMsg
    deriving stock (Show, Eq, Generic)
    deriving anyclass (ToJSON, FromJSON)

instance Pretty WalletEvent where
    pretty = \case
        GenericLog msg        -> pretty msg
        CheckpointLog msg     -> pretty msg
        RequestHandlerLog msg -> pretty msg
        TxBalanceLog msg      -> pretty msg

makePrisms ''WalletEvent

-- | The state used by the mock wallet environment.
data WalletState = WalletState {
    _ownPrivateKey  :: PrivateKey, -- ^ User's 'PrivateKey'.
    _nodeClient     :: NodeClientState,
    _chainIndex     :: ChainIndexState,
    _signingProcess :: SigningProcess
    } deriving Show

makeLenses ''WalletState

-- | Get the user's own public-key address.
ownAddress :: WalletState -> Address
ownAddress = pubKeyAddress . toPublicKey . view ownPrivateKey

-- | An empty wallet state with the public/private key pair for a wallet, and the public-key address
-- for that wallet as the sole watched address.
emptyWalletState :: Wallet -> WalletState
emptyWalletState w = WalletState pk emptyNodeClientState mempty sp  where
    pk = walletPrivKey w
    sp = defaultSigningProcess w

-- | An empty wallet using the given private key.
-- for that wallet as the sole watched address.
emptyWalletStateFromPrivateKey :: PrivateKey -> WalletState
emptyWalletStateFromPrivateKey pk = WalletState pk emptyNodeClientState mempty sp where
    sp = signWithPrivateKey pk

data PaymentArgs =
    PaymentArgs
        { availableFunds :: Map.Map TxOutRef TxOutTx
        -- ^ Funds that may be spent in order to balance the payment
        , ownPubKey      :: PubKey
        -- ^ Where to send the change (if any)
        , requestedValue :: Value
        -- ^ The value that must be covered by the payment's inputs
        }

handleWallet ::
    ( Member NodeClientEffect effs
    , Member ChainIndexEffect effs
    , Member (State WalletState) effs
    , Member (LogMsg TxBalanceMsg) effs
    )
    => WalletEffect ~> Eff effs
handleWallet = \case
    SubmitTxn tx -> do
        logInfo $ SubmittingTx tx
        W.publishTx tx
    OwnPubKey -> toPublicKey <$> gets _ownPrivateKey
    BalanceTx utx -> runError $ do
        logInfo $ BalancingUnbalancedTx utx
        utxo <- get >>= ownOutputs
        utxWithFees <- validateTxAndAddFees utxo utx
        -- balance to add fees
        tx' <- handleBalanceTx utxo (utx & U.tx . fee .~ (utxWithFees ^. U.tx . fee))
        tx'' <- handleAddSignature tx'
        logInfo $ FinishedBalancing tx''
        pure tx''
    TotalFunds -> foldMap (txOutValue . txOutTxOut) <$> (get >>= ownOutputs)

handleAddSignature ::
    Member (State WalletState) effs
    => Tx
    -> Eff effs Tx
handleAddSignature tx = do
    privKey <- gets _ownPrivateKey
    pure (addSignature privKey tx)

ownOutputs :: forall effs. Member ChainIndexEffect effs => WalletState -> Eff effs (Map.Map TxOutRef TxOutTx)
ownOutputs WalletState{_ownPrivateKey} = do
    let addr = pubKeyAddress $ toPublicKey _ownPrivateKey
    fromMaybe mempty . view (at addr) <$> watchedAddresses

validateTxAndAddFees ::
    ( Member (Error WAPI.WalletAPIError) effs
    , Member ChainIndexEffect effs
    , Member (LogMsg TxBalanceMsg) effs
    , Member (State WalletState) effs
    )
    => Map.Map TxOutRef TxOutTx
    -> UnbalancedTx
    -> Eff effs UnbalancedTx
validateTxAndAddFees ownTxOuts utx = do
    -- Balance and sign just for validation
    tx <- handleBalanceTx ownTxOuts utx
    signedTx <- handleAddSignature tx
    let utxoIndex        = Ledger.UtxoIndex $ unBalancedTxUtxoIndex utx <> (fmap txOutTxOut ownTxOuts)
        ((e, _), events) = Ledger.runValidation (Ledger.validateTransactionOffChain signedTx) utxoIndex
    flip traverse_ e $ \(phase, ve) -> do
        logWarn $ ValidationFailed phase (txId tx) tx ve events
        throwError $ WAPI.ValidationError ve
    let scriptsSize = getSum $ foldMap (Sum . scriptSize . Ledger.sveScript) events
        theFee = minFee tx <> Ada.lovelaceValueOf scriptsSize -- TODO: use protocol parameters
    pure $ utx{ unBalancedTxTx = (unBalancedTxTx utx){ txFee = theFee }}

lookupValue ::
    ( Member (Error WAPI.WalletAPIError) effs
    , Member ChainIndexEffect effs
    , Member (State WalletState) effs
    )
    => Map.Map TxOutRef TxOut
    -> Tx.TxIn
    -> Eff effs Value
lookupValue otherInputsMap outputRef = do
    walletIndexMap <- fmap Tx.txOutTxOut . AM.outRefMap . view (chainIndex . idxWatchedAddresses) <$> get
    chainIndexMap <- fmap Tx.txOutTxOut . AM.outRefMap <$> WAPI.watchedAddresses
    let txout = (otherInputsMap <> walletIndexMap <> chainIndexMap) ^. at (Tx.txInRef outputRef)
    case txout of
        Just output -> pure $ Tx.txOutValue output
        Nothing ->
            WAPI.throwOtherError $ "Unable to find TxOut for " <> fromString (show outputRef)

-- | balance an unbalanced transaction by adding missing inputs and outputs
handleBalanceTx ::
    forall effs.
    ( Member (State WalletState) effs
    , Member ChainIndexEffect effs
    , Member (Error WAPI.WalletAPIError) effs
    , Member (LogMsg TxBalanceMsg) effs
    )
    => Map.Map TxOutRef TxOutTx
    -> UnbalancedTx
    -> Eff effs Tx
handleBalanceTx utxo UnbalancedTx{unBalancedTxTx, unBalancedTxUtxoIndex} = do
    let filteredUnbalancedTxTx = removeEmptyOutputs unBalancedTxTx
    let txInputs = Set.toList $ Tx.txInputs filteredUnbalancedTxTx
    ownPubKey <- gets (toPublicKey . view ownPrivateKey)
    inputValues <- traverse (lookupValue unBalancedTxUtxoIndex) (Set.toList $ Tx.txInputs filteredUnbalancedTxTx)
    collateral  <- traverse (lookupValue unBalancedTxUtxoIndex) (Set.toList $ Tx.txCollateral filteredUnbalancedTxTx)
    let fees = txFee filteredUnbalancedTxTx
        left = txMint filteredUnbalancedTxTx <> fold inputValues
        right = fees <> foldMap (view Tx.outValue) (filteredUnbalancedTxTx ^. Tx.outputs)
        remainingFees = fees PlutusTx.- fold collateral -- TODO: add collateralPercent
        balance = left PlutusTx.- right
        (neg, pos) = Value.split balance

    tx' <- if Value.isZero pos
           then do
               logDebug NoOutputsAdded
               pure filteredUnbalancedTxTx
           else do
                logDebug $ AddingPublicKeyOutputFor pos
                pure $ addOutputs ownPubKey pos filteredUnbalancedTxTx

    tx'' <- if Value.isZero neg
            then do
                logDebug NoInputsAdded
                pure tx'
            else do
                logDebug $ AddingInputsFor neg
                -- filter out inputs from utxo that are already in unBalancedTx
                let inputsOutRefs = map Tx.txInRef txInputs
                    filteredUtxo = flip Map.filterWithKey utxo $ \txOutRef _ ->
                        txOutRef `notElem` inputsOutRefs
                addInputs filteredUtxo ownPubKey neg tx'

    if remainingFees `Value.leq` PlutusTx.zero
    then do
        logDebug NoCollateralInputsAdded
        pure tx''
    else do
        logDebug $ AddingCollateralInputsFor remainingFees
        addCollateral utxo remainingFees tx''

addOutputs :: PubKey -> Value -> Tx -> Tx
addOutputs pk vl tx = tx & over Tx.outputs (pko :) where
    pko = Tx.pubKeyTxOut vl pk

addCollateral
    :: Member (Error WAPI.WalletAPIError) effs
    => AM.UtxoMap
    -> Value
    -> Tx
    -> Eff effs Tx
addCollateral mp vl tx = do
    (spend, _) <- selectCoin (second (Tx.txOutValue . Tx.txOutTxOut) <$> Map.toList mp) vl
    let addTxCollateral =
            let ins = Set.fromList (Tx.pubKeyTxIn . fst <$> spend)
            in over Tx.collateralInputs (Set.union ins)
    pure $ tx & addTxCollateral

-- | @addInputs mp pk vl tx@ selects transaction outputs worth at least
--   @vl@ from the UTXO map @mp@ and adds them as inputs to @tx@. A public
--   key output for @pk@ is added containing any leftover change.
addInputs
    :: Member (Error WAPI.WalletAPIError) effs
    => AM.UtxoMap
    -> PubKey
    -> Value
    -> Tx
    -> Eff effs Tx
addInputs mp pk vl tx = do
    (spend, change) <- selectCoin (second (Tx.txOutValue . Tx.txOutTxOut) <$> Map.toList mp) vl
    let

        addTxIns  =
            let ins = Set.fromList (Tx.pubKeyTxIn . fst <$> spend)
            in over Tx.inputs (Set.union ins)

        addTxOuts = if Value.isZero change
                    then id
                    else addOutputs pk change

    pure $ tx & addTxOuts & addTxIns

-- Make a transaction output from a positive value.
mkChangeOutput :: PubKey -> Value -> Maybe TxOut
mkChangeOutput pubK v =
    if Value.isZero v then Nothing else Just (pubKeyTxOut v pubK)

-- | Given a set of @a@s with coin values, and a target value, select a number
-- of @a@ such that their total value is greater than or equal to the target.
selectCoin :: (Member (Error WAPI.WalletAPIError) effs)
    => [(a, Value)]
    -> Value
    -> Eff effs ([(a, Value)], Value)
selectCoin fnds vl =
        let
            total = foldMap snd fnds
            fundsWithTotal = P.zip fnds (drop 1 $ P.scanl (<>) mempty $ fmap snd fnds)
            err   = throwError
                    $ WAPI.InsufficientFunds
                    $ T.unwords
                        [ "Total:", T.pack $ show total
                        , "expected:", T.pack $ show vl]
        -- Values are in a partial order: what we want to check is that the
        -- total available funds are bigger than (or equal to) the required value.
        -- It is *not* correct to replace this condition with 'total `Value.lt` vl' -
        -- consider what happens if the amounts are incomparable.
        in  if not (total `Value.geq` vl)
            then err
            else
                let
                    fundsToSpend   = takeUntil (\(_, runningTotal) -> vl `Value.leq` runningTotal) fundsWithTotal
                    totalSpent     = case reverse fundsToSpend of
                                        []            -> PlutusTx.zero
                                        (_, total'):_ -> total'
                    change         = totalSpent PlutusTx.- vl
                in pure (fst <$> fundsToSpend, change)

-- | Removes transaction outputs with empty datum and empty value.
removeEmptyOutputs :: Tx -> Tx
removeEmptyOutputs tx = tx & over Tx.outputs (filter (not . isEmpty')) where
    isEmpty' (Tx.TxOut{Tx.txOutValue, Tx.txOutDatumHash}) =
        null (Value.flattenValue txOutValue) && isNothing txOutDatumHash

-- | Take elements from a list until the predicate is satisfied.
-- 'takeUntil' @p@ includes the first element for wich @p@ is true
-- (unlike @takeWhile (not . p)@).
takeUntil :: (a -> Bool) -> [a] -> [a]
takeUntil _ []       = []
takeUntil p (x:xs)
    | p x            = [x]
    | otherwise      = x : takeUntil p xs

-- | The default signing process is 'signWallet'
defaultSigningProcess :: Wallet -> SigningProcess
defaultSigningProcess = signWallet

signWithPrivateKey :: PrivateKey -> SigningProcess
signWithPrivateKey pk = SigningProcess $
    \pks tx -> foldM (signTxWithPrivateKey pk) tx pks

-- | Sign the transaction by calling 'WAPI.signTxnWithKey' (throwing a
--   'PrivateKeyNotFound' error if called with a key other than the
--   wallet's private key)
signWallet :: Wallet -> SigningProcess
signWallet wllt = SigningProcess $
    \pks tx -> foldM (signTxnWithKey wllt) tx pks

-- | Sign the transaction with the private key of the given public
--   key. Fails if the wallet doesn't have the private key.
signTxnWithKey :: (Member (Error WAPI.WalletAPIError) r) => Wallet -> Tx -> PubKeyHash -> Eff r Tx
signTxnWithKey wllt tx pubK = do
    let ownPubK = walletPubKey wllt
    if pubKeyHash ownPubK == pubK
    then pure (signWithWallet wllt tx)
    else throwError (WAPI.PrivateKeyNotFound pubK)

-- | Sign the transaction with the private key, if the hash is that of the
--   private key.
signTxWithPrivateKey :: (Member (Error WAPI.WalletAPIError) r) => PrivateKey -> Tx -> PubKeyHash -> Eff r Tx
signTxWithPrivateKey pk tx pubK = do
    let ownPubKey = toPublicKey pk
    if pubKeyHash ownPubKey == pubK
    then pure (addSignature pk tx)
    else throwError (WAPI.PrivateKeyNotFound pubK)

-- | Sign the transaction with the private keys of the given wallets,
--   ignoring the list of public keys that the 'SigningProcess' is passed.
signWallets :: [Wallet] -> SigningProcess
signWallets wallets = SigningProcess $ \_ tx ->
    let signingKeys = walletPrivKey <$> wallets in
    pure (foldr addSignature tx signingKeys)

data SigningProcessControlEffect r where
    SetSigningProcess :: SigningProcess -> SigningProcessControlEffect ()
makeEffect ''SigningProcessControlEffect

type SigningProcessEffs = '[State SigningProcess, Error WAPI.WalletAPIError]

handleSigningProcessControl :: (Members SigningProcessEffs effs) => Eff (SigningProcessControlEffect ': effs) ~> Eff effs
handleSigningProcessControl = interpret $ \case
    SetSigningProcess proc -> put proc

-- | An Entity is a thing that can hold 'Value'. Used in the 'balances'
-- function to compute who holds for a given chain state and set of wallets.
data Entity
  = WalletEntity Wallet
  | PubKeyHashEntity PubKeyHash
  | ScriptEntity ValidatorHash
  deriving (Eq, Ord)

instance Show Entity where
  show (WalletEntity w)     = "Wallet " <> show (getWallet w)
  show (ScriptEntity h)     = "Script " <> show h
  show (PubKeyHashEntity h) = "PubKeyHash " <> show h

type WalletSet = Map.Map Wallet WalletState

-- | Pick out all the public keys from the set of wallets and map them back to
-- their corresponding wallets.
walletPubKeyHashes :: WalletSet -> Map.Map PubKeyHash Wallet
walletPubKeyHashes = foldl' f Map.empty . Map.toList
  where
    f m (w, ws) = Map.insert (pubKeyHash $ toPublicKey $ _ownPrivateKey $ ws) w m

-- | For a set of wallets, convert them into a map of value: entity,
-- where entity is one of 'Entity'.
balances :: ChainState -> WalletSet -> Map.Map Entity Value
balances state wallets = foldl' f Map.empty . getIndex . _index $ state
  where
    toEntity :: Address -> Entity
    toEntity a = case addressCredential a of
                    PubKeyCredential h -> case Map.lookup h ws of
                        Nothing -> PubKeyHashEntity h
                        Just w  -> WalletEntity w
                    ScriptCredential h -> ScriptEntity h

    ws :: Map.Map PubKeyHash Wallet
    ws = walletPubKeyHashes wallets

    f m o = Map.insertWith (<>) (toEntity $ txOutAddress o) (txOutValue o) m
