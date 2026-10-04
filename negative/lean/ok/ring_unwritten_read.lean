import Icarus.Ring
open Icarus
example : Nat := ((Ring.empty : Ring Nat 4).push 7).get 0 (by decide)
