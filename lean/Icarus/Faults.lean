/-
Fault model and health classification. Faults are typed values, never strings.
`Flags` is the five-source summary the health monitor consumes; `Health` is its
deterministic classification. Mirrors reference/icarus_ref.py and
fstar/src/Icarus.Health.fst.
-/
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

def b2n (b : Bool) : Nat := if b then 1 else 0

def Flags.count (f : Flags) : Nat :=
  b2n f.meas + b2n f.est + b2n f.timing + b2n f.ctrlSat + b2n f.numeric

def classify (f : Flags) : Health :=
  if f.numeric then Health.unsafe_
  else if 2 ≤ f.count then Health.degraded
  else if f.count = 1 then Health.suspect
  else Health.healthy

def Health.rank : Health → Nat
  | .healthy => 0 | .suspect => 1 | .degraded => 2 | .unsafe_ => 3

/-- Wire encoding shared with the ICF fixtures: meas 1, est 2, timing 4, ctrl 8, numeric 16. -/
def Flags.mask (f : Flags) : Nat :=
  b2n f.meas + 2 * b2n f.est + 4 * b2n f.timing + 8 * b2n f.ctrlSat + 16 * b2n f.numeric

def ofMask (m : Nat) : Flags :=
  { meas := m % 2 == 1, est := m / 2 % 2 == 1, timing := m / 4 % 2 == 1
    ctrlSat := m / 8 % 2 == 1, numeric := m / 16 % 2 == 1 }

theorem numeric_dominates (f : Flags) (h : f.numeric = true) : classify f = Health.unsafe_ := by
  simp [classify, h]

theorem no_flags_healthy : classify ⟨false, false, false, false, false⟩ = Health.healthy := by decide

/-- Raising a flag never lowers the reported health. -/
def Flags.le (f g : Flags) : Prop :=
  (f.meas = true → g.meas = true) ∧ (f.est = true → g.est = true) ∧
  (f.timing = true → g.timing = true) ∧ (f.ctrlSat = true → g.ctrlSat = true) ∧
  (f.numeric = true → g.numeric = true)

theorem classify_monotone (f g : Flags) (h : f.le g) :
    (classify f).rank ≤ (classify g).rank := by
  obtain ⟨a, b, c, d, e⟩ := h
  rcases f with ⟨f1, f2, f3, f4, f5⟩
  rcases g with ⟨g1, g2, g3, g4, g5⟩
  cases f1 <;> cases f2 <;> cases f3 <;> cases f4 <;> cases f5 <;>
  cases g1 <;> cases g2 <;> cases g3 <;> cases g4 <;> cases g5 <;>
  simp_all [classify, Flags.count, b2n, Health.rank]

/-- The mask encoding round-trips for every in-range mask. -/
theorem mask_roundtrip : ∀ m : Fin 32, (ofMask m.val).mask = m.val := by decide

end Icarus
