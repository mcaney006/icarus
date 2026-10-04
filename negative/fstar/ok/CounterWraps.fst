module CounterWraps
open Icarus.Counter

let good () : Lemma (None? (bump max_seq)) = ()
