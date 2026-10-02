#include "share/atspre_staload.hats"
staload "./pool.sats"

fun good (p: pool_vt(2, 1)): void = let
  val (p0, l0) = pool_take(p)
  val p1 = pool_give(p0, l0)
  val (p2, l1) = pool_take(p1)
  val p3 = pool_give(p2, l1)
in pool_free(p3) end

implement main0 () = ()
