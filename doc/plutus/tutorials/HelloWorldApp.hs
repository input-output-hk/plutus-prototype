{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE PolyKinds        #-}
{-# LANGUAGE TemplateHaskell  #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies     #-}
{-# LANGUAGE TypeOperators    #-}
module HelloWorldApp where

import qualified Data.Text           as T
import           Playground.Contract
import           Plutus.Contract
import           PlutusTx.Prelude    hiding (String)


-- BLOCK1

-- | A 'Contract' that logs a message.
hello :: Contract () EmptySchema T.Text ()
hello = logInfo @String "Hello, world"

-- BLOCK2

endpoints :: Contract () EmptySchema T.Text ()
endpoints = hello

type DummySchema = Endpoint "dummy" ()

mkSchemaDefinitions ''DummySchema

$(mkKnownCurrencies [])
