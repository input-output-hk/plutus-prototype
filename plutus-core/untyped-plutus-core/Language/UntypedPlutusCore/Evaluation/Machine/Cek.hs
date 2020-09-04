-- | The CEK machine.
-- The CEK machine relies on variables having non-equal 'Unique's whenever they have non-equal
-- string names. I.e. 'Unique's are used instead of string names. This is for efficiency reasons.
-- The CEK machines handles name capture by design.
-- The type checker pass is a prerequisite.
-- Dynamic extensions to the set of built-ins are allowed.
-- In case an unknown dynamic built-in is encountered, an 'UnknownDynamicBuiltinNameError' is returned
-- (wrapped in 'OtherMachineError').

{-# LANGUAGE ConstraintKinds       #-}
{-# LANGUAGE DeriveAnyClass        #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE LambdaCase            #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE NPlusKPatterns        #-}
{-# LANGUAGE OverloadedStrings     #-}
{-# LANGUAGE RankNTypes            #-}
{-# LANGUAGE TemplateHaskell       #-}
{-# LANGUAGE TypeApplications      #-}
{-# LANGUAGE TypeFamilies          #-}
{-# LANGUAGE TypeOperators         #-}
{-# LANGUAGE UndecidableInstances  #-}

module Language.UntypedPlutusCore.Evaluation.Machine.Cek
    ( CekValue(..)
    , CekEvaluationException
    , EvaluationResult(..)
    , ErrorWithCause(..)
    , EvaluationError(..)
    , ExBudget(..)
    , ExBudgetCategory(..)
    , ExBudgetMode(..)
    , ExRestrictingBudget(..)
    , ExTally(..)
    , CekExBudgetState
    , CekExTally
    , exBudgetStateTally
    , extractEvaluationResult
    , runCek
    , runCekCounting
    , evaluateCek
    , unsafeEvaluateCek
    , readKnownCek
    )
where

import           PlutusPrelude

import           Language.UntypedPlutusCore.Core
import           Language.UntypedPlutusCore.Subst

import           Language.PlutusCore.Constant
import           Language.PlutusCore.Error
import           Language.PlutusCore.Evaluation.Machine.ExBudgeting
import           Language.PlutusCore.Evaluation.Machine.Exception
import           Language.PlutusCore.Evaluation.Machine.ExMemory
import           Language.PlutusCore.Evaluation.Result
import           Language.PlutusCore.Name
import           Language.PlutusCore.Pretty
import           Language.PlutusCore.Universe

import           Control.Lens                                       (AReview)
import           Control.Lens.Operators
import           Control.Lens.Setter
import           Control.Monad.Except
import           Control.Monad.Morph
import           Control.Monad.Reader
import           Control.Monad.State.Strict
import           Data.Array
import           Data.Hashable
import           Data.HashMap.Monoidal
import qualified Data.Map                                           as Map
import           Data.Text.Prettyprint.Doc

{- Note [Scoping]
   The CEK machine does not rely on the global uniqueness condition, so the renamer pass is not a
   prerequisite. The CEK machine correctly handles name shadowing.
-}

type TermWithMem uni = Term Name uni ExMemory

{- Note [Arities in VBuiltin]
The VBuiltin value below contains two copies of the arity (list of
TypeArg/TermArg pairs) for the relevant builtin.  The second of these
is consumed as the builtin is instantiated and applied to arguments,
to check that type and term arguments are interleaved correctly.  The
first copy of the arity is left unaltered and only used by
dischargeCekValue if we have to convert the frame back into a term
(see mkBuiltinApplication).  An alternative would be to look up the
full arity in mkBuiltinApplication, but that would require a lot of
things to be monadic (including the PrettyBy instance for CekValue,
which is a problem.)
-}

-- 'Values' for the modified CEK machine.
data CekValue uni =
    VCon ExMemory (Some (ValueOf uni))
  | VDelay ExMemory (TermWithMem uni) (CekValEnv uni)
  | VLamAbs ExMemory Name (TermWithMem uni) (CekValEnv uni)
  | VBuiltin            -- A partial builtin application, accumulating arguments for eventual full application.
      ExMemory
      BuiltinName
      Arity             -- Sorts of arguments to be provided (both types and terms): *don't change this*.
      Arity             -- A copy of the arity used for checking applications/instantiatons: see Note [Arities in VBuiltin]
      Int               -- The number of @force@s to apply to the builtin.
                        -- We need these to construct a term if the machine is returning a stuck partial application.
      [CekValue uni]    -- Arguments we've computed so far.
      (CekValEnv uni)   -- Initial environment, used for evaluating every argument
    deriving (Show, Eq) -- Eq is just for tests.

type CekValEnv uni = UniqueMap TermUnique (CekValue uni)

-- | The environment the CEK machine runs in.
data CekEnv uni = CekEnv
    { cekEnvMeans             :: DynamicBuiltinNameMeanings (CekValue uni)
    , cekEnvBudgetMode        :: ExBudgetMode
    , cekEnvBuiltinCostParams :: CostModel
    }

data CekUserError
    = CekOutOfExError ExRestrictingBudget ExBudget
    | CekEvaluationFailure -- ^ Error has been called or a builtin application has failed
    deriving (Show, Eq)

{- Note [Being generic over @term@ in 'CekM']
We have a @term@-generic version of 'CekM' called 'CekCarryingM', which itself requires a
@term@-generic version of 'CekEvaluationException' called 'CekEvaluationExceptionCarrying'.
The point is that in many different cases we can annotate an evaluation failure with a 'Term' that
caused it. Originally we were using 'CekValue' instead of 'Term', however that meant that we had to
ignore some important cases where we just can't produce a 'CekValue', for example if we encounter
a free variable, we can't turn it into a 'CekValue' and report the result as the cause of the
failure, which is bad. 'Term' is strictly more general than 'CekValue' and so we can always
1. report things like free variables
2. report a 'CekValue' turned into a 'Term' via 'dischargeCekValue'
We need the latter, because the constant application machinery, in the context of the CEK machine,
expects a list of 'CekValue's and so in the event of failure it has to report one of those
arguments, so we have no option but to call the constant application machinery with 'CekValue'
being the cause of a potential failure. But as mentioned, turning a 'CekValue' into a 'Term' is
no problem and we need that elsewhere anyway, so we don't need any extra machinery for calling the
constant application machinery over a list of 'CekValue's and turning the cause of a possible
failure into a 'Term', apart from the straightforward generalization of 'CekM'.
-}

-- | The CEK machine-specific 'EvaluationException', parameterized over @term@.
type CekEvaluationExceptionCarrying term =
    EvaluationException UnknownDynamicBuiltinNameError CekUserError term

-- See Note [Being generic over @term@ in 'CekM'].
-- | A generalized version of 'CekM' carrying a @term@.
-- 'State' is inside the 'ExceptT', so we can get it back in case of error.
type CekCarryingM term uni =
    ReaderT (CekEnv uni) (ExceptT (CekEvaluationExceptionCarrying term) (State CekExBudgetState))

-- | The CEK machine-specific 'EvaluationException'.
type CekEvaluationException uni = CekEvaluationExceptionCarrying (Term Name uni ())

-- | The monad the CEK machine runs in.
type CekM uni = CekCarryingM (Term Name uni ()) uni

data ExBudgetCategory
    = BForce
    | BApply
    | BVar
    | BBuiltin BuiltinName
    | BAST
    deriving stock (Show, Eq, Generic)
    deriving anyclass NFData
instance Hashable ExBudgetCategory
instance PrettyBy config ExBudgetCategory where
    prettyBy _ = viaShow

type CekExBudgetState = ExBudgetState ExBudgetCategory
type CekExTally       = ExTally       ExBudgetCategory

instance Pretty CekUserError where
    pretty (CekOutOfExError (ExRestrictingBudget res) b) =
        group $ "The limit" <+> prettyClassicDef res <+> "was reached by the execution environment. Final state:" <+> prettyClassicDef b
    pretty CekEvaluationFailure = "The provided Plutus code called 'error'."

arityOf :: BuiltinName -> CekM uni Arity
arityOf (StaticBuiltinName name) =
    pure $ builtinNameArities ! name
arityOf (DynBuiltinName name) = do
    DynamicBuiltinNameMeaning sch _ _ <- lookupDynamicBuiltinName name
    pure $ getArity sch
-- TODO: have a table of dynamic arities so that we don't have to do this computation every time.

{- | Given a possibly partially applied/instantiated builtin, reconstruct the
   original application from the type and term arguments we've got so far, using
   the supplied arity.  This also attempts to handle the case of bad
   interleavings for use in error messages.  The caller has to add the extra
   type or term argument that caused the error, then mkBuiltinApp works its way
   along the arity reconstructing the term.  When it can't find an argument of
   the appropriate kind it looks for one of the other kind (which should be the
   one supplied by the user): if it finds one it adds an extra application or
   instantiation as appropriate to what it's constructed so far and returns the
   result.  If there are no arguments of either kind left it just returns what
   it has at that point.  The only circumstances where this is currently called
   is if (a) the machine is returning a partially applied builtin, or (b) a
   wrongly interleaved builtin application is being reported in an error.  Note
   that we don't call this function if a builtin fails for some reason like
   division by zero; the term is discarded in that case anyway (see
   Note [Ignoring context in UserEvaluationError] in Exception.hs)
-}
mkBuiltinApplication :: ExMemory -> BuiltinName -> Arity -> Int -> [TermWithMem uni] -> TermWithMem uni
mkBuiltinApplication ex bn arity0 forces0 args0 =
  go arity0 forces0 args0 (Builtin ex bn)
    where go arity forces args term =
              case (arity, args, forces) of
                -- We've got to the end and successfully constructed the entire application
                ([], [], 0)                    -> term
                -- got an expected term argument
                (TermArg:arity', arg:args', _) -> go arity' forces args' (Apply ex term arg)
                -- term expected, type found
                (TermArg:_, [], _forces'+1)    -> Force ex term
                -- got an expected type argument
                (TypeArg:arity', _, forces'+1) -> go arity' forces' args (Force ex term)
                -- type expected, term found
                (TypeArg:_, arg:_, 0)          -> Apply ex term arg
                -- something else, including partial application
                _                              -> term

-- see Note [Scoping].
-- | Instantiate all the free variables of a term by looking them up in an environment.
-- Mutually recursive with dischargeCekVal.
dischargeCekValEnv
    :: (Closed uni, uni `Everywhere` ExMemoryUsage)
    => CekValEnv uni -> TermWithMem uni -> TermWithMem uni
dischargeCekValEnv valEnv =
    -- We recursively discharge the environments of Cek values, but we will gradually end up doing
    -- this to terms which have no free variables remaining, at which point we won't call this
    -- substitution function any more and so we will terminate.
    termSubstFreeNames $ \name -> do
        val <- lookupName name valEnv
        Just $ dischargeCekValue val

-- Convert a CekValue into a term by replacing all bound variables with the terms
-- they're bound to (which themselves have to be obtain by recursively discharging values).
dischargeCekValue
    :: (Closed uni, uni `Everywhere` ExMemoryUsage)
    => CekValue uni -> TermWithMem uni
dischargeCekValue = \case
    VCon     ex val                        -> Constant ex val
    VDelay   ex body env                   -> Delay ex (dischargeCekValEnv env body)
    VLamAbs  ex name body env              -> LamAbs ex name (dischargeCekValEnv env body)
    VBuiltin ex bn arity0 _ forces args  _ -> mkBuiltinApplication ex bn arity0 forces (fmap dischargeCekValue args)
    {- We only discharge a value when (a) it's being returned by the machine,
       or (b) it's needed for an error message.  When we're discharging VBuiltin
       we use arity0 to get the type and term arguments into the right sequence. -}

instance (Closed uni, GShow uni, uni `Everywhere` PrettyConst, uni `Everywhere` ExMemoryUsage) =>
            PrettyBy PrettyConfigPlc (CekValue uni) where
    prettyBy cfg = prettyBy cfg . dischargeCekValue

type instance UniOf (CekValue uni) = uni

instance (Closed uni, uni `Everywhere` ExMemoryUsage) => FromConstant (CekValue uni) where
    fromConstant val = VCon (memoryUsage val) val

instance AsConstant (CekValue uni) where
    asConstant (VCon _ val) = Just val
    asConstant _            = Nothing

instance ToExMemory (CekValue uni) where
    toExMemory = \case
        VCon     ex _           -> ex
        VDelay   ex _ _         -> ex
        VLamAbs  ex _ _ _       -> ex
        VBuiltin ex _ _ _ _ _ _ -> ex

instance ExBudgetBuiltin ExBudgetCategory where
    exBudgetBuiltin = BBuiltin

instance ToExMemory term => SpendBudget (CekCarryingM term uni) ExBudgetCategory term where
    builtinCostParams = asks cekEnvBuiltinCostParams
    spendBudget key budget = do
        modifying exBudgetStateTally
                (<> (ExTally (singleton key budget)))
        newBudget <- exBudgetStateBudget <%= (<> budget)
        mode <- asks cekEnvBudgetMode
        case mode of
            Counting -> pure ()
            Restricting resb ->
                when (exceedsBudget resb newBudget) $
                    throwingWithCause _EvaluationError
                        (UserEvaluationError $ CekOutOfExError resb newBudget)
                        Nothing  -- No value available for error

data Frame uni
    = FrameApplyFun (CekValue uni)                     -- ^ @[V _]@
    | FrameApplyArg (CekValEnv uni) (TermWithMem uni)  -- ^ @[_ N]@
    | FrameForce                                       -- ^ @(force _)@
    deriving (Show)

type Context uni = [Frame uni]

runCekM
    :: forall a uni
     . CekEnv uni
    -> CekExBudgetState
    -> CekM uni a
    -> (Either (CekEvaluationException uni) a, CekExBudgetState)
runCekM env s a = runState (runExceptT $ runReaderT a env) s

-- | Extend an environment with a variable name, the value the variable stands for
-- and the environment the value is defined in.
extendEnv :: Name -> CekValue uni -> CekValEnv uni -> CekValEnv uni
extendEnv = insertByName

-- | Look up a variable name in the environment.
lookupVarName :: Name -> CekValEnv uni -> CekM uni (CekValue uni)
lookupVarName varName varEnv = do
    case lookupName varName varEnv of
        Nothing  -> throwingWithCause _MachineError OpenTermEvaluatedMachineError $ Just var where
            var = Var () varName
        Just val -> pure val

-- | Look up a 'DynamicBuiltinName' in the environment.
lookupDynamicBuiltinName
    :: DynamicBuiltinName -> CekM uni (DynamicBuiltinNameMeaning (CekValue uni))
lookupDynamicBuiltinName dynName = do
    DynamicBuiltinNameMeanings means <- asks cekEnvMeans
    case Map.lookup dynName means of
        Nothing   -> throwingWithCause _MachineError err $ Just cause where
            err = OtherMachineError $ UnknownDynamicBuiltinNameErrorE dynName
            cause = Builtin () $ DynBuiltinName dynName
        Just mean -> pure mean

-- | The computing part of the CEK machine.
-- Either
-- 1. adds a frame to the context and calls 'computeCek' ('Force', 'Apply')
-- 2. calls 'returnCek' on values ('Delay', 'LamAbs', 'Constant', 'Builtin')
-- 3. returns 'EvaluationFailure' ('Error')
-- 4. looks up a variable in the environment and calls 'returnCek' ('Var')

computeCek
    :: (GShow uni, GEq uni, DefaultUni <: uni, Closed uni, uni `Everywhere` ExMemoryUsage)
    => Context uni -> CekValEnv uni -> TermWithMem uni -> CekM uni (Term Name uni ())
-- s ; ρ ▻ {L A}  ↦ s , {_ A} ; ρ ▻ L
computeCek ctx env (Force _ body) = do
    spendBudget BForce (ExBudget 1 1) -- TODO
    computeCek (FrameForce : ctx) env body
-- s ; ρ ▻ [L M]  ↦  s , [_ (M,ρ)]  ; ρ ▻ L
computeCek ctx env (Apply _ fun arg) = do
    spendBudget BApply (ExBudget 1 1) -- TODO
    computeCek (FrameApplyArg env arg : ctx) env fun
-- s ; ρ ▻ abs α L  ↦  s ◅ abs α (L , ρ)
computeCek ctx env (Delay ex body) =
    -- TODO: budget?
    returnCek ctx (VDelay ex body env)
-- s ; ρ ▻ lam x L  ↦  s ◅ lam x (L , ρ)
computeCek ctx env (LamAbs ex name body) =
    -- TODO: budget?
    returnCek ctx (VLamAbs ex name body env)
-- s ; ρ ▻ con c  ↦  s ◅ con c
computeCek ctx _ (Constant ex val) =
    returnCek ctx (VCon ex val)
-- s ; ρ ▻ builtin bn  ↦  s ◅ builtin bn arity arity [] [] ρ
computeCek ctx env (Builtin ex bn) = do
    -- TODO: budget?
  arity <- arityOf bn
  returnCek ctx (VBuiltin ex bn arity arity 0 [] env)
-- s ; ρ ▻ error A  ↦  <> A
computeCek _ _ (Error _) =
    throwingWithCause _EvaluationError (UserEvaluationError CekEvaluationFailure) . Just $ Error ()
-- s ; ρ ▻ x  ↦  s ◅ ρ[ x ]
computeCek ctx env (Var _ varName) = do
    spendBudget BVar (ExBudget 1 1) -- TODO
    val <- lookupVarName varName env
    returnCek ctx val

-- | Call 'dischargeCekValue' over the received 'CekVal' and feed the resulting 'Term' to
-- 'throwingWithCause' as the cause of the failure.
throwingDischarged
    :: ( MonadError (ErrorWithCause e (Term Name uni ())) m
       , Closed uni, uni `Everywhere` ExMemoryUsage
       )
    => AReview e t -> t -> CekValue uni -> m x
throwingDischarged l t = throwingWithCause l t . Just . void . dischargeCekValue

-- | The returning phase of the CEK machine.
-- Returns 'EvaluationSuccess' in case the context is empty, otherwise pops up one frame
-- from the context and uses it to decide how to proceed with the current value v.
--  'FrameForce': call instantiateEvaluate.  If v is a lambda then discard the type
--     and compute the body of v; if v is a builtin application then check that
--     it's expecting a type argument, either apply the builtin to its arguments or
--     and return the result, or extend the value with the type and call returnCek;
--     if v is anything else, fail.
--  'FrameApplyArg': call applyEvaluate. If v is a lambda then discard the type
--     and compute the body of v; if v is a builtin application then check that
--     it's expecting a type argument, either apply the builtin to its arguments
--     and return the result, or extend the value with the type and call returnCek;
--     if v is anything else, fail.
--  'FrameApplyFun': call applyEvaluate to attempt to apply the function
--     stored in the frame to an argument.  If the function is a lambda 'lam x ty body'
--     then extend the environment with a binding of v to x and call computeCek on the body.
--     If the is a builtin application then check that it's expecting a term argument,
--     and if it's the final argument then apply the builtin to its arguments
--     return the result, or extend the value with the new argument and call
--     returnCek.  If v is anything else, fail.
returnCek
    :: (GShow uni, GEq uni, DefaultUni <: uni, Closed uni, uni `Everywhere` ExMemoryUsage)
    => Context uni -> CekValue uni -> CekM uni (Term Name uni ())
--- Instantiate all the free variable of the resulting term in case there are any.
-- . ◅ V           ↦  [] V
returnCek [] val = pure $ void $ dischargeCekValue val
-- s , {_ A} ◅ abs α M  ↦  s ; ρ ▻ M [ α / A ]*
returnCek (FrameForce : ctx) fun = instantiateEvaluate ctx fun
-- s , [_ (M,ρ)] ◅ V  ↦  s , [V _] ; ρ ▻ M
returnCek (FrameApplyArg argVarEnv arg : ctx) fun = do
    computeCek (FrameApplyFun fun : ctx) argVarEnv arg
-- s , [(lam x (M,ρ)) _] ◅ V  ↦  s ; ρ [ x  ↦  V ] ▻ M
-- FIXME: add rule for VBuiltin once it's in the specification.
returnCek (FrameApplyFun fun : ctx) arg = do
    applyEvaluate ctx fun arg

{- Note [Accumulating arguments].  The VBuiltin value contains lists of type and
term arguments which grow as new arguments are encountered.  In the code below
We just add new entries by appending to the end of the list: l -> l++[x].  This
doesn't look terrbily good, but we don't expect the lists to ever contain more
than three or four elements, so the cost is unlikely to be high.  We could
accumulate lists in the normal way and reverse them when required, but this is
error-prone and reversal adds an extra cost anyway.  We could also use something
like Data.Sequence, but again we incur an extra cost because we have to convert
to a normal list when passing the arguments to the constant application
machinery.  If we really care we might want to convert the CAM to use sequences
instead of lists.
-}

-- | Instantiate a term with a type and proceed.
-- In case of 'VDelay' just ignore the type; for 'VBuiltin', extend
-- the type arguments with the type, decrement the argument count,
-- and proceed; otherwise, it's an error.
instantiateEvaluate
    :: (GShow uni, GEq uni, DefaultUni <: uni, Closed uni, uni `Everywhere` ExMemoryUsage)
    => Context uni -> CekValue uni -> CekM uni (Term Name uni ())
instantiateEvaluate ctx (VDelay _ body env) = computeCek ctx env body
instantiateEvaluate ctx val@(VBuiltin ex bn arity0 arity forces args argEnv) =
    case arity of
      []             ->
          throwingDischarged _MachineError EmptyBuiltinArityMachineError val
      TermArg:_      ->
      {- This should be impossible if we don't have zero-arity builtins:
         we will have found this case in an earlier call to instantiateEvaluate
         or applyEvaluate and called applyBuiltinName. -}
          throwingDischarged _MachineError UnexpectedBuiltinInstantiationMachineError val'
                        where val' = VBuiltin ex bn arity0 arity (forces + 1) args argEnv -- reconstruct the bad application
      TypeArg:arity' ->
          case arity' of
            [] -> applyBuiltinName ctx bn args  -- Final argument is a type argument
            _  -> returnCek ctx $ VBuiltin ex bn arity0 arity' (forces + 1) args argEnv -- More arguments expected
instantiateEvaluate _ val =
        throwingDischarged _MachineError NonPolymorphicInstantiationMachineError val


-- | Apply a function to an argument and proceed.
-- If the function is a 'LamAbs', then extend the current environment with a new variable and proceed.
-- If the function is a 'Builtin', then check whether we've got the right number of arguments.
-- If we do, then ask the constant application machinery to apply it, and proceed with
-- the result (or throw an error if something goes wrong); if we don't, then add the new
-- argument to the VBuiltin and call returnCek to look for more arguments.
applyEvaluate
    :: (GShow uni, GEq uni, DefaultUni <: uni, Closed uni, uni `Everywhere` ExMemoryUsage)
    => Context uni
    -> CekValue uni   -- lhs of application
    -> CekValue uni   -- rhs of application
    -> CekM uni (Term Name uni ())
applyEvaluate ctx (VLamAbs _ name body env) arg =
    computeCek ctx (extendEnv name arg env) body
applyEvaluate ctx val@(VBuiltin ex bn arity0 arity tyargs args argEnv) arg = do
    case arity of
      []        -> throwingDischarged _MachineError EmptyBuiltinArityMachineError val
                -- Should be impossible: see instantiateEvaluate.
      TypeArg:_ -> throwingDischarged _MachineError UnexpectedBuiltinTermArgumentMachineError val'
                   where val' = VBuiltin ex bn arity0 arity tyargs (args++[arg]) argEnv -- reconstruct the bad application
      TermArg:arity' -> do
          let args' = args ++ [arg]
          case arity' of
            [] -> applyBuiltinName ctx bn args' -- 'arg' was the final argument
            _  -> returnCek ctx $ VBuiltin ex bn arity0 arity' tyargs args' argEnv  -- More arguments expected
applyEvaluate _ val _ = throwingDischarged _MachineError NonFunctionalApplicationMachineError val

-- | Apply a builtin to a list of CekValue arguments
applyBuiltinName
    :: (GShow uni, GEq uni, DefaultUni <: uni, Closed uni, uni `Everywhere` ExMemoryUsage)
    => Context uni
    -> BuiltinName
    -> [CekValue uni]
    -> CekM uni (Term Name uni ())
applyBuiltinName ctx bn args = do
  -- Turn the cause of a possible failure, being a 'CekValue', into a 'Term'.
  -- See Note [Being generic over @term@ in 'CekM'].
  let dischargeError = hoist $ withExceptT $ mapErrorWithCauseF $ void . dischargeCekValue
  result <- case bn of
           n@(DynBuiltinName name) -> do
               DynamicBuiltinNameMeaning sch x exX <- lookupDynamicBuiltinName name
               dischargeError $ applyTypeSchemed n sch x exX args
           StaticBuiltinName name ->
               dischargeError $ applyStaticBuiltinName name args
  case result of
    EvaluationSuccess t -> returnCek ctx t
    EvaluationFailure ->
        throwingWithCause _EvaluationError (UserEvaluationError CekEvaluationFailure) $ Nothing
        {- NB: we're not reporting any context here.  When UserEvaluationError is
           invloved, Exception.extractEvaluationResult just throws the cause
           away (see Note [Ignoring context in UserEvaluationError]), so it
           doesn't matter if we don't have any context. We could provide
           applyBuiltinName with sufficient information to reconstruct the
           application, but that would add a cost without adding any benefit. -}

-- | Evaluate a term using the CEK machine and keep track of costing.
runCek
    :: (GShow uni, GEq uni, DefaultUni <: uni, Closed uni, uni `Everywhere` ExMemoryUsage)
    => DynamicBuiltinNameMeanings (CekValue uni)
    -> ExBudgetMode
    -> CostModel
    -> Term Name uni ()
    -> (Either (CekEvaluationException uni) (Term Name uni ()), CekExBudgetState)
runCek means mode params term =
    runCekM (CekEnv means mode params)
            (ExBudgetState mempty mempty)
        $ do
            spendBudget BAST (ExBudget 0 (termAnn memTerm))
            computeCek [] mempty memTerm
    where
        memTerm = withMemory term

-- | Evaluate a term using the CEK machine in the 'Counting' mode.
runCekCounting
    :: (GShow uni, GEq uni, DefaultUni <: uni, Closed uni, uni `Everywhere` ExMemoryUsage)
    => DynamicBuiltinNameMeanings (CekValue uni)
    -> CostModel
    -> Term Name uni ()
    -> (Either (CekEvaluationException uni) (Term Name uni ()), CekExBudgetState)
runCekCounting means = runCek means Counting

-- | Evaluate a term using the CEK machine.
evaluateCek
    :: (GShow uni, GEq uni, DefaultUni <: uni, Closed uni, uni `Everywhere` ExMemoryUsage)
    => DynamicBuiltinNameMeanings (CekValue uni)
    -> CostModel
    -> Term Name uni ()
    -> Either (CekEvaluationException uni) (Term Name uni ())
evaluateCek means params = fst . runCekCounting means params

-- | Evaluate a term using the CEK machine. May throw a 'CekMachineException'.
unsafeEvaluateCek
    :: ( GShow uni, GEq uni, DefaultUni <: uni
       , Closed uni
       , uni `Everywhere` ExMemoryUsage
       , uni `Everywhere` PrettyConst
       , Typeable uni
       )
    => DynamicBuiltinNameMeanings (CekValue uni)
    -> CostModel
    -> Term Name uni ()
    -> EvaluationResult (Term Name uni ())
unsafeEvaluateCek means params = either throw id . extractEvaluationResult . evaluateCek means params

-- | Unlift a value using the CEK machine.
readKnownCek
    :: ( GShow uni, GEq uni, DefaultUni <: uni, Closed uni, uni `Everywhere` ExMemoryUsage
       , KnownType (Term Name uni ()) a
       )
    => DynamicBuiltinNameMeanings (CekValue uni)
    -> CostModel
    -> Term Name uni ()
    -> Either (CekEvaluationException uni) a
readKnownCek means params = evaluateCek means params >=> readKnown
