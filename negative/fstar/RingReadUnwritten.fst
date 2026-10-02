(* EXPECT: Subtyping check failed|Assertion failed|could not prove *)
(* Reading age 3 from a ring holding only two entries would return an unwritten slot. *)
module RingReadUnwritten
open Icarus.Ring

let bad (r:ring int 4{r.len = 2}) : int = get r 3
