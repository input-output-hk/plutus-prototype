-- | Contract interface for the guessing game
module Main where

import qualified Language.Plutus.Contract.App                  as App
import           Language.PlutusTx.Coordination.Contracts.Game (game, guessTrace, lockTrace)

main :: IO ()
main = App.runWithTraces game
          [ ("lock", (App.Wallet 1, lockTrace))
          , ("guess", (App.Wallet 2, guessTrace)) ]

--curl -XPOST -d @out.json -H "Content-Type: application/json" localhost:8080/run
