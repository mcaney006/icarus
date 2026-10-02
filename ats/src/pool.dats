#define ATS_DYNLOADFLAG 0
#include "share/atspre_staload.hats"
staload UN = "prelude/SATS/unsafe.sats"
staload "./pool.sats"

(* Trusted kernel: the pool is a raw pointer that is the buffer while one slot is
   free and null while it is leased. The availability index is enforced entirely
   by the signatures in pool.sats; these four bodies are the only unsafe casts. *)
assume pool_vt(n, avail) = ptr

implement pool_make {n} (n) =
  $UN.castvwtp0{ptr}(arrayptr_make_elt<double>(i2sz(n), 0.0))

implement pool_take {n} (p) =
  @($UN.cast{ptr}(0), $UN.castvwtp0{arrayptr(double, n)}(p))

implement pool_give {n} (p, lease) = $UN.castvwtp0{ptr}(lease)

implement pool_free {n} (p) =
  arrayptr_free($UN.castvwtp0{arrayptr(double, n)}(p))
