#include "share/atspre_staload.hats"
staload "./linear.sats"
staload "./pool.sats"
staload "./ring.sats"
staload "./mode.sats"

%{^
extern long icarus_alloc_calls(void);
%}
extern fun alloc_calls (): lint = "mac#icarus_alloc_calls"

val failures = ref<int>(0)

fun check (name: string, ok: bool): void =
  if ok then println! ("PASS ", name)
  else (println! ("FAIL ", name); !failures := !failures + 1)

fun feq (a: double, b: double): bool = let
  val d = (if a > b then a - b else b - a): double
in d < 1.0e-12 end

fun lease_cycle {k:nat} .<k>.
  (p: pool_vt(3, 1), k: int(k)): pool_vt(3, 1) =
  if k > 0 then let
    val (p0, lease) = pool_take(p)
    val () = arrayptr_set_at(lease, 0, 1.5)
    val x = arrayptr_get_at(lease, 0)
    val () = arrayptr_set_at(lease, 2, x + 1.0)
    val p1 = pool_give(p0, lease)
  in lease_cycle(p1, k - 1) end
  else p

fun push_n {k:nat} .<k>. (r: !ring_vt(4), k: int(k), v: int): void =
  if k > 0 then (ring_push(r, 4, v); push_n(r, k - 1, v + 1))

implement main0 () = let
  (* ---- matrix library ------------------------------------------------ *)
  val a = mat_make(2, 3)
  val () = (matrixptr_set_at(a, 0, 3, 0, 1.0); matrixptr_set_at(a, 0, 3, 1, 2.0); matrixptr_set_at(a, 0, 3, 2, 3.0))
  val () = (matrixptr_set_at(a, 1, 3, 0, 4.0); matrixptr_set_at(a, 1, 3, 1, 5.0); matrixptr_set_at(a, 1, 3, 2, 6.0))
  val b = mat_make(3, 2)
  val () = (matrixptr_set_at(b, 0, 2, 0, 7.0); matrixptr_set_at(b, 0, 2, 1, 8.0))
  val () = (matrixptr_set_at(b, 1, 2, 0, 9.0); matrixptr_set_at(b, 1, 2, 1, 10.0))
  val () = (matrixptr_set_at(b, 2, 2, 0, 11.0); matrixptr_set_at(b, 2, 2, 1, 12.0))
  val c = mat_make(2, 2)
  val () = matmul(c, a, b, 2, 3, 2)
  val c00 = matrixptr_get_at(c, 0, 2, 0)
  val c01 = matrixptr_get_at(c, 0, 2, 1)
  val c10 = matrixptr_get_at(c, 1, 2, 0)
  val c11 = matrixptr_get_at(c, 1, 2, 1)
  val () = check("matrix: 2x3 * 3x2 product",
    feq(c00, 58.0) && feq(c01, 64.0) && feq(c10, 139.0) && feq(c11, 154.0))
  val i3 = mat_make(3, 3)
  val () = identity(i3, 3)
  val ai = mat_make(2, 3)
  val () = matmul(ai, a, i3, 2, 3, 3)
  val ai12 = matrixptr_get_at(ai, 1, 3, 2)
  val ai01 = matrixptr_get_at(ai, 0, 3, 1)
  val () = check("matrix: right identity", feq(ai12, 6.0) && feq(ai01, 2.0))
  val at = mat_make(3, 2)
  val () = transpose(at, a, 2, 3)
  val att = mat_make(2, 3)
  val () = transpose(att, at, 3, 2)
  val att12 = matrixptr_get_at(att, 1, 3, 2)
  val at21 = matrixptr_get_at(at, 2, 2, 1)
  val () = check("matrix: transpose involution", feq(att12, 6.0) && feq(at21, 6.0))
  val v = vec_make(3)
  val () = (arrayptr_set_at(v, 0, 1.0); arrayptr_set_at(v, 2, 1.0))
  val mv = vec_make(2)
  val () = matvec(mv, a, v, 2, 3)
  val mv0 = arrayptr_get_at(mv, 0)
  val mv1 = arrayptr_get_at(mv, 1)
  val () = check("matrix: matvec", feq(mv0, 4.0) && feq(mv1, 10.0))
  val u = vec_make(3)
  val () = (arrayptr_set_at(u, 0, 3.0); arrayptr_set_at(u, 1, 4.0); arrayptr_set_at(u, 2, 12.0))
  val u2 = vec_make(3)
  val () = vcopy(u2, u, 3)
  val () = check("vector: dot", feq(dot(u, u2, 3), 169.0))
  val () = check("vector: norm2", feq(norm2(u, 3), 13.0))
  val s = vec_make(3)
  val () = vadd(s, u, v, 3)
  val sa0 = arrayptr_get_at(s, 0)
  val sa2 = arrayptr_get_at(s, 2)
  val () = check("vector: add", feq(sa0, 4.0) && feq(sa2, 13.0))
  val () = vsub(s, u, v, 3)
  val ss0 = arrayptr_get_at(s, 0)
  val ss2 = arrayptr_get_at(s, 2)
  val () = check("vector: sub", feq(ss0, 2.0) && feq(ss2, 11.0))
  val () = vscale(s, 2.0, u, 3)
  val sm1 = arrayptr_get_at(s, 1)
  val () = check("vector: scalar multiply", feq(sm1, 8.0))
  val () = vneg(s, u, 3)
  val sn2 = arrayptr_get_at(s, 2)
  val () = check("vector: negate", feq(sn2, ~12.0))
  val () = clamp_all(u, 3, 5.0)
  val cl0 = arrayptr_get_at(u, 0)
  val cl1 = arrayptr_get_at(u, 1)
  val cl2 = arrayptr_get_at(u, 2)
  val () = check("vector: clamp stays inside the interval",
    feq(cl0, 3.0) && feq(cl1, 4.0) && feq(cl2, 5.0))
  val () = (matrixptr_free(a); matrixptr_free(b); matrixptr_free(c); matrixptr_free(i3); matrixptr_free(ai))
  val () = (matrixptr_free(at); matrixptr_free(att))
  val () = (arrayptr_free(v); arrayptr_free(mv); arrayptr_free(u); arrayptr_free(u2); arrayptr_free(s))

  (* ---- pool: leases are linear and the cycle never allocates ---------- *)
  val p = pool_make(3)
  val before = alloc_calls()
  val p = lease_cycle(p, 1000)
  val after = alloc_calls()
  val () = check("pool: 1000 take/give cycles allocate nothing", before = after)
  val () = pool_free(p)

  (* ---- ring ----------------------------------------------------------- *)
  val r = ring_make(4)
  val () = check("ring: empty has length 0", ring_len(r) = 0)
  val () = check("ring: empty refuses reads", ring_peek(r, 4, 0) = ~1)
  val () = push_n(r, 6, 4)
  val () = check("ring: length saturates at capacity", ring_len(r) = 4)
  val () = check("ring: newest is last push", ring_peek(r, 4, 0) = 9)
  val () = check("ring: third newest", ring_peek(r, 4, 2) = 7)
  val () = check("ring: oldest retained", ring_peek(r, 4, 3) = 6)
  val () = check("ring: age at capacity refused", ring_peek(r, 4, 4) = ~1)
  val () = check("ring: negative age refused", ring_peek(r, 4, ~1) = ~1)
  val () = ring_free(r)

  (* ---- modes ---------------------------------------------------------- *)
  val (_ | a1) = decide_mode(3, 0, false, 0, 0)
  val () = check("mode: Ready engages", a1 = 4)
  val (_ | a2) = decide_mode(4, 3, false, 0, 0)
  val () = check("mode: Running + Unsafe -> Safe", a2 = 6)
  val (_ | a3) = decide_mode(4, 1, true, 0, 0)
  val () = check("mode: overrun degrades", a3 = 5)
  val (_ | a4) = decide_mode(5, 0, false, 2, 0)
  val () = check("mode: third healthy frame recovers", a4 = 4)
  val (_ | a5) = decide_mode(5, 1, false, 0, 2)
  val () = check("mode: repeated bad frames -> Safe", a5 = 6)
  val (_ | a6) = decide_mode(6, 0, false, 9, 0)
  val () = check("mode: Safe absorbs", a6 = 6)
  val () = check("health: numeric dominates", classify(31) = 3)
  val () = check("health: two flags degraded", classify(3) = 2)
  val () = check("health: none healthy", classify(0) = 0)
  val () = check("health: one flag suspect", classify(8) = 1)

  val n = !failures
  val () = if n = 0 then println! ("selftest: all checks passed")
           else println! ("selftest: ", n, " FAILED")
in
  if n > 0 then exit(1)
end
