{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE RankNTypes            #-}

module PlutusCore.Check.Scoping where

import           PlutusCore.Name
import           PlutusCore.Quote

import           Control.Monad.Except
import           Data.Coerce
import           Data.Map.Strict      as Map
import           Data.Maybe
import           Data.Set             as Set

-- let nonrec x_1 = x_2 in x_3

-- let nonrec @(disappears_binding x_1) x_1 = @(stays_out_of_scope x_1) x_1 -> @(stays_free x_2) x_2 in @(disappears_bound x_1) x_1 -> @(stays_free x_3) x_3

-- let nonrec @(disappears_binding x_1) x_4 = @(stays_out_of_scope x_1) x_1 -> @(stays_free x_2) x_2 in @(disappears_bound x_1) x_4 -> @(stays_free x_3) x_3

-- @(disappears_binding x_1) x_4: x_1 must not be equal to x_4, x_1 is added to out_of_scope, x_4 is added to in_scope
-- @(stays_out_of_scope x_1) x_1: x_1 must be equal to x_1, x_1 must be in out_of_scope, x_1 must not be in in_scope
-- @(stays_free x_2) x_2: x_2 must be equal to x_2, x_2 must not be in out_of_scope, x_2 must not be in in_scope
-- @(disappears_bound x_1) x_4: x_1 must not be equal to x_4, x_1 must be in out_of_scope, x_4 must be in in_scope
-- @(stays_free x_3) x_3: x_3 must be equal to x_3, x_3 must not be in out_of_scope, x_3 must not be in in_scope



-- let nonrec x_1 = x_2 in x_3
-- let nonrec x_1 = x_2 in let nonrec x_1 = x_2 in x_3  -- Duplicating a binding makes the duplicate disappear


-- \x_1 -> x_2
-- x_1 (\x_1 -> x_1 x_2)
-- @(stays_out_of_scope x_1) x_1 (\(@disappears_binding x_1) x_1 -> @(disappears_variable x_1) x_1 @(stays_free x_2) x_2)
-- @(stays_out_of_scope x_1) x_1 (\(@disappears_binding x_1) x_3 -> @(disappears_variable x_1) x_3 @(stays_free x_2) x_2)

data ScopedName
    = TypeName TyName
    | TermName Name
    deriving (Show, Eq, Ord)

isSameScope :: ScopedName -> ScopedName -> Bool
isSameScope TypeName{} TypeName{} = True
isSameScope TermName{} TermName{} = True
isSameScope TypeName{} TermName{} = False
isSameScope TermName{} TypeName{} = False

data Persists
    = StaysOutOfScopeVariable
    | StaysFreeVariable
    deriving (Show)

data Changes
    = DisappearsBinding
    | DisappearsVariable
    deriving (Show)

data NameAction
    = Persists Persists
    | Changes Changes
    deriving (Show)

data NameAnn
    = NameAction NameAction ScopedName
    | NotAName
    deriving (Show)

class ToScopedName name where
    toScopedName :: name -> ScopedName

instance ToScopedName TyName where
    toScopedName = TypeName

instance ToScopedName Name where
    toScopedName = TermName

introduceBound :: ToScopedName name => name -> NameAnn
introduceBound = NameAction (Changes DisappearsBinding) . toScopedName

registerBound :: ToScopedName name => name -> NameAnn
registerBound = NameAction (Changes DisappearsVariable) . toScopedName

registerOutOfScope :: ToScopedName name => name -> NameAnn
registerOutOfScope = NameAction (Persists StaysOutOfScopeVariable) . toScopedName

registerFree :: ToScopedName name => name -> NameAnn
registerFree = NameAction (Persists StaysFreeVariable) . toScopedName

class Reference n t where
    referenceVia
        :: (forall name. ToScopedName name => name -> NameAnn)
        -> n
        -> t NameAnn
        -> t NameAnn

referenceInScope :: Reference n t => n -> t NameAnn -> t NameAnn
referenceInScope = referenceVia registerBound

referenceOutOfScope :: Reference n t => n -> t NameAnn -> t NameAnn
referenceOutOfScope = referenceVia registerOutOfScope

-- #####################################################
-- ## Information about scopes and relevant functions ##
-- #####################################################

data ScopeEntry
    = DisappearedBindings
    | DisappearedVariables
    | AppearedBindings
    | AppearedVariables
    | StayedOutOfScopeVariables
    | StayedFreeVariables
    deriving (Show, Eq, Ord)

newtype ScopeInfo = ScopeInfo
    { unScopeInfo :: Map ScopeEntry (Set ScopedName)
    } deriving (Show)

to :: ScopeEntry -> ScopeInfo -> Set ScopedName
to entry = fromMaybe Set.empty . Map.lookup entry . unScopeInfo

emptyScopeInfo :: ScopeInfo
emptyScopeInfo = ScopeInfo Map.empty

mergeScopeInfo :: ScopeInfo -> ScopeInfo -> Either ScopeError ScopeInfo
mergeScopeInfo si1 si2
    | duplicateDisappearedBindings /= Set.empty =
        Left $ DuplicateBindersInTheInput duplicateDisappearedBindings
    | duplicateAppearedBindings /= Set.empty =
        Left $ DuplicateBindersInTheOutput duplicateAppearedBindings
    | otherwise = Right $ coerce (Map.unionWith Set.union) si1 si2
    where
        disappearedBindings1 = to DisappearedBindings si1
        disappearedBindings2 = to DisappearedBindings si2
        duplicateDisappearedBindings = disappearedBindings1 `Set.intersection` disappearedBindings2
        appearedBindings1 = to AppearedBindings si1
        appearedBindings2 = to AppearedBindings si2
        duplicateAppearedBindings = appearedBindings1 `Set.intersection` appearedBindings2

-- We might want to use @Validation@ or something instead of 'Either'.
newtype ScopeErrorOrInfo = ScopeErrorOrInfo
    { unScopeErrorOrInfo :: Either ScopeError ScopeInfo
    }

instance Semigroup ScopeErrorOrInfo where
    ScopeErrorOrInfo errOrInfo1 <> ScopeErrorOrInfo errOrInfo2 =
        ScopeErrorOrInfo . join $ mergeScopeInfo <$> errOrInfo1 <*> errOrInfo2

instance Monoid ScopeErrorOrInfo where
    mempty = ScopeErrorOrInfo $ Right emptyScopeInfo

-- ########################################################################
-- ## Main class for collecting scope information and relevant functions ##
-- ########################################################################

class Scoping t where
    establishScoping :: MonadQuote m => t ann -> m (t NameAnn)

    collectScopeInfo :: t NameAnn -> ScopeErrorOrInfo

establishScopingBinder
    :: (Reference name lower, ToScopedName name, Scoping upper, Scoping lower, MonadQuote m)
    => (NameAnn -> name -> upper NameAnn -> lower NameAnn -> lower NameAnn)
    -> name
    -> upper ann
    -> lower ann
    -> m (lower NameAnn)
establishScopingBinder binder name upper lower = do
    upperS <- establishScoping upper
    referenceOutOfScope name .
        binder (introduceBound name) name upperS .
            referenceInScope name <$>
                establishScoping lower

-- #############################################
-- ## Checking coherence of scope information ##
-- #############################################

data ScopeError
    = UnannotatedName ScopedName
    | NameChangedItsScope ScopedName ScopedName
    | NameUnexpectedlyChanged ScopedName ScopedName
    | NameUnexpectedlyStayed ScopedName
    | DuplicateBindersInTheInput (Set ScopedName)
    | DuplicateBindersInTheOutput (Set ScopedName)
    | OldBindingsDiscordWithBoundVariables (Set ScopedName)
    | OldBindingsDiscordWithOutOfScopeVariables (Set ScopedName)
    | NewBindingsDiscordWithBoundVariables (Set ScopedName)
    | OldBindingsClashWithFreeVariables (Set ScopedName)
    | OldBindingsClashWithNewBindings (Set ScopedName)
    | NewBindingsClashWithFreeVariabes (Set ScopedName)
    deriving (Show)

overrideSname :: ScopeEntry -> ScopedName -> ScopeInfo -> ScopeInfo
overrideSname key = coerce . Map.insert key . Set.singleton

applyPersists :: Persists -> ScopedName -> ScopeInfo
applyPersists persists sname = overrideSname key sname emptyScopeInfo where
    key = case persists of
        StaysOutOfScopeVariable -> StayedOutOfScopeVariables
        StaysFreeVariable       -> StayedFreeVariables

applyChanges :: Changes -> ScopedName -> ScopedName -> ScopeInfo
applyChanges changes snameOld snameNew =
    overrideSname keyNew snameNew $ overrideSname keyOld snameOld emptyScopeInfo where
        (keyOld, keyNew) = case changes of
            DisappearsBinding  -> (DisappearedBindings, AppearedBindings)
            DisappearsVariable -> (DisappearedVariables, AppearedVariables)

applyNameAction
    :: NameAction -> ScopedName -> ScopedName -> Either ScopeError ScopeInfo
applyNameAction (Persists persists) snameOld snameNew =
    if snameOld == snameNew
        then Right $ applyPersists persists snameOld
        else Left $ NameUnexpectedlyChanged snameOld snameNew
applyNameAction (Changes changes) snameOld snameNew =
    if snameOld == snameNew
        then Left $ NameUnexpectedlyStayed snameOld
        else Right $ applyChanges changes snameOld snameNew

handleSname :: ToScopedName name => NameAnn -> name -> ScopeErrorOrInfo
handleSname ann nameNew = ScopeErrorOrInfo $ do
    let snameNew = toScopedName nameNew
    case ann of
        NotAName -> Left $ UnannotatedName snameNew
        NameAction action snameOld ->
            if snameOld `isSameScope` snameNew
                then applyNameAction action snameOld snameNew
                else Left $ NameChangedItsScope snameOld snameNew

symmetricDifference :: Ord a => Set a -> Set a -> Set a
symmetricDifference s t = (s `Set.union` t) `Set.difference` (s `Set.intersection` t)

leftUnlessEmpty :: (Set ScopedName -> ScopeError) -> Set ScopedName -> Either ScopeError ()
leftUnlessEmpty err s = unless (Set.null s) . Left $ err s

checkScopeInfo :: ScopeInfo -> Either ScopeError ()
checkScopeInfo scopeInfo = do
    let disappearedBindings       = to DisappearedBindings       scopeInfo
        disappearedVariables      = to DisappearedVariables      scopeInfo
        appearedBindings          = to AppearedBindings          scopeInfo
        appearedVariables         = to AppearedVariables         scopeInfo
        stayedOutOfScopeVariables = to StayedOutOfScopeVariables scopeInfo
        stayedFreeVariables       = to StayedFreeVariables       scopeInfo
    -- The next three are based on the assumption that for each binder we add at least one
    -- out-of-scope variable and at least one in-scope one.
    leftUnlessEmpty OldBindingsDiscordWithBoundVariables $
        disappearedBindings `symmetricDifference` disappearedVariables
    leftUnlessEmpty OldBindingsDiscordWithOutOfScopeVariables $
        disappearedBindings `symmetricDifference` stayedOutOfScopeVariables
    leftUnlessEmpty NewBindingsDiscordWithBoundVariables $
        appearedBindings `symmetricDifference` appearedVariables
    leftUnlessEmpty OldBindingsClashWithFreeVariables $
        disappearedBindings `Set.intersection` stayedFreeVariables
    leftUnlessEmpty OldBindingsClashWithNewBindings $
        disappearedBindings `Set.intersection` appearedBindings
    leftUnlessEmpty NewBindingsClashWithFreeVariabes $
        appearedBindings `Set.intersection` stayedFreeVariables

checkRespectsScoping :: Scoping t => (t NameAnn -> t NameAnn) -> t ann -> Either ScopeError ()
checkRespectsScoping ren =
    checkScopeInfo <=< unScopeErrorOrInfo . collectScopeInfo . ren . runQuote . establishScoping
