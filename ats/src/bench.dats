(* Microbenchmarks of the runtime's building blocks and of the frame loop. Prints
   CSV rows: language, operation, iterations, nanoseconds, allocator calls. The
   checksum line keeps every result observable so no loop can be discarded. *)
#include "share/atspre_staload.hats"
staload "./linear.sats"
staload "./ring.sats"
staload "./mode.sats"
staload "./fixture.sats"
staload "./sim.sats"

%{^
extern long icarus_alloc_calls(void);
extern long icarus_now_ns(void);
%}
extern fun alloc_calls (): lint = "mac#icarus_alloc_calls"
extern fun now_ns (): lint = "mac#icarus_now_ns"

fun row (name: string, iters: int, ns: lint, allocs: lint): void =
  println! ("ats,", name, ",", iters, ",", ns, ",", allocs)

fun fill {n:nat} {i:nat | i <= n} .<n-i>.
  (v: !arrayptr(double, n), n: int(n), i: int(i), base: double): void =
  if i < n then (arrayptr_set_at(v, i, base + g0int2float_int_double(i)); fill(v, n, i + 1, base))

fun fill_m {r,c:nat} (m: !matrixptr(double, r, c), r: int(r), c: int(c), base: double): void = let
  fun rows {i:nat | i <= r} .<r-i>. (m: !matrixptr(double, r, c), i: int(i)): void =
    if i < r then let
      fun cols {j:nat | j <= c} .<c-j>. (m: !matrixptr(double, r, c), j: int(j)): void =
        if j < c then
          (matrixptr_set_at(m, i, c, j, base / (1.0 + g0int2float_int_double(i + j))); cols(m, j + 1))
    in cols(m, 0); rows(m, i + 1) end
in rows(m, 0) end

fun loop_vadd (o: !arrayptr(double, 4), a: !arrayptr(double, 4), b: !arrayptr(double, 4), k: int): void =
  if k > 0 then (vadd(o, a, b, 4); vcopy(a, o, 4); loop_vadd(o, a, b, k - 1))

fun loop_dot (a: !arrayptr(double, 4), b: !arrayptr(double, 4), k: int, acc: double): double =
  if k > 0 then loop_dot(a, b, k - 1, acc + dot(a, b, 4)) else acc

fun loop_matvec (o: !arrayptr(double, 4), m: !matrixptr(double, 4, 4), v: !arrayptr(double, 4), k: int): void =
  if k > 0 then (matvec(o, m, v, 4, 4); vcopy(v, o, 4); loop_matvec(o, m, v, k - 1))

fun loop_matmul (o: !matrixptr(double, 4, 4), a: !matrixptr(double, 4, 4), b: !matrixptr(double, 4, 4), k: int): void =
  if k > 0 then (matmul(o, a, b, 4, 4, 4); loop_matmul(o, a, b, k - 1))

fun loop_ring (r: !ring_vt(16), k: int, acc: int): int =
  if k > 0 then (ring_push(r, 16, k); loop_ring(r, k - 1, (acc + ring_peek(r, 16, 3)) mod 1000003)) else acc

fun mode_of (m: int): [m1:nat | m1 <= 7] int(m1) = let val c1 = g1ofg0(m) in
  if c1 >= 0 then (if c1 <= 7 then c1 else 6) else 6 end

fun loop_decide (k: int, m: int, acc: int): int =
  if k > 0 then let
    val (_ | m1) = decide_mode(mode_of(m), k mod 4, (k mod 7) = 0, k mod 5, k mod 3)
    val next = (if m1 = 6 then 3 else m1): int
  in loop_decide(k - 1, next, acc + m1) end
  else acc

#define NV 10000000
#define NM 1000000

implement main0 (argc, argv) = let
  val a = vec_make(4)
  val b = vec_make(4)
  val o = vec_make(4)
  val () = (fill(a, 4, 0, 1.0e-9); fill(b, 4, 0, 1.0e-9))
  val m = mat_make(4, 4)
  val m2 = mat_make(4, 4)
  val mo = mat_make(4, 4)
  val () = (fill_m(m, 4, 4, 0.25); fill_m(m2, 4, 4, 0.5))
  val r = ring_make(16)

  val a0 = alloc_calls() val t0 = now_ns()
  val () = loop_vadd(o, a, b, NV)
  val t1 = now_ns() val a1 = alloc_calls()
  val () = row("vadd4", NV, t1 - t0, a1 - a0)

  val a0 = alloc_calls() val t0 = now_ns()
  val d = loop_dot(a, b, NV, 0.0)
  val t1 = now_ns() val a1 = alloc_calls()
  val () = row("dot4", NV, t1 - t0, a1 - a0)

  val a0 = alloc_calls() val t0 = now_ns()
  val () = loop_matvec(o, m, a, NV)
  val t1 = now_ns() val a1 = alloc_calls()
  val () = row("matvec4x4", NV, t1 - t0, a1 - a0)

  val a0 = alloc_calls() val t0 = now_ns()
  val () = loop_matmul(mo, m, m2, NM)
  val t1 = now_ns() val a1 = alloc_calls()
  val () = row("matmul4x4", NM, t1 - t0, a1 - a0)

  val a0 = alloc_calls() val t0 = now_ns()
  val rs = loop_ring(r, NV, 0)
  val t1 = now_ns() val a1 = alloc_calls()
  val () = row("ring_push_peek", NV, t1 - t0, a1 - a0)

  val a0 = alloc_calls() val t0 = now_ns()
  val ms = loop_decide(NV, 3, 0)
  val t1 = now_ns() val a1 = alloc_calls()
  val () = row("mode_decide", NV, t1 - t0, a1 - a0)

  val () =
    if argc >= 3 then let
      val opt = load_fixture(argv[1])
      val reps = g0string2int(argv[2])
    in
      case+ opt of
      | ~None_vt() => prerrln! ("bench: fixture rejected")
      | ~Some_vt(cfg) => let
          val steps = (let val @CFG(_, _, _, _, _, _, _, _, s, _) = cfg val v = s prval () = fold@(cfg) in v end): int
          val @(ns, al) = sim_bench(cfg, reps)
          val () = row("frame", reps * steps, ns, al)
        in cfg_free(cfg) end
    end

  val o0 = arrayptr_get_at(o, 0)
  val mo0 = matrixptr_get_at(mo, 0, 4, 0)
  val () = println! ("checksum,", o0 + d + mo0, ",", rs + ms)
in
  arrayptr_free(a); arrayptr_free(b); arrayptr_free(o);
  matrixptr_free(m); matrixptr_free(m2); matrixptr_free(mo); ring_free(r)
end
