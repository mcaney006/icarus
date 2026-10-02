(* EXPECT: unsolved constraint *)
(* Reading index 4 from a length 4 array: valid indices are 0..3. *)
#include "share/atspre_staload.hats"

fun bad (v: !arrayptr(double, 4)): double = arrayptr_get_at(v, 4)

implement main0 () = ()
