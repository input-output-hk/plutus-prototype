{-# LANGUAGE CPP #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE PatternSynonyms #-}

#include "HsNet.h"

module Network.Socket.Flag where

import qualified Data.Semigroup as Sem

import Network.Socket.Imports

{-
import Network.Socket.ReadShow

import qualified Text.Read as P
-}

-- | Message flags. To combine flags, use '(<>)'.
newtype MsgFlag = MsgFlag { fromMsgFlag :: CInt }
                deriving (Show, Eq, Ord, Num, Bits)

instance Sem.Semigroup MsgFlag where
    (<>) = (.|.)

instance Monoid MsgFlag where
    mempty = MsgFlag 0
#if !(MIN_VERSION_base(4,11,0))
    mappend = (Sem.<>)
#endif

-- | Send or receive OOB(out-of-bound) data.
pattern MSG_OOB :: MsgFlag
#ifdef MSG_OOB
pattern MSG_OOB = MsgFlag (#const MSG_OOB)
#else
pattern MSG_OOB = MsgFlag 0
#endif

-- | Bypass routing table lookup.
pattern MSG_DONTROUTE :: MsgFlag
#ifdef MSG_DONTROUTE
pattern MSG_DONTROUTE = MsgFlag (#const MSG_DONTROUTE)
#else
pattern MSG_DONTROUTE = MsgFlag 0
#endif

-- | Peek at incoming message without removing it from the queue.
pattern MSG_PEEK :: MsgFlag
#ifdef MSG_PEEK
pattern MSG_PEEK = MsgFlag (#const MSG_PEEK)
#else
pattern MSG_PEEK = MsgFlag 0
#endif

-- | End of record.
pattern MSG_EOR :: MsgFlag
#ifdef MSG_EOR
pattern MSG_EOR = MsgFlag (#const MSG_EOR)
#else
pattern MSG_EOR = MsgFlag 0
#endif

-- | Received data is truncated. More data exist.
pattern MSG_TRUNC :: MsgFlag
#ifdef MSG_TRUNC
pattern MSG_TRUNC = MsgFlag (#const MSG_TRUNC)
#else
pattern MSG_TRUNC = MsgFlag 0
#endif

-- | Received control message is truncated. More control message exist.
pattern MSG_CTRUNC :: MsgFlag
#ifdef MSG_CTRUNC
pattern MSG_CTRUNC = MsgFlag (#const MSG_CTRUNC)
#else
pattern MSG_CTRUNC = MsgFlag 0
#endif

-- | Wait until the requested number of bytes have been read.
pattern MSG_WAITALL :: MsgFlag
#ifdef MSG_WAITALL
pattern MSG_WAITALL = MsgFlag (#const MSG_WAITALL)
#else
pattern MSG_WAITALL = MsgFlag 0
#endif

{-
msgFlagPairs :: [Pair MsgFlag String]
msgFlagPairs =
    [ (MSG_OOB, "MSG_OOB")
    , (MSG_DONTROUTE, "MSG_DONTROUTE")
    , (MSG_PEEK, "MSG_PEEK")
    , (MSG_EOR, "MSG_EOR")
    , (MSG_TRUNC, "MSG_TRUNC")
    , (MSG_CTRUNC, "MSG_CTRUNC")
    , (MSG_WAITALL, "MSG_WAITALL")
    ]
-}
