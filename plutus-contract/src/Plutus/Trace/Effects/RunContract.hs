{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE ConstraintKinds     #-}
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE DeriveAnyClass      #-}
{-# LANGUAGE DeriveGeneric       #-}
{-# LANGUAGE DerivingStrategies  #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE GADTs               #-}
{-# LANGUAGE LambdaCase          #-}
{-# LANGUAGE NamedFieldPuns      #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE TemplateHaskell     #-}
{-# LANGUAGE TypeApplications    #-}
{-# LANGUAGE TypeFamilies        #-}
{-# LANGUAGE TypeOperators       #-}
{-

An effect for starting contract instances and calling endpoints on them.

-}
module Plutus.Trace.Effects.RunContract(
    RunContract(..)
    , ContractConstraints
    , ContractInstanceTag
    , activateContract
    , activateContractWallet
    , callEndpoint
    , callEndpoint_
    , getContractState
    , activeEndpoints
    , walletInstanceTag
    , handleRunContract
    , startContractThread
    , mapYieldEm
    ) where

import           Control.Monad                                   (void)
import           Control.Monad.Freer                             (Eff, Member, interpret, send, type (~>))
import           Control.Monad.Freer.Coroutine                   (Yield (..))
import           Control.Monad.Freer.Error                       (Error, throwError)
import           Control.Monad.Freer.Log                         (LogMsg, logError, mapLog)
import           Control.Monad.Freer.Reader                      (Reader, ask)
import           Control.Monad.Freer.State                       (State)
import           Control.Monad.Freer.TH                          (makeEffect)

import qualified Data.Aeson                                      as JSON
import           Data.Foldable                                   (toList)
import           Data.Maybe                                      (fromMaybe, listToMaybe)
import           Data.Profunctor                                 (Profunctor (..))
import           Data.Proxy                                      (Proxy (..))
import qualified Data.Row.Internal                               as V
import           Data.Sequence                                   (Seq)
import qualified Data.Sequence                                   as Seq
import           Data.String                                     (IsString (..))
import qualified GHC.TypeLits
import           Language.Plutus.Contract                        (Contract, EndpointDescription (..),
                                                                  HasBlockchainActions, HasEndpoint)
import qualified Language.Plutus.Contract.Effects.ExposeEndpoint as Endpoint
import           Language.Plutus.Contract.Resumable              (Request (rqRequest))
import           Language.Plutus.Contract.Schema                 (Input, Output, handlerName)
import           Plutus.Trace.Effects.ContractInstanceId         (ContractInstanceIdEff, nextId)
import           Plutus.Trace.Emulator.ContractInstance          (contractThread, getThread)
import           Plutus.Trace.Emulator.Types                     (ContractHandle (..), ContractInstanceState (..),
                                                                  ContractInstanceTag,
                                                                  EmulatorMessage (ContractInstanceStateRequest, ContractInstanceStateResponse),
                                                                  EmulatorRuntimeError (JSONDecodingError),
                                                                  EmulatorThreads, UserThreadMsg (UserThreadErr))
import           Plutus.Trace.Scheduler                          (AgentSystemCall, EmSystemCall, MessageCall (Message),
                                                                  Priority (..), Tag, ThreadId, fork, mkSysCall, sleep)
import           Wallet.Effects                                  (ContractRuntimeEffect, sendNotification)
import           Wallet.Emulator.MultiAgent                      (EmulatorEvent' (..), MultiAgentEffect,
                                                                  handleMultiAgentEffects)
import           Wallet.Emulator.Wallet                          (Wallet (..))
import           Wallet.Types                                    (Notification (..), NotificationError)

type ContractConstraints s =
    ( V.Forall (Output s) V.Unconstrained1
    , V.Forall (Input s) V.Unconstrained1
    , V.AllUniqueLabels (Input s)
    , V.AllUniqueLabels (Output s)
    , V.Forall (Input s) JSON.FromJSON
    , V.Forall (Input s) JSON.ToJSON
    , V.Forall (Output s) JSON.FromJSON
    , V.Forall (Output s) JSON.ToJSON
    )

-- | The 'ContractInstanceTag' for the contract instance of a wallet. Useful if
--   there is only a single contract instance for this wallet.
--   See note [Wallet contract instances]
walletInstanceTag :: Wallet -> ContractInstanceTag
walletInstanceTag (Wallet i) = fromString $ "Contract instance for wallet " <> show i

-- | Run a Plutus contract (client side)
data RunContract r where
    ActivateContract :: (ContractConstraints s, HasBlockchainActions s, Show e, JSON.FromJSON e, JSON.ToJSON e) => Wallet -> Contract s e a -> ContractInstanceTag -> RunContract (ContractHandle s e)
    CallEndpointP :: forall l ep s e. (ContractConstraints s, HasEndpoint l ep s, JSON.ToJSON ep) => Proxy l -> ContractHandle s e -> ep -> RunContract (Maybe NotificationError)
    GetContractState :: forall s e. (ContractConstraints s, JSON.FromJSON e) => ContractHandle s e -> RunContract (ContractInstanceState s e ())

makeEffect ''RunContract

-- | Call an endpoint on a contract instance.
callEndpoint ::
    forall l ep s e effs.
    (ContractConstraints s, HasEndpoint l ep s, Member RunContract effs, JSON.ToJSON ep) => ContractHandle s e -> ep -> Eff effs (Maybe NotificationError)
callEndpoint hdl v = callEndpointP (Proxy @l) hdl v

-- | Call an endpoint on a contract instance, ignoring the result.
callEndpoint_ ::
    forall l ep s e effs.
    (ContractConstraints s, HasEndpoint l ep s, Member RunContract effs, JSON.ToJSON ep) => ContractHandle s e -> ep -> Eff effs ()
callEndpoint_ hdl = void . callEndpointP (Proxy @l) hdl

-- | Like 'activateContract', but using 'walletInstanceTag' for the tag.
activateContractWallet :: forall s e effs. (HasBlockchainActions s, ContractConstraints s, Show e, JSON.ToJSON e, JSON.FromJSON e, Member RunContract effs) => Wallet -> Contract s e () -> Eff effs (ContractHandle s e)
activateContractWallet w contract = activateContract w contract (walletInstanceTag w)

-- | Handle the 'RunContract' effect by running each contract instance in an
--   emulator thread.
handleRunContract :: forall effs effs2.
    ( Member (State EmulatorThreads) effs2
    , Member (Error EmulatorRuntimeError) effs2
    , Member (Error EmulatorRuntimeError) effs
    , Member MultiAgentEffect effs2
    , Member (LogMsg EmulatorEvent') effs2
    , Member (LogMsg EmulatorEvent') effs
    , Member ContractInstanceIdEff effs
    , Member (State EmulatorThreads) effs
    , Member (Reader ThreadId) effs
    , Member ContractRuntimeEffect effs
    , Member (Yield (EmSystemCall effs2 EmulatorMessage) (Maybe EmulatorMessage)) effs
    )
    => RunContract
    ~> Eff effs
handleRunContract = \case
    ActivateContract w c t -> handleActivate @_ @_ @effs @effs2 w t (void c)
    CallEndpointP p h v -> handleCallEndpoint @_ @_ @_ @_ @effs p h v
    GetContractState hdl ->
        interpret (mapLog UserThreadEvent)
            $ handleGetContractState @_ @_ @(LogMsg UserThreadMsg ': effs) @effs2 hdl

handleGetContractState ::
    forall s e effs effs2.
    ( Member (State EmulatorThreads) effs
    , Member (Yield (EmSystemCall effs2 EmulatorMessage) (Maybe EmulatorMessage)) effs
    , Member (Reader ThreadId) effs
    , Member (Error EmulatorRuntimeError) effs
    , ContractConstraints s
    , JSON.FromJSON e
    , Member (LogMsg UserThreadMsg) effs
    )
    => ContractHandle s e
    -> Eff effs (ContractInstanceState s e ())
handleGetContractState ContractHandle{chInstanceId} = do
    ownId <- ask @ThreadId
    threadId <- getThread chInstanceId
    void $ mkSysCall @effs2 @EmulatorMessage Normal (Left $ Message threadId $ ContractInstanceStateRequest ownId)

    let checkResponse = \case
            Just (ContractInstanceStateResponse r) -> do
                case JSON.fromJSON @(ContractInstanceState s e ()) r of
                    JSON.Error e' -> do
                        let msg = JSONDecodingError e'
                        logError $ UserThreadErr msg
                        throwError msg
                    JSON.Success event' -> pure event'
            _ -> sleep @effs2 Sleeping >>= checkResponse
    sleep @effs2 Normal >>= checkResponse

handleActivate :: forall s e effs effs2.
    ( ContractConstraints s
    , Member ContractInstanceIdEff effs
    , Member (State EmulatorThreads) effs2
    , Member MultiAgentEffect effs2
    , Member (Error EmulatorRuntimeError) effs2
    , Member (LogMsg EmulatorEvent') effs2
    , Member (Yield (EmSystemCall effs2 EmulatorMessage) (Maybe EmulatorMessage)) effs
    , HasBlockchainActions s
    , Show e
    , JSON.ToJSON e
    )
    => Wallet
    -> ContractInstanceTag
    -> Contract s e ()
    -> Eff effs (ContractHandle s e)
handleActivate wllt tag con = do
    i <- nextId
    let handle = ContractHandle{chContract=con, chInstanceId = i, chInstanceTag = tag}
    void $ startContractThread @s @e @effs @effs2 wllt handle
    void $ sleep @effs2 @EmulatorMessage Normal
    pure handle

runningContractInstanceTag :: Tag
runningContractInstanceTag = "contract instance"

-- | Start a new thread for a contract instance (given by the handle).
--   The thread runs in the context of the wallet.
startContractThread ::
    forall s e effs effs2.
    ( Member (Yield (EmSystemCall effs2 EmulatorMessage) (Maybe EmulatorMessage)) effs
    , Member (State EmulatorThreads) effs2
    , Member MultiAgentEffect effs2
    , Member (Error EmulatorRuntimeError) effs2
    , Member (LogMsg EmulatorEvent') effs2
    , HasBlockchainActions s
    , ContractConstraints s
    , Show e
    , JSON.ToJSON e
    )
    => Wallet
    -> ContractHandle s e
    -> Eff effs (Maybe EmulatorMessage)
startContractThread wallet handle =
    fork @effs2 @EmulatorMessage runningContractInstanceTag Normal
        (interpret (mapYieldEm @_ @effs2)
            $ handleMultiAgentEffects wallet
            $ interpret (mapLog InstanceEvent)
            $ contractThread handle)

mapYieldEm ::
    forall effs effs2 c.
    (Member (Yield (EmSystemCall effs2 EmulatorMessage) (Maybe EmulatorMessage)) effs)
    => Yield (AgentSystemCall EmulatorMessage) (Maybe EmulatorMessage) c
    -> Eff effs c
mapYieldEm = mapYield @_ @(EmSystemCall effs2 EmulatorMessage) (fmap Left) id

-- | Handle a @Yield a b@ with a @Yield a' b'@ effect.
mapYield ::
    forall a a' b b' effs c.
    (Member (Yield a' b') effs)
    => (a -> a')
    -> (b' -> b)
    -> Yield a b c
    -> Eff effs c
mapYield f g = \case
    Yield a cont -> send @(Yield a' b') $ Yield (f a) (lmap g cont)

handleCallEndpoint :: forall s l e ep effs.
    ( HasEndpoint l ep s
    , Member ContractRuntimeEffect effs
    , JSON.ToJSON ep
    )
    => Proxy l
    -> ContractHandle s e
    -> ep
    -> Eff effs (Maybe NotificationError)
handleCallEndpoint p ContractHandle{chInstanceId} ep = do
    let epJson = JSON.toJSON ep
        description = Endpoint.EndpointDescription $ GHC.TypeLits.symbolVal p
        noti = Notification
                { notificationContractID=chInstanceId
                , notificationContractEndpoint=description
                , notificationContractArg = epJson
                }
    sendNotification noti

-- | Get the active endpoints of a contract instance.
activeEndpoints :: forall s e effs.
    ( Member RunContract effs
    , ContractConstraints s
    , JSON.FromJSON e
    )
    => ContractHandle s e
    -> Eff effs [EndpointDescription]
activeEndpoints = fmap (fmap (EndpointDescription . handlerName . rqRequest) . fromMaybe [] . lastMaybe . instHandlersHistory) . getContractState

lastMaybe :: Seq a -> Maybe a
lastMaybe = listToMaybe . toList . Seq.reverse
