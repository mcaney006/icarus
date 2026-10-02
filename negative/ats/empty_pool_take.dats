(* EXPECT: unsolved constraint|mismatch|cannot be assigned *)
(* The pool owns one buffer; a second take with the first lease outstanding has
   no pool_vt(n, 1) to consume. *)
#include "share/atspre_staload.hats"
staload "./pool.sats"

fun bad (p: pool_vt(2, 1)): void = let
  val (p0, l0) = pool_take(p)
  val (p1, l1) = pool_take(p0)
  val p2 = pool_give(p1, l1)
  val p3 = pool_give(p2, l0)
in pool_free(p3) end

implement main0 () = ()
