module Marlowe.Symbolic where

import Prelude

import Data.Array (filter, foldM, foldl, mapMaybe, reverse, (:))
import Data.Array as Array
import Data.BigInteger (BigInteger, fromInt)
import Data.Either (Either(..))
import Data.Enum (class BoundedEnum, class Enum, Cardinality(..))
import Data.Generic.Rep (class Generic)
import Data.Generic.Rep.Show (genericShow)
import Data.Lens (Lens', Lens, over, set, to, view, (^.))
import Data.Lens.Iso.Newtype (_Newtype)
import Data.Lens.Record (prop)
import Data.Map (Map)
import Data.Map as Map
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Newtype (class Newtype, unwrap, wrap)
import Data.Symbol (SProxy(..))
import Data.Symbolic (BooleanConstraint(..), IntConstraint(..), Sort(..), StringConstraint(..), Tree, Var(..), intVar, is, ite, smin, stringVar, (.<), (.<=), (.>), (.>=))
import Data.Tuple (Tuple(..), snd)
import Debug.Trace (trace)
import Examples.Marlowe.Contracts as ME
import Marlowe.Holes as Holes
import Marlowe.Parser as Parser
import Marlowe.Semantics (AccountId, Action(..), Bound(..), Case(..), ChoiceId, Contract(..), Observation(..), Party, Payee, Value(..), ValueId, maxDepth)
import Marlowe.Semantics as MS
import Text.Parsing.Parser (runParser)

overM :: forall m s t a b. Monad m => Lens s t a b -> (a -> m b) -> s -> m t
overM l f s = do
  let
    v = view l s
  newV <- f v
  pure $ set l newV s

class ToSymbolic a b where
  toSym :: a -> b

instance toSymbolicBoolean :: ToSymbolic Boolean BooleanConstraint where
  toSym true = True
  toSym false = Not True

instance toSymbolicString :: ToSymbolic String StringConstraint where
  toSym = StringConst

instance toSymbolicInt :: ToSymbolic BigInteger IntConstraint where
  toSym = IntConst

validInterval :: SSlotInterval -> BooleanConstraint
validInterval (SlotInterval (Slot from) (Slot to)) = from .<= to

above :: SSlot -> SSlotInterval -> BooleanConstraint
above (Slot v) (SlotInterval _ (Slot to)) = v .> to

fixInterval :: SSlotInterval -> SState -> Tree SIntervalResult
fixInterval interval@(SlotInterval from to) state =
  ite (validInterval interval)
    ( ite ((state ^. _minSlot) `above` interval)
        (pure (IntervalError $ IntervalInPastError (state ^. _minSlot) interval))
        ( let
            newLow = max to (state ^. _minSlot)

            currentInterval = SlotInterval newLow to

            env = Environment { slotInterval: currentInterval }

            newState = set _minSlot newLow state
          in
            pure (IntervalTrimmed env newState)
        )
    )
    (pure (IntervalError $ InvalidInterval interval))

inBounds :: IntConstraint -> Array Bound -> BooleanConstraint
inBounds num bounds = do
  foldl Or True $ inBound <$> bounds
  where
  inBound :: Bound -> BooleanConstraint
  inBound (Bound l u) = do
    (num .>= (toSym l)) `And` (num .<= (toSym u))

newtype SState
  = State
  { accounts :: Map SAccountId SAda
  , choices :: Map SChoiceId IntConstraint
  , boundValues :: Map ValueId IntConstraint
  , minSlot :: SSlot
  }

derive instance newtypeSState :: Newtype SState _

derive newtype instance showSState :: Show SState

_minSlot :: Lens' SState SSlot
_minSlot = _Newtype <<< prop (SProxy :: SProxy "minSlot")

_accounts :: Lens' SState (Map SAccountId SAda)
_accounts = _Newtype <<< prop (SProxy :: SProxy "accounts")

_choices :: Lens' SState (Map SChoiceId IntConstraint)
_choices = _Newtype <<< prop (SProxy :: SProxy "choices")

_boundValues :: Lens' SState (Map ValueId IntConstraint)
_boundValues = _Newtype <<< prop (SProxy :: SProxy "boundValues")

data SAccountId
  = AccountId IntConstraint StringConstraint

derive instance genericSAccountId :: Generic SAccountId _

derive instance eqSAccountId :: Eq SAccountId

derive instance ordSAccountId :: Ord SAccountId

instance showSAccountId :: Show SAccountId where
  show t = genericShow t

instance toSymbolicAccountId :: ToSymbolic AccountId SAccountId where
  toSym (MS.AccountId i s) = AccountId (toSym i) (toSym s)

data SChoiceId
  = ChoiceId StringConstraint StringConstraint

derive instance genericSChoiceId :: Generic SChoiceId _

instance showSChoiceId :: Show SChoiceId where
  show t = genericShow t

derive instance eqSChoiceId :: Eq SChoiceId

derive instance ordSChoiceId :: Ord SChoiceId

instance toSymbolicChoiceId :: ToSymbolic ChoiceId SChoiceId where
  toSym (MS.ChoiceId i s) = ChoiceId (toSym i) (toSym s)

sChoiceId :: ChoiceId -> SChoiceId
sChoiceId (MS.ChoiceId a b) = ChoiceId (StringConst a) (StringConst b)

data SPayee
  = Account SAccountId
  | Party Party

derive instance genericSPayee :: Generic SPayee _

derive instance eqSPayee :: Eq SPayee

derive instance ordSPayee :: Ord SPayee

instance showSPayee :: Show SPayee where
  show v = genericShow v

instance toSymbolicPayee :: ToSymbolic Payee SPayee where
  toSym (MS.Account s) = Account (toSym s)
  toSym (MS.Party p) = Party p

newtype SAda
  = Lovelace IntConstraint

derive instance newtypeSAda :: Newtype SAda _

derive newtype instance semiringSAda :: Semiring SAda

derive newtype instance ringSAda :: Ring SAda

derive newtype instance showSAda :: Show SAda

newtype SSlot
  = Slot IntConstraint

derive instance newtypeSSlot :: Newtype SSlot _

derive newtype instance showSSlot :: Show SSlot

derive instance eqSSlot :: Eq SSlot

derive instance ordSSlot :: Ord SSlot

data SSInput
  = SIDeposit
  | SIChoice
  | SINotify

derive instance genericSSInput :: Generic SSInput _

derive instance eqSSInput :: Eq SSInput

derive instance ordSSInput :: Ord SSInput

instance enumSSInput :: Enum SSInput where
  succ SIDeposit = Just SIChoice
  succ SIChoice = Just SINotify
  succ SINotify = Nothing
  pred SIDeposit = Nothing
  pred SIChoice = Just SIDeposit
  pred SINotify = Just SIChoice

instance boundedSSInput :: Bounded SSInput where
  top = SINotify
  bottom = SIDeposit

instance boundedEnumSSInput :: BoundedEnum SSInput where
  cardinality = Cardinality 3
  toEnum 0 = Just SIDeposit
  toEnum 1 = Just SIChoice
  toEnum 2 = Just SINotify
  toEnum _ = Nothing
  fromEnum SIDeposit = 0
  fromEnum SIChoice = 1
  fromEnum SINotify = 2

data SInput
  = IDeposit SAccountId StringConstraint SAda
  | IChoice SChoiceId IntConstraint
  | INotify

data SSlotInterval
  = SlotInterval SSlot SSlot

derive instance genericSSlotInterval :: Generic SSlotInterval _

instance showSSlotInterval :: Show SSlotInterval where
  show e = genericShow e

ivFrom :: SSlotInterval -> SSlot
ivFrom (SlotInterval from _) = from

ivTo :: SSlotInterval -> SSlot
ivTo (SlotInterval _ to) = to

newtype SEnvironment
  = Environment { slotInterval :: SSlotInterval }

derive instance newtypeSEnvironment :: Newtype SEnvironment _

_slotInterval :: Lens' SEnvironment SSlotInterval
_slotInterval = _Newtype <<< prop (SProxy :: SProxy "slotInterval")

data SIntervalError
  = InvalidInterval SSlotInterval
  | IntervalInPastError SSlot SSlotInterval

derive instance genericSIntervalError :: Generic SIntervalError _

instance showSIntervalError :: Show SIntervalError where
  show e = genericShow e

data SIntervalResult
  = IntervalTrimmed SEnvironment SState
  | IntervalError SIntervalError

newtype STransactionInput
  = TransactionInput
  { interval :: SSlotInterval
  , inputs :: (Array SInput)
  }

derive instance newtypeSTransaction :: Newtype STransactionInput _

-- EVALUATION
-- | Evaluate a @Value@ to Integer
evalValue :: SEnvironment -> SState -> Value -> Tree IntConstraint
evalValue env state value =
  let
    eval = evalValue env state
  in
    case value of
      AvailableMoney accId ->
        let
          balance = fromMaybe zero $ Map.lookup (toSym accId) (unwrap state).accounts
        in
          pure $ unwrap balance
      Constant integer -> pure $ IntConst integer
      NegValue val -> do
        v <- eval val
        pure $ negate v
      AddValue lhs rhs -> (+) <$> eval lhs <*> eval rhs
      SubValue lhs rhs -> (-) <$> eval lhs <*> eval rhs
      ChoiceValue choiceId defVal -> do
        let
          mval = Map.lookup (sChoiceId choiceId) (unwrap state).choices
        defVal' <- eval defVal
        pure $ fromMaybe defVal' mval
      SlotIntervalStart -> pure $ view (_slotInterval <<< to ivFrom <<< to unwrap) env
      SlotIntervalEnd -> pure $ view (_slotInterval <<< to ivTo <<< to unwrap) env
      UseValue valId -> pure $ fromMaybe zero $ Map.lookup valId (unwrap state).boundValues

-- | Evaluate an @Observation@ to Bool
evalObservation :: SEnvironment -> SState -> Observation -> Tree Boolean
evalObservation env state obs =
  let
    evalObs = evalObservation env state

    evalVal = evalValue env state
  in
    case obs of
      AndObs lhs rhs -> do
        a <- evalObs lhs
        b <- evalObs rhs
        pure $ a && b
      OrObs lhs rhs -> do
        a <- evalObs lhs
        b <- evalObs rhs
        pure $ a || b
      NotObs subObs -> not <$> evalObs subObs
      ChoseSomething choiceId -> pure $ (sChoiceId choiceId) `Map.member` (unwrap state).choices
      ValueGE lhs rhs -> do
        l <- evalVal lhs
        r <- evalVal rhs
        is $ l .>= r
      ValueGT lhs rhs -> do
        l <- evalVal lhs
        r <- evalVal rhs
        is $ l .> r
      ValueLT lhs rhs -> do
        l <- evalVal lhs
        r <- evalVal rhs
        is $ l .< r
      ValueLE lhs rhs -> do
        l <- evalVal lhs
        r <- evalVal rhs
        is $ l .<= r
      ValueEQ lhs rhs -> do
        l <- evalVal lhs
        r <- evalVal rhs
        is $ l `IntEQ` r
      TrueObs -> pure true
      FalseObs -> pure false

accountOwner :: SAccountId -> StringConstraint
accountOwner (AccountId _ owner) = owner

-- | Pick the first account with money in it
refundOne :: Map SAccountId SAda -> Tree (Maybe (Tuple (Tuple StringConstraint SAda) (Map SAccountId SAda)))
refundOne accounts = case Array.uncons (Map.toUnfoldable accounts) of
  Nothing -> pure Nothing
  Just { head, tail } ->
    let
      (Tuple key value) = head

      rest = Map.fromFoldable tail
    in
      ite ((unwrap value) .> zero)
        (pure (pure (Tuple (Tuple (accountOwner key) value) rest)))
        (refundOne rest)

data Payment
  = Payment StringConstraint SAda

derive instance genericPayment :: Generic Payment _

instance showPayment :: Show Payment where
  show t = genericShow t

data ReduceEffect
  = ReduceWithPayment Payment
  | ReduceNoPayment

derive instance genericReduceEffect :: Generic ReduceEffect _

instance showReduceEffect :: Show ReduceEffect where
  show t = genericShow t

-- | Obtains the amount of money available an account
moneyInAccount :: SAccountId -> Map SAccountId SAda -> SAda
moneyInAccount accId accounts = fromMaybe zero (Map.lookup accId accounts)

{-| Add the given amount of money to an account (only if it is positive).
    Return the updated Map
-}
addMoneyToAccount :: SAccountId -> SAda -> Map SAccountId SAda -> Tree (Map SAccountId SAda)
addMoneyToAccount accId money accounts =
  let
    balance = moneyInAccount accId accounts

    newBalance = balance + money
  in
    ite (unwrap money .<= zero)
      (pure accounts)
      (pure (Map.insert accId newBalance accounts))

{-| Gives the given amount of money to the given payee.
    Returns the appropriate effect and updated accounts
-}
giveMoney :: SPayee -> SAda -> Map SAccountId SAda -> Tree (Tuple ReduceEffect (Map SAccountId SAda))
giveMoney payee money accounts = case payee of
  Party party -> pure $ Tuple (ReduceWithPayment (Payment (toSym party) money)) accounts
  Account accId -> do
    newAccs <- addMoneyToAccount accId money accounts
    pure $ Tuple ReduceNoPayment newAccs

data ReduceWarning
  = ReduceNoWarning
  | ReduceNonPositivePay AccountId SPayee SAda
  | ReducePartialPay AccountId Payee SAda SAda
  | ReduceShadowing ValueId IntConstraint IntConstraint

derive instance genericReduceWarning :: Generic ReduceWarning _

instance showReduceWarning :: Show ReduceWarning where
  show t = genericShow t

data ReduceStepResult
  = Reduced ReduceWarning ReduceEffect SState Contract
  | NotReduced
  | AmbiguousSlotIntervalReductionError

derive instance genericReduceStepResult :: Generic ReduceStepResult _

instance showReduceStepResult :: Show ReduceStepResult where
  show t = genericShow t

-- | Carry a step of the contract with no inputs
reduceContractStep :: SEnvironment -> SState -> Contract -> Tree ReduceStepResult
reduceContractStep env state contract = case contract of
  -- FIXME: If Pablo can prove that all money is refunded on close then we can remove this and
  --        we can get rid of the removing function that causes forks
  Close -> do
    res <- refundOne (unwrap state).accounts
    case res of
      Just (Tuple (Tuple party money) newAccounts) ->
        let
          oldState = unwrap state

          newState = wrap (oldState { accounts = newAccounts })
        in
          pure $ Reduced ReduceNoWarning (ReduceWithPayment (Payment party money)) newState Close
      Nothing -> pure NotReduced
  Pay accId payee val nextContract -> do
    moneyToPay <- Lovelace <$> evalValue env state val
    ite (unwrap moneyToPay .<= zero)
      (pure $ Reduced (ReduceNonPositivePay accId (toSym payee) moneyToPay) ReduceNoPayment state nextContract)
      ( do
          let
            balance = moneyInAccount (toSym accId) (unwrap state).accounts -- always positive
          paidMoney <- Lovelace <$> smin (unwrap balance) (unwrap moneyToPay) -- always positive
          let
            newBalance = balance - paidMoney -- always positive

            newAccounts = Map.insert (toSym accId) newBalance (unwrap state).accounts
          warning <-
            ite ((unwrap paidMoney) .< (unwrap moneyToPay))
              (pure $ ReducePartialPay accId payee paidMoney moneyToPay)
              (pure ReduceNoWarning)
          (Tuple payment finalAccounts) <- giveMoney (toSym payee) paidMoney newAccounts
          let
            newState = set _accounts finalAccounts state
          pure $ Reduced warning payment newState nextContract
      )
  If observation contract1 contract2 -> do
    cond <- evalObservation env state observation
    let
      nextContract = if cond then contract1 else contract2
    pure $ Reduced ReduceNoWarning ReduceNoPayment state nextContract
  When _ timeout nextContract ->
    let
      startSlot = view (_slotInterval <<< to ivFrom) env

      endSlot = view (_slotInterval <<< to ivTo) env
    in
      ite (unwrap endSlot .< IntConst (unwrap timeout))
        (pure NotReduced)
        ( ite ((IntConst (unwrap timeout) .<= unwrap startSlot))
            (pure $ Reduced ReduceNoWarning ReduceNoPayment state nextContract)
            (pure AmbiguousSlotIntervalReductionError)
        )
  Let valId val nextContract -> do
    evaluatedValue <- evalValue env state val
    let
      newState = over _boundValues (Map.insert valId evaluatedValue) state

      warn = case Map.lookup valId (unwrap state).boundValues of
        Just oldVal -> ReduceShadowing valId oldVal evaluatedValue
        Nothing -> ReduceNoWarning
    pure $ Reduced warn ReduceNoPayment newState nextContract

data ReduceResult
  = ContractQuiescent (Array ReduceWarning) (Array Payment) SState Contract
  | RRAmbiguousSlotIntervalError

derive instance genericReduceResult :: Generic ReduceResult _

instance showReduceResult :: Show ReduceResult where
  show t = genericShow t

-- | Reduce a contract until it cannot be reduced more
reduceContractUntilQuiescent :: SEnvironment -> SState -> Contract -> Tree ReduceResult
reduceContractUntilQuiescent startEnv startState startContract =
  let
    reductionLoop ::
      SEnvironment -> SState -> Contract -> Array ReduceWarning -> Array Payment -> Tree ReduceResult
    reductionLoop env state contract warnings payments = do
      stepResult <- reduceContractStep env state contract
      case stepResult of
        Reduced warning effect newState nextContract -> do
          let
            newWarnings = case warning of
              ReduceNoWarning -> warnings
              _ -> warning : warnings

            newPayments = case effect of
              ReduceWithPayment payment -> payment : payments
              ReduceNoPayment -> payments
          reductionLoop env newState nextContract newWarnings newPayments
        AmbiguousSlotIntervalReductionError -> pure RRAmbiguousSlotIntervalError
        -- this is the last invocation of reductionLoop, so we can reverse lists
        NotReduced -> pure $ ContractQuiescent (reverse warnings) (reverse payments) state contract
  in
    reductionLoop startEnv startState startContract mempty mempty

data ApplyResult
  = Applied ApplyWarning SState Contract
  | ApplyNoMatchError

derive instance genericApplyResult :: Generic ApplyResult _

instance showApplyResult :: Show ApplyResult where
  show t = genericShow t

data ApplyWarning
  = ApplyNoWarning
  | ApplyNonPositiveDeposit StringConstraint SAccountId SAda

derive instance genericApplyWarning :: Generic ApplyWarning _

instance showApplyWarning :: Show ApplyWarning where
  show = genericShow

applyCases :: SEnvironment -> SState -> SInput -> Array Case -> Tree ApplyResult
applyCases env state input cases = case input of
  IDeposit accId1 party1 money -> case Array.uncons cases of
    Just { head: (Case (Deposit accId2 party2 val) cont), tail } -> do
      amount <- evalValue env state val
      warning <-
        ite (amount .> zero)
          (pure ApplyNoWarning)
          (pure (ApplyNonPositiveDeposit party1 (toSym accId2) (Lovelace amount)))
      newState <- overM _accounts (addMoneyToAccount accId1 money) state
      ite
        ( toSym (accId1 == (toSym accId2))
            `And`
              toSym (party1 == (toSym party2))
            `And`
              (unwrap money `IntEQ` amount)
        )
        (pure $ Applied warning newState cont)
        (applyCases env state input tail)
    Just { tail } -> applyCases env state input tail
    _ -> pure ApplyNoMatchError
  IChoice choId1 choice -> case Array.uncons cases of
    Just { head: (Case (Choice choId2 bounds) cont), tail } -> do
      let
        newState = over _choices (Map.insert choId1 choice) state

        isValidChoice = inBounds choice bounds

        isEqualChoice = toSym $ choId1 == toSym choId2
      ite (isEqualChoice `And` isValidChoice)
        (pure $ Applied ApplyNoWarning newState cont)
        (applyCases env state input tail)
    Just { tail } -> applyCases env state input tail
    _ -> pure ApplyNoMatchError
  INotify -> case Array.uncons cases of
    Just { head: (Case (Notify obs) cont), tail } -> do
      observationResult <- evalObservation env state obs
      if observationResult then
        pure $ Applied ApplyNoWarning state cont
      else
        applyCases env state input tail
    Just { tail } -> applyCases env state input tail
    _ -> pure ApplyNoMatchError

applyInput :: SEnvironment -> SState -> SInput -> Contract -> Tree ApplyResult
applyInput env state input (When cases _ _) = applyCases env state input cases

applyInput _ _ _ _ = pure ApplyNoMatchError

data TransactionWarning
  = TransactionNonPositiveDeposit StringConstraint SAccountId SAda
  | TransactionNonPositivePay AccountId SPayee SAda
  | TransactionPartialPay AccountId Payee SAda SAda
  -- ^ src    ^ dest ^ paid ^ expected
  | TransactionShadowing ValueId IntConstraint IntConstraint

-- oldVal ^  newVal ^
derive instance genericTransactionWarning :: Generic TransactionWarning _

instance showTransactionWarning :: Show TransactionWarning where
  show = genericShow

convertReduceWarnings :: Array ReduceWarning -> Array TransactionWarning
convertReduceWarnings =
  mapMaybe
    ( \first -> case first of
        ReduceNoWarning -> Nothing
        ReduceNonPositivePay accId payee amount -> Just (TransactionNonPositivePay accId payee amount)
        ReducePartialPay accId payee paid expected -> Just (TransactionPartialPay accId payee paid expected)
        ReduceShadowing valId oldVal newVal -> Just (TransactionShadowing valId oldVal newVal)
    )

convertApplyWarning :: ApplyWarning -> Array TransactionWarning
convertApplyWarning ApplyNoWarning = mempty

convertApplyWarning (ApplyNonPositiveDeposit party accId amount) = [ TransactionNonPositiveDeposit party accId amount ]

data ApplyAllResult
  = ApplyAllSuccess (Array TransactionWarning) (Array Payment) SState Contract
  | ApplyAllNoMatchError
  | ApplyAllAmbiguousSlotIntervalError

derive instance genericApplyAllResult :: Generic ApplyAllResult _

instance showApplyAllResult :: Show ApplyAllResult where
  show = genericShow

-- | Apply a list of Inputs to the contract
applyAllInputs :: SEnvironment -> SState -> Contract -> Array SInput -> Tree ApplyAllResult
applyAllInputs startEnv startState startContract startInputs =
  let
    applyAllLoop ::
      SEnvironment ->
      SState ->
      Contract ->
      Array SInput ->
      Array TransactionWarning ->
      Array Payment ->
      Tree ApplyAllResult
    applyAllLoop env state contract inputs warnings payments = do
      quiescent <- reduceContractUntilQuiescent env state contract
      case quiescent of
        RRAmbiguousSlotIntervalError -> pure ApplyAllAmbiguousSlotIntervalError
        ContractQuiescent reduceWarns pays curState cont -> case Array.uncons inputs of
          Nothing ->
            pure
              $ ApplyAllSuccess (warnings <> (convertReduceWarnings reduceWarns))
                  (payments <> pays)
                  curState
                  cont
          Just { head, tail } -> do
            applied <- applyInput env curState head cont
            case applied of
              Applied applyWarn newState nextContract ->
                applyAllLoop env newState nextContract tail
                  ( warnings <> (convertReduceWarnings reduceWarns)
                      <> (convertApplyWarning applyWarn)
                  )
                  (payments <> pays)
              ApplyNoMatchError -> pure ApplyAllNoMatchError
  in
    applyAllLoop startEnv startState startContract startInputs mempty mempty

-- Transactions
data TransactionError
  = TEAmbiguousSlotIntervalError
  | TEApplyNoMatchError
  | TEIntervalError SIntervalError
  | TEUselessTransaction

derive instance genericTransactionError :: Generic TransactionError _

instance showTransactionError :: Show TransactionError where
  show TEAmbiguousSlotIntervalError = "Abiguous slot interval"
  show TEApplyNoMatchError = "At least one of the inputs in the transaction is not allowed by the contract"
  show (TEIntervalError err) = show err
  show TEUselessTransaction = "Useless Transaction"

data TransactionOutput
  = TransactionOutput
    { txOutWarnings :: Array TransactionWarning
    , txOutPayments :: Array Payment
    , txOutState :: SState
    , txOutContract :: Contract
    }
  | Error TransactionError

derive instance genericTransactionOutput :: Generic TransactionOutput _

instance showTransactionOutput :: Show TransactionOutput where
  show = genericShow

-- | Try to compute outputs of a transaction give its input
computeTransaction :: STransactionInput -> SState -> Contract -> Tree TransactionOutput
computeTransaction tx state contract = do
  let
    inputs = (unwrap tx).inputs
  interval <- fixInterval (unwrap tx).interval state
  case interval of
    IntervalTrimmed env fixState -> do
      applied <- applyAllInputs env fixState contract inputs
      case applied of
        ApplyAllSuccess warnings payments newState cont ->
          if contract == cont then
            pure $ Error TEUselessTransaction
          else
            pure
              $ TransactionOutput
                  { txOutWarnings: warnings
                  , txOutPayments: payments
                  , txOutState: newState
                  , txOutContract: cont
                  }
        ApplyAllNoMatchError -> pure $ Error TEApplyNoMatchError
        ApplyAllAmbiguousSlotIntervalError -> pure $ Error TEAmbiguousSlotIntervalError
    IntervalError error -> pure $ Error (TEIntervalError error)

computeTransactions :: TransactionOutput -> Array STransactionInput -> Tree TransactionOutput
computeTransactions tout [] = pure tout

computeTransactions tout@(Error _) _ = pure tout

computeTransactions tout@(TransactionOutput { txOutWarnings, txOutPayments, txOutState, txOutContract }) inputs = do
  case Array.uncons inputs of
    Nothing -> pure tout
    Just { head, tail } -> do
      res <- computeTransaction head txOutState txOutContract
      computeTransactions res tail

mkInput :: String -> Tree SInput
mkInput suffix = do
  let
    var = Var ("input" <> suffix) IntSort

    mkEq = IntEQ (IntVar var)

    caseDeposit = IntConst (fromInt 0)

    caseChoice = IntConst (fromInt 1)
  ite (mkEq caseDeposit)
    ( pure
        $ IDeposit
            (AccountId (intVar $ "accNumber" <> suffix) (stringVar $ "accName" <> suffix))
            (stringVar $ "party" <> suffix)
            (Lovelace (intVar $ "money" <> suffix))
    )
    ( ite (mkEq caseChoice)
        ( pure
            $ IChoice (ChoiceId (stringVar $ "choiceName" <> suffix) (stringVar $ "choiceNumber" <> suffix))
                (intVar $ "choiceVal" <> suffix)
        )
        (pure INotify)
    )

-- We propose that the case of [[a, b]] is contained within the cases of [[a], [b]]
-- This is because [[a], [b]] creates a fork where the contract hits a timeout
-- This is equivalent when the slot number does not increase between [a] and [b]
data TxI
  = TxIn
  | TxE

derive instance genericTxI :: Generic TxI _

instance showTxI :: Show TxI where
  show = genericShow

mkTxs :: Int -> Tree (Array TxI)
mkTxs depth = do
  let
    mkEq i = IntEQ (IntVar (Var ("tx-input" <> show i) IntSort))

    caseInput = IntConst $ fromInt 0

    go acc inputs idx
      | idx == depth + 1 = pure acc

    go acc 0 idx = go (TxE : acc) 0 (idx + 1)

    go acc inputs idx =
      ite (mkEq idx caseInput)
        (go (TxIn : acc) (inputs - 1) (idx + 1))
        (go (TxE : acc) inputs (idx + 1))
  go [] depth 0

data TxInput
  = TxInput
  | TxEmpty
  | TxBoundary

derive instance genericTxInput :: Generic TxInput _

instance showTxInput :: Show TxInput where
  show = genericShow

getTransactionOutput :: Contract -> Tree TransactionOutput
getTransactionOutput contract = do
  let
    initialSlotInterval =
      SlotInterval
        (Slot $ (intVar "slot-start0"))
        (Slot $ (intVar "slot-end0"))

    mkSlotInterval suffix (SlotInterval (Slot a) (Slot b)) =
      SlotInterval
        (Slot $ (IntAdd a (intVar ("slot-start" <> suffix))))
        (Slot $ (IntAdd a (intVar ("slot-end" <> suffix))))

    state =
      State
        { accounts: mempty
        , choices: mempty
        , boundValues: mempty
        , minSlot: Slot $ IntVar $ Var "minSlot" IntSort
        }

    depth = maxDepth contract

    notEmpty TxE = false
    notEmpty _ = true

    mkTx :: (Tuple Int (Array STransactionInput)) -> TxI -> Tree (Tuple Int (Array STransactionInput))
    mkTx (Tuple idx acc) txi = do
      let
        slotInterval' = case Array.uncons acc of
          Nothing -> initialSlotInterval
          Just { head: (TransactionInput { interval }) } -> mkSlotInterval (show idx) interval
      inputs <- case txi of
        TxE -> pure []
        TxIn -> do
          i <- mkInput $ show idx
          pure [ i ]
      pure $ Tuple (idx + 1) $ TransactionInput { interval: slotInterval', inputs: inputs } : acc
  -- FIXME: just trying to get rid of empty txs as an experiment
  inputs <- filter notEmpty <$> mkTxs depth
  txs <- foldM mkTx (Tuple 1 []) inputs
  let
    startOutput =
      TransactionOutput
        { txOutWarnings: mempty
        , txOutPayments: mempty
        , txOutState: state
        , txOutContract: contract
        }
  computeTransactions startOutput (snd txs)

hasWarnings :: TransactionOutput -> Boolean
hasWarnings (Error _) = false
hasWarnings (TransactionOutput vs) = not $ Array.null vs.txOutWarnings