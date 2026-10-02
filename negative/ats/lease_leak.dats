(* EXPECT: linear|abandoned|not consumed *)
(* A lease that is never handed back is a leaked resource. *)
#include "share/atspre_staload.hats"
staload "./pool.sats"

fun bad (p: pool_vt(2, 1)): void = let
  val (p0, lease) = pool_take(p)
  val () = arrayptr_set_at(lease, 0, 1.0)
  val p1 = p0
in pool_free(p1) end

implement main0 () = ()
