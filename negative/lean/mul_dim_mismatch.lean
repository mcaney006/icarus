-- EXPECT: [Tt]ype mismatch|application type mismatch
-- Multiplying a 4x3 matrix by a 2x4 matrix.
import Icarus.Linear
open Icarus
example (a : Mat 4 3) (b : Mat 2 4) : Mat 4 4 := Mat.mul a b
