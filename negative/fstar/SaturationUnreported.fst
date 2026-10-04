module SaturationUnreported
open Icarus.Sat

let bad () : Lemma ((add max_raw 1).v = max_raw + 1) = ()
