#include "share/atspre_staload.hats"
staload "./pool.sats"

fun good (p: pool_vt(2, 1)): void = let
  val (p0, lease) = pool_take(p)
  val () = arrayptr_set_at(lease, 0, 1.0)
  val p1 = pool_give(p0, lease)
in pool_free(p1) end

implement main0 () = ()
