module Main (main) where

import qualified IsData.Spec as IsData
import qualified Lift.Spec   as Lift
import qualified Plugin.Spec as Plugin
import qualified StdLib.Spec as Lib
import qualified TH.Spec     as TH

import           Common

import           Test.Tasty

main :: IO ()
main = defaultMain $ runTestNestedIn ["test"] tests

tests :: TestNested
tests = testGroup "tests" <$> sequence [
    Plugin.tests
  , IsData.tests
  , Lift.tests
  , TH.tests
  , Lib.tests
  ]
