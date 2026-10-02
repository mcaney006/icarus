#define ATS_DYNLOADFLAG 0
#include "share/atspre_staload.hats"
staload "./ring.sats"

datavtype ring_(cap:int) =
  | {cap:pos} RING(cap) of (arrayptr(int, cap), [h:nat | h < cap] int(h), [l:nat | l <= cap] int(l))

assume ring_vt(cap) = ring_(cap)

implement ring_make {cap} (cap) =
  RING(arrayptr_make_elt<int>(i2sz(cap), 0), 0, 0)

implement ring_push {cap} (r, cap, x) = let
  val @RING(buf, head, len) = r
  val h = head
  val () = arrayptr_set_at(buf, h, x)
  val h1 = h + 1
  val () = head := ((if h1 < cap then h1 else 0): [h2:nat | h2 < cap] int(h2))
  val l = len
  val () = len := ((if l < cap then l + 1 else cap): [l2:nat | l2 <= cap] int(l2))
  prval () = fold@(r)
in end

implement ring_len {cap} (r) = let
  val @RING(buf, head, len) = r
  val l = len
  prval () = fold@(r)
in l end

(* Ages are measured back from the newest write. Both index expressions are linear
   in head, cap and age, so the solver proves them in range without a modulus. *)
implement ring_peek {cap} (r, cap, age) = let
  val @RING(buf, head, len) = r
  val h = head
  val l = len
  val a = g1ofg0(age)
  val res =
    if a >= 0 then
      (if a < l then
         (if h >= a + 1 then arrayptr_get_at(buf, h - 1 - a)
          else arrayptr_get_at(buf, h + cap - 1 - a))
       else ~1)
    else ~1
  prval () = fold@(r)
in res end

implement ring_free {cap} (r) = let
  val ~RING(buf, head, len) = r
in arrayptr_free(buf) end
