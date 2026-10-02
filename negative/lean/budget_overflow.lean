-- EXPECT: decide|evaluates to false|failed
-- Enlarging the Estimate stage to 400 ticks makes the schedule exceed the 1000 tick frame.
import Icarus.Numeric
example : ([120, 80, 400, 180, 160, 90, 50] : List Nat).sum ≤ Icarus.Numeric.frameBudget := by decide
