import Icarus.Controller
open Icarus
example {n m : Nat} (K : Mat m n) (x : Vec n) (i : Fin m) : control K x 1 i < 1 :=
  (control_bounded K x 1 (by decide) i).2
