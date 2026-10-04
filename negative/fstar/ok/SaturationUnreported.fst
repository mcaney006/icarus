module SaturationUnreported
open Icarus.Sat

let good () : Lemma ((add max_raw 1).v = max_raw /\ (add max_raw 1).sat = true) = ()
