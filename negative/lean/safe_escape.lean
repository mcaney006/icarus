-- EXPECT: decide|evaluates to false|failed|rfl
-- Safe is absorbing: no trigger moves it to Running.
import Icarus.Modes
open Icarus
example : step Mode.safe Trigger.recover = Mode.running := by decide
