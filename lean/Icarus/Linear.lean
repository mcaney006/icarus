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



/-! ### Finite-sum lemmas, proved from scratch (no Mathlib) -/

theorem sumFin_add (n : Nat) (f g : Fin n → Int) :
    Mat.sumFin n (fun i => f i + g i) = Mat.sumFin n f + Mat.sumFin n g := by
  induction n with
  | zero => rfl
  | succ k ih =>
    simp only [Mat.sumFin]
    rw [ih (fun i => f i.castSucc) (fun i => g i.castSucc)]
    omega

theorem sumFin_sub (n : Nat) (f g : Fin n → Int) :
    Mat.sumFin n (fun i => f i - g i) = Mat.sumFin n f - Mat.sumFin n g := by
  induction n with
  | zero => rfl
  | succ k ih =>
    simp only [Mat.sumFin]
    rw [ih (fun i => f i.castSucc) (fun i => g i.castSucc)]
    omega

theorem sumFin_mul_left (n : Nat) (s : Int) (f : Fin n → Int) :
    s * Mat.sumFin n f = Mat.sumFin n (fun i => s * f i) := by
  induction n with
  | zero => simp [Mat.sumFin]
  | succ k ih =>
    simp only [Mat.sumFin]
    rw [Int.mul_add, ih (fun i => f i.castSucc)]

theorem sumFin_congr (n : Nat) (f g : Fin n → Int) (h : ∀ i, f i = g i) :
    Mat.sumFin n f = Mat.sumFin n g := by
  have : f = g := funext h
  rw [this]

/-- Matrix–vector product distributes over vector subtraction and addition. -/
theorem mulVec_sub_apply {r c : Nat} (m : Mat r c) (a b : Vec c) (i : Fin r) :
    Mat.mulVec m (fun j => a j - b j) i = Mat.mulVec m a i - Mat.mulVec m b i := by
  simp only [Mat.mulVec]
  rw [← sumFin_sub]
  exact sumFin_congr c _ _ (fun j => by rw [Int.mul_sub])

theorem mulVec_add_apply {r c : Nat} (m : Mat r c) (a b : Vec c) (i : Fin r) :
    Mat.mulVec m (fun j => a j + b j) i = Mat.mulVec m a i + Mat.mulVec m b i := by
  simp only [Mat.mulVec]
  rw [← sumFin_add]
  exact sumFin_congr c _ _ (fun j => by rw [Int.mul_add])

/-- A zero matrix times anything, and anything times a zero vector, is zero (general n). -/
theorem mul_zero_left {r c p : Nat} (b : Mat c p) :
    Mat.mul (Mat.zero r c) b = Mat.zero r p := by
  funext i k; simp [Mat.mul, Mat.zero, sumFin_zero]

theorem mul_zero_right {r c p : Nat} (a : Mat r c) :
    Mat.mul a (Mat.zero c p) = Mat.zero r p := by
  funext i k; simp [Mat.mul, Mat.zero, sumFin_zero]

/-- The product of an r×c and a c×p matrix is r×p: the type says so, and the entry
formula is exactly the inner sum over the shared dimension c. -/
theorem mul_entry {r c p : Nat} (a : Mat r c) (b : Mat c p) (i : Fin r) (k : Fin p) :
    Mat.mul a b i k = Mat.sumFin c (fun j => a i j * b j k) := rfl

/-! ### Identity (general n) and associativity -/

theorem sumFin_swap (n m : Nat) (f : Fin n → Fin m → Int) :
    Mat.sumFin n (fun i => Mat.sumFin m (fun j => f i j))
      = Mat.sumFin m (fun j => Mat.sumFin n (fun i => f i j)) := by
  induction n with
  | zero => simp [Mat.sumFin, sumFin_zero]
  | succ k ih =>
    simp only [Mat.sumFin]
    rw [ih (fun i j => f i.castSucc j)]
    rw [← sumFin_add]

theorem fin_split {k : Nat} (i : Fin (k + 1)) :
    (∃ i' : Fin k, i = i'.castSucc) ∨ i = Fin.last k := by
  by_cases h : i.val < k
  · exact Or.inl ⟨⟨i.val, h⟩, Fin.ext rfl⟩
  · refine Or.inr (Fin.ext ?_)
    have := i.isLt
    simp [Fin.last]
    omega

/-- Summing `ite (i = j) 1 0 * v j` over j picks out `v i`. -/
theorem sumFin_unit (n : Nat) (v : Vec n) (i : Fin n) :
    Mat.sumFin n (fun j => (if i = j then (1 : Int) else 0) * v j) = v i := by
  induction n with
  | zero => exact i.elim0
  | succ k ih =>
    simp only [Mat.sumFin]
    rcases fin_split i with ⟨i', hi⟩ | hi
    · subst hi
      have h1 : ∀ j : Fin k, (if i'.castSucc = j.castSucc then (1 : Int) else 0) = (if i' = j then 1 else 0) := by
        intro j; simp [Fin.castSucc_inj]
      have h2 : (if i'.castSucc = Fin.last k then (1 : Int) else 0) = 0 := by
        simp [Fin.ne_of_lt (Fin.castSucc_lt_last i')]
      rw [h2]
      have := ih (fun j => v j.castSucc) i'
      simp only [h1]
      simpa using this
    · subst hi
      have h1 : ∀ j : Fin k, (if Fin.last k = j.castSucc then (1 : Int) else 0) = 0 := by
        intro j; simp [Fin.ne_of_gt (Fin.castSucc_lt_last j)]
      simp [h1, sumFin_zero]

theorem id_mulVec (n : Nat) (v : Vec n) : Mat.mulVec (Mat.id n) v = v := by
  funext i
  simp only [Mat.mulVec, Mat.id]
  exact sumFin_unit n v i

theorem mul_id_left (r c : Nat) (a : Mat r c) : Mat.mul (Mat.id r) a = a := by
  funext i k
  simp only [Mat.mul, Mat.id]
  exact sumFin_unit r (fun j => a j k) i

/-- Associativity of matrix multiplication, for compatible dimensions. -/
theorem mul_assoc' {r c p q : Nat} (a : Mat r c) (b : Mat c p) (d : Mat p q) :
    Mat.mul (Mat.mul a b) d = Mat.mul a (Mat.mul b d) := by
  funext i l
  simp only [Mat.mul]
  have lhs : ∀ k : Fin p,
      (Mat.sumFin c fun j => a i j * b j k) * d k l
        = Mat.sumFin c (fun j => a i j * b j k * d k l) := by
    intro k
    rw [Int.mul_comm, sumFin_mul_left]
    exact sumFin_congr c _ _ (fun j => by rw [Int.mul_comm, Int.mul_assoc])
  have rhs : ∀ j : Fin c,
      a i j * (Mat.sumFin p fun k => b j k * d k l)
        = Mat.sumFin p (fun k => a i j * b j k * d k l) := by
    intro j
    rw [sumFin_mul_left]
    exact sumFin_congr p _ _ (fun k => by rw [Int.mul_assoc])
  rw [sumFin_congr p _ _ lhs, sumFin_congr c _ _ rhs]
  exact (sumFin_swap p c (fun k j => a i j * b j k * d k l))

end Icarus
