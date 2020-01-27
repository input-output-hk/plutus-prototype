{-# LANGUAGE DeriveAnyClass     #-}
{-# LANGUAGE DeriveGeneric      #-}
{-# LANGUAGE DerivingStrategies #-}

module Plutus.SCB.Events
    ( module Events.Contract
    , module Events.Mock
    , module Events.User
    , ChainEvent(..)
    ) where

import           Data.Aeson                 (FromJSON, ToJSON)
import           Data.Text                  (Text)
import           GHC.Generics               (Generic)
import           Plutus.SCB.Events.Contract as Events.Contract
import           Plutus.SCB.Events.Mock     as Events.Mock
import           Plutus.SCB.Events.User     as Events.User

-- | A structure which ties together all possible event types into one parent.
data ChainEvent
    = RecordEntry !Events.Mock.Entry
    | RecordRequest
          !(Events.Contract.RequestEvent Events.Contract.ContractRequest)
    | RecordResponse
          !(Events.Contract.ResponseEvent Events.Contract.ContractResponse)
    | UserEvent Events.User.UserEvent
    | NodeEvent Text
    deriving (Show, Eq, Generic)
    deriving anyclass (FromJSON, ToJSON)
