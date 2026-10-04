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

#define VECTOR_OPS 10000000
#define MATRIX_OPS 1000000
#define READY 3
#define SAFE 6

typedef probe = @(lint, lint)

fun probe_start (): probe = @(alloc_calls(), now_ns())

fun probe_report (name: string, iterations: int, since: probe): void = let
  val elapsed = now_ns() - since.1
  val allocated = alloc_calls() - since.0
in println! ("ats,", name, ",", iterations, ",", elapsed, ",", allocated) end

fun ramp {n:nat} {i:nat | i <= n} .<n-i>. (v: !arrayptr(double, n), n: int(n), i: int(i), base: double): void =
  if i < n then (arrayptr_set_at(v, i, base + g0int2float_int_double(i)); ramp(v, n, i + 1, base))

fun hilbert {r,c:nat} (m: !matrixptr(double, r, c), r: int(r), c: int(c), base: double): void = let
  fun rows {i:nat | i <= r} .<r-i>. (m: !matrixptr(double, r, c), i: int(i)): void =
    if i < r then let
      fun columns {j:nat | j <= c} .<c-j>. (m: !matrixptr(double, r, c), j: int(j)): void =
        if j < c then (matrixptr_set_at(m, i, c, j, base / (1.0 + g0int2float_int_double(i + j))); columns(m, j + 1))
    in columns(m, 0); rows(m, i + 1) end
in rows(m, 0) end

fun vadd_loop {k:nat} .<k>. (out: !arrayptr(double, 4), a: !arrayptr(double, 4), b: !arrayptr(double, 4), k: int(k)): void =
  if k > 0 then (vadd(out, a, b, 4); vcopy(a, out, 4); vadd_loop(out, a, b, k - 1))

fun dot_loop {k:nat} .<k>. (a: !arrayptr(double, 4), b: !arrayptr(double, 4), k: int(k), acc: double): double =
  if k > 0 then dot_loop(a, b, k - 1, acc + dot(a, b, 4)) else acc

fun matvec_loop {k:nat} .<k>. (out: !arrayptr(double, 4), m: !matrixptr(double, 4, 4), v: !arrayptr(double, 4), k: int(k)): void =
  if k > 0 then (matvec(out, m, v, 4, 4); vcopy(v, out, 4); matvec_loop(out, m, v, k - 1))

fun matmul_loop {k:nat} .<k>. (out: !matrixptr(double, 4, 4), a: !matrixptr(double, 4, 4), b: !matrixptr(double, 4, 4), k: int(k)): void =
  if k > 0 then (matmul(out, a, b, 4, 4, 4); matmul_loop(out, a, b, k - 1))

fun ring_loop {k:nat} .<k>. (r: !ring_vt(16), k: int(k), acc: int): int =
  if k > 0 then (ring_push(r, 16, k); ring_loop(r, k - 1, (acc + ring_peek(r, 16, 3)) mod 1000003)) else acc

fun decide_loop {k:nat} .<k>. (k: int(k), current: natLte(7), acc: int): int =
  if k > 0 then let
    val (_ | after) = decide_mode(current, k mod 4, k mod 7 = 0, k mod 5, k mod 3)
  in decide_loop(k - 1, (if after = SAFE then READY else after): natLte(7), acc + after) end
  else acc

fun frame_bench (path: string, repetitions: int): void =
  case+ load_fixture(path) of
  | ~None_vt() => prerrln! ("bench: fixture rejected")
  | ~Some_vt(cfg) => let
      val @(elapsed, allocated) = sim_bench(cfg, repetitions)
      val () = println! ("ats,frame,", repetitions * cfg_steps(cfg), ",", elapsed, ",", allocated)
    in cfg_free(cfg) end

implement main0 (argc, argv) = let
  val a = vec_make(4)
  val b = vec_make(4)
  val out = vec_make(4)
  val () = (ramp(a, 4, 0, 1.0e-9); ramp(b, 4, 0, 1.0e-9))
  val m = mat_make(4, 4)
  val m2 = mat_make(4, 4)
  val product = mat_make(4, 4)
  val () = (hilbert(m, 4, 4, 0.25); hilbert(m2, 4, 4, 0.5))
  val history = ring_make(16)

  val since = probe_start()
  val () = vadd_loop(out, a, b, VECTOR_OPS)
  val () = probe_report("vadd4", VECTOR_OPS, since)

  val since = probe_start()
  val dots = dot_loop(a, b, VECTOR_OPS, 0.0)
  val () = probe_report("dot4", VECTOR_OPS, since)

  val since = probe_start()
  val () = matvec_loop(out, m, a, VECTOR_OPS)
  val () = probe_report("matvec4x4", VECTOR_OPS, since)

  val since = probe_start()
  val () = matmul_loop(product, m, m2, MATRIX_OPS)
  val () = probe_report("matmul4x4", MATRIX_OPS, since)

  val since = probe_start()
  val ring_sum = ring_loop(history, VECTOR_OPS, 0)
  val () = probe_report("ring_push_peek", VECTOR_OPS, since)

  val since = probe_start()
  val mode_sum = decide_loop(VECTOR_OPS, READY, 0)
  val () = probe_report("mode_decide", VECTOR_OPS, since)

  val () = if argc >= 3 then frame_bench(argv[1], g0string2int(argv[2]))

  val first = arrayptr_get_at(out, 0)
  val corner = matrixptr_get_at(product, 0, 4, 0)
  val () = println! ("checksum,", first + dots + corner, ",", ring_sum + mode_sum)
in
  arrayptr_free(a); arrayptr_free(b); arrayptr_free(out);
  matrixptr_free(m); matrixptr_free(m2); matrixptr_free(product); ring_free(history)
end
