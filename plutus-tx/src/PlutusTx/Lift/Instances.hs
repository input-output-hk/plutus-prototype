{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE DefaultSignatures     #-}
{-# LANGUAGE DeriveAnyClass        #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings     #-}
{-# LANGUAGE PolyKinds             #-}
{-# LANGUAGE TemplateHaskell       #-}
{-# LANGUAGE TypeApplications      #-}
{-# LANGUAGE TypeOperators         #-}
{-# LANGUAGE UndecidableInstances  #-}
{-# OPTIONS_GHC -Wno-orphans #-}
module PlutusTx.Lift.Instances () where

import qualified PlutusCore          as PLC

import           PlutusTx.Builtins   as Plutus
import           PlutusTx.Lift.Class

import           PlutusIR
import           PlutusIR.MkPir

import qualified Data.ByteString     as BS
import qualified Data.Kind           as GHC
import           Data.Proxy

import           GHC.TypeLits        (ErrorMessage (..), TypeError)

-- Derived instances

-- This instance ensures that we can apply typeable type constructors to typeable arguments and get a typeable
-- type. We need the kind variable, so that partial application of type constructors works.
instance (Typeable uni (f :: * -> k), Typeable uni (a :: *)) => Typeable uni (f a) where
    typeRep _ = TyApp () <$> typeRep (Proxy :: Proxy f) <*> typeRep (Proxy :: Proxy a)

{- Note [Typeable instances for function types]
Surely there is an obvious 'Typeable' instance for 'a -> b': we just turn it directly
into a 'TyFun'!

However, if you write this instance, you find that it overlaps with the instance for applied
type constructors. For is not '(->) a' an applied type constructor?

Vexing. However, if we run with this, we can define a 'Typeable' instance for '(->)' directly.
What is this? Well, it's something like '\a b . a -> b' as a type function. Which is a rather
silly thing to write, but it does work.
-}
-- See Note [Typeable instances for function types]
instance Typeable uni (->) where
    typeRep _ = do
        a <- PLC.liftQuote $ PLC.freshTyName "a"
        b <- PLC.liftQuote $ PLC.freshTyName "b"
        let tvda = TyVarDecl () a (Type ())
            tvdb = TyVarDecl () b (Type ())
        pure $ mkIterTyLam [tvda, tvdb] $ TyFun () (mkTyVar () tvda) (mkTyVar () tvdb)

-- Primitives

typeRepBuiltin
    :: forall (a :: GHC.Type) uni fun. uni `PLC.Includes` a
    => Proxy a -> RTCompile uni fun (Type TyName uni ())
typeRepBuiltin (_ :: Proxy a) = pure $ mkTyBuiltin @_ @a ()

liftBuiltin
    :: forall a uni fun. uni `PLC.Includes` a
    => a -> RTCompile uni fun (Term TyName Name uni fun ())
liftBuiltin = pure . mkConstant ()

instance (TypeError ('Text "Int is not supported, use Integer instead"))
    => Typeable uni Int where
    typeRep = Prelude.error "unsupported"

instance (TypeError ('Text "Int is not supported, use Integer instead"))
    => Lift uni Int where
    lift = Prelude.error "unsupported"

instance uni `PLC.Includes` Integer => Typeable uni Integer where
    typeRep = typeRepBuiltin

instance uni `PLC.Includes` Integer => Lift uni Integer where
    lift = liftBuiltin

instance uni `PLC.Includes` BS.ByteString => Typeable uni BS.ByteString where
    typeRep = typeRepBuiltin

instance uni `PLC.Includes` BS.ByteString => Lift uni BS.ByteString where
    lift = liftBuiltin

instance uni `PLC.Includes` Char => Typeable uni Char where
    typeRep = typeRepBuiltin

instance uni `PLC.Includes` Char => Lift uni Char where
    lift = liftBuiltin

instance uni `PLC.Includes` BS.ByteString => Typeable uni ByteString where
    typeRep _proxyPByteString = typeRepBuiltin (Proxy @BS.ByteString)

instance uni `PLC.Includes` BS.ByteString => Lift uni ByteString where
    lift b = liftBuiltin $ toHaskellByteString b

-- Standard types
-- These need to be in a separate file for TH staging reasons

makeLift ''Data
makeLift ''Bool
makeLift ''Maybe
makeLift ''Either
makeLift ''[]
makeLift ''()
-- include a few tuple instances for convenience
makeLift ''(,)
makeLift ''(,,)
makeLift ''(,,,)
makeLift ''(,,,,)
