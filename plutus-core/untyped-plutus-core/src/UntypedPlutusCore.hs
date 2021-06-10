module UntypedPlutusCore
    ( module Export
    , applyProgram
    , parseScoped
    ) where

import           UntypedPlutusCore.Check.Uniques       as Uniques
import           UntypedPlutusCore.Parser              as Parser
import           UntypedPlutusCore.Rename              as Rename

import           PlutusCore.Name                       as Export
import           UntypedPlutusCore.Core                as Export
import           UntypedPlutusCore.Core.Instance.CBOR  as Export
import           UntypedPlutusCore.Core.Instance.Flat  as Export
import           UntypedPlutusCore.DeBruijn            as Export
import           UntypedPlutusCore.Size                as Export
import           UntypedPlutusCore.Subst               as Export
import           UntypedPlutusCore.Transform.Globalify as Export
import           UntypedPlutusCore.Transform.Simplify  as Export
-- Also has some functions


import qualified PlutusCore                            as PLC
import qualified PlutusCore.Error                      as PLC
import           PlutusPrelude                         (through)

import           Control.Monad.Except                 (MonadError, (<=<))
import qualified Data.ByteString.Lazy                 as BSL

-- | Take one PLC program and apply it to another.
applyProgram :: Program name uni fun () -> Program name uni fun () -> Program name uni fun ()
applyProgram (Program _ _ t1) (Program _ _ t2) = Program () (PLC.defaultVersion ()) (Apply () t1 t2)

-- | Parse and rewrite so that names are globally unique, not just unique within
-- their scope.
parseScoped
    :: (PLC.AsParseError e PLC.AlexPosn,
        PLC.AsUniqueError e PLC.AlexPosn,
        MonadError e m,
        PLC.MonadQuote m)
    => BSL.ByteString
    -> m (Program PLC.Name PLC.DefaultUni PLC.DefaultFun PLC.AlexPosn)
-- don't require there to be no free variables at this point, we might be parsing an open term
parseScoped = through (Uniques.checkProgram (const True)) <=< Rename.rename <=< Parser.parseProgram
