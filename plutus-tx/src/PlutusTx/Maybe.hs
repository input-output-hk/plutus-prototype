{-# OPTIONS_GHC -fno-omit-interface-pragmas #-}
module PlutusTx.Maybe (Maybe(..), isJust, isNothing, maybe, fromMaybe, mapMaybe) where

import           PlutusTx.List (foldr)
import           Prelude       hiding (foldr, maybe)

{- HLINT ignore -}

{-# INLINABLE isJust #-}
-- | Check if a 'Maybe' @a@ is @Just a@
--
--   >>> isJust Nothing
--   False
--   >>> isJust (Just "plutus")
--   True
--
isJust :: Maybe a -> Bool
isJust m = case m of { Just _ -> True; _ -> False; }

{-# INLINABLE isNothing #-}
-- | Check if a 'Maybe' @a@ is @Nothing@
--
--   >>> isNothing Nothing
--   True
--   >>> isNothing (Just "plutus")
--   False
--
isNothing :: Maybe a -> Bool
isNothing m = case m of { Just _ -> False; _ -> True; }

{-# INLINABLE maybe #-}
-- | Plutus Tx version of 'Prelude.maybe'.
--
--   >>> maybe "platypus" (\s -> s) (Just "plutus")
--   "plutus"
--   >>> maybe "platypus" (\s -> s) Nothing
--   "platypus"
--
maybe :: b -> (a -> b) -> Maybe a -> b
maybe b f m = case m of
    Nothing -> b
    Just a  -> f a

{-# INLINABLE fromMaybe #-}
-- | Plutus Tx version of 'Data.Maybe.fromMaybe'
fromMaybe :: a -> Maybe a -> a
fromMaybe a = maybe a id

{-# INLINABLE mapMaybe #-}
-- | Plutus Tx version of 'Data.Maybe.mapMaybe'.
--
--   >>> mapMaybe (\i -> if i == 2 then Just '2' else Nothing) [1, 2, 3, 4]
--   "2"
--
mapMaybe :: (a -> Maybe b) -> [a] -> [b]
mapMaybe p = foldr (\e xs -> case p e of { Just e' -> e':xs; Nothing -> xs}) []
