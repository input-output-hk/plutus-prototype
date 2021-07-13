{-# LANGUAGE DataKinds                  #-}
{-# LANGUAGE DeriveAnyClass             #-}
{-# LANGUAGE DeriveGeneric              #-}
{-# LANGUAGE DerivingStrategies         #-}
{-# LANGUAGE FlexibleContexts           #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE LambdaCase                 #-}
{-# LANGUAGE MultiParamTypeClasses      #-}
{-# LANGUAGE NoImplicitPrelude          #-}
{-# LANGUAGE OverloadedStrings          #-}
{-# LANGUAGE RecordWildCards            #-}
{-# LANGUAGE ScopedTypeVariables        #-}
{-# LANGUAGE TemplateHaskell            #-}
{-# LANGUAGE TypeApplications           #-}
{-# LANGUAGE TypeFamilies               #-}
{-# LANGUAGE TypeOperators              #-}
{-# options_ghc -fno-strictness         #-}
{-# options_ghc -fno-specialise         #-}

module Plutus.Contracts.Uniswap.OnChain
    ( mkUniswapValidator
    , validateLiquidityMinting
    ) where

import           Ledger
import           Ledger.Constraints.OnChain       as Constraints
import           Ledger.Constraints.TxConstraints as Constraints
import           Ledger.Value                     (AssetClass (..), symbols)
import           Plutus.Contracts.Uniswap.Pool    (calculateAdditionalLiquidity, calculateInitialLiquidity,
                                                   calculateRemoval, checkSwap, lpTicker)
import           Plutus.Contracts.Uniswap.Types
import qualified PlutusTx
import           PlutusTx.Prelude

{-# INLINABLE findOwnInput' #-}
findOwnInput' :: ScriptContext -> TxInInfo
findOwnInput' ctx = fromMaybe (error ()) (findOwnInput ctx)

{-# INLINABLE valueWithin #-}
valueWithin :: TxInInfo -> Value
valueWithin = txOutValue . txInInfoResolved

{-# INLINABLE validateSwap #-}
-- | We check the swap is valid through 'checkSwap', and otherwise just make
-- sure that the pool token is passed through.
validateSwap :: LiquidityPool -> Coin PoolState -> ScriptContext -> Bool
validateSwap LiquidityPool{..} c ctx =
    checkSwap oldA oldB newA newB                                                       &&
    traceIfFalse "expected pool state token to be present in input" (isUnity inVal c)   &&
    traceIfFalse "expected pool state token to be present in output" (isUnity outVal c) &&
    traceIfFalse "did not expect Uniswap minting" noUniswapMinting
  where
    info :: TxInfo
    info = scriptContextTxInfo ctx

    ownInput :: TxInInfo
    ownInput = findOwnInput' ctx

    ownOutput :: TxOut
    ownOutput = case [ o
                     | o <- getContinuingOutputs ctx
                     , txOutDatumHash o == Just (snd $ ownHashes ctx)
                     ] of
        [o] -> o
        _   -> traceError "expected exactly one output to the same liquidity pool"

    oldA = amountA inVal
    oldB = amountB inVal
    newA = amountA outVal
    newB = amountB outVal

    amountA v = amountOf v lpCoinA
    amountB v = amountOf v lpCoinB

    inVal, outVal :: Value
    inVal  = valueWithin ownInput
    outVal = txOutValue ownOutput

    noUniswapMinting :: Bool
    noUniswapMinting =
      let
        AssetClass (cs, _) = unCoin c
        minted             = txInfoForge info
      in
        all (/= cs) $ symbols minted

{-# INLINABLE validateCreate #-}
-- | Ths validates the creation of a liquidity pool to exchange coins. In order to be
-- valid,
--
--  1,2. We need to be dealing with the Uniswap coin,
--  3. We have to exchanging different coins,
--  4. The pool can't already exist,
--  5. The pool needs a single value as output,
--  6. The liquidity amount needs to be as-determined by 'calculateInitialLiquidity'
--      (i.e. the amount from the Uniswap V2 paper).
--  7,8. We need to be exchanging more than zero of each kind of coin.
--  9. It should output a pool with the determined properties
validateCreate :: Uniswap
               -> Coin PoolState
               -> [LiquidityPool]
               -> LiquidityPool
               -> ScriptContext
               -> Bool
validateCreate Uniswap{..} c lps lp@LiquidityPool{..} ctx =
    traceIfFalse "Uniswap coin not present" (isUnity (valueWithin $ findOwnInput' ctx) usCoin)          && -- 1.
    Constraints.checkOwnOutputConstraint ctx (OutputConstraint (Factory $ lp : lps) $ unitValue usCoin) && -- 2.
    (unCoin lpCoinA /= unCoin lpCoinB)                                                                  && -- 3.
    all (/= lp) lps                                                                                     && -- 4.
    isUnity minted c                                                                                    && -- 5.
    (amountOf minted liquidityCoin' == liquidity)                                                       && -- 6.
    (outA > 0)                                                                                          && -- 7.
    (outB > 0)                                                                                          && -- 8.
    Constraints.checkOwnOutputConstraint ctx (OutputConstraint (Pool lp liquidity) $                       -- 9.
        valueOf lpCoinA outA <> valueOf lpCoinB outB <> unitValue c)
  where
    poolOutput :: TxOut
    poolOutput = case [o | o <- getContinuingOutputs ctx, isUnity (txOutValue o) c] of
        [o] -> o
        _   -> traceError "expected exactly one pool output"

    outA      = amountOf (txOutValue poolOutput) lpCoinA
    outB      = amountOf (txOutValue poolOutput) lpCoinB
    liquidity = calculateInitialLiquidity outA outB

    minted :: Value
    minted = txInfoForge $ scriptContextTxInfo ctx

    liquidityCoin' :: Coin Liquidity
    liquidityCoin' = let AssetClass (cs,_) = unCoin c in mkCoin cs $ lpTicker lp

{-# INLINABLE validateCloseFactory #-}
-- | See 'Plutus.Contracts.Uniswap.OffChain.close'.
validateCloseFactory :: Uniswap -> Coin PoolState -> [LiquidityPool] -> ScriptContext -> Bool
validateCloseFactory Uniswap{..} c lps ctx =
    traceIfFalse "Uniswap coin not present" (isUnity (valueWithin $ findOwnInput' ctx) usCoin)                          && -- 1.
    traceIfFalse "wrong mint value"        (txInfoForge info == negate (unitValue c <>  valueOf lC (snd lpLiquidity))) && -- 2.
    traceIfFalse "factory output wrong"                                                                                    -- 3.
        (Constraints.checkOwnOutputConstraint ctx $ OutputConstraint (Factory $ filter (/= fst lpLiquidity) lps) $ unitValue usCoin)
  where
    info :: TxInfo
    info = scriptContextTxInfo ctx

    poolInput :: TxInInfo
    poolInput = case [ i
                     | i <- txInfoInputs info
                     , isUnity (valueWithin i) c
                     ] of
        [i] -> i
        _   -> traceError "expected exactly one pool input"

    lpLiquidity :: (LiquidityPool, Amount Liquidity)
    lpLiquidity = case txOutDatumHash . txInInfoResolved $ poolInput of
        Nothing -> traceError "pool input witness missing"
        Just h  -> findPoolDatum info h

    lC :: Coin Liquidity
    lC  = let AssetClass (cs, _) = unCoin c in mkCoin cs (lpTicker $ fst lpLiquidity)

{-# INLINABLE validateClosePool #-}
-- | See 'Plutus.Contracts.Uniswap.OffChain.close'.
validateClosePool :: Uniswap -> ScriptContext -> Bool
validateClosePool us ctx = hasFactoryInput
  where
    info :: TxInfo
    info = scriptContextTxInfo ctx

    hasFactoryInput :: Bool
    hasFactoryInput =
        traceIfFalse "Uniswap factory input expected" $
        isUnity (valueSpent info) (usCoin us)

{-# INLINABLE validateRemove #-}
-- | See 'Plutus.Contracts.Uniswap.OffChain.remove'.
validateRemove :: Coin PoolState -> LiquidityPool -> Amount Liquidity -> ScriptContext -> Bool
validateRemove c lp liquidity ctx =
    traceIfFalse "zero removal"                        (diff > 0)                                     &&
    traceIfFalse "removal of too much liquidity"       (diff < liquidity)                             &&
    traceIfFalse "pool state coin missing"             (isUnity inVal c)                              &&
    traceIfFalse "wrong liquidity pool output"         (fst lpLiquidity == lp)                        &&
    traceIfFalse "pool state coin missing from output" (isUnity outVal c)                             &&
    traceIfFalse "liquidity tokens not burnt"          (txInfoForge info == negate (valueOf lC diff)) &&
    traceIfFalse "non-positive liquidity"              (outA > 0 && outB > 0)
  where
    info :: TxInfo
    info = scriptContextTxInfo ctx

    ownInput :: TxInInfo
    ownInput = findOwnInput' ctx

    output :: TxOut
    output = case getContinuingOutputs ctx of
        [o] -> o
        _   -> traceError "expected exactly one Uniswap output"

    inVal, outVal :: Value
    inVal  = valueWithin ownInput
    outVal = txOutValue output

    lpLiquidity :: (LiquidityPool, Amount Liquidity)
    lpLiquidity = case txOutDatumHash output of
        Nothing -> traceError "pool output witness missing"
        Just h  -> findPoolDatum info h

    lC :: Coin Liquidity
    lC = let AssetClass (cs, _) = unCoin c in mkCoin cs (lpTicker lp)

    diff         = liquidity - snd lpLiquidity
    inA          = amountOf inVal $ lpCoinA lp
    inB          = amountOf inVal $ lpCoinB lp
    (outA, outB) = calculateRemoval inA inB liquidity diff

{-# INLINABLE validateAdd #-}
-- | See 'Plutus.Contracts.Uniswap.OffChain.add'.
validateAdd :: Coin PoolState -> LiquidityPool -> Amount Liquidity -> ScriptContext -> Bool
validateAdd c lp liquidity ctx =
    traceIfFalse "pool stake token missing from input"          (isUnity inVal c)                                                    &&
    traceIfFalse "output pool for same liquidity pair expected" (lp == fst outDatum)                                                 &&
    traceIfFalse "must not remove tokens"                       (delA >= 0 && delB >= 0)                                             &&
    traceIfFalse "insufficient liquidity"                       (delL >= 0)                                                          &&
    traceIfFalse "wrong amount of liquidity tokens"             (delL == calculateAdditionalLiquidity oldA oldB liquidity delA delB) &&
    traceIfFalse "wrong amount of liquidity tokens minted"      (txInfoForge info == valueOf lC delL)
  where
    info :: TxInfo
    info = scriptContextTxInfo ctx

    ownInput :: TxInInfo
    ownInput = findOwnInput' ctx

    ownOutput :: TxOut
    ownOutput = case [ o
                     | o <- getContinuingOutputs ctx
                     , isUnity (txOutValue o) c
                     ] of
        [o] -> o
        _   -> traceError "expected exactly on pool output"

    outDatum :: (LiquidityPool, Amount Liquidity)
    outDatum = case txOutDatum ownOutput of
        Nothing -> traceError "pool output datum hash not found"
        Just h  -> findPoolDatum info h

    inVal, outVal :: Value
    inVal  = valueWithin ownInput
    outVal = txOutValue ownOutput

    oldA = amountOf inVal aC
    oldB = amountOf inVal bC
    delA = amountOf outVal aC - oldA
    delB = amountOf outVal bC - oldB
    delL = snd outDatum - liquidity

    aC = lpCoinA lp
    bC = lpCoinB lp

    lC :: Coin Liquidity
    lC = let AssetClass (cs, _) = unCoin c in mkCoin cs $ lpTicker lp

{-# INLINABLE findPoolDatum #-}
findPoolDatum :: TxInfo -> DatumHash -> (LiquidityPool, Amount Liquidity)
findPoolDatum info h = case findDatum h info of
    Just (Datum d) -> case PlutusTx.fromBuiltinData d of
        Just (Pool lp a) -> (lp, a)
        _                -> traceError "error decoding data"
    _              -> traceError "pool input datum not found"

{-# INLINABLE mkUniswapValidator #-}
mkUniswapValidator :: Uniswap
                   -> Coin PoolState
                   -> UniswapDatum
                   -> UniswapAction
                   -> ScriptContext
                   -> Bool
mkUniswapValidator us c (Factory lps) (Create lp) ctx = validateCreate us c lps lp ctx
mkUniswapValidator _  c (Pool lp _)   Swap        ctx = validateSwap lp c ctx
mkUniswapValidator us c (Factory lps) Close       ctx = validateCloseFactory us c lps ctx
mkUniswapValidator us _ (Pool _  _)   Close       ctx = validateClosePool us ctx
mkUniswapValidator _  c (Pool lp a)   Remove      ctx = validateRemove c lp a ctx
mkUniswapValidator _  c (Pool lp a)   Add         ctx = validateAdd c lp a ctx
mkUniswapValidator _  _ _             _           _   = False

{-# INLINABLE validateLiquidityMinting #-}
validateLiquidityMinting :: Uniswap -> TokenName -> () -> ScriptContext -> Bool
validateLiquidityMinting Uniswap{..} tn _ ctx
  = case [ i
         | i <- txInfoInputs $ scriptContextTxInfo ctx
         , let v = valueWithin i
         , isUnity v usCoin || isUnity v lpC
         ] of
    [_]    -> True
    [_, _] -> True
    _      -> traceError "pool state minting without Uniswap input"
  where
    lpC :: Coin Liquidity
    lpC = mkCoin (ownCurrencySymbol ctx) tn
