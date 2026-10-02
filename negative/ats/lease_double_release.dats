(* EXPECT: no longer available|linear|cannot be assigned *)
(* Handing the same lease back twice duplicates a linear resource. *)
#include "share/atspre_staload.hats"
staload "./pool.sats"

fun bad (p: pool_vt(2, 1)): pool_vt(2, 1) = let
  val (p0, lease) = pool_take(p)
  val p1 = pool_give(p0, lease)
  val p2 = pool_give(p1, lease)
in p2 end

implement main0 () = ()
