-- EXPECT: [Tt]ype mismatch|application type mismatch
-- A 4x3 matrix applied to a length-2 vector.
import Icarus.Linear
open Icarus
example (m : Mat 4 3) (v : Vec 2) : Vec 4 := Mat.mulVec m v
