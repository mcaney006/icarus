#include "share/atspre_staload.hats"
staload "./mode.sats"

fun bad (): [m1:nat | m1 <= 7] (LEGAL(6, m1) | int(m1)) =
  (LEGAL_DEGRADED_RUNNING() | 4)

implement main0 () = ()
