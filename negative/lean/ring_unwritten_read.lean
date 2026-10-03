-- EXPECT: decide|evaluates to false|failed
-- A fresh ring has length 0, so no age satisfies the read precondition.
import Icarus.Ring
open Icarus.Ring
example : Nat := get (empty : Ring Nat 4) 0 (by decide)
