set_option autoImplicit false

namespace Icarus.Numeric

def sat (lim x : Int) : Int := max (-lim) (min lim x)

theorem sat_mem {lim x : Int} (h : 0 ≤ lim) : -lim ≤ sat lim x ∧ sat lim x ≤ lim := by
  unfold sat; omega

theorem sat_lb {lim x : Int} (h : 0 ≤ lim) : -lim ≤ sat lim x := (sat_mem h).1
theorem sat_ub {lim x : Int} (h : 0 ≤ lim) : sat lim x ≤ lim := (sat_mem h).2

theorem sat_id {lim x : Int} (h₁ : -lim ≤ x) (h₂ : x ≤ lim) : sat lim x = x := by
  unfold sat; omega

theorem sat_idem {lim x : Int} (h : 0 ≤ lim) : sat lim (sat lim x) = sat lim x :=
  sat_id (sat_lb h) (sat_ub h)

def ctrlLimit : Int := 1

theorem control_in_interval (x : Int) : -1 ≤ sat ctrlLimit x ∧ sat ctrlLimit x ≤ 1 :=
  sat_mem (by decide)

def stageBudgets : List Nat := [120, 80, 220, 180, 160, 90, 50]
def frameBudget : Nat := 1000

theorem budget_fits : stageBudgets.sum ≤ frameBudget := by decide
theorem budget_margin : frameBudget - stageBudgets.sum = 100 := by decide

theorem budget_overflow {extra : Nat} (h : 100 < extra) : ¬ stageBudgets.sum + extra ≤ frameBudget := by
  simp only [show stageBudgets.sum = 900 by decide, frameBudget]; omega

theorem estimate_at_400_overflows : ¬ ([120, 80, 400, 180, 160, 90, 50] : List Nat).sum ≤ frameBudget := by
  decide

end Icarus.Numeric
