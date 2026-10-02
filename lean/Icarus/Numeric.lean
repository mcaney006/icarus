/-
Numeric invariants proved over ℤ: the saturation / normalization clamp always
lands in its interval, is identity inside the interval, and is idempotent; the
timing stage budgets fit the frame, and enlarging a stage past the margin is
detectably infeasible. Mirrors the CTRL_LIMIT / MEAS_LIMIT / budget constants in
reference/icarus_ref.py.
-/
namespace Icarus.Numeric

def sat (lim x : Int) : Int :=
  if x < -lim then -lim else if lim < x then lim else x

theorem sat_lb {lim x : Int} (h : 0 ≤ lim) : -lim ≤ sat lim x := by
  unfold sat; split
  · omega
  · split <;> omega

theorem sat_ub {lim x : Int} (h : 0 ≤ lim) : sat lim x ≤ lim := by
  unfold sat; split
  · omega
  · split <;> omega

theorem sat_mem {lim x : Int} (h : 0 ≤ lim) : -lim ≤ sat lim x ∧ sat lim x ≤ lim :=
  ⟨sat_lb h, sat_ub h⟩

theorem sat_id {lim x : Int} (h1 : -lim ≤ x) (h2 : x ≤ lim) : sat lim x = x := by
  unfold sat; split
  · omega
  · split <;> omega

theorem sat_idem {lim x : Int} (h : 0 ≤ lim) : sat lim (sat lim x) = sat lim x :=
  let m := sat_mem h; sat_id m.1 m.2

/-- Abstract actuator interval [-1,1] (scaled to integers by the fixed-point scale). -/
def ctrlLimit : Int := 1
theorem control_in_interval (x : Int) : -1 ≤ sat ctrlLimit x ∧ sat ctrlLimit x ≤ 1 :=
  sat_mem (by decide)

def stageBudgets : List Nat := [120, 80, 220, 180, 160, 90, 50]
def frameBudget : Nat := 1000

theorem budget_fits : stageBudgets.sum ≤ frameBudget := by decide
theorem budget_margin : frameBudget - stageBudgets.sum = 100 := by decide

/-- Enlarging a stage beyond the 100-tick margin makes the frame infeasible. -/
theorem budget_overflow {extra : Nat} (h : 100 < extra) :
    ¬ (stageBudgets.sum + extra ≤ frameBudget) := by
  have hs : stageBudgets.sum = 900 := by decide
  rw [hs]; unfold frameBudget; omega

example : ¬ (([120,80,400,180,160,90,50] : List Nat).sum ≤ frameBudget) := by decide

end Icarus.Numeric
