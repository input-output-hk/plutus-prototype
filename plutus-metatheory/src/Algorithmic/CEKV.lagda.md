# CEK machine that discharges builtin args

```
{-# OPTIONS --rewriting #-}

module Algorithmic.CEKV where

open import Agda.Builtin.String using (primStringFromList; primStringAppend)
open import Function hiding (_∋_)
open import Data.Product using (proj₁;proj₂)
open import Data.List using ([];_∷_)
open import Data.List.Properties
open import Relation.Binary.PropositionalEquality renaming ([_] to [[_]];subst to substEq)
open import Data.Unit using (⊤;tt)
open import Data.Product using (_×_;Σ) renaming (_,_ to _,,_)
open import Data.Sum
open import Data.Integer using (_<?_;_+_;_-_;∣_∣;_≤?_;_≟_;ℤ) renaming (_*_ to _**_)
open import Data.Bool using (true;false)
open import Relation.Nullary
open import Relation.Nullary.Decidable
import Debug.Trace as Debug
open import Utils

open import Type
open import Type.BetaNormal
open import Type.BetaNBE using (nf)
open import Type.BetaNBE.RenamingSubstitution
open import Algorithmic
open import Algorithmic.RenamingSubstitution
open import Builtin
open import Builtin.Signature Ctx⋆ Kind ∅ _,⋆_ * _∋⋆_ Z S _⊢Nf⋆_ (ne ∘ `) con
open import Builtin.Constant.Type
open import Builtin.Constant.Term Ctx⋆ Kind * _⊢Nf⋆_ con
open import Utils using (decIf;just;nothing)

open import Algorithmic.ReductionEC using (Arg;Term;Type;_<>>_∈_;start;bubble;arity;saturated;_<><_;<>>2<>>';lemma<>2;unique<>>;Bwd;[];_∷_;<>>-cancel-both;<>>-cancel-both')

data Env : Ctx ∅ → Set

data BAPP (b : Builtin) : ∀{az}{as}
  → az <>> as ∈ arity b
  → (A : ∅ ⊢Nf⋆ *) → Set

data Value : (A : ∅ ⊢Nf⋆ *) → Set where
  V-ƛ : ∀ {Γ}{A B : ∅ ⊢Nf⋆ *}
    → (M : Γ , A ⊢ B)
    → Env Γ
    → Value (A ⇒ B)

  V-Λ : ∀ {Γ K}{B : ∅ ,⋆ K ⊢Nf⋆ *}
    → (M : Γ ,⋆ K ⊢ B)
    → Env Γ
    → Value (Π B)

  V-wrap : ∀{K}
   → {A : ∅ ⊢Nf⋆ (K ⇒ *) ⇒ K ⇒ *}
   → {B : ∅ ⊢Nf⋆ K}
   → Value (nf (embNf A · ƛ (μ (embNf (weakenNf A)) (` Z)) · embNf B))
   → Value (μ A B)

  V-con : {tcn : TyCon}
    → (cn : TermCon {∅} (con tcn))
    → Value (con tcn)

  V-I⇒ : ∀ b {A B as as'}
       → (p : as <>> (Term ∷ as') ∈ arity b)
       → BAPP b p (A ⇒ B)
       → Value (A ⇒ B)

  V-IΠ : ∀ b {K}{B : ∅ ,⋆ K ⊢Nf⋆ *}{as as'}
       → (p : as <>> (Type ∷ as') ∈ arity b)
       → BAPP b p (Π B)
       → Value (Π B)

data BAPP b where
  base : BAPP b (start (arity b)) (itype b)
  app : ∀{A B}{az as}
    → (p : az <>> (Term ∷ as) ∈ arity b)
    → BAPP b p (A ⇒ B)
    → Value A → BAPP b (bubble p) B
  app⋆ : ∀{B C}{az as}
    → (p : az <>> (Type ∷ as) ∈ arity b)
    → BAPP b p (Π B)
    → {A : ∅ ⊢Nf⋆ K}
    → (q : C ≡ B [ A ]Nf)
    → BAPP b (bubble p) C

data Env where
  [] : Env ∅
  _∷_ : ∀{Γ A} → Env Γ → Value A → Env (Γ , A)

lookup : ∀{Γ A} → Γ ∋ A → Env Γ → Value A
lookup Z     (ρ ∷ v) = v
lookup (S x) (ρ ∷ v) = lookup x ρ

convValue : ∀{A A'}(p : A ≡ A') → Value A → Value A'
convValue refl v = v



data Error : ∅ ⊢Nf⋆ * → Set where
  -- an actual error term
  E-error : (A : ∅ ⊢Nf⋆ *) → Error A

discharge : ∀{A} → Value A → ∅ ⊢ A

env2ren : ∀{Γ} → Env Γ → Sub (ne ∘ `) Γ ∅
env2ren (ρ ∷ V) Z     = conv⊢ refl (sym (subNf-id _)) (discharge V)
env2ren (ρ ∷ C)                   (S x) = env2ren ρ x

dischargeBody : ∀{Γ A B} → Γ , A ⊢ B → Env Γ → ∅ , A ⊢ B
dischargeBody M ρ = conv⊢
  (cong (∅ ,_) (subNf-id _))
  (subNf-id _)
  (sub (ne ∘ `) (exts (ne ∘ `) (env2ren ρ)) M)

dischargeBody⋆ : ∀{Γ K A} → Γ ,⋆ K ⊢ A → Env Γ → ∅ ,⋆ K ⊢ A
dischargeBody⋆ {A = A} M ρ = conv⊢
  refl
  (trans
    (subNf-cong
      {f = extsNf (ne ∘ `)}
      {g = ne ∘ `}
      (λ{ Z → refl; (S α) → refl})
      A)
    (subNf-id A))
  (sub (extsNf (ne ∘ `)) (exts⋆ (ne ∘ `) (env2ren ρ)) M)

dischargeB : ∀{b A}{az}{as}{p : az <>> as ∈ arity b} → BAPP b p A → ∅ ⊢ A
dischargeB {b = b} base = ibuiltin b
dischargeB (app p bt vu) = dischargeB bt · discharge vu
dischargeB (app⋆ p bt refl) = dischargeB bt ·⋆ _

discharge (V-ƛ M ρ)  = ƛ (dischargeBody M ρ)
discharge (V-Λ M ρ)  = Λ (dischargeBody⋆ M ρ)
discharge (V-wrap V) = wrap _ _ (discharge V)
discharge (V-con c)  = con c
discharge (V-I⇒ b p bt) = dischargeB bt
discharge (V-IΠ b p bt) = dischargeB bt

BUILTIN : ∀ b {A} → BAPP b (saturated (arity b)) A → Value A ⊎ ∅ ⊢Nf⋆ *
BUILTIN addInteger (app _ (app _ base (V-con (integer i))) (V-con (integer i'))) = inj₁ (V-con (integer (i + i')))
BUILTIN subtractInteger (app _ (app _ base (V-con (integer i))) (V-con (integer i'))) = inj₁ (V-con (integer (i - i')))
BUILTIN multiplyInteger (app _ (app _ base (V-con (integer i))) (V-con (integer i'))) = inj₁ (V-con (integer (i ** i')))
BUILTIN divideInteger (app _ (app _ base (V-con (integer i))) (V-con (integer i'))) = decIf
  (i' ≟ ℤ.pos 0)
  (inj₂ (con integer))
  (inj₁ (V-con (integer (div i i'))))
BUILTIN quotientInteger (app _ (app _ base (V-con (integer i))) (V-con (integer i'))) = decIf
  (i' ≟ ℤ.pos 0)
  (inj₂ (con integer))
  (inj₁ (V-con (integer (quot i i'))))
BUILTIN remainderInteger (app _ (app _ base (V-con (integer i))) (V-con (integer i'))) = decIf
  (i' ≟ ℤ.pos 0)
  (inj₂ (con integer))
  (inj₁ (V-con (integer (rem i i'))))
BUILTIN modInteger (app _ (app _ base (V-con (integer i))) (V-con (integer i'))) = decIf
  (i' ≟ ℤ.pos 0)
  (inj₂ (con integer))
  (inj₁ (V-con (integer (mod i i'))))
BUILTIN lessThanInteger (app _ (app _ base (V-con (integer i))) (V-con (integer i'))) = decIf (i <? i') (inj₁ (V-con (bool true))) (inj₁ (V-con (bool false)))
BUILTIN lessThanEqualsInteger (app _ (app _ base (V-con (integer i))) (V-con (integer i'))) = decIf (i ≤? i') (inj₁ (V-con (bool true))) (inj₁ (V-con (bool false)))
BUILTIN greaterThanInteger (app _ (app _ base (V-con (integer i))) (V-con (integer i'))) = decIf (i I>? i')
  (inj₁ (V-con (bool true)))
  (inj₁ (V-con (bool false)))
BUILTIN greaterThanEqualsInteger (app _ (app _ base (V-con (integer i))) (V-con (integer i'))) = decIf (i I≥? i') (inj₁ (V-con (bool true))) (inj₁ (V-con (bool false)))
BUILTIN equalsInteger (app _ (app _ base (V-con (integer i))) (V-con (integer i'))) = decIf (i ≟ i') (inj₁ (V-con (bool true))) (inj₁ (V-con (bool false)))
BUILTIN concatenate (app _ (app _ base (V-con (bytestring b))) (V-con (bytestring b'))) = inj₁ (V-con (bytestring (concat b b')))
BUILTIN takeByteString (app _ (app _ base (V-con (integer i))) (V-con (bytestring b))) = inj₁ (V-con (bytestring (take i b)))
BUILTIN dropByteString (app _ (app _ base (V-con (integer i))) (V-con (bytestring b))) = inj₁ (V-con (bytestring (drop i b)))
BUILTIN lessThanByteString (app _ (app _ base (V-con (bytestring b))) (V-con (bytestring b'))) = inj₁ (V-con (bool (B< b b')))
BUILTIN greaterThanByteString (app _ (app _ base (V-con (bytestring b))) (V-con (bytestring b'))) = inj₁ (V-con (bool (B> b b')))
BUILTIN sha2-256 (app _ base (V-con (bytestring b))) =
  inj₁ (V-con (bytestring (SHA2-256 b)))
BUILTIN sha3-256 (app _ base (V-con (bytestring b))) =
  inj₁ (V-con (bytestring (SHA3-256 b)))
BUILTIN verifySignature (app _ (app _ (app _ base (V-con (bytestring k))) (V-con (bytestring d))) (V-con (bytestring c))) with (verifySig k d c)
... | just b = inj₁ (V-con (bool b))
... | nothing = inj₂ (con bool)

BUILTIN equalsByteString (app _ (app _ base (V-con (bytestring b))) (V-con (bytestring b'))) = inj₁ (V-con (bool (equals b b')))
BUILTIN ifThenElse (app _ (app _ (app _ (app⋆ _ base refl) (V-con (bool false))) vt) vf) = inj₁ vf
BUILTIN ifThenElse (app _ (app _ (app _ (app⋆ _ base refl) (V-con (bool true))) vt) vf) = inj₁ vt
BUILTIN charToString (app _ base (V-con (char c))) = inj₁ (V-con (string (primStringFromList Data.List.[ c ])))
BUILTIN append (app _ (app _ base (V-con (string s))) (V-con (string s'))) = inj₁ (V-con (string (primStringAppend s s')))
BUILTIN trace (app _ base (V-con (string s))) =
  inj₁ (V-con (Debug.trace s unit))

convBApp : (b : Builtin) → ∀{az}{as}(p p' : az <>> as ∈ arity b)
  → ∀{A}
  → BAPP b p A
  → BAPP b p' A
convBApp b p p' q rewrite unique<>> p p' = q

BUILTIN' : ∀ b {A}{az}(p : az <>> [] ∈ arity b)
  → BAPP b p A
  → Value A ⊎ ∅ ⊢Nf⋆ *
BUILTIN' b {az = az} p q
  with sym (trans (cong ([] <><_) (sym (<>>2<>>' _ _ _ p))) (lemma<>2 az []))
... | refl = BUILTIN b (convBApp b p (saturated (arity b)) q)

open import Data.Product using (∃)

bappTermLem : ∀  b {A}{az as}(p : az <>> (Term ∷ as) ∈ arity b)
  → BAPP b p A → ∃ λ A' → ∃ λ A'' → A ≡ A' ⇒ A''
bappTermLem addInteger _ base = _ ,, _ ,, refl
bappTermLem addInteger {as = as} .(bubble p) (app {az = az} p q x)
  with <>>-cancel-both az (([] ∷ Term) ∷ Term) as p
bappTermLem addInteger {as = .[]} (bubble (start .(Term ∷ Term ∷ []))) (app {az = _} (start .(Term ∷ Term ∷ [])) base x)
  | refl ,, refl = _ ,, _ ,, refl
bappTermLem addInteger {as = as} .(bubble p) (app⋆ {az = az} p q q₁)
  with <>>-cancel-both' az (([] ∷ Type) ∷ Term) (([] ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, ()
bappTermLem subtractInteger _ base = _ ,, _ ,, refl
bappTermLem subtractInteger {as = as} .(bubble p) (app {az = az} p q x)
  with <>>-cancel-both az (([] ∷ Term) ∷ Term) as p
bappTermLem subtractInteger {as = .[]} (bubble (start .(Term ∷ Term ∷ []))) (app {az = _} (start .(Term ∷ Term ∷ [])) base x)
  | refl ,, refl = _ ,, _ ,, refl
bappTermLem subtractInteger {as = as} (bubble p) (app⋆ {az = az} p q q₁)
  with <>>-cancel-both' az (([] ∷ Type) ∷ Term) (([] ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, ()
bappTermLem multiplyInteger _ base = _ ,, _ ,, refl
bappTermLem multiplyInteger {as = as} .(bubble p) (app {az = az} p q x)
  with <>>-cancel-both az (([] ∷ Term) ∷ Term) as p
bappTermLem multiplyInteger {as = .[]} (bubble (start .(Term ∷ Term ∷ []))) (app {az = _} (start .(Term ∷ Term ∷ [])) base x)
  | refl ,, refl = _ ,, _ ,, refl
bappTermLem multiplyInteger {as = as} .(bubble p) (app⋆ {az = az} p q q₁)
  with <>>-cancel-both' az (([] ∷ Type) ∷ Term) (([] ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, ()
bappTermLem divideInteger _ base = _ ,, _ ,, refl
bappTermLem divideInteger {as = as} .(bubble p) (app {az = az} p q x)
  with <>>-cancel-both az (([] ∷ Term) ∷ Term) as p
bappTermLem divideInteger {as = .[]} (bubble (start .(Term ∷ Term ∷ []))) (app {az = _} (start .(Term ∷ Term ∷ [])) base x)
  | refl ,, refl = _ ,, _ ,, refl
bappTermLem divideInteger {as = as} .(bubble p) (app⋆ {az = az} p q q₁)
  with <>>-cancel-both' az (([] ∷ Type) ∷ Term) (([] ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, ()
bappTermLem quotientInteger _ base = _ ,, _ ,, refl
bappTermLem quotientInteger {as = as} .(bubble p) (app {az = az} p q x)
  with <>>-cancel-both az (([] ∷ Term) ∷ Term) as p
bappTermLem quotientInteger {as = .[]} (bubble (start .(Term ∷ Term ∷ []))) (app {az = _} (start .(Term ∷ Term ∷ [])) base x)
  | refl ,, refl = _ ,, _ ,, refl
bappTermLem quotientInteger {as = as} .(bubble p) (app⋆ {az = az} p q q₁)
  with <>>-cancel-both' az (([] ∷ Type) ∷ Term) (([] ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, ()
bappTermLem remainderInteger _ base = _ ,, _ ,, refl
bappTermLem remainderInteger {as = as} .(bubble p) (app {az = az} p q x)
  with <>>-cancel-both az (([] ∷ Term) ∷ Term) as p
bappTermLem remainderInteger {as = .[]} (bubble (start .(Term ∷ Term ∷ []))) (app {az = _} (start .(Term ∷ Term ∷ [])) base x)
  | refl ,, refl = _ ,, _ ,, refl
bappTermLem remainderInteger {as = as} .(bubble p) (app⋆ {az = az} p q q₁)
  with <>>-cancel-both' az (([] ∷ Type) ∷ Term) (([] ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, ()
bappTermLem modInteger _ base = _ ,, _ ,, refl
bappTermLem modInteger {as = as} .(bubble p) (app {az = az} p q x)
  with <>>-cancel-both az (([] ∷ Term) ∷ Term) as p
bappTermLem modInteger {as = .[]} (bubble (start .(Term ∷ Term ∷ []))) (app {az = _} (start .(Term ∷ Term ∷ [])) base x)
  | refl ,, refl = _ ,, _ ,, refl
bappTermLem modInteger {as = as} .(bubble p) (app⋆ {az = az} p q q₁)
  with <>>-cancel-both' az (([] ∷ Type) ∷ Term) (([] ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, ()
bappTermLem lessThanInteger _ base = _ ,, _ ,, refl
bappTermLem lessThanInteger {as = as} .(bubble p) (app {az = az} p q x)
  with <>>-cancel-both az (([] ∷ Term) ∷ Term) as p
bappTermLem lessThanInteger {as = .[]} (bubble (start .(Term ∷ Term ∷ []))) (app {az = _} (start .(Term ∷ Term ∷ [])) base x)
  | refl ,, refl = _ ,, _ ,, refl
bappTermLem lessThanInteger {as = as} .(bubble p) (app⋆ {az = az} p q q₁)
  with <>>-cancel-both' az (([] ∷ Type) ∷ Term) (([] ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, ()
bappTermLem lessThanEqualsInteger _ base = _ ,, _ ,, refl
bappTermLem lessThanEqualsInteger {as = as} .(bubble p) (app {az = az} p q x)
  with <>>-cancel-both az (([] ∷ Term) ∷ Term) as p
bappTermLem lessThanEqualsInteger {as = .[]} (bubble (start .(Term ∷ Term ∷ []))) (app {az = _} (start .(Term ∷ Term ∷ [])) base x)
  | refl ,, refl = _ ,, _ ,, refl
bappTermLem lessThanEqualsInteger {as = as} .(bubble p) (app⋆ {az = az} p q q₁)
  with <>>-cancel-both' az (([] ∷ Type) ∷ Term) (([] ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, ()
bappTermLem greaterThanInteger _ base = _ ,, _ ,, refl
bappTermLem greaterThanInteger {as = as} .(bubble p) (app {az = az} p q x)
  with <>>-cancel-both az (([] ∷ Term) ∷ Term) as p
bappTermLem greaterThanInteger {as = .[]} (bubble (start .(Term ∷ Term ∷ []))) (app {az = _} (start .(Term ∷ Term ∷ [])) base x)
  | refl ,, refl = _ ,, _ ,, refl
bappTermLem greaterThanInteger {as = as} .(bubble p) (app⋆ {az = az} p q q₁)
  with <>>-cancel-both' az (([] ∷ Type) ∷ Term) (([] ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, ()
bappTermLem greaterThanEqualsInteger _ base = _ ,, _ ,, refl
bappTermLem greaterThanEqualsInteger {as = as} .(bubble p) (app {az = az} p q x)
  with <>>-cancel-both az (([] ∷ Term) ∷ Term) as p
bappTermLem greaterThanEqualsInteger {as = .[]} (bubble (start .(Term ∷ Term ∷ []))) (app {az = _} (start .(Term ∷ Term ∷ [])) base x)
  | refl ,, refl = _ ,, _ ,, refl
bappTermLem greaterThanEqualsInteger {as = as} .(bubble p) (app⋆ {az = az} p q q₁)
  with <>>-cancel-both' az (([] ∷ Type) ∷ Term) (([] ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, ()
bappTermLem equalsInteger _ base = _ ,, _ ,, refl
bappTermLem equalsInteger {as = as} .(bubble p) (app {az = az} p q x)
  with <>>-cancel-both az (([] ∷ Term) ∷ Term) as p
bappTermLem equalsInteger {as = .[]} (bubble (start .(Term ∷ Term ∷ []))) (app {az = _} (start .(Term ∷ Term ∷ [])) base x)
  | refl ,, refl = _ ,, _ ,, refl
bappTermLem equalsInteger {as = as} .(bubble p) (app⋆ {az = az} p q q₁)
  with <>>-cancel-both' az (([] ∷ Type) ∷ Term) (([] ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, ()
bappTermLem concatenate _ base = _ ,, _ ,, refl
bappTermLem concatenate {as = as} .(bubble p) (app {az = az} p q x)
  with <>>-cancel-both az (([] ∷ Term) ∷ Term) as p
bappTermLem concatenate {as = .[]} (bubble (start .(Term ∷ Term ∷ []))) (app {az = _} (start .(Term ∷ Term ∷ [])) base x)
  | refl ,, refl = _ ,, _ ,, refl
bappTermLem concatenate {as = as} .(bubble p) (app⋆ {az = az} p q q₁)
  with <>>-cancel-both' az (([] ∷ Type) ∷ Term) (([] ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, ()
bappTermLem takeByteString _ base = _ ,, _ ,, refl
bappTermLem takeByteString {as = as} .(bubble p) (app {az = az} p q x)
  with <>>-cancel-both az (([] ∷ Term) ∷ Term) as p
bappTermLem takeByteString {as = .[]} (bubble (start .(Term ∷ Term ∷ []))) (app {az = _} (start .(Term ∷ Term ∷ [])) base x)
  | refl ,, refl = _ ,, _ ,, refl
bappTermLem takeByteString {as = as} .(bubble p) (app⋆ {az = az} p q q₁)
  with <>>-cancel-both' az (([] ∷ Type) ∷ Term) (([] ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, ()

bappTermLem dropByteString _ base = _ ,, _ ,, refl
bappTermLem dropByteString {as = as} .(bubble p) (app {az = az} p q x)
  with <>>-cancel-both az (([] ∷ Term) ∷ Term) as p
bappTermLem dropByteString {as = .[]} (bubble (start .(Term ∷ Term ∷ []))) (app {az = _} (start .(Term ∷ Term ∷ [])) base x)
  | refl ,, refl = _ ,, _ ,, refl
bappTermLem dropByteString {as = as} .(bubble p) (app⋆ {az = az} p q q₁)
  with <>>-cancel-both' az (([] ∷ Type) ∷ Term) (([] ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, ()
bappTermLem lessThanByteString _ base = _ ,, _ ,, refl
bappTermLem lessThanByteString {as = as} .(bubble p) (app {az = az} p q x)
  with <>>-cancel-both az (([] ∷ Term) ∷ Term) as p
bappTermLem lessThanByteString {as = .[]} (bubble (start .(Term ∷ Term ∷ []))) (app {az = _} (start .(Term ∷ Term ∷ [])) base x)
  | refl ,, refl = _ ,, _ ,, refl
bappTermLem lessThanByteString {as = as} .(bubble p) (app⋆ {az = az} p q q₁)
  with <>>-cancel-both' az (([] ∷ Type) ∷ Term) (([] ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, ()

bappTermLem greaterThanByteString _ base = _ ,, _ ,, refl
bappTermLem greaterThanByteString {as = as} .(bubble p) (app {az = az} p q x)
  with <>>-cancel-both az (([] ∷ Term) ∷ Term) as p
bappTermLem greaterThanByteString {as = .[]} (bubble (start .(Term ∷ Term ∷ []))) (app {az = _} (start .(Term ∷ Term ∷ [])) base x)
  | refl ,, refl = _ ,, _ ,, refl
bappTermLem greaterThanByteString {as = as} .(bubble p) (app⋆ {az = az} p q q₁)
  with <>>-cancel-both' az (([] ∷ Type) ∷ Term) (([] ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, ()
bappTermLem sha2-256 {az = az} {as} p q with <>>-cancel-both az ([] ∷ Term) as p
bappTermLem sha2-256 {az = .[]} {.[]} .(start (Term ∷ [])) base | refl ,, refl = _ ,, _ ,, refl
bappTermLem sha3-256 {az = az} {as} p q with <>>-cancel-both az ([] ∷ Term) as p
bappTermLem sha3-256 {az = .[]} {.[]} .(start (Term ∷ [])) base | refl ,, refl = _ ,, _ ,, refl
bappTermLem verifySignature .(start (Term ∷ Term ∷ Term ∷ [])) base = _ ,, _ ,, refl
bappTermLem verifySignature .(bubble (start (Term ∷ Term ∷ Term ∷ []))) (app .(start (Term ∷ Term ∷ Term ∷ [])) base x) = _ ,, _ ,, refl
bappTermLem verifySignature {as = as} .(bubble (bubble p)) (app .(bubble p) (app {az = az} p q x₁) x) with <>>-cancel-both az ((([] ∷ Term) ∷ Term) ∷ Term) as p
bappTermLem verifySignature {as = .[]} (bubble (bubble .(start (Term ∷ Term ∷ Term ∷ [])))) (app .(bubble (start (Term ∷ Term ∷ Term ∷ []))) (app {az = _} .(start (Term ∷ Term ∷ Term ∷ [])) base x₁) x) | refl ,, refl = _ ,, _ ,, refl
bappTermLem verifySignature {as = as} .(bubble (bubble p)) (app .(bubble p) (app⋆ {az = az} p q q₁₁) x) with <>>-cancel-both' az ((([] ∷ Type) ∷ Term) ∷ Term) ((([] ∷ Term) ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, ()
bappTermLem verifySignature {as = as} .(bubble (bubble p)) (app⋆ .(bubble p) (app {az = az} p q x₁) q₁)  with <>>-cancel-both' az ((([] ∷ Term) ∷ Type) ∷ Term) ((([] ∷ Term) ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, ()
bappTermLem verifySignature {as = as} .(bubble (bubble p)) (app⋆ .(bubble p) (app⋆ {az = az} p q q₂) q₁) with <>>-cancel-both' az ((([] ∷ Type) ∷ Type) ∷ Term) ((([] ∷ Term) ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, ()
bappTermLem equalsByteString _ base = _ ,, _ ,, refl
bappTermLem equalsByteString {as = as} .(bubble p) (app {az = az} p q x)
  with <>>-cancel-both az (([] ∷ Term) ∷ Term) as p
bappTermLem equalsByteString {as = .[]} (bubble (start .(Term ∷ Term ∷ []))) (app {az = _} (start .(Term ∷ Term ∷ [])) base x)
  | refl ,, refl = _ ,, _ ,, refl
bappTermLem equalsByteString {as = as} .(bubble p) (app⋆ {az = az} p q q₁)
  with <>>-cancel-both' az (([] ∷ Type) ∷ Term) (([] ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, ()

bappTermLem ifThenElse {as = as} .(bubble (bubble (bubble p))) (app .(bubble (bubble p)) (app .(bubble p) (app {az = az} p q x₂) x₁) x) with <>>-cancel-both' az (((([] ∷ Term) ∷ Term) ∷ Term) ∷ Term) (((([] ∷ Type) ∷ Term) ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, ()
bappTermLem ifThenElse {as = as} .(bubble (bubble (bubble p))) (app .(bubble (bubble p)) (app .(bubble p) (app⋆ {az = az} p q q₁) x₁) x) with <>>-cancel-both az (((([] ∷ Type) ∷ Term) ∷ Term) ∷ Term) as p
bappTermLem ifThenElse {as = .[]} (bubble (bubble (bubble .(start (Type ∷ Term ∷ Term ∷ Term ∷ []))))) (app .(bubble (bubble (start (Type ∷ Term ∷ Term ∷ Term ∷ [])))) (app .(bubble (start (Type ∷ Term ∷ Term ∷ Term ∷ []))) (app⋆ {az = _} .(start (Type ∷ Term ∷ Term ∷ Term ∷ [])) base refl) x₁) x) | refl ,, refl = _ ,, _ ,, refl
bappTermLem ifThenElse .(bubble (bubble (start (Type ∷ Term ∷ Term ∷ Term ∷ [])))) (app .(bubble (start (Type ∷ Term ∷ Term ∷ Term ∷ []))) (app⋆ (start .(Type ∷ Term ∷ Term ∷ Term ∷ [])) base refl) x) = _ ,, _ ,, refl
bappTermLem ifThenElse {as = as} .(bubble (bubble (bubble p))) (app .(bubble (bubble p)) (app⋆ (bubble {as = as₁} p) q q₁₁) x) with <>>-cancel-both' as₁ (((([] ∷ _) ∷ Type) ∷ Term) ∷ Term) (((([] ∷ Type) ∷ Term) ∷ Term) ∷ Term)as p refl
... | refl ,, refl ,, ()
bappTermLem ifThenElse .(bubble (start (Type ∷ Term ∷ Term ∷ Term ∷ []))) (app⋆ .(start (Type ∷ Term ∷ Term ∷ Term ∷ [])) base refl) = _ ,, _ ,, refl
bappTermLem ifThenElse {as = as} .(bubble (bubble (bubble p))) (app⋆ .(bubble (bubble p)) (app .(bubble p) (app {az = az} p q x₂) x₁) q₁) with <>>-cancel-both' az (((([] ∷ Term) ∷ Term) ∷ Type) ∷ Term) (((([] ∷ Type) ∷ Term) ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, ()
bappTermLem ifThenElse {as = as} .(bubble (bubble (bubble p))) (app⋆ .(bubble (bubble p)) (app .(bubble p) (app⋆ {az = az} p q q₂) x₁) q₁) with <>>-cancel-both' az (((([] ∷ Type) ∷ Term) ∷ Type) ∷ Term) (((([] ∷ Type) ∷ Term) ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, ()
bappTermLem ifThenElse {as = as} .(bubble (bubble (bubble p))) (app⋆ .(bubble (bubble p)) (app⋆ .(bubble p) (app {az = az} p q x₂) q₂) q₁) with <>>-cancel-both' az (((([] ∷ Term) ∷ Type) ∷ Type) ∷ Term) (((([] ∷ Type) ∷ Term) ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, ()
bappTermLem ifThenElse {as = as} .(bubble (bubble (bubble p))) (app⋆ .(bubble (bubble p)) (app⋆ .(bubble p) (app⋆ {az = az} p q q₃) q₂) q₁) with <>>-cancel-both' az (((([] ∷ Type) ∷ Type) ∷ Type) ∷ Term) (((([] ∷ Type) ∷ Term) ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, ()
bappTermLem charToString {az = az} {as} p q with <>>-cancel-both az ([] ∷ Term) as p
bappTermLem charToString {az = .[]} {.[]} .(start (Term ∷ [])) base | refl ,, refl = _ ,, _ ,, refl
bappTermLem append _ base = _ ,, _ ,, refl
bappTermLem append {as = as} .(bubble p) (app {az = az} p q x)
  with <>>-cancel-both az (([] ∷ Term) ∷ Term) as p
bappTermLem append {as = .[]} (bubble (start .(Term ∷ Term ∷ []))) (app {az = _} (start .(Term ∷ Term ∷ [])) base x)
  | refl ,, refl = _ ,, _ ,, refl
bappTermLem append {as = as} .(bubble p) (app⋆ {az = az} p q q₁)
  with <>>-cancel-both' az (([] ∷ Type) ∷ Term) (([] ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, ()
bappTermLem trace {az = az} {as} p q with <>>-cancel-both az ([] ∷ Term) as p
bappTermLem trace {az = .[]} {.[]} .(start (Term ∷ [])) base | refl ,, refl = _ ,, _ ,, refl

bappTypeLem : ∀  b {A}{az as}(p : az <>> (Type ∷ as) ∈ arity b)
  → BAPP b p A → ∃ λ K → ∃ λ (B : ∅ ,⋆ K ⊢Nf⋆ *) → A ≡ Π B
bappTypeLem addInteger {as = as} .(bubble p) (app {az = az} p q x)
  with <>>-cancel-both' az (([] ∷ Term) ∷ Type) (([] ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, () 
bappTypeLem addInteger {as = as} .(bubble p) (app⋆ {az = az} p q q₁)
  with <>>-cancel-both' az (([] ∷ Type) ∷ Type) (([] ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, ()

bappTypeLem subtractInteger {as = as} .(bubble p) (app {az = az} p q x)
  with <>>-cancel-both' az (([] ∷ Term) ∷ Type) (([] ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, () 
bappTypeLem subtractInteger {as = as} .(bubble p) (app⋆ {az = az} p q q₁)
  with <>>-cancel-both' az (([] ∷ Type) ∷ Type) (([] ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, ()

bappTypeLem multiplyInteger {as = as} .(bubble p) (app {az = az} p q x)
  with <>>-cancel-both' az (([] ∷ Term) ∷ Type) (([] ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, () 
bappTypeLem multiplyInteger {as = as} .(bubble p) (app⋆ {az = az} p q q₁)
  with <>>-cancel-both' az (([] ∷ Type) ∷ Type) (([] ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, ()

bappTypeLem divideInteger {as = as} .(bubble p) (app {az = az} p q x)
  with <>>-cancel-both' az (([] ∷ Term) ∷ Type) (([] ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, () 
bappTypeLem divideInteger {as = as} .(bubble p) (app⋆ {az = az} p q q₁)
  with <>>-cancel-both' az (([] ∷ Type) ∷ Type) (([] ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, ()

bappTypeLem quotientInteger {as = as} .(bubble p) (app {az = az} p q x)
  with <>>-cancel-both' az (([] ∷ Term) ∷ Type) (([] ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, () 
bappTypeLem quotientInteger {as = as} .(bubble p) (app⋆ {az = az} p q q₁)
  with <>>-cancel-both' az (([] ∷ Type) ∷ Type) (([] ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, ()

bappTypeLem remainderInteger {as = as} .(bubble p) (app {az = az} p q x)
  with <>>-cancel-both' az (([] ∷ Term) ∷ Type) (([] ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, () 
bappTypeLem remainderInteger {as = as} .(bubble p) (app⋆ {az = az} p q q₁)
  with <>>-cancel-both' az (([] ∷ Type) ∷ Type) (([] ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, ()
bappTypeLem modInteger {as = as} .(bubble p) (app {az = az} p q x)
  with <>>-cancel-both' az (([] ∷ Term) ∷ Type) (([] ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, () 
bappTypeLem modInteger {as = as} .(bubble p) (app⋆ {az = az} p q q₁)
  with <>>-cancel-both' az (([] ∷ Type) ∷ Type) (([] ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, ()
bappTypeLem lessThanInteger {as = as} .(bubble p) (app {az = az} p q x)
  with <>>-cancel-both' az (([] ∷ Term) ∷ Type) (([] ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, () 
bappTypeLem lessThanInteger {as = as} .(bubble p) (app⋆ {az = az} p q q₁)
  with <>>-cancel-both' az (([] ∷ Type) ∷ Type) (([] ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, ()
bappTypeLem lessThanEqualsInteger {as = as} .(bubble p) (app {az = az} p q x)
  with <>>-cancel-both' az (([] ∷ Term) ∷ Type) (([] ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, () 
bappTypeLem lessThanEqualsInteger {as = as} .(bubble p) (app⋆ {az = az} p q q₁)
  with <>>-cancel-both' az (([] ∷ Type) ∷ Type) (([] ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, ()
bappTypeLem greaterThanInteger {as = as} .(bubble p) (app {az = az} p q x)
  with <>>-cancel-both' az (([] ∷ Term) ∷ Type) (([] ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, () 
bappTypeLem greaterThanInteger {as = as} .(bubble p) (app⋆ {az = az} p q q₁)
  with <>>-cancel-both' az (([] ∷ Type) ∷ Type) (([] ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, ()
bappTypeLem greaterThanEqualsInteger {as = as} .(bubble p) (app {az = az} p q x)
  with <>>-cancel-both' az (([] ∷ Term) ∷ Type) (([] ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, () 
bappTypeLem greaterThanEqualsInteger {as = as} .(bubble p) (app⋆ {az = az} p q q₁)
  with <>>-cancel-both' az (([] ∷ Type) ∷ Type) (([] ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, ()
bappTypeLem equalsInteger {as = as} .(bubble p) (app {az = az} p q x)
  with <>>-cancel-both' az (([] ∷ Term) ∷ Type) (([] ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, () 
bappTypeLem equalsInteger {as = as} .(bubble p) (app⋆ {az = az} p q q₁)
  with <>>-cancel-both' az (([] ∷ Type) ∷ Type) (([] ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, ()
bappTypeLem concatenate {as = as} .(bubble p) (app {az = az} p q x)
  with <>>-cancel-both' az (([] ∷ Term) ∷ Type) (([] ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, () 
bappTypeLem concatenate {as = as} .(bubble p) (app⋆ {az = az} p q q₁)
  with <>>-cancel-both' az (([] ∷ Type) ∷ Type) (([] ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, ()
bappTypeLem takeByteString {as = as} .(bubble p) (app {az = az} p q x)
  with <>>-cancel-both' az (([] ∷ Term) ∷ Type) (([] ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, () 
bappTypeLem takeByteString {as = as} .(bubble p) (app⋆ {az = az} p q q₁)
  with <>>-cancel-both' az (([] ∷ Type) ∷ Type) (([] ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, ()
bappTypeLem dropByteString {as = as} .(bubble p) (app {az = az} p q x)
  with <>>-cancel-both' az (([] ∷ Term) ∷ Type) (([] ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, () 
bappTypeLem dropByteString {as = as} .(bubble p) (app⋆ {az = az} p q q₁)
  with <>>-cancel-both' az (([] ∷ Type) ∷ Type) (([] ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, ()
bappTypeLem lessThanByteString {as = as} .(bubble p) (app {az = az} p q x)
  with <>>-cancel-both' az (([] ∷ Term) ∷ Type) (([] ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, () 
bappTypeLem lessThanByteString {as = as} .(bubble p) (app⋆ {az = az} p q q₁)
  with <>>-cancel-both' az (([] ∷ Type) ∷ Type) (([] ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, ()
bappTypeLem greaterThanByteString {as = as} .(bubble p) (app {az = az} p q x)
  with <>>-cancel-both' az (([] ∷ Term) ∷ Type) (([] ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, () 
bappTypeLem greaterThanByteString {as = as} .(bubble p) (app⋆ {az = az} p q q₁)
  with <>>-cancel-both' az (([] ∷ Type) ∷ Type) (([] ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, ()
bappTypeLem sha2-256 {az = az} {as} p q
  with <>>-cancel-both' az ([] ∷ Type) ([] ∷ Term) as p refl
... | refl ,, refl ,, ()
bappTypeLem sha3-256 {az = az} {as} p q
  with <>>-cancel-both' az ([] ∷ Type) ([] ∷ Term) as p refl
... | refl ,, refl ,, ()
bappTypeLem verifySignature {as = as} .(bubble (bubble p)) (app .(bubble p) (app {az = az} p q x) x')
  with <>>-cancel-both' az ((([] ∷ Term) ∷ Term) ∷ Type) ((([] ∷ Term) ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, ()
bappTypeLem verifySignature {as = as} .(bubble (bubble p)) (app .(bubble p) (app⋆ {az = az} p q q₁₁) x)
  with <>>-cancel-both' az ((([] ∷ Type) ∷ Term) ∷ Type) ((([] ∷ Term) ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, ()
bappTypeLem verifySignature {as = as} .(bubble (bubble p)) (app⋆ .(bubble p) (app {az = az} p q x₁) q₁) with <>>-cancel-both' az ((([] ∷ Term) ∷ Type) ∷ Type) ((([] ∷ Term) ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, ()
bappTypeLem verifySignature {as = as} .(bubble (bubble p)) (app⋆ .(bubble p) (app⋆ {az = az} p q q₂) q₁) with <>>-cancel-both' az ((([] ∷ Type) ∷ Type) ∷ Type) ((([] ∷ Term) ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, ()
bappTypeLem equalsByteString {as = as} .(bubble p) (app {az = az} p q x)
  with <>>-cancel-both' az (([] ∷ Term) ∷ Type) (([] ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, () 
bappTypeLem equalsByteString {as = as} .(bubble p) (app⋆ {az = az} p q q₁)
  with <>>-cancel-both' az (([] ∷ Type) ∷ Type) (([] ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, ()
bappTypeLem ifThenElse .(start (Type ∷ Term ∷ Term ∷ Term ∷ [])) base = _ ,, _ ,, refl
bappTypeLem ifThenElse {as = as} .(bubble (bubble (bubble p))) (app .(bubble (bubble p)) (app .(bubble p) (app {az = az} p q x₂) x₁) x)
  with <>>-cancel-both' az (((([] ∷ Term) ∷ Term) ∷ Term) ∷ Type) (((([] ∷ Type) ∷ Term) ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, ()
bappTypeLem ifThenElse {as = as} .(bubble (bubble (bubble p))) (app .(bubble (bubble p)) (app .(bubble p) (app⋆ {az = az} p q q₁₂) x₁) x) with <>>-cancel-both' az (((([] ∷ Type) ∷ Term) ∷ Term) ∷ Type) (((([] ∷ Type) ∷ Term) ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, ()
bappTypeLem ifThenElse {as = as} .(bubble (bubble (bubble p))) (app .(bubble (bubble p)) (app⋆ .(bubble p) (app {az = az} p q x₂) q₁₁) x) with <>>-cancel-both' az (((([] ∷ Term) ∷ Type) ∷ Term) ∷ Type) (((([] ∷ Type) ∷ Term) ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, ()
bappTypeLem ifThenElse {as = as} .(bubble (bubble (bubble p))) (app .(bubble (bubble p)) (app⋆ .(bubble p) (app⋆ {az = az} p q q₂) q₁) x)  with <>>-cancel-both' az (((([] ∷ Type) ∷ Type) ∷ Term) ∷ Type) (((([] ∷ Type) ∷ Term) ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, ()
bappTypeLem ifThenElse {as = as} .(bubble (bubble (bubble p))) (app⋆ .(bubble (bubble p)) (app .(bubble p) (app {az = az} p q x₂) x₁) q₁)  with <>>-cancel-both' az (((([] ∷ Term) ∷ Term) ∷ Type) ∷ Type) (((([] ∷ Type) ∷ Term) ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, ()
bappTypeLem ifThenElse {as = as} .(bubble (bubble (bubble p))) (app⋆ .(bubble (bubble p)) (app .(bubble p) (app⋆ {az = az} p q q₂) x₁) q₁)  with <>>-cancel-both' az (((([] ∷ Type) ∷ Term) ∷ Type) ∷ Type) (((([] ∷ Type) ∷ Term) ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, ()
bappTypeLem ifThenElse {as = as} .(bubble (bubble (bubble p))) (app⋆ .(bubble (bubble p)) (app⋆ .(bubble p) (app {az = az} p q x₂) q₂) q₁)  with <>>-cancel-both' az (((([] ∷ Term) ∷ Type) ∷ Type) ∷ Type) (((([] ∷ Type) ∷ Term) ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, ()
bappTypeLem ifThenElse {as = as} .(bubble (bubble (bubble p))) (app⋆ .(bubble (bubble p)) (app⋆ .(bubble p) (app⋆ {az = az} p q q₃) q₂) q₁) with <>>-cancel-both' az (((([] ∷ Type) ∷ Type) ∷ Type) ∷ Type) (((([] ∷ Type) ∷ Term) ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, ()
bappTypeLem charToString {az = az} {as} p q
  with <>>-cancel-both' az ([] ∷ Type) ([] ∷ Term) as p refl
... | refl ,, refl ,, ()
bappTypeLem append {as = as} .(bubble p) (app {az = az} p q x)
  with <>>-cancel-both' az (([] ∷ Term) ∷ Type) (([] ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, () 
bappTypeLem append {as = as} .(bubble p) (app⋆ {az = az} p q q₁)
  with <>>-cancel-both' az (([] ∷ Type) ∷ Type) (([] ∷ Term) ∷ Term) as p refl
... | refl ,, refl ,, ()
bappTypeLem trace {az = az} {as} p q
  with <>>-cancel-both' az ([] ∷ Type) ([] ∷ Term) as p refl
... | refl ,, refl ,, ()

V-I : ∀ b {A : ∅ ⊢Nf⋆ *}{a as as'}
       → (p : as <>> a ∷ as' ∈ arity b)
       → BAPP b p A
       → Value A
V-I b {a = Term} p q with bappTermLem b p q
... | _ ,, _ ,, refl = V-I⇒ b p q
V-I b {a = Type} p q  with bappTypeLem b p q
... | _ ,, _ ,, refl = V-IΠ b p q

data Frame : (T : ∅ ⊢Nf⋆ *) → (H : ∅ ⊢Nf⋆ *) → Set where
  -·     : ∀{Γ}{A B : ∅ ⊢Nf⋆ *} → Γ ⊢ A → Env Γ → Frame B (A ⇒ B)
  _·-     : {A B : ∅ ⊢Nf⋆ *} → Value (A ⇒ B) → Frame B A

  -·⋆     : ∀{K}{B : ∅ ,⋆ K ⊢Nf⋆ *}(A : ∅ ⊢Nf⋆ K)
    → Frame (B [ A ]Nf) (Π B)

  wrap-   : ∀{K}{A : ∅ ⊢Nf⋆ (K ⇒ *) ⇒ K ⇒ *}{B : ∅ ⊢Nf⋆ K}
    → Frame (μ A B)
            (nf (embNf A · ƛ (μ (embNf (weakenNf A)) (` Z)) · embNf B))
  unwrap- : ∀{K}{A : ∅ ⊢Nf⋆ (K ⇒ *) ⇒ K ⇒ *}{B : ∅ ⊢Nf⋆ K}
    → Frame (nf (embNf A · ƛ (μ (embNf (weakenNf A)) (` Z)) · embNf B))
            (μ A B)

data Stack (T : ∅ ⊢Nf⋆ *) : (H : ∅ ⊢Nf⋆ *) → Set where
  ε   : Stack T T
  _,_ : ∀{H1 H2} → Stack T H1 → Frame H1 H2 → Stack T H2

data State (T : ∅ ⊢Nf⋆ *) : Set where
  _;_▻_ : ∀{Γ}{H : ∅ ⊢Nf⋆ *} → Stack T H → Env Γ → Γ ⊢ H → State T
  _◅_ : {H : ∅ ⊢Nf⋆ *} → Stack T H → Value H → State T
  □     : Value T → State T
  ◆     : ∅ ⊢Nf⋆ * → State T



ival : ∀ b → Value (itype b)
ival addInteger = V-I⇒ addInteger _ base
ival subtractInteger = V-I⇒ subtractInteger _ base
ival multiplyInteger = V-I⇒ multiplyInteger _ base
ival divideInteger = V-I⇒ divideInteger _ base
ival quotientInteger = V-I⇒ quotientInteger _ base
ival remainderInteger = V-I⇒ remainderInteger _ base
ival modInteger = V-I⇒ modInteger _ base
ival lessThanInteger = V-I⇒ lessThanInteger _ base
ival lessThanEqualsInteger = V-I⇒ lessThanEqualsInteger _ base
ival greaterThanInteger = V-I⇒ greaterThanInteger _ base
ival greaterThanEqualsInteger = V-I⇒ greaterThanEqualsInteger _ base
ival equalsInteger = V-I⇒ equalsInteger _ base
ival concatenate = V-I⇒ concatenate _ base
ival takeByteString = V-I⇒ takeByteString _ base
ival dropByteString = V-I⇒ dropByteString _ base
ival lessThanByteString = V-I⇒ lessThanByteString _ base
ival greaterThanByteString = V-I⇒ greaterThanByteString _ base
ival sha2-256 = V-I⇒ sha2-256 _ base
ival sha3-256 = V-I⇒ sha3-256 _ base
ival verifySignature = V-I⇒ verifySignature _ base
ival equalsByteString = V-I⇒ equalsByteString _ base
ival ifThenElse = V-IΠ ifThenElse _ base
ival charToString = V-I⇒ charToString _ base
ival append = V-I⇒ append _ base
ival trace = V-I⇒ trace _ base

step : ∀{T} → State T → State T
step (s ; ρ ▻ ` x)             = s ◅ lookup x ρ
step (s ; ρ ▻ ƛ L)             = s ◅ V-ƛ L ρ
step (s ; ρ ▻ (L · M))         = (s , -· M ρ) ; ρ ▻ L
step (s ; ρ ▻ Λ L)             = s ◅ V-Λ L ρ
step (s ; ρ ▻ (L ·⋆ A))        = (s , -·⋆ A) ; ρ ▻ L
step (s ; ρ ▻ wrap A B L) = (s , wrap-) ; ρ ▻ L
step (s ; ρ ▻ unwrap L) = (s , unwrap-) ; ρ ▻ L
step (s ; ρ ▻ con c) = s ◅ V-con c
step (s ; ρ ▻ ibuiltin b) = s ◅ ival b
step (s ; ρ ▻ error A) = ◆ A
step (ε ◅ V) = □ V
step ((s , -· M ρ') ◅ V) = (s , V ·-) ; ρ' ▻ M
step ((s , (V-ƛ M ρ ·-)) ◅ V) = s ; ρ ∷ V ▻ M
step ((s , -·⋆ A) ◅ V-Λ M ρ) = s ; ρ ▻ (M [ A ]⋆)
step ((s , wrap- {A = A}{B = B}) ◅ V) = s ◅ V-wrap V
step ((s , unwrap-) ◅ V-wrap V) = s ◅ V
step ((s , (V-I⇒ b {as' = []} p vs ·-)) ◅ V)
  with BUILTIN' b (bubble p) (app p vs V)
... | inj₁ V = s ◅ V
... | inj₂ A = ◆ A
step ((s , (V-I⇒ b {as' = x₂ ∷ as'} p vs ·-)) ◅ V) =
  s ◅ V-I b (bubble p) (app p vs V)
step ((s , -·⋆ A) ◅ V-IΠ b {as' = []} p vs)
  with BUILTIN' b (bubble p) (app⋆ p vs refl)
... | inj₁ V = s ◅ V
... | inj₂ A = ◆ A
step ((s , -·⋆ A) ◅ V-IΠ b {as' = x₂ ∷ as'} p vs) =
  s ◅ V-I b (bubble p) (app⋆ p vs refl)
step (□ V) = □ V
step (◆ A) = ◆ A

open import Data.Nat

stepper : ℕ → ∀{T} → State T → Either RuntimeError (State T)
stepper zero st = inj₁ gasError
stepper (suc n) st with step st
stepper (suc n) st | (s ; ρ ▻ M) = stepper n (s ; ρ ▻ M)
stepper (suc n) st | (s ◅ V) = stepper n (s ◅ V)
stepper (suc n) st | (□ V)   = return (□ V)
stepper (suc n) st | ◆ A     = return (◆ A)

