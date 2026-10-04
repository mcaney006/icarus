#include "share/atspre_staload.hats"
staload "./mode.sats"

fun good (): [m1:nat | m1 <= 7] (LEGAL(6, m1) | int(m1)) =
  (LEGAL_STAY() | 6)

implement main0 () = ()
