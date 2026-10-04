import Icarus.Ring
open Icarus
example : Nat := (Ring.empty : Ring Nat 4).get 0 (by decide)
