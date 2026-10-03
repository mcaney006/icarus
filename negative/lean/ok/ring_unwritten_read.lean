import Icarus.Ring
open Icarus.Ring
example : Nat := get (push (empty : Ring Nat 4) 7) 0 (by decide)
