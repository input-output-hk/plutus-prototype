{-# LANGUAGE FlexibleInstances        #-}
{-# LANGUAGE FunctionalDependencies   #-}
{-# LANGUAGE MultiParamTypeClasses    #-}
{-# LANGUAGE StandaloneKindSignatures #-}
{-# LANGUAGE TypeFamilies             #-}
{-# LANGUAGE UndecidableInstances     #-}

{-# OPTIONS_GHC -Wno-orphans #-}
{-# OPTIONS_GHC -fno-strictness #-}
{-# OPTIONS_GHC -fno-specialise #-}
{-# OPTIONS_GHC -fno-omit-interface-pragmas #-}

module PlutusTx.Builtins.Class where

import           Data.ByteString            (ByteString)
import           PlutusTx.Builtins.Internal

import           Data.String                (IsString (..))

import qualified GHC.Magic                  as Magic

import           Prelude                    hiding (fst, head, null, snd, tail)

{- Note [Fundeps versus type families in To/FromBuiltin]
We could use a type family here to get the builtin representation of a type. After all, it's
entirely determined by the Haskell type.

However, this is harder for the plugin to deal with. It's okay to have a type variable
for the representation type that needs to be instantiated later, but it's *not* okay to
have an irreducible type application on a type variable. So fundeps are much nicer here.
-}

{-|
A class witnessing the ability to convert from the builtin representation to the Haskell representation.
-}
class FromBuiltin arep a | arep -> a where
    fromBuiltin :: arep -> a

{-|
A class witnessing the ability to convert from the Haskell representation to the builtin representation.
-}
class ToBuiltin a arep | a -> arep where
    toBuiltin :: a -> arep

instance FromBuiltin BuiltinInteger Integer where
    {-# INLINABLE fromBuiltin #-}
    fromBuiltin = id
instance ToBuiltin Integer BuiltinInteger where
    {-# INLINABLE toBuiltin #-}
    toBuiltin = id

instance FromBuiltin BuiltinBool Bool where
    {-# INLINABLE fromBuiltin #-}
    fromBuiltin b = ifThenElse b True False
instance ToBuiltin Bool BuiltinBool where
    {-# INLINABLE toBuiltin #-}
    toBuiltin b = if b then true else false

{- Note [Strict conversions to/from unit]
Converting to/from unit *should* be straightforward: just ``const ()`.`
*But* GHC is very good at optimizing this, and we sometimes use unit
where side effects matter, e.g. as the result of `trace`. So GHC will
tend to turn `fromBuiltin (trace s)` into `()`, which is wrong.

So we want our conversions to/from unit to be strict in Haskell. This
means we need to case pointlessly on the argument, which means we need
case on unit (`chooseUnit`) as a builtin. But then it all works okay.
-}

instance FromBuiltin BuiltinUnit () where
    -- See Note [Strict conversions to/from unit]
    {-# INLINABLE fromBuiltin #-}
    fromBuiltin u = chooseUnit u ()
instance ToBuiltin () BuiltinUnit where
    -- See Note [Strict conversions to/from unit]
    {-# INLINABLE toBuiltin #-}
    toBuiltin x = case x of () -> unitval

instance FromBuiltin BuiltinByteString ByteString where
    {-# INLINABLE fromBuiltin #-}
    fromBuiltin = id
instance ToBuiltin ByteString BuiltinByteString where
    {-# INLINABLE toBuiltin #-}
    toBuiltin = id

instance FromBuiltin BuiltinChar Char where
    {-# INLINABLE fromBuiltin #-}
    fromBuiltin = id
instance ToBuiltin Char BuiltinChar where
    {-# INLINABLE toBuiltin #-}
    toBuiltin = id

{- Note [noinline hack]
For some functions we have two conflicting desires:
- We want to have the unfolding available for the plugin.
- We don't want the function to *actually* get inlined before the plugin runs, since we rely
on being able to see the original function for some reason.

'INLINABLE' achieves the first, but may cause the function to be inlined too soon.

We can solve this at specific call sites by using the 'noinline' magic function from
GHC. This stops GHC from inlining it. As a bonus, it also won't be inlined if
that function is compiled later into the body of another function.

We do therefore need to handle 'noinline' in the plugin, as it itself does not have
an unfolding.
-}

-- We can't put this in `Builtins.hs`, since that force `O0` deliberately, which prevents
-- the unfoldings from going in. So we just stick it here. Fiddly.
instance IsString BuiltinString where
    -- Try and make sure the dictionary selector goes away, it's simpler to match on
    -- the application of 'stringToBuiltinString'
    {-# INLINE fromString #-}
    -- See Note [noinline hack]
    fromString = Magic.noinline stringToBuiltinString

{-# INLINABLE stringToBuiltinString #-}
stringToBuiltinString :: String -> BuiltinString
stringToBuiltinString = go
    where
        go []     = emptyString
        go (x:xs) = charToString x `appendString` go xs

instance FromBuiltin BuiltinString BuiltinString where
    {-# INLINABLE fromBuiltin #-}
    fromBuiltin = id
instance ToBuiltin BuiltinString BuiltinString where
    {-# INLINABLE toBuiltin #-}
    toBuiltin = id

{- Note [From/ToBuiltin instances for polymorphic builtin types]
For various technical reasons
(see Note [Representable built-in functions over polymorphic built-in types])
it's not always easy to provide polymorphic constructors for builtin types, but
we can usually provide destructors.

What this means in practice is that we can write a generic FromBuiltin instance
for pairs that makes use of polymorphic fst/snd builtins, but we can't write
a polymorphic ToBuiltin instance because we'd need a polymorphic version of (,).

Instead we write monomorphic instances corresponding to monomorphic constructor
builtins that we add for specific purposes.
-}

instance (FromBuiltin arep a, FromBuiltin brep b) => FromBuiltin (BuiltinPair arep brep) (a,b) where
    {-# INLINABLE fromBuiltin #-}
    fromBuiltin p = (fromBuiltin $ fst p, fromBuiltin $ snd p)
instance ToBuiltin (BuiltinData, BuiltinData) (BuiltinPair BuiltinData BuiltinData) where
    {-# INLINABLE toBuiltin #-}
    toBuiltin (d1, d2) = mkPairData d1 d2

instance FromBuiltin arep a => FromBuiltin (BuiltinList arep) [a] where
    {-# INLINABLE fromBuiltin #-}
    fromBuiltin = go
      where
          -- The combination of both INLINABLE and a type signature seems to stop this getting lifted to the top
          -- level, which means it gets a proper unfolding, which means that specialization can work, which can
          -- actually help quite a bit here.
          {-# INLINABLE go #-}
          go :: BuiltinList arep -> [a]
          -- Note that we are using builtin ifThenElse here so this is *strict* application! So we need to do
          -- the manual laziness ourselves. We could instead convert the boolean to a Haskell boolean and use
          -- normal if, but we might as well use the builtins directly here.
          go l = ifThenElse (null l) (\_ -> []) (\_ -> fromBuiltin (head l):go (tail l)) unitval

instance ToBuiltin [BuiltinData] (BuiltinList BuiltinData) where
    {-# INLINABLE toBuiltin #-}
    toBuiltin []     = mkNilData unitval
    toBuiltin (d:ds) = mkCons d (toBuiltin ds)

instance ToBuiltin [(BuiltinData, BuiltinData)] (BuiltinList (BuiltinPair BuiltinData BuiltinData)) where
    {-# INLINABLE toBuiltin #-}
    toBuiltin []     = mkNilPairData unitval
    toBuiltin (d:ds) = mkCons (toBuiltin d) (toBuiltin ds)

instance FromBuiltin BuiltinData BuiltinData where
    {-# INLINABLE fromBuiltin #-}
    fromBuiltin = id
instance ToBuiltin BuiltinData BuiltinData where
    {-# INLINABLE toBuiltin #-}
    toBuiltin = id
