#include "share/atspre_staload.hats"
staload "./pool.sats"

fun good (p: pool_vt(2, 1)): pool_vt(2, 1) = let
  val (p0, lease) = pool_take(p)
in pool_give(p0, lease) end

implement main0 () = ()
