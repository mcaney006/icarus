/-
Dimension-indexed linear algebra over Int, in Lean. Vectors and matrices are
functions out of `Fin n` so a size mismatch is not a runtime condition but a
type error. Integer entries are deliberate: they model the fixed-point
representation exactly, so every statement here is about the arithmetic the
fixed-point implementations actually perform. Mirrors the matvec/vadd helpers in
reference/icarus_ref.py.
-/
set_option autoImplicit false
set_option maxRecDepth 4000

namespace Icarus

abbrev Vec (n : Nat) := Fin n → Int
abbrev Mat (r c : Nat) := Fin r → Fin c → Int

namespace Vec
def zero (n : Nat) : Vec n := fun _ => 0
def add {n : Nat} (a b : Vec n) : Vec n := fun i => a i + b i
def sub {n : Nat} (a b : Vec n) : Vec n := fun i => a i - b i
def smul {n : Nat} (s : Int) (a : Vec n) : Vec n := fun i => s * a i
def neg {n : Nat} (a : Vec n) : Vec n := fun i => - a i
end Vec

namespace Mat
def zero (r c : Nat) : Mat r c := fun _ _ => 0
def id (n : Nat) : Mat n n := fun i j => if i = j then 1 else 0
def transpose {r c : Nat} (m : Mat r c) : Mat c r := fun j i => m i j

/-- Sum of `f 0 + ... + f (n-1)`, structural so `simp`/`decide` can reduce it. -/
def sumFin : (n : Nat) → (Fin n → Int) → Int
  | 0,     _ => 0
  | k + 1, f => sumFin k (fun i => f i.castSucc) + f (Fin.last k)

/-- Matrix–vector product; the type fixes the result at `Vec r`. -/
def mulVec {r c : Nat} (m : Mat r c) (v : Vec c) : Vec r :=
  fun i => sumFin c (fun j => m i j * v j)

/-- Matrix–matrix product; inner dimension `c` must agree, result is `Mat r p`. -/
def mul {r c p : Nat} (a : Mat r c) (b : Mat c p) : Mat r p :=
  fun i k => sumFin c (fun j => a i j * b j k)
end Mat

theorem sumFin_zero (n : Nat) : Mat.sumFin n (fun _ => 0) = 0 := by
  induction n with
  | zero => rfl
  | succ k ih => simp [Mat.sumFin, ih]

/-- `A x` always has exactly `r` components, whatever `A`, `x` are. -/
theorem mulVec_dim {r c : Nat} (m : Mat r c) (v : Vec c) :
    ∃ w : Vec r, Mat.mulVec m v = w := ⟨_, rfl⟩

theorem zero_mulVec {r c : Nat} (v : Vec c) :
    Mat.mulVec (Mat.zero r c) v = Vec.zero r := by
  funext i; simp [Mat.mulVec, Mat.zero, Vec.zero, sumFin_zero]

theorem mulVec_zero {r c : Nat} (m : Mat r c) :
    Mat.mulVec m (Vec.zero c) = Vec.zero r := by
  funext i; simp [Mat.mulVec, Vec.zero, sumFin_zero]

/-- Identity is a left unit on vectors: `I x = x`. Proved on concrete dimensions
used by the toy plant; the general-n statement is recorded as unproved in PROOFS.md. -/
theorem id_mulVec_4 (v : Vec 4) : Mat.mulVec (Mat.id 4) v = v := by
  funext i
  match i with
  | ⟨0, _⟩ => simp +decide [Mat.mulVec, Mat.id, Mat.sumFin, Fin.last, Fin.ext_iff]
  | ⟨1, _⟩ => simp +decide [Mat.mulVec, Mat.id, Mat.sumFin, Fin.last, Fin.ext_iff]
  | ⟨2, _⟩ => simp +decide [Mat.mulVec, Mat.id, Mat.sumFin, Fin.last, Fin.ext_iff]
  | ⟨3, _⟩ => simp +decide [Mat.mulVec, Mat.id, Mat.sumFin, Fin.last, Fin.ext_iff]

theorem id_mulVec_2 (v : Vec 2) : Mat.mulVec (Mat.id 2) v = v := by
  funext i
  match i with
  | ⟨0, _⟩ => simp +decide [Mat.mulVec, Mat.id, Mat.sumFin, Fin.last, Fin.ext_iff]
  | ⟨1, _⟩ => simp +decide [Mat.mulVec, Mat.id, Mat.sumFin, Fin.last, Fin.ext_iff]

/-- The abstract plant: x⁺ = A x + B u + w. All three dimensions are in the type. -/
def plantStep {n m : Nat} (A : Mat n n) (B : Mat n m)
    (x : Vec n) (u : Vec m) (w : Vec n) : Vec n :=
  Vec.add (Vec.add (Mat.mulVec A x) (Mat.mulVec B u)) w

/-- Synthetic measurement: y = C x + v. -/
def measure {n p : Nat} (C : Mat p n) (x : Vec n) (v : Vec p) : Vec p :=
  Vec.add (Mat.mulVec C x) v

/-- Zero input, zero disturbance, zero state is a fixed point of any plant. -/
theorem plantStep_origin {n m : Nat} (A : Mat n n) (B : Mat n m) :
    plantStep A B (Vec.zero n) (Vec.zero m) (Vec.zero n) = Vec.zero n := by
  funext i; simp [plantStep, Vec.add, mulVec_zero, Vec.zero]

end Icarus
