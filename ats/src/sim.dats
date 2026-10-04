#define ATS_DYNLOADFLAG 0
#include "share/atspre_staload.hats"
staload "./linear.sats"
staload "./pool.sats"
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

#define MEAS_LIMIT 50.0
#define INNOV_THRESH 10.0
#define STATE_BOUND 1000.0
#define CTRL_LIMIT 1.0
#define DEGRADED_CTRL 0.5
#define STUCK_VALUE 7.0
#define EXCEEDANCE 1.0e-12
#define NOMINAL_FRAME_COST 900
#define FRAME_BUDGET 1000
#define READY 3
#define RUNNING 4
#define DEGRADED 5
#define HEALTHY 0
#define MEAS 1
#define ESTIMATOR 2
#define TIMING 4
#define CTRL_SAT 8
#define NUMERIC 16
#define STALE 32
#define MEASUREMENT_DROPOUT 0
#define STALE_MEASUREMENT 1
#define BIASED_MEASUREMENT 2
#define STUCK_CHANNEL 3
#define OUT_OF_RANGE 4
#define TIMING_OVERRUN 5
#define NUMERIC_SATURATION 6
#define ESTIMATOR_DISAGREEMENT 8
#define CONTROL_SATURATION 9
#define NO_FAULT ~1

typedef mode = natLte(7)

fun dabs (x: double): double = if x < 0.0 then ~x else x
fun dmin (a: double, b: double): double = if b < a then b else a
fun dmax (a: double, b: double): double = if b > a then b else a
fun median3 (a: double, b: double, c: double): double = dmax(dmin(a, b), dmin(dmax(a, b), c))

fun has (events: int, bit: int): bool = (events / bit) mod 2 = 1
fun with_bit (events: int, bit: int): int = if has(events, bit) then events else events + bit
fun bit_if (raised: bool, bit: int): int = if raised then bit else 0

fun any_exceeding {n:nat} {i:nat | i <= n} .<n-i>. (v: !arrayptr(double, n), n: int(n), i: int(i), limit: double): bool =
  if i < n then (if dabs(arrayptr_get_at(v, i)) > limit then true else any_exceeding(v, n, i + 1, limit)) else false

fun any_out_of_range {n:nat} {i:nat | i <= n} .<n-i>. (v: !arrayptr(double, n), n: int(n), i: int(i), bound: double): bool =
  if i < n then (if dabs(arrayptr_get_at(v, i)) <= bound then any_out_of_range(v, n, i + 1, bound) else true) else false

fun hold_if {n:nat} {i:nat | i <= n} .<n-i>.
  (y: !arrayptr(double, n), held: !arrayptr(double, n), n: int(n), i: int(i), hold: bool): void =
  if i < n then let
    val previous = arrayptr_get_at(held, i)
    val sampled = arrayptr_get_at(y, i)
  in arrayptr_set_at(y, i, (if hold then previous else sampled): double); hold_if(y, held, n, i + 1, hold) end

fun zero_unless {n:nat} {i:nat | i <= n} .<n-i>. (u: !arrayptr(double, n), n: int(n), i: int(i), keep: bool): void =
  if i < n then let val x = arrayptr_get_at(u, i) in arrayptr_set_at(u, i, (if keep then x else 0.0): double); zero_unless(u, n, i + 1, keep) end

fun vote {i:nat | i <= 2} .<2-i>.
  (y: !arrayptr(double, 2), c0: !arrayptr(double, 2), c1: !arrayptr(double, 2), c2: !arrayptr(double, 2), i: int(i)): void =
  if i < 2 then let
    val a = arrayptr_get_at(c0, i)
    val b = arrayptr_get_at(c1, i)
    val c = arrayptr_get_at(c2, i)
  in arrayptr_set_at(y, i, median3(a, b, c)); vote(y, c0, c1, c2, i + 1) end

fun load_columns {first,width:nat | first + width <= 6} {r:nat | r < STEP_CAPACITY} {j:nat | j <= width} .<width-j>.
  (table: !matrixptr(double, STEP_CAPACITY, 6), r: int(r), first: int(first), width: int(width),
   out: !arrayptr(double, width), j: int(j)): void =
  if j < width then (arrayptr_set_at(out, j, matrixptr_get_at(table, r, 6, first + j)); load_columns(table, r, first, width, out, j + 1))

fun inject
  (kind: int, chosen: lane, param: double, events: int,
   c0: !arrayptr(double, 2), c1: !arrayptr(double, 2), c2: !arrayptr(double, 2), held: !arrayptr(double, 2)): int = let
  val current = arrayptr_get_at(c0, chosen)
  val previous = arrayptr_get_at(held, chosen)
  val dropout = kind = MEASUREMENT_DROPOUT
  val first = (if kind = BIASED_MEASUREMENT then current + param
               else if kind = STUCK_CHANNEL then STUCK_VALUE
               else if kind = OUT_OF_RANGE then param
               else if dropout then previous
               else current): double
  val second = arrayptr_get_at(c1, chosen)
  val third = arrayptr_get_at(c2, chosen)
  val () = arrayptr_set_at(c0, chosen, first)
  val () = arrayptr_set_at(c1, chosen, (if dropout then previous else second): double)
  val () = arrayptr_set_at(c2, chosen, (if dropout then previous else third): double)
in
  if kind = MEASUREMENT_DROPOUT orelse kind = BIASED_MEASUREMENT orelse kind = STUCK_CHANNEL orelse kind = OUT_OF_RANGE
  then with_bit(events, MEAS)
  else if kind = STALE_MEASUREMENT then with_bit(events, STALE)
  else if kind = NUMERIC_SATURATION then with_bit(events, NUMERIC)
  else if kind = ESTIMATOR_DISAGREEMENT then with_bit(events, ESTIMATOR)
  else if kind = CONTROL_SATURATION then with_bit(events, CTRL_SAT)
  else events
end

fun inject_all {j:nat | j <= FAULT_CAPACITY} .<FAULT_CAPACITY-j>.
  (steps: !arrayptr(int, FAULT_CAPACITY), kinds: !arrayptr(fault_kind, FAULT_CAPACITY),
   lanes: !arrayptr(lane, FAULT_CAPACITY), params: !arrayptr(double, FAULT_CAPACITY),
   count: fault_count, frame: int, j: int(j), events: int,
   c0: !arrayptr(double, 2), c1: !arrayptr(double, 2), c2: !arrayptr(double, 2), held: !arrayptr(double, 2)): int =
  if j < FAULT_CAPACITY then let
    val step = arrayptr_get_at(steps, j)
    val kind = arrayptr_get_at<fault_kind>(kinds, j)
    val chosen = arrayptr_get_at<lane>(lanes, j)
    val param = arrayptr_get_at(params, j)
    val live = j < count andalso step = frame
    val events = inject((if live then kind else NO_FAULT): int, chosen, param, events, c0, c1, c2, held)
  in inject_all(steps, kinds, lanes, params, count, frame, j + 1, events, c0, c1, c2, held) end
  else events

fun overrun_at {j:nat | j <= FAULT_CAPACITY} .<FAULT_CAPACITY-j>.
  (steps: !arrayptr(int, FAULT_CAPACITY), kinds: !arrayptr(fault_kind, FAULT_CAPACITY),
   params: !arrayptr(double, FAULT_CAPACITY), count: fault_count, frame: int, j: int(j)): int =
  if j < FAULT_CAPACITY then let
    val step = arrayptr_get_at(steps, j)
    val kind = arrayptr_get_at<fault_kind>(kinds, j)
    val ticks = arrayptr_get_at(params, j)
  in
    if j < count andalso step = frame andalso kind = TIMING_OVERRUN then g0float2int_double_int(ticks)
    else overrun_at(steps, kinds, params, count, frame, j + 1)
  end
  else NO_FAULT

datavtype st_vt =
  | ST of (
      arrayptr(double, 4), arrayptr(double, 4), arrayptr(double, 2), arrayptr(double, 2),
      arrayptr(double, 4), arrayptr(double, 2),
      arrayptr(double, 2), arrayptr(double, 2), arrayptr(double, 2),
      arrayptr(double, 4), arrayptr(double, 4), arrayptr(double, 4), arrayptr(double, 2), arrayptr(double, 2),
      mode, int, int, ring_vt(4),
      arrayptr(int, STEP_CAPACITY + 1), arrayptr(int, STEP_CAPACITY), arrayptr(int, STEP_CAPACITY))

fun st_make (x0: !arrayptr(double, 4)): st_vt = let
  val x = vec_make(4)
  val () = vcopy(x, x0, 4)
in
  ST(x, vec_make(4), vec_make(2), vec_make(2), vec_make(4), vec_make(2),
     vec_make(2), vec_make(2), vec_make(2), vec_make(4), vec_make(4), vec_make(4), vec_make(2), vec_make(2),
     READY, 0, 0, ring_make(4),
     arrayptr_make_elt<int>(i2sz(STEP_CAPACITY + 1), 0), arrayptr_make_elt<int>(i2sz(STEP_CAPACITY), 0),
     arrayptr_make_elt<int>(i2sz(STEP_CAPACITY), 0))
end

fun st_free (s: st_vt): void = let
  val ~ST(x, xhat, u_prev, held, w, v, c0, c1, c2, s1, s2, s3, feedback, predicted, _, _, _, history, modes, healths, masks) = s
in
  arrayptr_free(x); arrayptr_free(xhat); arrayptr_free(u_prev); arrayptr_free(held); arrayptr_free(w); arrayptr_free(v);
  arrayptr_free(c0); arrayptr_free(c1); arrayptr_free(c2); arrayptr_free(s1); arrayptr_free(s2); arrayptr_free(s3);
  arrayptr_free(feedback); arrayptr_free(predicted); ring_free(history);
  arrayptr_free(modes); arrayptr_free(healths); arrayptr_free(masks)
end

fun do_frame {k:nat | k < STEP_CAPACITY}
  (cfg: !cfg_vt, st: !st_vt, k: int(k), y: !arrayptr(double, 2), u: !arrayptr(double, 2), innovation: !arrayptr(double, 2))
  : void = let
  val @CFG(a, b, c, gain, observer, table, _, fault_steps, fault_kinds, fault_lanes, fault_params, _, fault_count) = cfg
  val @ST(x, xhat, u_prev, held, w, v, c0, c1, c2, s1, s2, s3, feedback, predicted,
          current, healthy, bad, history, modes, healths, masks) = st
  val before = current

  val () = load_columns(table, k, 0, 4, w, 0)
  val () = load_columns(table, k, 4, 2, v, 0)
  val () = matvec(c0, c, x, 2, 4)
  val () = vadd(c1, c0, v, 2)
  val () = vcopy(c0, c1, 2)
  val () = vcopy(c2, c1, 2)
  val events = inject_all(fault_steps, fault_kinds, fault_lanes, fault_params, fault_count, k, 0, 0, c0, c1, c2, held)
  val () = vote(y, c0, c1, c2, 0)
  val stale = has(events, STALE)
  val () = hold_if(y, held, 2, 0, stale)

  val out_of_band = any_exceeding(y, 2, 0, MEAS_LIMIT + EXCEEDANCE)
  val () = clamp_all(y, 2, MEAS_LIMIT)
  val () = vcopy(held, y, 2)

  val () = matvec(predicted, c, xhat, 2, 4)
  val () = vsub(innovation, y, predicted, 2)
  val disagreeing = norm2(innovation, 2) > INNOV_THRESH
  val () = matvec(s1, a, xhat, 4, 4)
  val () = matvec(s2, b, u_prev, 4, 2)
  val () = vadd(s3, s1, s2, 4)
  val () = matvec(s2, observer, innovation, 4, 2)
  val () = vadd(xhat, s3, s2, 4)

  val overrun = overrun_at(fault_steps, fault_kinds, fault_params, fault_count, k, 0)
  val miss = overrun >= 0 andalso NOMINAL_FRAME_COST + overrun > FRAME_BUDGET

  val active = before = RUNNING orelse before = DEGRADED
  val limit = (if before = DEGRADED then DEGRADED_CTRL else CTRL_LIMIT): double
  val () = matvec(feedback, gain, xhat, 2, 4)
  val () = vneg(u, feedback, 2)
  val saturating = any_exceeding(u, 2, 0, limit + EXCEEDANCE)
  val () = clamp_all(u, 2, limit)
  val () = zero_unless(u, 2, 0, active)

  val numeric = any_out_of_range(xhat, 4, 0, STATE_BOUND) orelse has(events, NUMERIC)
  val mask = bit_if(has(events, MEAS) orelse stale orelse out_of_band, MEAS)
           + bit_if(has(events, ESTIMATOR) orelse disagreeing, ESTIMATOR)
           + bit_if(miss, TIMING)
           + bit_if(active andalso (has(events, CTRL_SAT) orelse saturating), CTRL_SAT)
           + bit_if(numeric, NUMERIC)
  val health = classify(mask)

  val (_ | after) = decide_mode(before, health, miss, healthy, bad)
  val streak = (if health = HEALTHY then healthy + 1 else 0): int
  val episode = (if before = RUNNING andalso after = DEGRADED then 0
                 else if before = DEGRADED andalso after = DEGRADED andalso health <> HEALTHY then bad + 1
                 else bad): int
  val () = current := after
  val () = healthy := streak
  val () = bad := episode

  val () = ring_push(history, 4, health)
  val () = arrayptr_set_at(modes, k, before)
  val () = arrayptr_set_at(modes, k + 1, after)
  val () = arrayptr_set_at(healths, k, health)
  val () = arrayptr_set_at(masks, k, mask)

  val () = matvec(s1, a, x, 4, 4)
  val () = matvec(s2, b, u, 4, 2)
  val () = vadd(s3, s1, s2, 4)
  val () = vadd(x, s3, w, 4)
  val () = vcopy(u_prev, u, 2)

  prval () = fold@(st)
  prval () = fold@(cfg)
in end

fun frames {s:nat | s <= STEP_CAPACITY} {k:nat | k <= s} .<s-k>.
  (cfg: !cfg_vt, st: !st_vt, k: int(k), steps: int(s), measurements: pool_vt(2, 1), controls: pool_vt(2, 1), scratch: pool_vt(2, 1))
  : @(pool_vt(2, 1), pool_vt(2, 1), pool_vt(2, 1)) =
  if k < steps then let
    val (measurements, y) = pool_take(measurements)
    val (controls, u) = pool_take(controls)
    val (scratch, innovation) = pool_take(scratch)
    val () = do_frame(cfg, st, k, y, u, innovation)
  in frames(cfg, st, k + 1, steps, pool_give(measurements, y), pool_give(controls, u), pool_give(scratch, innovation)) end
  else @(measurements, controls, scratch)

fun fresh_state (cfg: !cfg_vt): st_vt = let
  val @CFG(_, _, _, _, _, _, x0, _, _, _, _, _, _) = cfg
  val st = st_make(x0)
  prval () = fold@(cfg)
in st end

fun timed_frames (cfg: !cfg_vt, st: !st_vt): @(lint, lint) = let
  val steps = cfg_steps(cfg)
  val measurements = pool_make(2)
  val controls = pool_make(2)
  val scratch = pool_make(2)
  val allocations = alloc_calls()
  val start = now_ns()
  val @(measurements, controls, scratch) = frames(cfg, st, 0, steps, measurements, controls, scratch)
  val elapsed = now_ns() - start
  val allocated = alloc_calls() - allocations
  val () = (pool_free(measurements); pool_free(controls); pool_free(scratch))
in @(elapsed, allocated) end

fun print_ints {n:nat} {i:nat | i <= n} .<n-i>. (v: !arrayptr(int, n), n: int(n), i: int(i), count: int): void =
  if i < n then (if i < count then (print_char(' '); print_int(arrayptr_get_at(v, i)); print_ints(v, n, i + 1, count)))

fun scaled (x: double): lint = let val t = x * 1.0e9 in g0float2int_double_lint((if t >= 0.0 then t + 0.5 else t - 0.5): double) end

fun print_state {i:nat | i <= 4} .<4-i>. (x: !arrayptr(double, 4), i: int(i)): void =
  if i < 4 then (print_char(' '); print_lint(scaled(arrayptr_get_at(x, i))); print_state(x, i + 1))

implement run_sim (cfg) = let
  val steps = cfg_steps(cfg)
  val st = fresh_state(cfg)
  val @(_, allocated) = timed_frames(cfg, st)
  val () = let
    val @ST(x, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, modes, healths, masks) = st
    val () = (print_string("M"); print_ints(modes, STEP_CAPACITY + 1, 0, steps + 1); print_newline())
    val () = (print_string("H"); print_ints(healths, STEP_CAPACITY, 0, steps); print_newline())
    val () = (print_string("G"); print_ints(masks, STEP_CAPACITY, 0, steps); print_newline())
    val () = (print_string("X"); print_state(x, 0); print_newline())
    prval () = fold@(st)
  in end
  val () = st_free(st)
in allocated end

implement sim_bench (cfg, reps) = let
  fun repeat {r:nat} .<r>. (cfg: !cfg_vt, remaining: int(r), elapsed: lint, allocated: lint): @(lint, lint) =
    if remaining > 0 then let
      val st = fresh_state(cfg)
      val @(ns, calls) = timed_frames(cfg, st)
      val () = st_free(st)
    in repeat(cfg, remaining - 1, elapsed + ns, allocated + calls) end
    else @(elapsed, allocated)
  val repetitions = g1ofg0(reps)
in if repetitions >= 0 then repeat(cfg, repetitions, 0L, 0L) else @(0L, 0L) end
