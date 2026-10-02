module RingReadUnwritten
open Icarus.Ring

let good (r:ring int 4{r.len = 2}) : int = get r 1
