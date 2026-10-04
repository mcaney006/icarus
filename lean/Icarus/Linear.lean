set_option autoImplicit false

namespace Icarus

abbrev Vec (n : Nat) := Fin n → Int
abbrev Mat (r c : Nat) := Fin r → Fin c → Int

namespace Vec
def zero (n : Nat) : Vec n := fun _ => 0
def add {n : Nat} (a b : Vec n) : Vec n := fun i => a i + b i
def sub {n : Nat} (a b : Vec n) : Vec n := fun i => a i - b i
def smul {n : Nat} (s : Int) (a : Vec n) : Vec n := fun i => s * a i
def neg {n : Nat} (a : Vec n) : Vec n := fun i => -a i
end Vec

namespace Mat
def zero (r c : Nat) : Mat r c := fun _ _ => 0
def id (n : Nat) : Mat n n := fun i j => if i = j then 1 else 0
def transpose {r c : Nat} (m : Mat r c) : Mat c r := fun j i => m i j

def sumFin : (n : Nat) → (Fin n → Int) → Int
  | 0, _ => 0
  | k + 1, f => sumFin k (fun i => f i.castSucc) + f (Fin.last k)

def mulVec {r c : Nat} (m : Mat r c) (v : Vec c) : Vec r := fun i => sumFin c fun j => m i j * v j

def mul {r c p : Nat} (a : Mat r c) (b : Mat c p) : Mat r p := fun i k => sumFin c fun j => a i j * b j k
end Mat

open Mat (sumFin)

theorem sumFin_zero (n : Nat) : sumFin n (fun _ => 0) = 0 := by
  induction n with
  | zero => rfl
  | succ k ih => simp [sumFin, ih]

theorem sumFin_add (n : Nat) (f g : Fin n → Int) : sumFin n (fun i => f i + g i) = sumFin n f + sumFin n g := by
  induction n with
  | zero => rfl
  | succ k ih => simp only [sumFin, ih fun i => f i.castSucc]; omega

theorem sumFin_sub (n : Nat) (f g : Fin n → Int) : sumFin n (fun i => f i - g i) = sumFin n f - sumFin n g := by
  induction n with
  | zero => rfl
  | succ k ih => simp only [sumFin, ih fun i => f i.castSucc]; omega

theorem sumFin_mul_left (n : Nat) (s : Int) (f : Fin n → Int) : s * sumFin n f = sumFin n (fun i => s * f i) := by
  induction n with
  | zero => simp [sumFin]
  | succ k ih => simp only [sumFin, Int.mul_add, ih fun i => f i.castSucc]

theorem sumFin_congr {n : Nat} {f g : Fin n → Int} (h : ∀ i, f i = g i) : sumFin n f = sumFin n g :=
  congrArg _ (funext h)

theorem sumFin_swap (n m : Nat) (f : Fin n → Fin m → Int) :
    sumFin n (fun i => sumFin m (f i)) = sumFin m (fun j => sumFin n (f · j)) := by
  induction n with
  | zero => simp [sumFin, sumFin_zero]
  | succ k ih => simp only [sumFin, ih fun i => f i.castSucc, ← sumFin_add]

theorem fin_split {k : Nat} (i : Fin (k + 1)) : (∃ j : Fin k, i = j.castSucc) ∨ i = Fin.last k :=
  if h : i.val < k then .inl ⟨⟨i.val, h⟩, rfl⟩ else .inr (Fin.ext (by simp [Fin.last]; omega))

theorem sumFin_unit (n : Nat) (v : Vec n) (i : Fin n) :
    sumFin n (fun j => (if i = j then (1 : Int) else 0) * v j) = v i := by
  induction n with
  | zero => exact i.elim0
  | succ k ih =>
    simp only [sumFin]
    rcases fin_split i with ⟨i, rfl⟩ | rfl
    · simpa [Fin.castSucc_inj, Fin.ne_of_lt (Fin.castSucc_lt_last i)] using ih (fun j => v j.castSucc) i
    · simp [Fin.ne_of_gt (Fin.castSucc_lt_last _), sumFin_zero]

theorem zero_mulVec {r c : Nat} (v : Vec c) : Mat.mulVec (Mat.zero r c) v = Vec.zero r := by
  funext i; simp [Mat.mulVec, Mat.zero, Vec.zero, sumFin_zero]

theorem mulVec_zero {r c : Nat} (m : Mat r c) : Mat.mulVec m (Vec.zero c) = Vec.zero r := by
  funext i; simp [Mat.mulVec, Vec.zero, sumFin_zero]

theorem mulVec_add_apply {r c : Nat} (m : Mat r c) (a b : Vec c) (i : Fin r) :
    Mat.mulVec m (Vec.add a b) i = Mat.mulVec m a i + Mat.mulVec m b i := by
  simp only [Mat.mulVec, Vec.add, ← sumFin_add, Int.mul_add]

theorem mulVec_sub_apply {r c : Nat} (m : Mat r c) (a b : Vec c) (i : Fin r) :
    Mat.mulVec m (Vec.sub a b) i = Mat.mulVec m a i - Mat.mulVec m b i := by
  simp only [Mat.mulVec, Vec.sub, ← sumFin_sub, Int.mul_sub]

theorem mulVec_sub {r c : Nat} (m : Mat r c) (a b : Vec c) :
    Mat.mulVec m (Vec.sub a b) = Vec.sub (Mat.mulVec m a) (Mat.mulVec m b) :=
  funext (mulVec_sub_apply m a b)

theorem id_mulVec (n : Nat) (v : Vec n) : Mat.mulVec (Mat.id n) v = v :=
  funext (sumFin_unit n v)

theorem mul_id_left (r c : Nat) (a : Mat r c) : Mat.mul (Mat.id r) a = a :=
  funext fun i => funext fun k => sumFin_unit r (a · k) i

theorem mul_zero_left {r c p : Nat} (b : Mat c p) : Mat.mul (Mat.zero r c) b = Mat.zero r p := by
  funext i k; simp [Mat.mul, Mat.zero, sumFin_zero]

theorem mul_zero_right {r c p : Nat} (a : Mat r c) : Mat.mul a (Mat.zero c p) = Mat.zero r p := by
  funext i k; simp [Mat.mul, Mat.zero, sumFin_zero]

theorem mul_assoc' {r c p q : Nat} (a : Mat r c) (b : Mat c p) (d : Mat p q) :
    Mat.mul (Mat.mul a b) d = Mat.mul a (Mat.mul b d) := by
  funext i l
  simp only [Mat.mul]
  rw [sumFin_congr fun k => (Int.mul_comm _ _).trans (sumFin_mul_left c (d k l) _),
      sumFin_congr fun j => sumFin_mul_left p (a i j) _, sumFin_swap]
  exact sumFin_congr fun j => sumFin_congr fun k => by
    rw [Int.mul_comm (d k l), Int.mul_assoc]

def plantStep {n m : Nat} (A : Mat n n) (B : Mat n m) (x : Vec n) (u : Vec m) (w : Vec n) : Vec n :=
  Vec.add (Vec.add (Mat.mulVec A x) (Mat.mulVec B u)) w

def measure {n p : Nat} (C : Mat p n) (x : Vec n) (v : Vec p) : Vec p :=
  Vec.add (Mat.mulVec C x) v

theorem plantStep_origin {n m : Nat} (A : Mat n n) (B : Mat n m) :
    plantStep A B (Vec.zero n) (Vec.zero m) (Vec.zero n) = Vec.zero n := by
  simp [plantStep, mulVec_zero]; rfl

end Icarus
