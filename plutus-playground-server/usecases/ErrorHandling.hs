{-# LANGUAGE DataKinds         #-}
{-# LANGUAGE FlexibleContexts  #-}
{-# LANGUAGE MonoLocalBinds    #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell   #-}
{-# LANGUAGE TypeApplications  #-}
{-# LANGUAGE TypeOperators     #-}

module ErrorHandling where

-- TRIM TO HERE
-- Demonstrates how to deal with errors in Plutus contracts. We define a custom
-- error type 'MyError' with three constructors and use
-- 'Control.Lens.makeClassyPrisms' to generate the 'AsMyError' class. We can
-- then use 'MyError' in our contracts with the combinators from
-- 'Control.Monad.Error.Lens'. The unit tests in 'Spec.ErrorHandling' show how
-- to write tests for error conditions.
import           Control.Lens             (makeClassyPrisms)
import           Control.Monad            (void)
import           Control.Monad.Error.Lens (catching, throwing, throwing_)
import           Data.Text                (Text)

import           Control.Applicative      ((<|>))
import           Language.Plutus.Contract (type (.\/), AsContractError (_ContractError), BlockchainActions, Contract,
                                           ContractError, Endpoint, HasWriteTx, endpoint, submitTx)
import           Playground.Contract
import           Prelude                  (Show, mempty, pure, ($), (>>))

type Schema =
    BlockchainActions
     .\/ Endpoint "throwError" ()
     .\/ Endpoint "catchError" ()
     .\/ Endpoint "catchContractError" ()

-- | 'MyError' has a constructor for each type of error that our contract
 --   can throw. The 'MyContractError' constructor wraps a 'ContractError'.
data MyError =
    Error1 Text
    | Error2
    | MyContractError ContractError
    deriving Show

makeClassyPrisms ''MyError

instance AsContractError MyError where
    -- 'ContractError' is another error type. It is defined in
    -- 'Language.Plutus.Contract.Request'. By making 'MyError' an
    -- instance of 'AsContractError' we can handle 'ContractError's
    -- thrown by other contracts in our code (see 'catchContractError')
    _ContractError = _MyContractError


-- | Throw an 'Error1', using 'Control.Monad.Error.Lens.throwing' and the
--   prism generated by 'makeClassyPrisms'
throw :: AsMyError e => Contract s e ()
throw = throwing _Error1 "something went wrong"

-- | Handle the error from 'throw' using 'Control.Monad.Error.Lens.catching'
throwAndCatch :: AsMyError e => Contract s e ()
throwAndCatch =
    let handleError1 :: Text -> Contract s e ()
        handleError1 _ = pure ()
     in catching _Error1 throw handleError1

-- | Handle an error from another contract (in this case, 'writeTxSucess')
catchContractError :: (AsMyError e, AsContractError e, HasWriteTx s) => Contract s e ()
catchContractError =
    catching _MyContractError
        (void $ submitTx mempty)
        (\_ -> throwing_ _Error2)

contract
    :: ( AsMyError e
       , AsContractError e
       )
    => Contract Schema e ()
contract =
    (endpoint @"throwError" >> throw)
    <|> (endpoint @"catchError" >> throwAndCatch)
    <|> (endpoint @"catchContractError" >> catchContractError)

endpoints :: (AsMyError e, AsContractError e) => Contract Schema e ()
endpoints = contract

mkSchemaDefinitions ''Schema

$(mkKnownCurrencies [])
