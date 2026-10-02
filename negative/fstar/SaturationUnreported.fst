(* EXPECT: Subtyping check failed|Assertion failed|could not prove *)
(* Adding one to the largest representable value does not produce max_raw + 1;
   it saturates, so the claimed exact result is false. *)
module SaturationUnreported
open Icarus.Sat

let bad () : Lemma ((add max_raw 1).v = max_raw + 1) = ()
