-- EXPECT: decide|evaluates to false|failed
-- Boot to Running is not in the legal table.
import Icarus.Modes
open Icarus
example : legal Mode.boot Mode.running = true := by decide
