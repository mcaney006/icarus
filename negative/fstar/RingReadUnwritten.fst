module RingReadUnwritten
open Icarus.Ring

let bad (r:ring int 4{r.len = 2}) : int = get r 3
