{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}
{-# LANGUAGE TypeOperators       #-}

module Webserver where

import           Data.Proxy               (Proxy (Proxy))
import           Data.Time.Units          (Second)
import           Network.Wai.Handler.Warp as Warp
import           Playground.Server        (initializeServerContext)
import qualified Playground.Server        as Server
import           Servant                  (serve, (:<|>) ((:<|>)))
import qualified Webghc.Server            as Webghc

type API = Server.Web :<|> Webghc.API

run :: Int -> Second -> Maybe FilePath -> IO ()
run port maxInterpretationTime secrets = do
  appConfig <- initializeServerContext maxInterpretationTime secrets
  handlers <- Server.mkHandlers appConfig
  let server = handlers :<|> Webghc.server 80
  Warp.run port (serve (Proxy @API) server)
