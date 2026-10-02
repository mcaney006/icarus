(* EXPECT: unsolved constraint|mismatch|cannot be assigned *)
(* Safe (6) to Running (4) has no LEGAL constructor: Degraded to Running is 5 to 4. *)
#include "share/atspre_staload.hats"
staload "./mode.sats"

fun bad (): [m1:nat | m1 <= 7] (LEGAL(6, m1) | int(m1)) =
  (LEGAL_DEGRADED_RUNNING() | 4)

implement main0 () = ()
