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
%}
extern fun alloc_calls (): lint = "mac#icarus_alloc_calls"

(* Artificial constants, shared with reference/icarus_ref.py. *)
#define MEAS_LIMIT 50.0
#define INNOV_THRESH 10.0
#define STATE_BOUND 1000.0
#define CTRL_LIMIT 1.0
#define DEGRADED_CTRL 0.5
#define STUCK_VALUE 7.0

fun dabs (x: double): double = if x < 0.0 then ~x else x
fun dmin (a: double, b: double): double = if b < a then b else a
fun dmax (a: double, b: double): double = if b > a then b else a
fun median3 (a: double, b: double, c: double): double = dmax(dmin(a, b), dmin(dmax(a, b), c))

(* ---- bounded index helpers: pure, so linear arrays are touched unconditionally *)
fun idx2 (c: int): [i:nat | i < 2] int(i) = let val c1 = g1ofg0(c) in
  if c1 >= 0 then (if c1 < 2 then c1 else 0) else 0 end
fun idx3 (c: int): [i:nat | i < 3] int(i) = let val c1 = g1ofg0(c) in
  if c1 >= 0 then (if c1 < 3 then c1 else 0) else 0 end
fun idx16 (c: int): [i:nat | i < 16] int(i) = let val c1 = g1ofg0(c) in
  if c1 >= 0 then (if c1 < 16 then c1 else 0) else 0 end
fun idx128 (c: int): [i:nat | i < 128] int(i) = let val c1 = g1ofg0(c) in
  if c1 >= 0 then (if c1 < 128 then c1 else 0) else 0 end
fun idx129 (c: int): [i:nat | i < 129] int(i) = let val c1 = g1ofg0(c) in
  if c1 >= 0 then (if c1 < 129 then c1 else 0) else 0 end
fun mode_of (m: int): [m1:nat | m1 <= 7] int(m1) = let val c1 = g1ofg0(m) in
  if c1 >= 0 then (if c1 <= 7 then c1 else 6) else 6 end

(* ---- flag arithmetic on small non-negative ints (bit b present iff (e / b) mod 2 = 1) *)
fun has (e: int, b: int): bool = ((e / b) mod 2) = 1
fun bit_if (cond: bool, b: int): int = if cond then b else 0

(* ---- vector predicates --------------------------------------------------- *)
fun any_abs_gt {n:nat} {i:nat | i <= n} .<n-i>.
  (v: !arrayptr(double, n), n: int(n), i: int(i), thr: double): bool =
  if i < n then
    (if dabs(arrayptr_get_at(v, i)) > thr then true else any_abs_gt(v, n, i + 1, thr))
  else false

(* NaN and infinity count as out of range because the comparison is negated. *)
fun any_out_of_range {n:nat} {i:nat | i <= n} .<n-i>.
  (v: !arrayptr(double, n), n: int(n), i: int(i), bound: double): bool =
  if i < n then
    (if dabs(arrayptr_get_at(v, i)) <= bound then any_out_of_range(v, n, i + 1, bound) else true)
  else false

fun select_vec {n:nat} {i:nat | i <= n} .<n-i>.
  (y: !arrayptr(double, n), alt: !arrayptr(double, n), n: int(n), i: int(i), use_alt: bool): void =
  if i < n then let
    val a = arrayptr_get_at(alt, i)
    val b = arrayptr_get_at(y, i)
    val () = arrayptr_set_at(y, i, (if use_alt then a else b): double)
  in select_vec(y, alt, n, i + 1, use_alt) end

fun keep_if {n:nat} {i:nat | i <= n} .<n-i>.
  (u: !arrayptr(double, n), n: int(n), i: int(i), keep: bool): void =
  if i < n then let
    val a = arrayptr_get_at(u, i)
    val () = arrayptr_set_at(u, i, (if keep then a else 0.0): double)
  in keep_if(u, n, i + 1, keep) end

fun vote {i:nat | i <= 2} .<2-i>.
  (y: !arrayptr(double, 2), c0: !arrayptr(double, 2), c1: !arrayptr(double, 2),
   c2: !arrayptr(double, 2), i: int(i)): void =
  if i < 2 then let
    val a = arrayptr_get_at(c0, i)
    val b = arrayptr_get_at(c1, i)
    val c = arrayptr_get_at(c2, i)
    val () = arrayptr_set_at(y, i, median3(a, b, c))
  in vote(y, c0, c1, c2, i + 1) end

(* ---- step table ---------------------------------------------------------- *)
fun load_step_w {j:nat | j <= 4} .<4-j>.
  (wv: !matrixptr(double, 128, 6), r: [r:nat | r < 128] int(r), wk: !arrayptr(double, 4), j: int(j)): void =
  if j < 4 then let
    val x = matrixptr_get_at(wv, r, 6, j)
    val () = arrayptr_set_at(wk, j, x)
  in load_step_w(wv, r, wk, j + 1) end

fun load_step_v {j:nat | j <= 2} .<2-j>.
  (wv: !matrixptr(double, 128, 6), r: [r:nat | r < 128] int(r), vk: !arrayptr(double, 2), j: int(j)): void =
  if j < 2 then let
    val x = matrixptr_get_at(wv, r, 6, 4 + j)
    val () = arrayptr_set_at(vk, j, x)
  in load_step_v(wv, r, vk, j + 1) end

(* ---- fault injection ----------------------------------------------------- *)
fun orb (e: int, b: int): int = if has(e, b) then e else e + b

(* One event. Returns the updated event mask: 1 measurement, 2 estimator,
   8 control saturation, 16 numeric, 32 stale marker. Channel faults touch only
   channel 0 except a dropout, which freezes the component on all three. *)
fun apply_one
  (kind: int, ch: [c:nat | c < 2] int(c), param: double, ev: int,
   c0: !arrayptr(double, 2), c1: !arrayptr(double, 2), c2: !arrayptr(double, 2),
   lastm: !arrayptr(double, 2)): int = let
  val cur = arrayptr_get_at(c0, ch)
  val last = arrayptr_get_at(lastm, ch)
  val v0 = (if kind = 2 then cur + param
            else if kind = 3 then STUCK_VALUE
            else if kind = 4 then param
            else if kind = 0 then last
            else cur): double
  val () = arrayptr_set_at(c0, ch, v0)
  val o1 = arrayptr_get_at(c1, ch)
  val () = arrayptr_set_at(c1, ch, (if kind = 0 then last else o1): double)
  val o2 = arrayptr_get_at(c2, ch)
  val () = arrayptr_set_at(c2, ch, (if kind = 0 then last else o2): double)
in
  if kind = 0 then orb(ev, 1)
  else if kind = 1 then orb(ev, 32)
  else if kind = 2 then orb(ev, 1)
  else if kind = 3 then orb(ev, 1)
  else if kind = 4 then orb(ev, 1)
  else if kind = 6 then orb(ev, 16)
  else if kind = 8 then orb(ev, 2)
  else if kind = 9 then orb(ev, 8)
  else ev
end

fun apply_faults {j:nat | j <= 16} .<16-j>.
  (fl: !matrixptr(double, 16, 4), nf: int, k: int, j: int(j), ev: int,
   c0: !arrayptr(double, 2), c1: !arrayptr(double, 2), c2: !arrayptr(double, 2),
   lastm: !arrayptr(double, 2)): int =
  if j < 16 then let
    val r = idx16(j)
    val step = g0float2int_double_int(matrixptr_get_at(fl, r, 4, 0))
    val kind = g0float2int_double_int(matrixptr_get_at(fl, r, 4, 1))
    val ch = idx2(g0float2int_double_int(matrixptr_get_at(fl, r, 4, 2)))
    val param = matrixptr_get_at(fl, r, 4, 3)
    val live = (j < nf) andalso (step = k)
    val eff = (if live then kind else ~1): int   (* kind ~1 leaves every channel and the event mask unchanged *)
    val ev1 = apply_one(eff, ch, param, ev, c0, c1, c2, lastm)
  in apply_faults(fl, nf, k, j + 1, ev1, c0, c1, c2, lastm) end
  else ev

(* Overrun ticks injected at step k, or ~1. *)
fun overrun_at {j:nat | j <= 16} .<16-j>.
  (fl: !matrixptr(double, 16, 4), nf: int, k: int, j: int(j), found: int): int =
  if j < 16 then let
    val r = idx16(j)
    val step = g0float2int_double_int(matrixptr_get_at(fl, r, 4, 0))
    val kind = g0float2int_double_int(matrixptr_get_at(fl, r, 4, 1))
    val ticks = g0float2int_double_int(matrixptr_get_at(fl, r, 4, 3))
    val take = (found < 0) andalso (j < nf) andalso (step = k) andalso (kind = 5)
  in overrun_at(fl, nf, k, j + 1, (if take then ticks else found): int) end
  else found

(* ---- mutable simulator state: every field is allocated once, before the loop *)
datavtype st_vt =
  | ST of (
      arrayptr(double, 4), arrayptr(double, 4),                   (* x, xhat *)
      arrayptr(double, 2), arrayptr(double, 2),                   (* uprev, last measurement *)
      arrayptr(double, 4), arrayptr(double, 2),                   (* step disturbance, noise *)
      arrayptr(double, 2), arrayptr(double, 2), arrayptr(double, 2), (* three channels *)
      arrayptr(double, 4), arrayptr(double, 4), arrayptr(double, 4), (* n-scratch *)
      arrayptr(double, 2), arrayptr(double, 2),                   (* m/p-scratch *)
      arrayptr(int, 3),                                           (* mode, healthy, bad *)
      ring_vt(4),                                                 (* recent health history *)
      arrayptr(int, 129), arrayptr(int, 128), arrayptr(int, 128)) (* recorded M H G *)

fun st_make (x0: !arrayptr(double, 4)): st_vt = let
  val x = vec_make(4)
  val () = vcopy(x, x0, 4)
  val ctl = arrayptr_make_elt<int>(i2sz(3), 0)
  val () = arrayptr_set_at(ctl, 0, 3)   (* begin in Ready *)
in
  ST(x, vec_make(4), vec_make(2), vec_make(2), vec_make(4), vec_make(2),
     vec_make(2), vec_make(2), vec_make(2), vec_make(4), vec_make(4), vec_make(4),
     vec_make(2), vec_make(2), ctl, ring_make(4),
     arrayptr_make_elt<int>(i2sz(129), 0), arrayptr_make_elt<int>(i2sz(128), 0),
     arrayptr_make_elt<int>(i2sz(128), 0))
end

fun st_free (s: st_vt): void = let
  val ~ST(x, xhat, uprev, lastm, wk, vk, c0, c1, c2, t1, t2, t3, tm, tp, ctl, ring, om, oh, og) = s
in
  arrayptr_free(x); arrayptr_free(xhat); arrayptr_free(uprev); arrayptr_free(lastm);
  arrayptr_free(wk); arrayptr_free(vk); arrayptr_free(c0); arrayptr_free(c1); arrayptr_free(c2);
  arrayptr_free(t1); arrayptr_free(t2); arrayptr_free(t3); arrayptr_free(tm); arrayptr_free(tp);
  arrayptr_free(ctl); ring_free(ring); arrayptr_free(om); arrayptr_free(oh); arrayptr_free(og)
end

(* One frame. y, u and innov are leased buffers (measurement frame, control frame,
   estimator scratch). *)
fun do_frame
  (cfg: !cfg_vt, st: !st_vt, k: int,
   y: !arrayptr(double, 2), u: !arrayptr(double, 2), innov: !arrayptr(double, 2)): void = let
  val @CFG(a, b, c, kk, l, wv, fl, x0, steps, nf) = cfg
  val @ST(x, xhat, uprev, lastm, wk, vk, c0, c1, c2, t1, t2, t3, tm, tp, ctl, ring, om, oh, og) = st
  val mode0 = arrayptr_get_at(ctl, 0)
  val healthy = arrayptr_get_at(ctl, 1)
  val bad = arrayptr_get_at(ctl, 2)

  (* Acquire: three redundant channels of C x + v, faults, per component vote *)
  val r = idx128(k)
  val () = load_step_w(wv, r, wk, 0)
  val () = load_step_v(wv, r, vk, 0)
  val () = matvec(c0, c, x, 2, 4)
  val () = vadd(c1, c0, vk, 2)
  val () = vcopy(c0, c1, 2)
  val () = vcopy(c2, c1, 2)
  val ev = apply_faults(fl, nf, k, 0, 0, c0, c1, c2, lastm)
  val () = vote(y, c0, c1, c2, 0)
  val stale = has(ev, 32)
  val () = select_vec(y, lastm, 2, 0, stale)

  (* Normalize *)
  val oob = any_abs_gt(y, 2, 0, MEAS_LIMIT + 1.0e-12)
  val () = clamp_all(y, 2, MEAS_LIMIT)
  val () = vcopy(lastm, y, 2)

  (* Estimate: innovation against the prior estimate, then the observer update *)
  val () = matvec(tp, c, xhat, 2, 4)
  val () = vsub(innov, y, tp, 2)
  val big_innov = (norm2(innov, 2) > INNOV_THRESH)
  val () = matvec(t1, a, xhat, 4, 4)
  val () = matvec(t2, b, uprev, 4, 2)
  val () = vadd(t3, t1, t2, 4)
  val () = matvec(t2, l, innov, 4, 2)
  val () = vadd(xhat, t3, t2, 4)

  (* Timing: nominal 900 ticks against a 1000 tick frame *)
  val over = overrun_at(fl, nf, k, 0, ~1)
  val miss = (over >= 0) andalso (900 + over > 1000)

  (* Control: raw feedback every frame, authority selected by mode *)
  val active = (mode0 = 4) orelse (mode0 = 5)
  val lim = (if mode0 = 5 then DEGRADED_CTRL else CTRL_LIMIT): double
  val () = matvec(tm, kk, xhat, 2, 4)
  val () = vneg(u, tm, 2)
  val over_lim = any_abs_gt(u, 2, 0, lim + 1.0e-12)
  val saturated = active andalso over_lim
  val () = clamp_all(u, 2, lim)
  val () = keep_if(u, 2, 0, active)

  (* Validate and classify *)
  val numeric = any_out_of_range(xhat, 4, 0, STATE_BOUND) orelse has(ev, 16)
  val mask =
    bit_if(has(ev, 1) orelse stale orelse oob, 1) + bit_if(has(ev, 2) orelse big_innov, 2)
    + bit_if(miss, 4) + bit_if(has(ev, 8) orelse saturated, 8) + bit_if(numeric, 16)
  val health = classify(mask)

  (* Decide *)
  val m = mode_of(mode0)
  val (_ | m1) = decide_mode(m, health, miss, healthy, bad)
  val healthy1 = (if health = 0 then healthy + 1 else 0): int
  val bad1 = (if mode0 = 4 andalso m1 = 5 then 0
              else if mode0 = 5 andalso m1 = 5 then (if health = 0 then bad else bad + 1)
              else bad): int
  val () = arrayptr_set_at(ctl, 0, m1)
  val () = arrayptr_set_at(ctl, 1, healthy1)
  val () = arrayptr_set_at(ctl, 2, bad1)

  (* Record *)
  val () = ring_push(ring, 4, health)
  val () = arrayptr_set_at(om, idx129(k), mode0)
  val () = arrayptr_set_at(om, idx129(k + 1), m1)
  val () = arrayptr_set_at(oh, idx128(k), health)
  val () = arrayptr_set_at(og, idx128(k), mask)

  (* The hidden plant advances under the control just applied *)
  val () = matvec(t1, a, x, 4, 4)
  val () = matvec(t2, b, u, 4, 2)
  val () = vadd(t3, t1, t2, 4)
  val () = vadd(x, t3, wk, 4)
  val () = vcopy(uprev, u, 2)

  prval () = fold@(st)
  prval () = fold@(cfg)
in end

(* The loop threads three pools linearly: each frame takes one lease from each and
   must give each back, or the program does not typecheck. *)
fun frames {k:nat | k <= 128} .<128-k>.
  (cfg: !cfg_vt, st: !st_vt, k: int(k), steps: int,
   pm: pool_vt(2, 1), pu: pool_vt(2, 1), ps: pool_vt(2, 1))
  : @(pool_vt(2, 1), pool_vt(2, 1), pool_vt(2, 1)) =
  if k < 128 then
    (if k < steps then let
       val (pm0, y) = pool_take(pm)
       val (pu0, u) = pool_take(pu)
       val (ps0, innov) = pool_take(ps)
       val () = do_frame(cfg, st, k, y, u, innov)
       val pm1 = pool_give(pm0, y)
       val pu1 = pool_give(pu0, u)
       val ps1 = pool_give(ps0, innov)
     in frames(cfg, st, k + 1, steps, pm1, pu1, ps1) end
     else @(pm, pu, ps))
  else @(pm, pu, ps)

fun print_ints {n:nat} {i:nat | i <= n} .<n-i>.
  (v: !arrayptr(int, n), n: int(n), i: int(i), count: int): void =
  if i < n then
    (if i < count then (print_char(' '); print_int(arrayptr_get_at(v, i)); print_ints(v, n, i + 1, count))
     else ())

fun scaled (x: double): lint = let
  val t = x * 1.0e9
in g0float2int_double_lint((if t >= 0.0 then t + 0.5 else t - 0.5): double) end

fun print_state {i:nat | i <= 4} .<4-i>. (x: !arrayptr(double, 4), i: int(i)): void =
  if i < 4 then (print_char(' '); print_lint(scaled(arrayptr_get_at(x, i))); print_state(x, i + 1))

implement run_sim (cfg) = let
  val steps = (let val @CFG(_, _, _, _, _, _, _, _, s, _) = cfg val v = s prval () = fold@(cfg) in v end): int
  val st = (let val @CFG(_, _, _, _, _, _, _, x0, _, _) = cfg val s0 = st_make(x0) prval () = fold@(cfg) in s0 end)
  val pm = pool_make(2)
  val pu = pool_make(2)
  val ps = pool_make(2)
  val before = alloc_calls()
  val @(pm1, pu1, ps1) = frames(cfg, st, 0, steps, pm, pu, ps)
  val after = alloc_calls()
  val () = (pool_free(pm1); pool_free(pu1); pool_free(ps1))
  val () = let
    val @ST(x, _, _, _, _, _, _, _, _, _, _, _, _, _, ctl, _, om, oh, og) = st
    val () = (print_string("M"); print_ints(om, 129, 0, steps + 1); print_newline())
    val () = (print_string("H"); print_ints(oh, 128, 0, steps); print_newline())
    val () = (print_string("G"); print_ints(og, 128, 0, steps); print_newline())
    val () = (print_string("X"); print_state(x, 0); print_newline())
    prval () = fold@(st)
  in end
  val () = st_free(st)
in after - before end
