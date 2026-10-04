module CounterWraps
open Icarus.Counter

let bad () : Lemma (bump max_seq = Some 0) = ()
