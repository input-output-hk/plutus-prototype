{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DataKinds           #-}
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

An emulator trace is a contract trace that can be run in the Plutus emulator.

-}
module Plutus.Trace.Emulator(
    Emulator
    , EmulatorTrace
    , EmulatorErr(..)
    , ContractHandle(..)
    , ContractInstanceTag
    , ContractConstraints
    -- * Constructing Traces
    , RunContract.activateContract
    , RunContract.activateContractWallet
    , RunContract.walletInstanceTag
    , RunContract.callEndpoint
    , RunContract.callEndpoint_
    , RunContract.getContractState
    , RunContract.activeEndpoints
    , EmulatedWalletAPI.liftWallet
    , EmulatedWalletAPI.payToWallet
    , Waiting.nextSlot
    , Waiting.waitUntilSlot
    , Waiting.waitNSlots
    , EmulatorControl.freezeContractInstance
    , EmulatorControl.thawContractInstance
    -- ** Inspecting the chain state
    , EmulatorControl.setSigningProcess
    , EmulatorControl.chainState
    , ChainState.chainNewestFirst
    , ChainState.txPool
    , ChainState.index
    , ChainState.currentSlot
    -- ** Inspecting the agent states
    , EmulatorControl.agentState
    , Wallet.ownPrivateKey
    , Wallet.nodeClient
    , Wallet.chainIndex
    , Wallet.signingProcess
    -- * Running traces
    , EmulatorConfig(..)
    , initialChainState
    , defaultEmulatorConfig
    , runEmulatorStream
    -- * Interpreter
    , interpretEmulatorTrace
    ) where

import           Control.Lens
import           Control.Monad                           (void)
import           Control.Monad.Freer
import           Control.Monad.Freer.Coroutine           (Yield)
import           Control.Monad.Freer.Error               (Error)
import           Control.Monad.Freer.Extras              (raiseEnd6)
import           Control.Monad.Freer.Log                 (LogMessage (..), LogMsg (..), mapLog)
import           Control.Monad.Freer.Reader              (Reader)
import           Control.Monad.Freer.State               (State, evalState)
import qualified Data.Map                                as Map
import           Data.Maybe                              (fromMaybe)
import           Plutus.Trace.Scheduler                  (EmSystemCall, ThreadId, exit, runThreads)
import           Wallet.Effects                          (ContractRuntimeEffect)
import           Wallet.Emulator.Chain                   (ChainControlEffect, ChainEffect)
import qualified Wallet.Emulator.Chain                   as ChainState
import           Wallet.Emulator.MultiAgent              (EmulatorEvent, EmulatorEvent' (..), EmulatorState,
                                                          MultiAgentControlEffect, MultiAgentEffect, schedulerEvent)
import           Wallet.Emulator.Stream                  (EmulatorConfig (..), EmulatorErr (..), defaultEmulatorConfig,
                                                          initialChainState, runTraceStream)
import qualified Wallet.Emulator.Wallet                  as Wallet

import           Plutus.Trace.Effects.ContractInstanceId (ContractInstanceIdEff, handleDeterministicIds)
import           Plutus.Trace.Effects.EmulatedWalletAPI  (EmulatedWalletAPI, handleEmulatedWalletAPI)
import qualified Plutus.Trace.Effects.EmulatedWalletAPI  as EmulatedWalletAPI
import           Plutus.Trace.Effects.EmulatorControl    (EmulatorControl, handleEmulatorControl)
import qualified Plutus.Trace.Effects.EmulatorControl    as EmulatorControl
import           Plutus.Trace.Effects.RunContract        (RunContract, handleRunContract, mapYieldEm)
import qualified Plutus.Trace.Effects.RunContract        as RunContract
import           Plutus.Trace.Effects.Waiting            (Waiting, handleWaiting)
import qualified Plutus.Trace.Effects.Waiting            as Waiting
import           Plutus.Trace.Emulator.ContractInstance  (EmulatorRuntimeError, handleContractRuntime)
import           Plutus.Trace.Emulator.System            (launchSystemThreads)
import           Plutus.Trace.Emulator.Types             (ContractConstraints, ContractHandle (..), ContractInstanceTag,
                                                          Emulator, EmulatorMessage (..), EmulatorThreads,
                                                          UserThreadMsg (..))
import           Streaming                               (Stream)
import           Streaming.Prelude                       (Of)

-- | Effects that make up an emulator trace:
--   Running contracts, waiting for blockchain events,
--   changing emulator internal state, and logging.
type EmulatorTraceEffs effs =
            RunContract
            ': Waiting
            ': ContractRuntimeEffect
            ': EmulatorControl
            ': EmulatedWalletAPI
            ': LogMsg String
            ': effs

type EmulatorTrace a = Eff (EmulatorTraceEffs '[]) a

handleEmulatorTrace ::
    forall effs a.
    ( Member MultiAgentEffect effs
    , Member MultiAgentControlEffect effs
    , Member (State EmulatorThreads) effs
    , Member (State EmulatorState) effs
    , Member (Error EmulatorRuntimeError) effs
    , Member (LogMsg EmulatorEvent') effs
    , Member ContractInstanceIdEff effs
    )
    => EmulatorTrace a
    -> Eff (Reader ThreadId ': Yield (EmSystemCall effs EmulatorMessage) (Maybe EmulatorMessage) ': effs) ()
handleEmulatorTrace action = do
    _ <- interpret (mapLog (UserThreadEvent . UserLog))
            . interpret handleEmulatedWalletAPI
            . interpret (handleEmulatorControl @_ @effs)
            . interpret (mapLog (UserThreadEvent . NotificationMsg))
            . interpret (mapYieldEm @_ @effs)
            . reinterpret2 @_ @_ (handleContractRuntime @_)
            . interpret (handleWaiting @_ @effs)
            . interpret (handleRunContract @_ @effs)
            $ raiseEnd6 action
    void $ exit @effs @EmulatorMessage

-- | Run a 'Trace Emulator', streaming the log messages as they arrive
runEmulatorStream :: forall effs a.
    EmulatorConfig
    -> EmulatorTrace a
    -> Stream (Of (LogMessage EmulatorEvent)) (Eff effs) (Maybe EmulatorErr, EmulatorState)
runEmulatorStream conf = runTraceStream conf . interpretEmulatorTrace conf

-- | Interpret a 'Trace Emulator' action in the multi agent and emulated
--   blockchain effects.
interpretEmulatorTrace :: forall effs a.
    ( Member MultiAgentEffect effs
    , Member MultiAgentControlEffect effs
    , Member (Error EmulatorRuntimeError) effs
    , Member ChainEffect effs
    , Member ChainControlEffect effs
    , Member (LogMsg EmulatorEvent') effs
    , Member (State EmulatorState) effs
    )
    => EmulatorConfig
    -> EmulatorTrace a
    -> Eff effs ()
interpretEmulatorTrace conf action =
    -- add a wait action to the beginning to ensure that the
    -- initial transaction gets validated before the wallets
    -- try to spend their funds
    let action' = Waiting.nextSlot >> action >> Waiting.nextSlot
        defaultWallets = Wallet.Wallet <$> [1..10]
        wallets = fromMaybe defaultWallets (preview (initialChainState . _Left . to Map.keys) conf)
    in
    evalState @EmulatorThreads mempty
        $ handleDeterministicIds
        $ interpret (mapLog (review schedulerEvent))
        $ runThreads
        $ do
            raise $ launchSystemThreads wallets
            handleEmulatorTrace action'
