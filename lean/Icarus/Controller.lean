/-
Controller and estimator specifications for the abstract plant, over Int (the
exact model of the fixed-point arithmetic). Nothing here is tuned to a physical
system; K and L are arbitrary matrices of the right shape. The theorems are
about this model only.
-/
import Icarus.Linear
import Icarus.Numeric
set_option autoImplicit false

namespace Icarus

/-- u = sat(-K x̂): every actuator-like component is clamped to the abstract interval. -/
def control {n m : Nat} (K : Mat m n) (xhat : Vec n) (lim : Int) : Vec m :=
  fun i => Numeric.sat lim (-(Mat.mulVec K xhat i))

/-- The control output lies inside [-lim, lim] for every state estimate and every gain. -/
theorem control_bounded {n m : Nat} (K : Mat m n) (xhat : Vec n) (lim : Int) (h : 0 ≤ lim)
    (i : Fin m) : -lim ≤ control K xhat lim i ∧ control K xhat lim i ≤ lim :=
  Numeric.sat_mem h

/-- Saturation is idempotent: re-clamping an already-clamped control changes nothing. -/
theorem control_idempotent {n m : Nat} (K : Mat m n) (xhat : Vec n) (lim : Int) (h : 0 ≤ lim)
    (i : Fin m) : Numeric.sat lim (control K xhat lim i) = control K xhat lim i :=
  Numeric.sat_idem h

/-- Luenberger observer: x̂⁺ = A x̂ + B u + L (y − C x̂). Dimensions n, m, p are in the types,
so an estimator for (n, p) cannot be given a measurement of any other size. -/
def observe {n m p : Nat} (A : Mat n n) (B : Mat n m) (C : Mat p n) (L : Mat n p)
    (xhat : Vec n) (u : Vec m) (y : Vec p) : Vec n :=
  Vec.add (Vec.add (Mat.mulVec A xhat) (Mat.mulVec B u))
    (Mat.mulVec L (Vec.sub y (Mat.mulVec C xhat)))

/-- With no disturbance or noise the estimation error obeys e⁺ = (A − L C) e, whatever the
control input u: the input cancels exactly. -/
theorem observer_error {n m p : Nat} (A : Mat n n) (B : Mat n m) (C : Mat p n) (L : Mat n p)
    (x xhat : Vec n) (u : Vec m) :
    Vec.sub (observe A B C L xhat u (Mat.mulVec C x)) (plantStep A B x u (Vec.zero n))
      = Vec.sub (Mat.mulVec A (Vec.sub xhat x))
                (Mat.mulVec L (Mat.mulVec C (Vec.sub xhat x))) := by
  funext i
  have e1 : Mat.mulVec A (Vec.sub xhat x) i = Mat.mulVec A xhat i - Mat.mulVec A x i :=
    mulVec_sub_apply A xhat x i
  have e2 : ∀ q : Fin p, Mat.mulVec C (Vec.sub xhat x) q = Mat.mulVec C xhat q - Mat.mulVec C x q :=
    fun q => mulVec_sub_apply C xhat x q
  have e3 : Mat.mulVec L (Mat.mulVec C (Vec.sub xhat x)) i
      = Mat.mulVec L (fun q => Mat.mulVec C xhat q - Mat.mulVec C x q) i := by
    have : Mat.mulVec C (Vec.sub xhat x) = fun q => Mat.mulVec C xhat q - Mat.mulVec C x q :=
      funext e2
    rw [this]
  have e4 : Mat.mulVec L (Vec.sub (Mat.mulVec C x) (Mat.mulVec C xhat)) i
      = Mat.mulVec L (Mat.mulVec C x) i - Mat.mulVec L (Mat.mulVec C xhat) i :=
    mulVec_sub_apply L (Mat.mulVec C x) (Mat.mulVec C xhat) i
  have e5 : Mat.mulVec L (fun q => Mat.mulVec C xhat q - Mat.mulVec C x q) i
      = Mat.mulVec L (Mat.mulVec C xhat) i - Mat.mulVec L (Mat.mulVec C x) i :=
    mulVec_sub_apply L (Mat.mulVec C xhat) (Mat.mulVec C x) i
  simp only [observe, plantStep, Vec.add, Vec.sub, Vec.zero] at *
  omega

end Icarus
