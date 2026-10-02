(* EXPECT: Subtyping check failed|Assertion failed|could not prove *)
(* A sequence number at its limit must report exhaustion, not wrap to zero. *)
module CounterWraps
open Icarus.Counter

let bad () : Lemma (bump max_seq = Some 0) = ()
