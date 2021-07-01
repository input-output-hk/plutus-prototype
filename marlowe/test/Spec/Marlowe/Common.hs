{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# OPTIONS_GHC -fno-warn-incomplete-uni-patterns -fno-warn-name-shadowing -fno-warn-unused-do-bind #-}
module Spec.Marlowe.Common where

import           Data.Map.Strict  (Map)

import           Language.Marlowe
import           Ledger           (pubKeyHash)
import qualified Ledger
import qualified Ledger.Value     as Val
import qualified PlutusTx.Ratio   as P
import           Test.QuickCheck
import           Wallet           (PubKey (..))
import           Wallet.Emulator

newtype MarloweScenario = MarloweScenario { mlInitialBalances :: Map PubKey Ledger.Value }

amount :: Gen Integer
amount = choose (-100, 100)


positiveAmount :: Gen Integer
positiveAmount = choose (1, 100)


partyGen :: Gen Party
partyGen = oneof [ return $ Role "alice"
                 , return $ Role "bob"
                 , return $ PK (pubKeyHash "6361726f6c")
                 ]


shrinkParty :: Party -> [Party]
shrinkParty party = case party of
    PK _         -> [Role "alice", Role "bob"]
    Role "bob"   -> [Role "alice"]
    Role "alice" -> []
    _            -> []


payeeGen :: Gen Payee
payeeGen = oneof [ Account <$> partyGen
                 , Party <$> partyGen
                 ]


shrinkPayee :: Payee -> [Payee]
shrinkPayee (Account accId) = [Account x | x <- shrinkParty accId]
shrinkPayee (Party party)   = [Party x | x <- shrinkParty party]


tokenGen :: Gen Token
tokenGen = oneof [ return $ Token "" ""
                 , return $ Token "424954" "434f494e"
                 ]


shrinkToken :: Token -> [Token]
shrinkToken (Token "" "") = []
shrinkToken (Token _ _)   = [Token "" ""]


simpleIntegerGen :: Gen Integer
simpleIntegerGen = frequency [ (1, return (-100))
                             , (1, return (-1))
                             , (2, return 0)
                             , (64, return 1)
                             , (32, return 2)
                             , (16, return 4)
                             , (8, return 8)
                             , (4, return 16)
                             , (2, return 32)
                             ]


shrinkSimpleInteger :: Integer -> [Integer]
shrinkSimpleInteger 0 = []
shrinkSimpleInteger v = [0, v `quot` 2]


choiceIdGen :: Gen ChoiceId
choiceIdGen = do choName <- oneof [ return "first"
                                  , return "second"
                                  ]
                 chooser <- partyGen
                 return $ ChoiceId choName chooser


shrinkChoiceId :: ChoiceId -> [ChoiceId]
shrinkChoiceId (ChoiceId "second" chooser) = ChoiceId "first" chooser
                                            :[ChoiceId "second" x | x <- shrinkParty chooser]
shrinkChoiceId (ChoiceId "first" chooser) = [ChoiceId "first" x | x <- shrinkParty chooser]
shrinkChoiceId _ = []


valueIdGen :: Gen ValueId
valueIdGen = oneof [ return "alpha"
                   , return "beta"
                   ]


shrinkValueId :: ValueId -> [ValueId]
shrinkValueId "beta"  = ["alpha"]
shrinkValueId "alpha" = []
shrinkValueId _       = []


rationalGen :: Gen P.Rational
rationalGen = do
    a <- simpleIntegerGen
    b <- positiveAmount
    return $ a % b


valueGenSized :: Int -> Gen (Value Observation)
valueGenSized s
  | s > 0 = oneof [ AvailableMoney <$> partyGen <*> tokenGen
                  , Constant <$> simpleIntegerGen
                  , NegValue <$> valueGenSized (s - 1)
                  , AddValue <$> valueGenSized (s `quot` 2) <*> valueGenSized (s `quot` 2)
                  , SubValue <$> valueGenSized (s `quot` 2) <*> valueGenSized (s `quot` 2)
                  , MulValue <$> valueGenSized (s `quot` 2) <*> valueGenSized (s `quot` 2)
                  , ChoiceValue <$> choiceIdGen
                  , Scale <$> rationalGen <*> valueGenSized (s - 1)
                  , Cond  <$> observationGenSized (s `quot` 3)
                          <*> valueGenSized (s `quot` 2)
                          <*> valueGenSized (s `quot` 2)
                  , return SlotIntervalStart
                  , return SlotIntervalEnd
                  , UseValue <$> valueIdGen
                  ]
  | otherwise = oneof [ AvailableMoney <$> partyGen <*> tokenGen
                      , Constant <$> simpleIntegerGen
                      , return SlotIntervalStart
                      , return SlotIntervalEnd
                      , UseValue <$> valueIdGen
                      ]


valueGen ::  Gen (Value Observation)
valueGen = sized valueGenSized


shrinkValue :: Value Observation -> [Value Observation]
shrinkValue value = case value of
    Constant x -> [Constant y | y <- shrinkSimpleInteger x]
    SlotIntervalStart -> [Constant 0]
    SlotIntervalEnd -> [Constant 0, SlotIntervalStart]
    AvailableMoney accId tok -> Constant 0 : ([AvailableMoney x tok | x <- shrinkParty accId]
               ++ [AvailableMoney accId y | y <- shrinkToken tok])
    UseValue valId -> Constant 0 : [UseValue x | x <- shrinkValueId valId]
    ChoiceValue choId -> Constant 0 : [ChoiceValue x | x <- shrinkChoiceId choId]
    NegValue val -> Constant 0 : val : [NegValue x | x <- shrinkValue val]
    AddValue val1 val2 -> Constant 0 : val1 : val2 : ([AddValue x val2 | x <- shrinkValue val1]
                         ++ [AddValue val1 y | y <- shrinkValue val2])
    SubValue val1 val2 -> Constant 0 : val1 : val2 : ([SubValue x val2 | x <- shrinkValue val1]
                         ++ [SubValue val1 y | y <- shrinkValue val2])
    MulValue val1 val2 -> Constant 0 : val1 : val2 : ([MulValue x val2 | x <- shrinkValue val1]
                         ++ [MulValue val1 y | y <- shrinkValue val2])
    Scale r val -> Constant 0 : val : [Scale r v | v <- shrinkValue val]
    Cond b val1 val2 -> Constant 0 : val1 : val2 : ([Cond x val1 val2 | x <- shrinkObservation b]
                         ++ [Cond b x val2 | x <- shrinkValue val1]
                         ++ [Cond b val1 y | y <- shrinkValue val2])


observationGenSized :: Int -> Gen Observation
observationGenSized s
  | s > 0 = oneof [ AndObs <$> observationGenSized (s `quot` 2)
                           <*> observationGenSized (s `quot` 2)
                  , OrObs <$> observationGenSized (s `quot` 2)
                          <*> observationGenSized (s `quot` 2)
                  , NotObs <$> observationGenSized (s - 1)
                  , ChoseSomething <$> choiceIdGen
                  , ValueGE <$> valueGenSized (s `quot` 2)
                            <*> valueGenSized (s `quot` 2)
                  , ValueGT <$> valueGenSized (s `quot` 2)
                            <*> valueGenSized (s `quot` 2)
                  , ValueLT <$> valueGenSized (s `quot` 2)
                            <*> valueGenSized (s `quot` 2)
                  , ValueLE <$> valueGenSized (s `quot` 2)
                            <*> valueGenSized (s `quot` 2)
                  , ValueEQ <$> valueGenSized (s `quot` 2)
                            <*> valueGenSized (s `quot` 2)
                  , return TrueObs
                  , return FalseObs
                  ]
  | otherwise = oneof [ ChoseSomething <$> choiceIdGen
                      , return TrueObs
                      , return FalseObs
                      ]


shrinkObservation :: Observation -> [Observation]
shrinkObservation obs = case obs of
    FalseObs -> []
    TrueObs  -> [FalseObs]
    ChoseSomething choId -> FalseObs:TrueObs:[ChoseSomething x | x <- shrinkChoiceId choId]
    ValueGE lhs rhs -> FalseObs:TrueObs:([ValueGE x rhs | x <- shrinkValue lhs]
                     ++ [ValueGE lhs y | y <- shrinkValue rhs])
    ValueGT lhs rhs -> FalseObs:TrueObs:([ValueGT x rhs | x <- shrinkValue lhs]
                     ++ [ValueGT lhs y | y <- shrinkValue rhs])
    ValueLT lhs rhs -> FalseObs:TrueObs:([ValueLT x rhs | x <- shrinkValue lhs]
                     ++ [ValueLT lhs y | y <- shrinkValue rhs])
    ValueLE lhs rhs -> FalseObs:TrueObs:([ValueLE x rhs | x <- shrinkValue lhs]
                     ++ [ValueLE lhs y | y <- shrinkValue rhs])
    ValueEQ lhs rhs -> FalseObs:TrueObs:([ValueEQ x rhs | x <- shrinkValue lhs]
                     ++ [ValueEQ lhs y | y <- shrinkValue rhs])
    AndObs lhs rhs ->  FalseObs:TrueObs:lhs:rhs:([AndObs x rhs | x <- shrinkObservation lhs]
                             ++ [AndObs lhs y | y <- shrinkObservation rhs])
    OrObs lhs rhs ->   FalseObs:TrueObs:lhs:rhs:([OrObs x rhs | x <- shrinkObservation lhs]
                             ++ [OrObs lhs y | y <- shrinkObservation rhs])
    NotObs subObs ->   FalseObs:TrueObs:subObs:[NotObs x | x <- shrinkObservation subObs]


boundListGenAux :: Int -> Integer -> Gen [Bound]
boundListGenAux s lb
  | s > 0 = do inc1 <- simpleIntegerGen
               inc2 <- simpleIntegerGen
               let tlb = lb + inc1
                   thb = tlb + inc2
               rest <- boundListGenAux (s - 1) thb
               return (Bound tlb thb:rest)
  | otherwise = return []


listLengthGen :: Gen Int
listLengthGen = frequency [ (1, return 0)
                          , (8, return 1)
                          , (4, return 2)
                          , (1, return 3)
                          ]


boundListGen :: Gen [Bound]
boundListGen = do len <- listLengthGen
                  firstBound <- simpleIntegerGen
                  boundListGenAux len firstBound


actionGenSized :: Int -> Gen Action
actionGenSized s =
  oneof [ Deposit <$> partyGen <*> partyGen <*> tokenGen <*> valueGenSized (s - 1)
        , Choice <$> choiceIdGen <*> boundListGen
        , Notify <$> observationGenSized (s - 1)
        ]


shrinkAction :: Action -> [Action]
shrinkAction action = case action of
    Deposit accId party tok val -> Notify FalseObs : [Deposit accId party tok v | v <- shrinkValue val]
        ++ [Deposit x party tok val | x <- shrinkParty accId]
        ++ [Deposit accId y tok val | y <- shrinkParty party]
        ++ [Deposit accId party z val | z <- shrinkToken tok]
    Choice choId boundList -> Notify FalseObs
        : [Choice choId b | b <- shrinkList (const []) boundList]
        ++ [Choice x boundList | x <- shrinkChoiceId choId]
    Notify obs -> [Notify x | x <- shrinkObservation obs]


caseRelGenSized :: Int -> Integer -> Gen (Case Contract)
caseRelGenSized s bn = Case <$> actionGenSized s <*> contractRelGenSized s bn


shrinkCase :: Case Contract -> [Case Contract]
shrinkCase (Case act cont) = [Case act x | x <- shrinkContract cont]
                              ++ [Case y cont | y <- shrinkAction act]


contractRelGenSized :: Int -> Integer -> Gen Contract
contractRelGenSized s bn
  | s > 0 = oneof [ return Close
                  , Pay <$> partyGen <*> payeeGen <*> tokenGen
                        <*> valueGenSized (s `quot` 4)
                        <*> contractRelGenSized (s - 1) bn
                  , If <$> observationGenSized (s `quot` 4)
                       <*> contractRelGenSized (s `quot` 3) bn
                       <*> contractRelGenSized (s `quot` 3) bn
                  , Let <$> valueIdGen <*> valueGenSized (s `quot` 2) <*> contractRelGenSized (s `quot` 2) bn
                  , do timeOutDelta <- simpleIntegerGen
                       numCases <- listLengthGen
                       let newTimeout = bn + timeOutDelta
                           ns = if numCases > 0 then s `quot` numCases else s - 1
                       When <$> vectorOf numCases (caseRelGenSized ns bn)
                            <*> (return $ Slot newTimeout)
                            <*> contractRelGenSized ns newTimeout
                  , Assert <$> observationGenSized (s `quot` 3)
                           <*> contractRelGenSized (s `quot` 2) bn
                  ]
  | otherwise = return Close


contractGenSized :: Int -> Gen Contract
contractGenSized s = do iniBn <- simpleIntegerGen
                        contractRelGenSized s iniBn


contractGen :: Gen Contract
contractGen = sized contractGenSized


shrinkContract :: Contract -> [Contract]
shrinkContract cont = case cont of
    Close -> []
    Let vid val cont -> Close : cont : ([Let vid v cont | v <- shrinkValue val]
              ++ [Let vid val c | c <- shrinkContract cont])
    Pay accId payee tok val cont ->
        Close:cont:([Pay accId payee tok val c | c <- shrinkContract cont]
              ++ [Pay accId payee tok v cont | v <- shrinkValue val]
              ++ [Pay x payee tok val cont | x <- shrinkParty accId]
              ++ [Pay accId y tok val cont | y <- shrinkPayee payee]
              ++ [Pay accId payee z val cont | z <- shrinkToken tok])
    If obs cont1 cont2 ->
        Close:cont1:cont2:([If obs x cont2 | x <- shrinkContract cont1]
                      ++ [If obs cont1 y | y <- shrinkContract cont2]
                      ++ [If z cont1 cont2 | z <- shrinkObservation obs])
    When [] (Slot tim) cont ->
        Close:cont:([When [] (Slot tim) x | x <- shrinkContract cont]
              ++ [When [] (Slot y) cont | y <- shrinkSimpleInteger tim])
    When l (Slot tim) cont ->
        Close:cont:([When nl (Slot tim) cont | nl <- shrinkList shrinkCase l]
              ++ [When l (Slot tim) x | x <- shrinkContract cont]
              ++ [When l (Slot y) cont | y <- shrinkSimpleInteger tim])
    Assert obs cont ->
        Close:cont:([Assert x cont | x <- shrinkObservation obs]
              ++ [Assert obs y | y <- shrinkContract cont])


pangramContract :: Contract
pangramContract = let
    alicePk = PK $ pubKeyHash $ walletPubKey $ Wallet 1
    aliceAcc = alicePk
    bobRole = Role "Bob"
    constant = Constant 100
    choiceId = ChoiceId "choice" alicePk
    token = Token (Val.currencySymbol "aa") (Val.tokenName "name")
    valueExpr = AddValue constant (SubValue constant (NegValue constant))
    in Assert TrueObs $ When
        [ Case (Deposit aliceAcc alicePk ada valueExpr)
            (Let "x" valueExpr
                (Pay aliceAcc (Party bobRole) ada (UseValue "x") Close))
        , Case (Choice choiceId [Bound 0 1, Bound 10 20])
            (If (ChoseSomething choiceId `OrObs` (ChoiceValue choiceId `ValueEQ` Scale (1 % 10) constant))
                (Pay aliceAcc (Account aliceAcc) token (AvailableMoney aliceAcc token) Close)
                Close)
        , Case (Notify (AndObs (SlotIntervalStart `ValueLT` SlotIntervalEnd) TrueObs)) Close
        ] (Slot 100) Close
