import Icarus.Numeric
example : ([120, 80, 400, 180, 160, 90, 50] : List Nat).sum ≤ Icarus.Numeric.frameBudget := by decide
