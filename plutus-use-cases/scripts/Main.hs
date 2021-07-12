{-# LANGUAGE NamedFieldPuns #-}
module Main(main) where

import qualified Control.Foldl                  as L
import           Control.Monad.Freer            (run)
import qualified Data.ByteString.Lazy           as BSL
import           Data.Default                   (Default (..))
import           Data.Foldable                  (traverse_)
import           Flat                           (flat)
import           Ledger.Index                   (ScriptValidationEvent (..))
import           Plutus.Trace.Emulator          (EmulatorConfig, EmulatorTrace)
import qualified Plutus.Trace.Emulator          as Trace
import           Plutus.V1.Ledger.Api           (ExBudget (..))
import           Plutus.V1.Ledger.Scripts       (Script (..))
import qualified Streaming.Prelude              as S
import           System.Directory               (createDirectoryIfMissing)
import           System.Environment             (getArgs)
import           System.FilePath                ((</>))
import qualified Wallet.Emulator.Folds          as Folds
import           Wallet.Emulator.Stream         (foldEmulatorStreamM)

import qualified Plutus.Contracts.Crowdfunding  as Crowdfunding
import qualified Plutus.Contracts.Uniswap.Trace as Uniswap
import qualified Spec.Auction                   as Auction
import qualified Spec.Currency                  as Currency
import qualified Spec.Escrow                    as Escrow
import qualified Spec.Future                    as Future
import qualified Spec.GameStateMachine          as GameStateMachine
import qualified Spec.MultiSig                  as MultiSig
import qualified Spec.MultiSigStateMachine      as MultiSigStateMachine
import qualified Spec.PingPong                  as PingPong
import qualified Spec.Prism                     as Prism
import qualified Spec.PubKey                    as PubKey
import qualified Spec.Stablecoin                as Stablecoin
import qualified Spec.TokenAccount              as TokenAccount
import qualified Spec.Vesting                   as Vesting

main :: IO ()
main = do
    args <- getArgs
    case args of
        [script_path] -> writeScripts script_path
        _             -> traverse_ putStrLn [
            "usage: plutus-use-cases-scripts SCRIPT_PATH",
            "Run a number of emulator traces and write all fully applied validator scripts to SCRIPT_PATH"
            ]

writeScripts :: FilePath -> IO ()
writeScripts fp = do
    putStrLn $ "Writing scripts to: " <> fp
    traverse_ (writeScriptsTo fp)
        [ ("auction_1", Auction.auctionTrace1, Auction.auctionEmulatorCfg)
        , ("auction_2", Auction.auctionTrace2, Auction.auctionEmulatorCfg)
        , ("crowdfunding-success", Crowdfunding.successfulCampaign, def)
        , ("currency", Currency.currencyTrace, def)
        , ("escrow-redeem_1", Escrow.redeemTrace, def)
        , ("escrow-redeem_2", Escrow.redeem2Trace, def)
        , ("escrow-refund", Escrow.refundTrace, def)
        , ("future-increase-margin", Future.increaseMarginTrace, def)
        , ("future-settle-early", Future.settleEarlyTrace, def)
        , ("future-pay-out", Future.payOutTrace, def)
        , ("game-sm-success", GameStateMachine.successTrace, def)
        , ("game-sm-success_2", GameStateMachine.successTrace2, def)
        , ("multisig-success", MultiSig.succeedingTrace, def)
        , ("multisig-failure", MultiSig.failingTrace, def)
        , ("multisig-sm", MultiSigStateMachine.lockProposeSignPay 3 2, def)
        , ("ping-pong", PingPong.pingPongTrace, def)
        , ("ping-pong_2", PingPong.twoPartiesTrace, def)
        , ("prism", Prism.prismTrace, def)
        , ("pubkey", PubKey.pubKeyTrace, def)
        , ("stablecoin_1", Stablecoin.stablecoinTrace, def)
        , ("stablecoin_2", Stablecoin.maxReservesExceededTrace, def)
        , ("token-account", TokenAccount.tokenAccountTrace, def)
        , ("vesting", Vesting.retrieveFundsTrace, def)
        , ("uniswap", Uniswap.uniswapTrace, def)
        ]

{-| Run an emulator trace and write the applied scripts to a file in Flat format
    using the name as a prefix.  There's an instance of Codec.Serialise for
    Script in Scripts.hs (see Note [Using Flat inside CBOR instance of Script]),
    which wraps Flat-encoded bytestings in CBOR, but that's not used here: we
    just use unwrapped Flat because that's more convenient for use with the
    `plc` command, for example.
-}
writeScriptsTo
    :: FilePath
    -> (String, EmulatorTrace a, EmulatorConfig)
    -> IO ()
writeScriptsTo fp (prefix, trace, emulatorCfg) = do
    let events =
            S.fst'
            $ run
            $ foldEmulatorStreamM (L.generalize Folds.scriptEvents)
            $ Trace.runEmulatorStream emulatorCfg trace
        showBudget (ExBudget exCPU exMemory) = show exCPU <> ", " <> show exMemory
        writeScript (idx, ScriptValidationEvent{sveScript, sveResult}) = do
            let filename = fp </> prefix <> "-" <> show idx <> ".flat"
            putStrLn $ "Writing script: " <> filename <> " (Cost: " <> either show (showBudget . fst) sveResult <> ")"
            BSL.writeFile filename (BSL.fromStrict . flat . unScript $ sveScript)
    createDirectoryIfMissing True fp
    traverse_ writeScript (zip [1::Int ..] events)
