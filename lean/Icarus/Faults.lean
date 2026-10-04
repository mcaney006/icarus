set_option autoImplicit false

namespace Icarus

inductive FaultKind
  | measurementDropout | staleMeasurement | biasedMeasurement | stuckChannel
  | outOfRange | timingOverrun | numericSaturation | corruptFixture
  | estimatorDisagreement | controlSaturation
deriving DecidableEq, Repr

inductive Health
  | healthy | suspect | degraded | unsafe_
deriving DecidableEq, Repr

structure Flags where
  meas : Bool
  est : Bool
  timing : Bool
  ctrlSat : Bool
  numeric : Bool
deriving DecidableEq, Repr

namespace Flags

def none : Flags := ⟨false, false, false, false, false⟩

def bits (f : Flags) : List Bool := [f.meas, f.est, f.timing, f.ctrlSat, f.numeric]

def count (f : Flags) : Nat := f.bits.count true

def mask (f : Flags) : Nat := f.bits.foldr (fun b acc => b.toNat + 2 * acc) 0

def ofMask (m : Nat) : Flags := ⟨m.testBit 0, m.testBit 1, m.testBit 2, m.testBit 3, m.testBit 4⟩

def le (f g : Flags) : Prop := ∀ p ∈ f.bits.zip g.bits, p.1 → p.2

end Flags

export Flags (ofMask)

def classify (f : Flags) : Health :=
  if f.numeric then .unsafe_ else if 2 ≤ f.count then .degraded else if f.count = 1 then .suspect else .healthy

theorem numeric_dominates (f : Flags) (h : f.numeric) : classify f = .unsafe_ := by
  simp [classify, h]

theorem no_flags_healthy : classify Flags.none = .healthy := rfl

theorem count_le : ∀ (xs ys : List Bool), xs.length = ys.length →
    (∀ p ∈ xs.zip ys, p.1 → p.2) → xs.count true ≤ ys.count true
  | [], [], _, _ => Nat.le_refl 0
  | x :: xs, y :: ys, hl, h => by
    have tail := count_le xs ys (by simpa using hl) fun p hp => h p (List.mem_cons_of_mem _ hp)
    have head := h (x, y) List.mem_cons_self
    cases x <;> cases y <;> simp_all <;> try omega

theorem classify_monotone (f g : Flags) (h : f.le g) : (classify f).ctorIdx ≤ (classify g).ctorIdx := by
  have hc : f.count ≤ g.count := count_le f.bits g.bits rfl h
  have hn : f.numeric → g.numeric := h (f.numeric, g.numeric) (by simp [Flags.bits])
  unfold classify
  repeat' split
  all_goals first | decide | (simp_all <;> omega)

theorem mask_roundtrip : ∀ m : Fin 32, (ofMask m).mask = m := by decide

end Icarus
