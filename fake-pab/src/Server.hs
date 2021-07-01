{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE DeriveAnyClass        #-}
{-# LANGUAGE DerivingStrategies    #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings     #-}
{-# LANGUAGE QuasiQuotes           #-}
{-# LANGUAGE StandaloneDeriving    #-}
{-# LANGUAGE TupleSections         #-}
{-# LANGUAGE TypeApplications      #-}
{-# OPTIONS_GHC -Wno-orphans #-}

module Server where

import           API                               (API, ApplyInputRequest (..), CreateContractRequest (..),
                                                    GetContractHistoryResponse (..), GetContractStateResponse (..),
                                                    JSON_API, PLAIN_API, PrivateKey, PublicKey, RawHtml (..),
                                                    TransferRequest (..))
import           Control.Concurrent                (threadDelay)
import           Control.Exception                 (Exception (toException), throwIO)
import           Control.Monad                     (when, zipWithM)
import           Control.Monad.Except              (ExceptT, void)
import           Control.Monad.IO.Class            (MonadIO, liftIO)
import           Control.Monad.Logger              (LoggingT, MonadLogger, logInfoN, runStderrLoggingT)
import           Control.Monad.Reader              (ReaderT, runReaderT)
import qualified Crypto.Hash.SHA256                as SHA256
import           Data.Aeson                        (FromJSON, ToJSON, eitherDecode, encode)
import qualified Data.Aeson                        as Aeson
import           Data.Bifunctor                    (Bifunctor (..), bimap)
import qualified Data.ByteString                   as BS
import qualified Data.ByteString.Base16            as B16
import qualified Data.ByteString.Lazy              as BSL
import qualified Data.ByteString.Lazy.UTF8         as BSLU
import qualified Data.ByteString.UTF8              as BSU
import           Data.Either                       (fromRight)
import           Data.List                         (foldl')
import           Data.Map                          (Map)
import qualified Data.Map                          as Map
import           Data.Pool                         (Pool, withResource)
import           Data.Proxy                        (Proxy (Proxy))
import           Data.Ratio                        (Ratio, denominator, numerator)
import           Data.Set                          (Set)
import qualified Data.Set                          as Set
import           Data.String                       as S
import           Data.Text                         (Text)
import qualified Data.Text                         as Text
import qualified Data.Text.Encoding                as TE
import           Data.Time.Clock                   (diffUTCTime, getCurrentTime, nominalDiffTimeToSeconds)
import           Database.PostgreSQL.Simple        (Connection, FromRow, Only (..), SqlError, execute, executeMany,
                                                    query, query_, returning, withTransaction)
import           Database.PostgreSQL.Simple.Errors (ConstraintViolation (..), catchViolation)
import           Database.PostgreSQL.Simple.SqlQQ  (sql)
import           GHC.Generics                      (Generic)
import           Language.Marlowe                  (ChoiceId (ChoiceId), Contract (..), Input (..), Party (..),
                                                    Payment (Payment), Slot (..), State, Token (Token),
                                                    TransactionInput (..), TransactionOutput (..), TransactionWarning,
                                                    computeTransaction, emptyState, extractContractRoles)
import           Ledger                            (PubKeyHash (..))
import           Network.Wai.Middleware.Cors       (cors, corsRequestHeaders, simpleCorsResourcePolicy)
import           Plutus.V1.Ledger.Value            (CurrencySymbol (..), TokenName (..), Value (..), currencySymbol,
                                                    tokenName)
import qualified PlutusTx.AssocMap                 as AssocMap
import qualified PlutusTx.ByteString               as PlutusTx
import           Servant                           (Application, Handler (Handler), Server, ServerError, hoistServer,
                                                    serve, serveDirectoryFileServer, throwError, (:<|>) ((:<|>)), (:>))
import           Text.Blaze.Html.Renderer.Pretty   (renderHtml)
import qualified Text.Blaze.Html5                  as H
import qualified Text.Blaze.Html5.Attributes       as A

fromCurrencySymbol :: CurrencySymbol -> String
fromCurrencySymbol =  Text.unpack . TE.decodeUtf8 . B16.encode . PlutusTx.toHaskellByteString . unCurrencySymbol

toCurrencySymbol :: String -> CurrencySymbol
toCurrencySymbol = currencySymbol . fromRight mempty . B16.decode . TE.encodeUtf8 . Text.pack

fromPubKeyHash :: PubKeyHash -> PublicKey
fromPubKeyHash =  Text.unpack . TE.decodeUtf8 . B16.encode . PlutusTx.toHaskellByteString . getPubKeyHash

toPubKeyHash :: PublicKey -> PubKeyHash
toPubKeyHash = PubKeyHash . PlutusTx.fromHaskellByteString . fromRight mempty . B16.decode . TE.encodeUtf8 . Text.pack

handlersJSON :: Pool Connection -> FilePath -> Server JSON_API
handlersJSON conns staticPath = createWallet conns :<|>
                                listWalletFunds conns :<|>
                                transferFundsJSON conns :<|>
                                createContractJSON conns :<|>
                                getContractState conns :<|>
                                getContractHistory conns :<|>
                                applyInputJSON conns

handlersPlain :: Pool Connection -> FilePath -> Server PLAIN_API
handlersPlain conns staticPath = showResult . createWallet conns :<|>
                                 showResult . listWalletFunds conns :<|>
                                 transferFundsPlain conns :<|>
                                 createContractPlain conns :<|>
                                 showResult . getContractStatePlain conns :<|>
                                 showResult . getContractHistoryPlain conns :<|>
                                 applyInputPlain conns

handlers :: Pool Connection -> FilePath -> Server API
handlers conns staticPath = handlersJSON conns staticPath :<|>
                            handlersPlain conns staticPath :<|>
                            testEndpoint :<|>
                            dashboard conns :<|>
                            serveDirectoryFileServer staticPath

showResult :: Show a => Handler a -> Handler String
showResult handler = do x <- handler
                        return (show x)

-- Creates a Wallet with 1000 ADA
createWallet :: Pool Connection -> PrivateKey -> Handler PublicKey
createWallet conns privateKey =
  liftIO . withResource conns $ \conn -> withTransaction conn (do
    catchViolation catcher $ do
      execute conn
        [sql|WITH mc_insert AS (INSERT INTO money_container DEFAULT VALUES
                                RETURNING money_container_id AS id),
                  wallet_insert AS (INSERT INTO wallet (money_container_id, pub_key)
                                    VALUES ((SELECT id FROM mc_insert), ?))
              INSERT INTO currency_amount (amount, money_container_id, currency_symbol, token_name)
              VALUES (1000000000, (SELECT id FROM mc_insert), '', '')|] [publicKey]
      return publicKey)
  where
    publicKey = BSU.toString $ B16.encode $ SHA256.hash $ BSU.fromString privateKey

    catcher :: SqlError -> ConstraintViolation -> IO PublicKey
    catcher _ (UniqueViolation "wallet_pub_key_key") = return publicKey
    catcher e _                                      = throwIO e

-- Lists the amount a wallet has of each currency (of currencies it ever had some amount of)
listWalletFunds :: Pool Connection -> PublicKey -> Handler (Map CurrencySymbol [(TokenName, Integer)])
listWalletFunds conns publicKey =
  liftIO . withResource conns $ \conn -> withTransaction conn (do
      result <- query conn
                  [sql| SELECT ca.currency_symbol, ca.token_name, SUM(amount) AS amount
                        FROM wallet w INNER JOIN currency_amount ca
                          ON w.money_container_id = ca.money_container_id
                        WHERE w.pub_key = ?
                        GROUP BY ca.currency_symbol, ca.token_name
                  |] [publicKey]
      return $ Map.fromListWith (++) [(toCurrencySymbol cs, [(tokenName tn, fromRatio am)]) | (cs, tn, am) <- result])



-- Creates a transaction to transfer funds
transferFunds :: Pool Connection -> PrivateKey -> CurrencySymbol -> TokenName -> Integer -> PublicKey -> Handler ()
transferFunds conns srcPrivKey currSym (TokenName tok) amount destPubKey =
  let curr = fromCurrencySymbol currSym in
  liftIO . withResource conns $ \conn -> withTransaction conn (do
    when (amount > 0) $ do
      execute conn
        [sql|WITH source_container AS (SELECT get_or_create_money_container_id_from_pubkey(?) AS id),
                  destination_container AS (SELECT get_or_create_money_container_id_from_pubkey(?) AS id),
                  main_transaction AS (INSERT INTO transaction (signing_wallet_id)
                                       VALUES ((SELECT id FROM source_container))
                                       RETURNING transaction_id AS id)
              INSERT INTO transaction_line (transaction_id, line_num, money_container_id, amount_change, currency_symbol, token_name)
              VALUES ((SELECT id FROM main_transaction), 1, (SELECT id FROM source_container), ?, ?, ?),
                     ((SELECT id FROM main_transaction), 2, (SELECT id FROM destination_container), ?, ?, ?)|]
                   (srcPubKey,
                    destPubKey,
                    -amount, curr, PlutusTx.toHaskellByteString tok, amount, curr, PlutusTx.toHaskellByteString tok)
      return ())
  where
    srcPubKey = BSU.toString $ B16.encode $ SHA256.hash $ BSU.fromString srcPrivKey

transferFundsPlain :: Pool Connection -> String -> String -> String -> Integer -> String -> Handler String
transferFundsPlain conns srcPrivKey curr tok amount destPubKey =
  show <$> transferFunds conns srcPrivKey (toCurrencySymbol curr) (tokenName (BSU.fromString tok)) amount destPubKey

transferFundsJSON :: Pool Connection -> API.TransferRequest -> Handler ()
transferFundsJSON conns TransferRequest { src_priv_key = src_priv_key
                                        , currency_symbol = currency_symbol
                                        , token_symbol = token_symbol
                                        , amount = amount
                                        , dest_pub_key = dest_pub_key
                                        } = transferFunds conns src_priv_key currency_symbol token_symbol amount (fromPubKeyHash dest_pub_key)

-- Adds a contract to the list of contracts
createContractPlain :: Pool Connection -> String -> String -> String -> Handler String
createContractPlain conns creator_priv_key role_distribution contract =
  show <$> createContract conns (read creator_priv_key) ([(tokenName name, pubkey) | (name, pubkey) <- read role_distribution]) (fromRight Close $ eitherDecode $ BSLU.fromString contract)

createContractJSON :: Pool Connection -> CreateContractRequest -> Handler (Either String CurrencySymbol)
createContractJSON conns CreateContractRequest { creator_priv_key = creator_priv_key
                                               , role_distribution = role_distribution
                                               , contract = contract
                                               } =
  createContract conns creator_priv_key (map (second fromPubKeyHash) role_distribution) contract

createContract :: Pool Connection -> PrivateKey -> [(TokenName, PublicKey)] -> Contract -> Handler (Either String CurrencySymbol)
createContract conns privkey distrib contract =
  let owners = Map.fromList distrib :: Map TokenName PublicKey
      ownerTokenNames = Map.keys owners
      ownerTokenNamesStr = map unTokenName ownerTokenNames
      roles = extractContractRoles contract in
  if roles `Set.isSubsetOf` Set.fromList (Map.keys owners)
  then
    liftIO . withResource conns $ \conn -> withTransaction conn (do
      [Only currencySymbol] <- query_ conn [sql| WITH curr_sym AS (INSERT INTO currency_symbol (currency_symbol)
                                                                   VALUES ((SELECT encode(digest(COUNT(currency_symbol)::text,'sha256'),'hex') FROM currency_symbol))
                                                                   RETURNING currency_symbol)
                                                 SELECT cs.currency_symbol FROM curr_sym cs
                                           |] :: IO [Only String]
      executeMany conn [sql| INSERT INTO token (currency_symbol, token_name)
                             VALUES (?, ?)
                       |] ([(currencySymbol, BSU.toString (PlutusTx.toHaskellByteString tns)) | tns <- ownerTokenNamesStr] :: [(String, String)])
      sequence_ [execute conn [sql| INSERT INTO currency_amount (amount, currency_symbol, token_name, money_container_id)
                                    VALUES (?, ?, ?, get_or_create_money_container_id_from_pubkey(?))
                              |] (1 :: Integer, currencySymbol, BSU.toString (PlutusTx.toHaskellByteString tns), pk) | (TokenName tns, pk) <- Map.toList owners ]
      [Only currSlot] <- query_ conn
                      [sql| SELECT MAX(slot_number) + 1
                            FROM slot
                      |]
      [Only moneyContainerId] <- query_ conn
                              [sql| INSERT INTO money_container DEFAULT VALUES
                                    RETURNING money_container_id AS id |]
      let contractJSON = Aeson.encode contract
          stateJSON = Aeson.encode $ emptyState (Slot $ fromRatio currSlot)
      execute conn [sql| INSERT INTO contract (money_container_id, contract, state, currency_symbol, original_contract, original_state)
                         VALUES (?, ?, ?, ?, ?, ?)
                   |] (fromRatio moneyContainerId, contractJSON, stateJSON, currencySymbol, contractJSON, stateJSON)
      return $ Right (toCurrencySymbol currencySymbol))
  else let missingRoles = roles `Set.difference` Set.fromList ownerTokenNames in
       return $ Left $ "You didn't specify owners of these roles: " <> show missingRoles

data DatabaseParsingException = ErrorParsingContractState
                              | CouldNotFindPubKeyForRole String
  deriving (Eq, Ord)

instance Exception DatabaseParsingException

instance Show DatabaseParsingException where
  showsPrec _ ErrorParsingContractState = showString "Could not parse state of the current contract in DB"
  showsPrec _ (CouldNotFindPubKeyForRole role) = showString "Could not find single PubKey for Role " . showString role . showString " in DB"

-- Obtains the remaining contract and current state for a given currency symbol
getContractStatePlain :: Pool Connection -> String -> Handler GetContractStateResponse
getContractStatePlain conns currSymb = getContractState conns (toCurrencySymbol currSymb)

getContractState :: Pool Connection -> CurrencySymbol -> Handler GetContractStateResponse
getContractState conns encCurrSymb =
  let currencySymbol = fromCurrencySymbol encCurrSymb in
  liftIO . withResource conns $ \conn -> withTransaction conn (do
      (_, currentState, currentContract) <- getCurrentStateAndContract conn currencySymbol
      return (GetContractStateResponse { curr_state = currentState
                                      , curr_contract = currentContract
                                      }))

getCurrentStateAndContract :: Connection -> String -> IO (Integer, State, Contract)
getCurrentStateAndContract conn currencySymbol = do
      [(contractId, currentStateStr, currentContractStr)]
         <- query conn [sql| SELECT money_container_id, state, contract
                             FROM contract
                             WHERE currency_symbol = ?
                       |] (Only currencySymbol) :: IO [(Ratio Integer, BSLU.ByteString, BSLU.ByteString)]
      case (eitherDecode currentStateStr, eitherDecode currentContractStr) of
        (Right currentState, Right currentContract) ->
            return (fromRatio contractId, currentState, currentContract)
        _ -> throwIO (toException ErrorParsingContractState)

-- Obtains the original contract and state for a give currency symbol
getContractHistoryPlain :: Pool Connection -> String -> Handler GetContractHistoryResponse
getContractHistoryPlain conns currSymb = getContractHistory conns (toCurrencySymbol currSymb)

getContractHistory :: Pool Connection -> CurrencySymbol -> Handler GetContractHistoryResponse
getContractHistory conns encCurrSymb =
  let currencySymbol = fromCurrencySymbol encCurrSymb in
  liftIO . withResource conns $ \conn -> withTransaction conn (do
      [(contractContainerId, originalStateStr, originalContractStr)]
         <- query conn [sql| SELECT money_container_id, original_state, original_contract
                             FROM contract
                             WHERE currency_symbol = ?
                       |] (Only currencySymbol) :: IO [(Ratio Integer, BSLU.ByteString, BSLU.ByteString)]
      inputs
         <- query conn [sql| SELECT inputs
                             FROM transaction
                             WHERE contract_id = ?
                               AND reason_invalid IS NULL
                               AND slot_number IS NOT NULL
                             ORDER BY transaction_id ASC
                       |] (Only (fromRatio contractContainerId)) :: IO [Only BSLU.ByteString]
      case (eitherDecode originalStateStr, eitherDecode originalContractStr) of
        (Right originalState, Right originalContract) ->
            return (GetContractHistoryResponse { original_state = originalState
                                             , original_contract = originalContract
                                             , inputs = [ input | Only eitherInput <- inputs
                                                                , Right input <- [eitherDecode eitherInput] ]
                                             })
        _ -> throwIO (toException ErrorParsingContractState))

fromTokenName :: TokenName -> String
fromTokenName = BSU.toString . PlutusTx.toHaskellByteString . unTokenName

extractPubkeysAndRoles :: [Input] -> (Set PublicKey, Set String)
extractPubkeysAndRoles = foldl' extractPubkeyOrRole mempty
  where
    extractPubkeyOrRole :: (Set PublicKey, Set String) -> Input -> (Set PublicKey, Set String)
    extractPubkeyOrRole acc (IDeposit _ party _ _)         = acc <> extractFromParty party
    extractPubkeyOrRole acc (IChoice (ChoiceId _ party) _) = acc <> extractFromParty party
    extractPubkeyOrRole acc INotify                        = acc

    extractFromParty :: Party -> (Set PublicKey, Set String)
    extractFromParty (PK pk)     = (Set.singleton (fromPubKeyHash pk), mempty)
    extractFromParty (Role role) = (mempty, Set.singleton (fromTokenName role))

type AmountDiffSummary = (Map (PublicKey, (String, String)) Integer, Map (String, (String, String)) Integer)

extractPaymentsFromInputs :: [Input] -> AmountDiffSummary
extractPaymentsFromInputs = foldl' extractPaymentFromInput (Map.empty, Map.empty)
  where
    extractPaymentFromInput :: AmountDiffSummary -> Input -> AmountDiffSummary
    extractPaymentFromInput acc (IDeposit _ party (Token currSym tokName) amount) = addPaymentToParty acc party (fromCurrencySymbol currSym) (fromTokenName tokName) (-amount)
    extractPaymentFromInput acc (IChoice _ _) = acc
    extractPaymentFromInput acc INotify = acc

addPaymentsFromOutputs :: AmountDiffSummary -> [Payment] -> AmountDiffSummary
addPaymentsFromOutputs = foldl' addPaymentFromOutput
  where
    addPaymentFromOutput :: AmountDiffSummary -> Payment -> AmountDiffSummary
    addPaymentFromOutput acc (Payment party (Value value)) =
      Map.foldlWithKey' (\intermediateAcc currSym ->
        Map.foldlWithKey' (\innerAcc tokName ->
          addPaymentToParty innerAcc party (fromCurrencySymbol currSym) (fromTokenName tokName)
                         ) intermediateAcc
                       ) acc (Map.map toStandardMap $ toStandardMap value)

toStandardMap :: Ord a => AssocMap.Map a b -> Map a b
toStandardMap = Map.fromList . AssocMap.toList

addPaymentToParty :: AmountDiffSummary -> Party -> String -> String -> Integer -> AmountDiffSummary
addPaymentToParty (mpk, mrol) (PK pk) currSym tokName amount = (Map.alter (addMaybeVal amount) (fromPubKeyHash pk, (currSym, tokName)) mpk, mrol)
addPaymentToParty (mpk, mrol) (Role role) currSym tokName amount = (mpk, Map.alter (addMaybeVal amount) (fromTokenName role, (currSym, tokName)) mrol)

addMaybeVal :: Integer -> Maybe Integer -> Maybe Integer
addMaybeVal amount oldAmount = let newAmount = maybe amount (+ amount) oldAmount in
                          if newAmount == 0 then Nothing else Just newAmount

-- Get a map between role names (token names for the given currency symbol) and public keys
mapRolesToPubkeys :: Connection -> String -> Set String -> IO (Map String PublicKey)
mapRolesToPubkeys conn currencySymbol roleSet = Map.fromList <$> mapM mapRoleToPubKey (Set.toList roleSet)
  where
  mapRoleToPubKey :: String -> IO (String, PublicKey)
  mapRoleToPubKey tokenName = do
    res <- query conn [sql| SELECT wa.pub_key
                            FROM currency_amount ca INNER JOIN wallet wa on ca.money_container_id = wa.money_container_id
                            WHERE ca.currency_symbol = ? AND ca.token_name = ? AND ca.amount > 0
                      |] (currencySymbol, tokenName) :: IO [Only String]
    case res of
      [Only pubkey] -> return (tokenName, pubkey)
      _             -> throwIO (toException $ CouldNotFindPubKeyForRole tokenName)

addRolePaymentsToPubKeyPayments :: Map String PublicKey
                                -> Map (PublicKey, (String, String)) Integer
                                -> Map (String, (String, String)) Integer
                                -> Maybe (Map (PublicKey, (String, String)) Integer)
addRolePaymentsToPubKeyPayments rolePubKeyMap pubKeyPaymentMap =
  Map.foldlWithKey' (\mAcc (role, tok) amount ->
                       (do acc <- mAcc
                           pubKey <- Map.lookup role rolePubKeyMap
                           return $ Map.alter (addMaybeVal amount) (pubKey, tok) acc))
                    (Just pubKeyPaymentMap)


balancePayments :: Map (PublicKey, (String, String)) Integer -> Map (Maybe PublicKey, (String, String)) Integer
balancePayments combinedPayments =
    Map.mapKeys (first Just) combinedPayments
      `Map.union`
        Map.mapKeys (Nothing,) (calculateCounterPayments combinedPayments)
  where
    aggregatePaymentsByToken :: Map (PublicKey, (String, String)) Integer -> Map (String, String) Integer
    aggregatePaymentsByToken = Map.mapKeysWith (+) snd

    filterZeroPayments :: Map a Integer -> Map a Integer
    filterZeroPayments = Map.filter (/= 0)

    invertPayments :: Map a Integer -> Map a Integer
    invertPayments = Map.map negate

    calculateCounterPayments :: Map (PublicKey, (String, String)) Integer -> Map (String, String) Integer
    calculateCounterPayments = invertPayments . filterZeroPayments . aggregatePaymentsByToken

-- Create transaction entry with the given parameters
createTransaction :: Connection -> Integer -> String -> TransactionInput -> State -> State -> Contract -> Contract -> Integer -> Integer -> IO Integer
createTransaction conn contractId publicKey transactionInput currentState
                  newState currentContract newContract minSlot maxSlot = do
    [Only res] <- query conn [sql| INSERT INTO transaction
                                          (contract_id, signing_wallet_id, inputs, state_before,
                                           state_after, contract_before, contract_after, min_slot, max_slot)
                                   VALUES (?, (SELECT get_or_create_money_container_id_from_pubkey(?)), ?, ?, ?, ?, ?, ?, ?)
                                   RETURNING transaction_id
                      |] (contractId, publicKey, encode transactionInput, encode currentState,
                          encode newState, encode currentContract, encode newContract, minSlot, maxSlot) :: IO [Only (Ratio Integer)]
    return $ fromRatio res

-- Create transaction line entry with the given parameters (also create wallets if needed)
addTransactionLineByPubKey :: PublicKey -> Connection -> Integer -> Integer -> Integer -> String -> String -> IO ()
addTransactionLineByPubKey thisPublicKey conn transactionId lineNum amount thisCurrSymbol thisTokenName = do
    execute conn [sql| INSERT INTO transaction_line
                                          (transaction_id, line_num, money_container_id,
                                           amount_change, currency_symbol, token_name)
                                   VALUES (?, ?, (SELECT get_or_create_money_container_id_from_pubkey(?)),
                                           ?, ?, ?)
                      |] (transactionId, lineNum, thisPublicKey, amount, thisCurrSymbol, thisTokenName)
    return ()

-- Create transaction line entry with the given parameters (also create wallets if needed)
addTransactionLineByContainerId :: Integer -> Connection -> Integer -> Integer -> Integer -> String -> String -> IO ()
addTransactionLineByContainerId containerId conn transactionId lineNum amount thisCurrSymbol thisTokenName = do
    execute conn [sql| INSERT INTO transaction_line
                                          (transaction_id, line_num, money_container_id,
                                           amount_change, currency_symbol, token_name)
                                   VALUES (?, ?, ?, ?, ?, ?)
                      |] (transactionId, lineNum, containerId, amount, thisCurrSymbol, thisTokenName)
    return ()

-- Creates a transaction that applies a TransactionInput to a contract with a given currency symbol
applyInput :: Pool Connection -> PrivateKey -> CurrencySymbol -> TransactionInput -> Handler (Either String [TransactionWarning])
applyInput conns privateKey encCurrSymb transactionInput@TransactionInput {txInterval = (Slot minSlot, Slot maxSlot)} =
  liftIO . withResource conns $ \conn -> withTransaction conn (do
      (contractId, currentState, currentContract) <- getCurrentStateAndContract conn currencySymbol
      case computeTransaction transactionInput currentState currentContract of
        TransactionOutput
          { txOutWarnings = warningList
          , txOutPayments = payments
          , txOutState    = newState
          , txOutContract = newContract } -> do
            let (pubKeySet, roleSet) = extractPubkeysAndRoles (txInputs transactionInput)
                (pubKeyPaymentMap, rolePaymentMap) = addPaymentsFromOutputs (extractPaymentsFromInputs (txInputs transactionInput)) payments
            rolePubKeyMap <- mapRolesToPubkeys conn currencySymbol (Set.union roleSet (Set.map fst $ Map.keysSet rolePaymentMap))
            case mapM (`Map.lookup` rolePubKeyMap) (Set.toList roleSet)  of
              Nothing -> return (Left "Could not resolve all roles in inputs")
              Just pubKeysForRoleSet ->
                if Set.union pubKeySet (Set.fromList pubKeysForRoleSet) `Set.isSubsetOf` Set.singleton publicKey
                then case addRolePaymentsToPubKeyPayments rolePubKeyMap pubKeyPaymentMap rolePaymentMap of
                       Nothing -> return (Left "Could not resolve all roles in input")
                       Just combinedPubKeyPaymentMap -> (do
                             let balancedPubKeyPaymentMap = balancePayments combinedPubKeyPaymentMap
                             transactionId <- createTransaction conn contractId publicKey transactionInput
                                                                currentState newState currentContract newContract
                                                                minSlot maxSlot
                             sequence_ [(case mThisPublicKey of
                                          Just thisPublicKey -> addTransactionLineByPubKey thisPublicKey
                                          Nothing            -> addTransactionLineByContainerId contractId) conn transactionId lineNum amount thisCurrSymbol thisTokenName
                                        | (lineNum, ((mThisPublicKey, (thisCurrSymbol, thisTokenName)), amount)) <- zip [1..] (Map.toList balancedPubKeyPaymentMap)]
                             return (Right warningList))
                else return (Left "The transaction hasn't been signed by all the required public keys")
        Error terror -> return (Left (show terror)))
  where
    publicKey = BSU.toString $ B16.encode $ SHA256.hash $ BSU.fromString privateKey
    currencySymbol = fromCurrencySymbol encCurrSymb

applyInputJSON :: Pool Connection -> ApplyInputRequest -> Handler (Either String [TransactionWarning])
applyInputJSON conns ApplyInputRequest { signing_priv_key         = signingPrivKey
                                       , contract_currency_symbol = currSymbol
                                       , input_to_apply           = parsedInput
                                       } = applyInput conns signingPrivKey currSymbol parsedInput

applyInputPlain :: Pool Connection -> String -> String -> String -> Handler String
applyInputPlain conn signingPrivKey currSymbol inputToApply =
  case eitherDecode (BSLU.fromString inputToApply) of
       Right parsedInput -> do
          res <- applyInput conn signingPrivKey (toCurrencySymbol currSymbol) parsedInput
          return (show res)
       Left errStr -> return errStr

fromRatio :: Ratio Integer -> Integer
fromRatio am = numerator am `div` denominator am

app :: Pool Connection -> FilePath -> Application
app conn staticPath =
  cors (const $ Just policy) $ serve (Proxy @API) (handlers conn staticPath)
  where
    policy =
      simpleCorsResourcePolicy

initializeApplication :: Pool Connection -> FilePath -> IO Application
initializeApplication conn staticPath = return $ app conn staticPath

testEndpoint :: Handler RawHtml
testEndpoint = pure $ RawHtml $ BSLU.fromString $ renderHtml $ H.docTypeHtml $ H.html $ do
  H.head $
    H.title "Test page"
  H.body $
    H.h1 "It works!"

data ContainerType = Wallet PublicKey
                   | Contract

displayContainerType :: ContainerType -> [String]
displayContainerType Contract    = ["contract", "N/A"]
displayContainerType (Wallet pk) = ["wallet", pk]

dashboard :: Pool Connection -> Handler RawHtml
dashboard conns = do
  liftIO . withResource conns $ \conn -> withTransaction conn (do
    currSlot <- getCurrentSlot conn :: IO Integer
    containerInfo <- getContainerContents conn :: IO (Map Integer (ContainerType, Map (String, String) Integer))
    transactionInfo <- getTransactionInfo conn :: IO (Map Integer (PublicKey, Maybe Integer, Maybe String))
    pure $ RawHtml $ BSLU.fromString $ renderHtml $ H.docTypeHtml $ H.html $ do
      H.head $ do
        H.meta H.! A.httpEquiv "refresh" H.! A.content "0.2"
        H.title "Fake-pab dashboard"
        H.style "table, th, td { border: 1px solid black; }"
      H.body $ do
        H.h2 (H.toHtml $ "Current slot: " ++ show currSlot)
        H.h2 "Money containers (last 15)"
        H.table $ do
          H.tr $ mapM_ H.th ["Id", "Type", "Public key", "Currency symbol", "Token name", "Amount"]
          sequence_  [ let numRows = Map.size value in
                       let spanV = spanVertically numRows idx in
                       H.tr $ sequence_
                                       (spanV [show id] ++
                                        spanV (displayContainerType containerType) ++
                                        map (H.td . H.toHtml) [ currSymb, tokenName, show amount ])
                               | (id, (containerType, value)) <- Map.toList containerInfo
                               , (idx, ((currSymb, tokenName), amount)) <- zip [1..] (Map.toList value)
                             ]
        H.h2 "Transactions (last 15)"
        H.table $ do
          H.tr $ mapM_ H.th ["Transaction Number", "Signing Public Key", "Block number", "Reason failed"]
          sequence_  [ H.tr $ mapM_ (H.td . H.toHtml) [show transactionId, signingKey, maybe "" show mBlockNumber, maybe "" id mReasonFailed]
                               | (transactionId, (signingKey, mBlockNumber, mReasonFailed)) <- Map.toList transactionInfo
                             ])
  where
    spanVertically :: Int -> Int -> [String] -> [H.Html]
    spanVertically numRows currRow v
      | currRow > 1 = []
      | otherwise = [H.td H.! A.rowspan (fromString $ show numRows) $ H.toHtml el | el <- v]

getCurrentSlot :: Connection -> IO Integer
getCurrentSlot conn = do
  [Only currSlotRatio]
      <- query_ conn [sql| SELECT MAX(slot_number)
                           FROM slot
                     |] :: IO [Only (Ratio Integer)]
  return (fromRatio currSlotRatio)

getContainerContents :: Connection -> IO (Map Integer (ContainerType, Map (String, String) Integer))
getContainerContents conn = do
  result <- query_ conn [sql| SELECT ca.money_container_id, wa.pub_key, ca.currency_symbol, ca.token_name, ca.amount
                              FROM currency_amount ca LEFT OUTER JOIN wallet wa ON ca.money_container_id = wa.money_container_id
                              ORDER BY ca.money_container_id DESC
                              LIMIT 15
                        |]
  return (Map.fromListWith (\(a1, a2) (_, b2) -> (a1, a2 `Map.union` b2))
                           [(fromRatio containerIdRatio, (maybe Contract Wallet mPublicKey, Map.singleton (currencySymbol, tokenName) (fromRatio amountRatio)))
                            | (containerIdRatio, mPublicKey, currencySymbol, tokenName, amountRatio) <- result])

getTransactionInfo :: Connection -> IO (Map Integer (PublicKey, Maybe Integer, Maybe String))
getTransactionInfo conn = do
  result <- query_ conn [sql| SELECT t.transaction_id, wa.pub_key, t.slot_number, t.reason_invalid
                              FROM transaction t INNER JOIN wallet wa ON t.signing_wallet_id = wa.money_container_id
                              ORDER BY t.transaction_id DESC
                              LIMIT 15
                        |]
  return (Map.fromList [(fromRatio transactionId, (publicKey, fmap fromRatio maybeSlot, maybeReason))
                        | (transactionId, publicKey, maybeSlot, maybeReason) <- result])


miner :: Connection -> IO ()
miner conn = do
    threadDelay 1000000
    miner_aux conn
  where
  miner_aux :: Connection -> IO ()
  miner_aux conn = do
     before <- getCurrentTime
     -- Create slot placeholder
     [Only result] <- query_ conn
                        [sql| WITH new_slot AS (INSERT INTO slot DEFAULT VALUES
                                                RETURNING slot_number)
                              SELECT slot_number FROM new_slot
                        |]
     -- Process transactions
     transactionIds <- query conn
                          [sql| WITH chosen_transactions AS (SELECT transaction_id
                                                             FROM transaction
                                                             WHERE slot_number IS NULL
                                                             ORDER BY transaction_id ASC
                                                             LIMIT 30)
                                UPDATE transaction ut
                                SET slot_number = ?
                                FROM chosen_transactions st
                                WHERE st.transaction_id = ut.transaction_id
                                RETURNING st.transaction_id; |] [fromRatio result]
     sequence_ [ void (query conn [sql| SELECT process_transaction(?); |] [fromRatio transactionId] :: (IO [Only Bool])) | Only transactionId <- transactionIds]
     -- Validate slot
     execute conn
        [sql| UPDATE slot SET is_settled = true WHERE slot_number = ? |] [fromRatio result]

     after <- getCurrentTime
     threadDelay $ max 0 (round (1000000 - nominalDiffTimeToSeconds (diffUTCTime after before) * 1000000))
     miner_aux conn

