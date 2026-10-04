import Icarus.Numeric
example : ([120, 80, 220, 180, 160, 90, 50] : List Nat).sum ≤ Icarus.Numeric.frameBudget := by decide
