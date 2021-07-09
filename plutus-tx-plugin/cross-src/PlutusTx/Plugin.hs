module PlutusTx.Plugin (plugin) where

import qualified GhcPlugins                    as GHC

plugin :: GHC.Plugin
plugin = GHC.defaultPlugin