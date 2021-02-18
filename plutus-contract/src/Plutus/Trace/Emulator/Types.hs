{-# LANGUAGE AllowAmbiguousTypes  #-}
{-# LANGUAGE ConstraintKinds      #-}
{-# LANGUAGE DataKinds            #-}
{-# LANGUAGE DeriveAnyClass       #-}
{-# LANGUAGE DeriveGeneric        #-}
{-# LANGUAGE DerivingStrategies   #-}
{-# LANGUAGE FlexibleContexts     #-}
{-# LANGUAGE GADTs                #-}
{-# LANGUAGE LambdaCase           #-}
{-# LANGUAGE NamedFieldPuns       #-}
{-# LANGUAGE OverloadedStrings    #-}
{-# LANGUAGE TemplateHaskell      #-}
{-# LANGUAGE TypeApplications     #-}
{-# LANGUAGE TypeFamilies         #-}
{-# LANGUAGE TypeOperators        #-}
{-# LANGUAGE UndecidableInstances #-}

module Plutus.Trace.Emulator.Types(
    EmulatorMessage(..)
    , EmulatorThreads(..)
    , instanceIdThreads
    , EmulatorAgentThreadEffs
    , EmulatedWalletEffects
    , EmulatedWalletEffects'
    , ContractInstanceTag(..)
    , walletInstanceTag
    , ContractHandle(..)
    , Emulator
    , ContractConstraints
    -- * Instance state
    , ContractInstanceState(..)
    , ContractInstanceStateInternal(..)
    , emptyInstanceState
    , addEventInstanceState
    , toInstanceState
    -- * Logging
    , ContractInstanceLog(..)
    , cilId
    , cilMessage
    , cilTag
    , EmulatorRuntimeError(..)
    , ContractInstanceMsg(..)
    , _Started
    , _StoppedNoError
    , _StoppedWithError
    , _ReceiveEndpointCall
    , _NoRequestsHandled
    , _HandledRequest
    , _CurrentRequests
    , _InstErr
    , _ContractLog
    , UserThreadMsg(..)
    ) where

import           Control.Lens
import           Control.Monad.Freer.Coroutine
import           Control.Monad.Freer.Error
import           Control.Monad.Freer.Log            (LogMessage, LogMsg, LogObserve)
import           Control.Monad.Freer.Reader         (Reader)
import           Data.Aeson                         (FromJSON, ToJSON)
import qualified Data.Aeson                         as JSON
import           Data.Map                           (Map)
import qualified Data.Row.Internal                  as V
import           Data.Sequence                      (Seq)
import           Data.String                        (IsString (..))
import           Data.Text                          (Text)
import qualified Data.Text                          as T
import           Data.Text.Prettyprint.Doc          (Pretty (..), braces, colon, fillSep, hang, parens, viaShow, vsep,
                                                     (<+>))
import           GHC.Generics                       (Generic)
import           Language.Plutus.Contract           (Contract (..))
import           Language.Plutus.Contract.Resumable (Request (..), Requests (..), Response (..))
import qualified Language.Plutus.Contract.Resumable as State
import           Language.Plutus.Contract.Schema    (Event, Handlers, Input, Output)
import           Language.Plutus.Contract.Types     (ResumableResult (..), SuspendedContract (..))
import qualified Language.Plutus.Contract.Types     as Contract.Types
import           Ledger.Slot                        (Slot (..))
import           Ledger.Tx                          (Tx)
import           Plutus.Trace.Scheduler             (AgentSystemCall, ThreadId)
import qualified Wallet.API                         as WAPI
import qualified Wallet.Effects                     as Wallet
import           Wallet.Emulator.LogMessages        (RequestHandlerLogMsg, TxBalanceMsg)
import           Wallet.Emulator.Wallet             (Wallet (..))
import           Wallet.Types                       (ContractInstanceId, EndpointDescription, Notification (..),
                                                     NotificationError)

type ContractConstraints s =
    ( V.Forall (Output s) V.Unconstrained1
    , V.Forall (Input s) V.Unconstrained1
    , V.AllUniqueLabels (Input s)
    , V.Forall (Input s) JSON.FromJSON
    , V.Forall (Input s) JSON.ToJSON
    , V.Forall (Output s) JSON.FromJSON
    , V.Forall (Output s) JSON.ToJSON
    )

-- | Messages sent to, and received by, threads in the emulator.
data EmulatorMessage =
    NewSlot [[Tx]] Slot -- ^ A new slot has begun and some blocks were added.
    | EndpointCall ThreadId EndpointDescription JSON.Value -- ^ Call to an endpoint
    | EndpointCallResult (Maybe NotificationError) -- ^ Response to an endpoint call
    | Freeze -- ^ Tell the contract instance to freeze itself (see note [Freeze and Thaw])
    | ContractInstanceStateRequest ThreadId -- ^ Request for the current state of a contract instance
    | ContractInstanceStateResponse JSON.Value -- ^ Response to a contract instance state request
    deriving stock (Eq, Show)

-- | A map of contract instance ID to thread ID
newtype EmulatorThreads =
    EmulatorThreads
        { _instanceIdThreads :: Map ContractInstanceId ThreadId
        } deriving newtype (Semigroup, Monoid)

makeLenses ''EmulatorThreads

-- | Effects that are used to handle requests by contract instances.
--   In the emulator these effects are handled by 'Wallet.Emulator.MultiAgent'.
--   In the PAB they are handled by the actual wallet/node/chain index,
--   mediated by the PAB runtime.
type EmulatedWalletEffects' effs =
        Wallet.WalletEffect
        ': Error WAPI.WalletAPIError
        ': Wallet.NodeClientEffect
        ': Wallet.ChainIndexEffect
        ': Wallet.SigningProcessEffect
        ': LogObserve (LogMessage T.Text)
        ': LogMsg RequestHandlerLogMsg
        ': LogMsg TxBalanceMsg
        ': LogMsg T.Text
        ': effs

type EmulatedWalletEffects = EmulatedWalletEffects' '[]

-- | Effects available to emulator agent threads. Includes emulated wallet
--   effects and effects related to threading / waiting for messages.
type EmulatorAgentThreadEffs effs =
    LogMsg ContractInstanceLog

    ': EmulatedWalletEffects' (
        Yield (AgentSystemCall EmulatorMessage) (Maybe EmulatorMessage)
        ': Reader ThreadId
        ': effs
        )

data Emulator

-- | A reference to a running contract in the emulator.
data ContractHandle s e =
    ContractHandle
        { chContract    :: Contract s e ()
        , chInstanceId  :: ContractInstanceId
        , chInstanceTag :: ContractInstanceTag
        }

data EmulatorRuntimeError =
    ThreadIdNotFound ContractInstanceId
    | InstanceIdNotFound Wallet
    | JSONDecodingError String
    deriving stock (Eq, Ord, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)

instance Pretty EmulatorRuntimeError where
    pretty = \case
        ThreadIdNotFound i   -> "Thread ID not found:" <+> pretty i
        InstanceIdNotFound w -> "Instance ID not found:" <+> pretty w
        JSONDecodingError e  -> "JSON decoding error:" <+> pretty e

-- | A user-defined tag for a contract instance. Used to find the instance's
--   log messages in the emulator log.
newtype ContractInstanceTag = ContractInstanceTag { unContractInstanceTag :: Text }
    deriving stock (Eq, Ord, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)
    deriving newtype (IsString, Pretty)

-- | The 'ContractInstanceTag' for the contract instance of a wallet. See note
--   [Wallet contract instances]
walletInstanceTag :: Wallet -> ContractInstanceTag
walletInstanceTag (Wallet i) = fromString $ "Contract instance for wallet " <> show i

-- | Log message produced by the user (main) thread
data UserThreadMsg =
    UserThreadErr EmulatorRuntimeError
    | UserLog String
    | NotificationMsg ContractInstanceMsg
    deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)

instance Pretty UserThreadMsg where
    pretty = \case
        UserLog str       -> pretty str
        UserThreadErr e   -> "Error:" <+> pretty e
        NotificationMsg m -> "Notification:" <+> pretty m

-- | Log messages produced by contract instances
data ContractInstanceMsg =
    Started
    | StoppedNoError
    | StoppedWithError String
    | ReceiveEndpointCall JSON.Value
    | ReceiveEndpointCallSuccess
    | ReceiveEndpointCallFailure NotificationError
    | NoRequestsHandled
    | HandledRequest (Response JSON.Value)
    | CurrentRequests [Request JSON.Value]
    | InstErr EmulatorRuntimeError
    | ContractLog JSON.Value
    | SendingNotification Notification
    | NotificationSuccess Notification
    | NotificationFailure NotificationError
    | SendingContractState ThreadId
    | Freezing
    deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)

instance Pretty ContractInstanceMsg where
    pretty = \case
        Started -> "Contract instance started"
        StoppedNoError -> "Contract instance stopped (no errors)"
        StoppedWithError e -> "Contract instance stopped with error:" <+> pretty e
        ReceiveEndpointCall v -> "Receive endpoint call:" <+> viaShow v
        ReceiveEndpointCallSuccess -> "Endpoint call succeeded"
        ReceiveEndpointCallFailure f -> "Endpoint call failed:" <+> pretty f
        NoRequestsHandled -> "No requests handled"
        HandledRequest rsp -> "Handled request:" <+> pretty (take 50 . show . JSON.encode <$> rsp)
        CurrentRequests lst -> "Current requests" <+> parens (pretty (length lst)) <> colon <+> fillSep (pretty . fmap (take 50 . show . JSON.encode) <$> lst)
        InstErr e -> "Error:" <+> pretty e
        ContractLog v -> "Contract log:" <+> viaShow v
        SendingNotification Notification{notificationContractID,notificationContractEndpoint} ->
            "Sending notification" <+> pretty notificationContractEndpoint <+> "to" <+> pretty notificationContractID
        NotificationSuccess Notification{notificationContractID,notificationContractEndpoint} ->
            "Notification" <+> pretty notificationContractEndpoint <+> "of" <+> pretty notificationContractID <+> "succeeded"
        NotificationFailure e ->
            "Notification failed:" <+> viaShow e
        Freezing -> "Freezing contract instance"
        SendingContractState t -> "Sending contract state to" <+> pretty t

data ContractInstanceLog =
    ContractInstanceLog
        { _cilMessage :: ContractInstanceMsg
        , _cilId      :: ContractInstanceId
        , _cilTag     :: ContractInstanceTag
        }
    deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)

instance Pretty ContractInstanceLog where
    pretty ContractInstanceLog{_cilMessage, _cilId, _cilTag} =
        hang 2 $ vsep [pretty _cilId <+> braces (pretty _cilTag) <> colon, pretty _cilMessage]

-- | State of the contract instance, internal to the contract instance thread.
--   It contains both the serialisable state of the contract instance and the
--   non-serialisable continuations in 'SuspendedContract'.
data ContractInstanceStateInternal s e a =
    ContractInstanceStateInternal
        { cisiSuspState       :: SuspendedContract e (Event s) (Handlers s) a
        , cisiEvents          :: Seq (Response (Event s))
        , cisiHandlersHistory :: Seq [State.Request (Handlers s)]
        }

-- | Extract the serialisable 'ContractInstanceState' from the
--   'ContractInstanceStateInternal'. We need to do this when
--   we want to send the instance state to another thread.
toInstanceState :: ContractInstanceStateInternal s e a -> ContractInstanceState s e a
toInstanceState ContractInstanceStateInternal{cisiSuspState=SuspendedContract{_resumableResult}, cisiEvents, cisiHandlersHistory} =
    ContractInstanceState
        { instContractState = _resumableResult
        , instEvents = cisiEvents
        , instHandlersHistory = cisiHandlersHistory
        }

-- | The state of a running contract instance with schema @s@ and error type @e@
--   Serialisable to JSON.
data ContractInstanceState s e a =
    ContractInstanceState
        { instContractState   :: ResumableResult e (Event s) (Handlers s) a
        , instEvents          :: Seq (Response (Event s))
        , instHandlersHistory :: Seq [State.Request (Handlers s)]
        }
        deriving stock Generic

deriving anyclass instance  (V.Forall (Input s) JSON.ToJSON, V.Forall (Output s) JSON.ToJSON, JSON.ToJSON e, JSON.ToJSON a) => JSON.ToJSON (ContractInstanceState s e a)
deriving anyclass instance  (V.Forall (Input s) JSON.FromJSON, V.Forall (Output s) JSON.FromJSON, JSON.FromJSON e, JSON.FromJSON a, V.AllUniqueLabels (Input s), V.AllUniqueLabels (Output s)) => JSON.FromJSON (ContractInstanceState s e a)

emptyInstanceState :: Contract s e a -> ContractInstanceStateInternal s e a
emptyInstanceState (Contract c) =
    ContractInstanceStateInternal
        { cisiSuspState = Contract.Types.suspend c
        , cisiEvents = mempty
        , cisiHandlersHistory = mempty
        }

addEventInstanceState :: forall s e a.
    Response (Event s)
    -> ContractInstanceStateInternal s e a
    -> Maybe (ContractInstanceStateInternal s e a)
addEventInstanceState event ContractInstanceStateInternal{cisiSuspState, cisiEvents, cisiHandlersHistory} =
    case Contract.Types.runStep cisiSuspState event of
        Nothing -> Nothing
        Just newState ->
            let SuspendedContract{_resumableResult=ResumableResult{_requests=Requests rq}} = cisiSuspState in
            Just ContractInstanceStateInternal
                { cisiSuspState = newState
                , cisiEvents = cisiEvents |> event
                , cisiHandlersHistory = cisiHandlersHistory |> rq
                }

makeLenses ''ContractInstanceLog
makePrisms ''ContractInstanceMsg


-- | What to do when the initial thread finishes.
data OnInitialThreadStopped =
    KeepGoing -- ^ Keep going until all threads have finished.
    | Stop -- ^ Stop right away.
    deriving stock (Eq, Ord, Show)
