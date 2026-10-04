import Icarus.Linear
import Icarus.Numeric

set_option autoImplicit false

namespace Icarus

def control {n m : Nat} (K : Mat m n) (xhat : Vec n) (lim : Int) : Vec m :=
  fun i => Numeric.sat lim (-Mat.mulVec K xhat i)

theorem control_bounded {n m : Nat} (K : Mat m n) (xhat : Vec n) (lim : Int) (h : 0 ≤ lim) (i : Fin m) :
    -lim ≤ control K xhat lim i ∧ control K xhat lim i ≤ lim :=
  Numeric.sat_mem h

theorem control_idempotent {n m : Nat} (K : Mat m n) (xhat : Vec n) (lim : Int) (h : 0 ≤ lim) (i : Fin m) :
    Numeric.sat lim (control K xhat lim i) = control K xhat lim i :=
  Numeric.sat_idem h

def observe {n m p : Nat} (A : Mat n n) (B : Mat n m) (C : Mat p n) (L : Mat n p)
    (xhat : Vec n) (u : Vec m) (y : Vec p) : Vec n :=
  Vec.add (Vec.add (Mat.mulVec A xhat) (Mat.mulVec B u)) (Mat.mulVec L (Vec.sub y (Mat.mulVec C xhat)))

theorem observer_error {n m p : Nat} (A : Mat n n) (B : Mat n m) (C : Mat p n) (L : Mat n p)
    (x xhat : Vec n) (u : Vec m) :
    Vec.sub (observe A B C L xhat u (Mat.mulVec C x)) (plantStep A B x u (Vec.zero n))
      = Vec.sub (Mat.mulVec A (Vec.sub xhat x)) (Mat.mulVec L (Mat.mulVec C (Vec.sub xhat x))) := by
  simp only [observe, plantStep, mulVec_sub]
  funext i
  simp only [Vec.add, Vec.sub, Vec.zero]
  omega

end Icarus
