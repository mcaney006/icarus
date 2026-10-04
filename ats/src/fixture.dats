#define ATS_DYNLOADFLAG 0
#include "share/atspre_staload.hats"
staload "./fixture.sats"

#define VALUE_CAPACITY 160
#define FNV_OFFSET 0x811C9DC5u
#define FNV_PRIME 16777619u
#define WIRE_SCALE 1.0e9

%{^
extern long icarus_read_file(const char*, char*, long);
%}
extern fun read_file {n:nat} (path: string, buf: !arrayptr(char, n), cap: int(n)): int = "mac#icarus_read_file"

vtypedef input = arrayptr(char, INPUT_CAPACITY)
vtypedef values = arrayptr(double, VALUE_CAPACITY)
typedef tally = [c:int | ~1 <= c; c <= VALUE_CAPACITY] int(c)

datatype seal = SEALED | TAMPERED | UNSEALED

fun digit_value (c: char): double = g0int2float_int_double(char2int0(c) - char2int0('0'))

fun is_digit (c: char): bool = c >= '0' andalso c <= '9'

fun hash_line {l:nat | l <= INPUT_CAPACITY} {i:nat | i < l} .<l-i>.
  (buf: !input, len: int(l), i: int(i), hash: uint): [k:nat | i < k; k <= l] @(int(k), uint) = let
  val c = arrayptr_get_at(buf, i)
  val mixed = (hash lxor g0int2uint_int_uint(char2int0(c))) * FNV_PRIME
in
  if c = '\n' then @(i + 1, mixed)
  else if i + 1 < len then hash_line(buf, len, i + 1, mixed)
  else @(i + 1, mixed)
end

fun digest {l:nat | l <= INPUT_CAPACITY} {i:nat | i <= l} .<l-i>.
  (buf: !input, len: int(l), i: int(i), acc: double, seen: bool): @(double, bool) =
  if i < len then let
    val c = arrayptr_get_at(buf, i)
  in
    if is_digit(c) then digest(buf, len, i + 1, acc * 10.0 + digit_value(c), true)
    else if c = ' ' andalso not(seen) then digest(buf, len, i + 1, acc, seen)
    else @(acc, seen)
  end
  else @(acc, seen)

fun verify {l:nat | l <= INPUT_CAPACITY} {i:nat | i <= l} .<l-i>.
  (buf: !input, len: int(l), i: int(i), hash: uint): seal =
  if i >= len then UNSEALED
  else if arrayptr_get_at(buf, i) = 'Z' then let
    val @(claimed, present) = digest(buf, len, i + 1, 0.0, false)
  in
    if not(present) then UNSEALED
    else if claimed = g0int2float_lint_double(g0uint2int_uint_lint(hash)) then SEALED
    else TAMPERED
  end
  else let val @(next, hash) = hash_line(buf, len, i, hash) in verify(buf, len, next, hash) end

fun commit {c:nat | c <= VALUE_CAPACITY}
  (vals: !values, pending: bool, count: int(c), negative: bool, magnitude: double): tally =
  if not(pending) then count
  else if count < VALUE_CAPACITY then
    (arrayptr_set_at(vals, count, (if negative then ~magnitude else magnitude): double); count + 1)
  else ~1

fun read_values {l:nat | l <= INPUT_CAPACITY} {j:nat | j <= l} {c:nat | c <= VALUE_CAPACITY} .<l-j>.
  (buf: !input, len: int(l), j: int(j), vals: !values, count: int(c), magnitude: double, negative: bool, pending: bool)
  : [k:nat | k <= l] @(int(k), tally) =
  if j >= len then @(len, commit(vals, pending, count, negative, magnitude))
  else let
    val c = arrayptr_get_at(buf, j)
  in
    if c = '\n' then @(j + 1, commit(vals, pending, count, negative, magnitude))
    else if c = ' ' then let
      val committed = commit(vals, pending, count, negative, magnitude)
    in
      if committed < 0 then @(len, ~1) else read_values(buf, len, j + 1, vals, committed, 0.0, false, false)
    end
    else if c = '-' then
      (if pending then @(len, ~1) else read_values(buf, len, j + 1, vals, count, 0.0, true, false))
    else if is_digit(c) then read_values(buf, len, j + 1, vals, count, magnitude * 10.0 + digit_value(c), negative, true)
    else @(len, ~1)
  end

fun value_at (vals: !values, k: int): double = let
  val k = g1ofg0(k)
in
  if k >= 0 then (if k < VALUE_CAPACITY then arrayptr_get_at(vals, k) else 0.0) else 0.0
end

fun bounded_index {n:nat} (x: double, limit: int(n)): [i:int | ~1 <= i; i < n] int(i) =
  if x >= 0.0 andalso x < g0int2float_int_double(limit) then let
    val i = g1ofg0(g0float2int_double_int(x))
  in if i >= 0 then (if i < limit then i else ~1) else ~1 end
  else ~1

fun fill_row {r,c:nat} {i:nat | i < r} {j:nat | j <= c} .<c-j>.
  (m: !matrixptr(double, r, c), c: int(c), i: int(i), j: int(j), vals: !values, k: int): void =
  if j < c then (matrixptr_set_at(m, i, c, j, value_at(vals, k) / WIRE_SCALE); fill_row(m, c, i, j + 1, vals, k + 1))

fun fill_matrix {r,c:nat} {i:nat | i <= r} .<r-i>.
  (m: !matrixptr(double, r, c), r: int(r), c: int(c), i: int(i), vals: !values, k: int): void =
  if i < r then (fill_row(m, c, i, 0, vals, k); fill_matrix(m, r, c, i + 1, vals, k + c))

fun fill_vector {n:nat} {j:nat | j <= n} .<n-j>. (v: !arrayptr(double, n), n: int(n), j: int(j), vals: !values): void =
  if j < n then (arrayptr_set_at(v, j, value_at(vals, j) / WIRE_SCALE); fill_vector(v, n, j + 1, vals))

fun fill_columns {first:nat} {width:nat | first + width <= 6} {r:nat | r < STEP_CAPACITY} .<width>.
  (m: !matrixptr(double, STEP_CAPACITY, 6), r: int(r), first: int(first), width: int(width), vals: !values, k: int): void =
  if width > 0 then
    (matrixptr_set_at(m, r, 6, first, value_at(vals, k) / WIRE_SCALE); fill_columns(m, r, first + 1, width - 1, vals, k + 1))

fun apply_record
  (tag: char, vals: !values, count: natLte(VALUE_CAPACITY),
   a: !matrixptr(double, 4, 4), b: !matrixptr(double, 4, 2), c: !matrixptr(double, 2, 4),
   k: !matrixptr(double, 2, 4), l: !matrixptr(double, 4, 2), table: !matrixptr(double, STEP_CAPACITY, 6),
   x0: !arrayptr(double, 4), fault_steps: !arrayptr(int, FAULT_CAPACITY),
   fault_kinds: !arrayptr(fault_kind, FAULT_CAPACITY), fault_lanes: !arrayptr(lane, FAULT_CAPACITY),
   fault_params: !arrayptr(double, FAULT_CAPACITY), steps: step_count, faults: fault_count)
  : @(bool, step_count, fault_count) =
  if tag = 'D' then let
    val n = value_at(vals, 0)
    val m = value_at(vals, 1)
    val p = value_at(vals, 2)
    val declared = bounded_index(value_at(vals, 3), STEP_CAPACITY + 1)
  in
    if declared < 0 then @(false, steps, faults)
    else if count = 4 andalso n = 4.0 andalso m = 2.0 andalso p = 2.0 then @(true, declared, faults)
    else @(false, steps, faults)
  end
  else if tag = 'A' then (if count = 16 then (fill_matrix(a, 4, 4, 0, vals, 0); @(true, steps, faults)) else @(false, steps, faults))
  else if tag = 'B' then (if count = 8 then (fill_matrix(b, 4, 2, 0, vals, 0); @(true, steps, faults)) else @(false, steps, faults))
  else if tag = 'C' then (if count = 8 then (fill_matrix(c, 2, 4, 0, vals, 0); @(true, steps, faults)) else @(false, steps, faults))
  else if tag = 'K' then (if count = 8 then (fill_matrix(k, 2, 4, 0, vals, 0); @(true, steps, faults)) else @(false, steps, faults))
  else if tag = 'L' then (if count = 8 then (fill_matrix(l, 4, 2, 0, vals, 0); @(true, steps, faults)) else @(false, steps, faults))
  else if tag = 'X' then (if count = 4 then (fill_vector(x0, 4, 0, vals); @(true, steps, faults)) else @(false, steps, faults))
  else if tag = 'W' then let val r = bounded_index(value_at(vals, 0), steps) in
    if count = 5 then (if r >= 0 then (fill_columns(table, r, 0, 4, vals, 1); @(true, steps, faults)) else @(false, steps, faults))
    else @(false, steps, faults)
  end
  else if tag = 'V' then let val r = bounded_index(value_at(vals, 0), steps) in
    if count = 3 then (if r >= 0 then (fill_columns(table, r, 4, 2, vals, 1); @(true, steps, faults)) else @(false, steps, faults))
    else @(false, steps, faults)
  end
  else if tag = 'F' then let
    val step = bounded_index(value_at(vals, 0), steps)
    val kind = bounded_index(value_at(vals, 1), 10)
    val lane = bounded_index(value_at(vals, 2), 2)
    val param = value_at(vals, 3) / WIRE_SCALE
  in
    if faults >= FAULT_CAPACITY then @(false, steps, faults)
    else if kind < 0 then @(false, steps, faults)
    else if lane < 0 then @(false, steps, faults)
    else if count = 4 andalso step >= 0 then let
      val () = arrayptr_set_at(fault_steps, faults, step)
      val () = arrayptr_set_at<fault_kind>(fault_kinds, faults, kind)
      val () = arrayptr_set_at<lane>(fault_lanes, faults, lane)
      val () = arrayptr_set_at(fault_params, faults, param)
    in @(true, steps, faults + 1) end
    else @(false, steps, faults)
  end
  else @(true, steps, faults)

fun record (tag: char, vals: !values, count: natLte(VALUE_CAPACITY), cfg: !cfg_vt): bool = let
  val @CFG(a, b, c, k, l, table, x0, fault_steps, fault_kinds, fault_lanes, fault_params, steps, faults) = cfg
  val @(accepted, next_steps, next_faults) =
    apply_record(tag, vals, count, a, b, c, k, l, table, x0, fault_steps, fault_kinds, fault_lanes, fault_params, steps, faults)
  val () = steps := next_steps
  val () = faults := next_faults
  prval () = fold@(cfg)
in accepted end

fun skip_line {l:nat | l <= INPUT_CAPACITY} {i:nat | i <= l} .<l-i>. (buf: !input, len: int(l), i: int(i)): [k:nat | k <= l] int(k) =
  if i < len then (if arrayptr_get_at(buf, i) = '\n' then i + 1 else skip_line(buf, len, i + 1)) else len

fun parse_all {l:nat | l <= INPUT_CAPACITY} {i:nat | i <= l} .<l-i>.
  (buf: !input, len: int(l), i: int(i), vals: !values, cfg: !cfg_vt): bool =
  if i >= len then true
  else let
    val tag = arrayptr_get_at(buf, i)
  in
    if tag = '#' then let val next = skip_line(buf, len, i) in if next > i then parse_all(buf, len, next, vals, cfg) else false end
    else let
      val @(next, count) = read_values(buf, len, i + 1, vals, 0, 0.0, false, false)
    in
      if count < 0 then false
      else if next <= i then false
      else record(tag, vals, count, cfg) andalso parse_all(buf, len, next, vals, cfg)
    end
  end

fun reject (reason: string): bool = (println! ("REJECT ", reason); false)

fun ingest (path: string, buf: !input, vals: !values, cfg: !cfg_vt): bool = let
  val size = g1ofg0(read_file(path, buf, INPUT_CAPACITY))
in
  if size = ~2 then reject("fixture exceeds the 65536 byte input capacity")
  else if size < 0 then reject("unreadable fixture")
  else if size > INPUT_CAPACITY then reject("fixture exceeds the 65536 byte input capacity")
  else case+ verify(buf, size, 0, FNV_OFFSET) of
    | UNSEALED() => reject("missing Z checksum line")
    | TAMPERED() => reject("checksum mismatch")
    | SEALED() => parse_all(buf, size, 0, vals, cfg) orelse reject("malformed or out-of-shape record")
end

fun cfg_make (): cfg_vt =
  CFG(mat_zero(4, 4), mat_zero(4, 2), mat_zero(2, 4), mat_zero(2, 4), mat_zero(4, 2),
      mat_zero(STEP_CAPACITY, 6), arrayptr_make_elt<double>(i2sz(4), 0.0),
      arrayptr_make_elt<int>(i2sz(FAULT_CAPACITY), 0), arrayptr_make_elt<fault_kind>(i2sz(FAULT_CAPACITY), 0),
      arrayptr_make_elt<lane>(i2sz(FAULT_CAPACITY), 0), arrayptr_make_elt<double>(i2sz(FAULT_CAPACITY), 0.0),
      0, 0)
where {
  fun mat_zero {r,c:nat} (r: int(r), c: int(c)): matrixptr(double, r, c) = matrixptr_make_elt<double>(i2sz(r), i2sz(c), 0.0)
}

implement cfg_free (cfg) = let
  val ~CFG(a, b, c, k, l, table, x0, fault_steps, fault_kinds, fault_lanes, fault_params, _, _) = cfg
in
  matrixptr_free(a); matrixptr_free(b); matrixptr_free(c); matrixptr_free(k); matrixptr_free(l);
  matrixptr_free(table); arrayptr_free(x0);
  arrayptr_free(fault_steps); arrayptr_free(fault_kinds); arrayptr_free(fault_lanes); arrayptr_free(fault_params)
end

implement cfg_steps (cfg) = let
  val @CFG(_, _, _, _, _, _, _, _, _, _, _, steps, _) = cfg
  val declared = steps
  prval () = fold@(cfg)
in declared end

implement load_fixture (path) = let
  val buf = arrayptr_make_elt<char>(i2sz(INPUT_CAPACITY), '\000')
  val vals = arrayptr_make_elt<double>(i2sz(VALUE_CAPACITY), 0.0)
  val cfg = cfg_make()
  val ingested = ingest(path, buf, vals, cfg)
  val () = (arrayptr_free(buf); arrayptr_free(vals))
in
  if ingested then Some_vt(cfg) else (cfg_free(cfg); None_vt())
end
