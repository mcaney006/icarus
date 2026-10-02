#define ATS_DYNLOADFLAG 0
#include "share/atspre_staload.hats"
staload "./fixture.sats"

%{^
extern long icarus_read_file(const char*, char*, long);
%}
extern fun read_file {n:nat} (path: string, buf: !arrayptr(char, n), cap: int(n)): int
  = "mac#icarus_read_file"

(* ---- checksum: FNV-1a over every byte before the Z line ------------------- *)

fun hash_line {l:nat | l <= 65536} {i:nat | i < l} .<l-i>.
  (buf: !arrayptr(char, 65536), len: int(l), i: int(i), h: uint)
  : [k:nat | i < k; k <= l] @(int(k), uint) = let
  val c = arrayptr_get_at(buf, i)
  val h1 = (h lxor g0int2uint_int_uint(char2int0(c))) * 16777619u
in
  if c = '\n' then @(i + 1, h1)
  else if i + 1 < len then hash_line(buf, len, i + 1, h1)
  else @(i + 1, h1)
end

fun z_value {l:nat | l <= 65536} {i:nat | i <= l} .<l-i>.
  (buf: !arrayptr(char, 65536), len: int(l), i: int(i), acc: double, started: bool): @(double, bool) =
  if i < len then let
    val c = arrayptr_get_at(buf, i)
  in
    if c >= '0' andalso c <= '9' then
      z_value(buf, len, i + 1, acc * 10.0 + g0int2float_int_double(char2int0(c) - 48), true)
    else if c = ' ' andalso not(started) then z_value(buf, len, i + 1, acc, started)
    else @(acc, started)
  end else @(acc, started)

(* 1 verified, 0 mismatch, ~1 missing or malformed *)
fun verify {l:nat | l <= 65536} {i:nat | i <= l} .<l-i>.
  (buf: !arrayptr(char, 65536), len: int(l), i: int(i), h: uint): int =
  if i >= len then ~1
  else let
    val c = arrayptr_get_at(buf, i)
  in
    if c = 'Z' then let
      val @(z, ok) = z_value(buf, len, i + 1, 0.0, false)
    in
      if ok then (if z = g0int2float_lint_double(g0uint2int_uint_lint(h)) then 1 else 0) else ~1
    end
    else let
      val @(k, h1) = hash_line(buf, len, i, h)
    in verify(buf, len, k, h1) end
  end

(* ---- one record line: tag, then integers ---------------------------------- *)

(* The clamp is the bounds check: it yields an index the solver can see is in
   range, and the callers below reject any record whose count is out of range
   before the clamped value could ever matter. *)
fun idx160 (c: int): [i:nat | i < 160] int(i) = let
  val c1 = g1ofg0(c)
in
  if c1 >= 0 then (if c1 < 160 then c1 else 0) else 0
end

fun store (vals: !arrayptr(double, 160), cnt: int, v: double): int = let
  val i = idx160(cnt)
  val () = arrayptr_set_at(vals, i, v)
in
  if cnt >= 0 then (if cnt < 160 then cnt + 1 else ~1) else ~1
end

(* Always touches the array; when nothing is pending it writes back what is there. *)
fun commit (vals: !arrayptr(double, 160), inum: bool, cnt: int, neg: bool, cur: double): int = let
  val i = idx160(cnt)
  val old = arrayptr_get_at(vals, i)
  val v = (if neg then ~cur else cur): double
  val () = arrayptr_set_at(vals, i, (if inum then v else old): double)
in
  if inum then (if cnt >= 0 then (if cnt < 160 then cnt + 1 else ~1) else ~1) else cnt
end

fun get_val (vals: !arrayptr(double, 160), k: int): double = let
  val i = idx160(k)
in arrayptr_get_at(vals, i) end

(* Returns the start of the next line and the number of values read, or ~1. *)
fun read_nums {l:nat | l <= 65536} {j:nat | j <= l} .<l-j>.
  (buf: !arrayptr(char, 65536), len: int(l), j: int(j), vals: !arrayptr(double, 160),
   cnt: int, cur: double, neg: bool, inum: bool): [k:nat | k <= l] @(int(k), int) =
  if j >= len then let
    val c1 = commit(vals, inum, cnt, neg, cur)
  in @(len, c1) end
  else let
    val c = arrayptr_get_at(buf, j)
  in
    if c = '\n' then let
      val c1 = commit(vals, inum, cnt, neg, cur)
    in @(j + 1, c1) end
    else if c = ' ' then let
      val c1 = commit(vals, inum, cnt, neg, cur)
    in if c1 < 0 then @(len, ~1) else read_nums(buf, len, j + 1, vals, c1, 0.0, false, false) end
    else if c = '-' then
      (if inum then @(len, ~1) else read_nums(buf, len, j + 1, vals, cnt, 0.0, true, false))
    else if c >= '0' andalso c <= '9' then
      read_nums(buf, len, j + 1, vals, cnt,
        cur * 10.0 + g0int2float_int_double(char2int0(c) - 48), neg, true)
    else @(len, ~1)
  end

(* Copies r*c scaled values, consuming them from index k on. *)
fun fill_cols {r,c:nat} {i:nat | i < r} {j:nat | j <= c} .<c-j>.
  (m: !matrixptr(double, r, c), c: int(c), i: int(i), j: int(j),
   vals: !arrayptr(double, 160), k: int): void =
  if j < c then let
    val v = get_val(vals, k)
    val () = matrixptr_set_at(m, i, c, j, v / 1.0e9)
  in fill_cols(m, c, i, j + 1, vals, k + 1) end

fun fill_rows {r,c:nat} {i:nat | i <= r} .<r-i>.
  (m: !matrixptr(double, r, c), r: int(r), c: int(c), i: int(i),
   vals: !arrayptr(double, 160), k: int): void =
  if i < r then
    (fill_cols(m, c, i, 0, vals, k); fill_rows(m, r, c, i + 1, vals, k + c))

fun fill_vec {n:nat} {j:nat | j <= n} .<n-j>.
  (v: !arrayptr(double, n), n: int(n), j: int(j), vals: !arrayptr(double, 160)): void =
  if j < n then let
    val x = get_val(vals, j)
    val () = arrayptr_set_at(v, j, x / 1.0e9)
  in fill_vec(v, n, j + 1, vals) end

(* A single row of the step table: columns [c0, c0+w) taken from vals[1..]. *)
fun fill_step_row {j:nat | j <= 6} {w:nat | j + w <= 6} {r:nat | r < 128} .<w>.
  (m: !matrixptr(double, 128, 6), r: int(r), j: int(j), w: int(w),
   vals: !arrayptr(double, 160), k: int): void =
  if w > 0 then let
    val v = get_val(vals, k)
    val () = matrixptr_set_at(m, r, 6, j, v / 1.0e9)
  in fill_step_row(m, r, j + 1, w - 1, vals, k + 1) end

(* ---- dispatch ------------------------------------------------------------- *)

fun as_index (x: double, lo: int, hi: int): int = let
  val i = g0float2int_double_int(x)
in if i >= lo then (if i < hi then i else ~1) else ~1 end

(* result: ~1 reject; otherwise a small record-kind code the caller ignores *)
fun record
  (tag: char, vals: !arrayptr(double, 160), cnt: int,
   a: !matrixptr(double, 4, 4), b: !matrixptr(double, 4, 2), c: !matrixptr(double, 2, 4),
   kk: !matrixptr(double, 2, 4), l: !matrixptr(double, 4, 2),
   wv: !matrixptr(double, 128, 6), fl: !matrixptr(double, 16, 4), x0: !arrayptr(double, 4),
   steps: int, nf: int): @(int, int, int) =
  (* returns (status, steps, nf); status ~1 rejects *)
  if tag = 'D' then
    (if cnt = 4 then let
       val n = get_val(vals, 0)
       val m = get_val(vals, 1)
       val p = get_val(vals, 2)
       val s = as_index(get_val(vals, 3), 0, 129)
     in
       if n = 4.0e0 then
         (if m = 2.0e0 then
           (if p = 2.0e0 then (if s >= 0 then @(0, s, nf) else @(~1, steps, nf)) else @(~1, steps, nf))
          else @(~1, steps, nf))
       else @(~1, steps, nf)
     end else @(~1, steps, nf))
  else if tag = 'A' then
    (if cnt = 16 then (fill_rows(a, 4, 4, 0, vals, 0); @(0, steps, nf)) else @(~1, steps, nf))
  else if tag = 'B' then
    (if cnt = 8 then (fill_rows(b, 4, 2, 0, vals, 0); @(0, steps, nf)) else @(~1, steps, nf))
  else if tag = 'C' then
    (if cnt = 8 then (fill_rows(c, 2, 4, 0, vals, 0); @(0, steps, nf)) else @(~1, steps, nf))
  else if tag = 'K' then
    (if cnt = 8 then (fill_rows(kk, 2, 4, 0, vals, 0); @(0, steps, nf)) else @(~1, steps, nf))
  else if tag = 'L' then
    (if cnt = 8 then (fill_rows(l, 4, 2, 0, vals, 0); @(0, steps, nf)) else @(~1, steps, nf))
  else if tag = 'X' then
    (if cnt = 4 then (fill_vec(x0, 4, 0, vals); @(0, steps, nf)) else @(~1, steps, nf))
  else if tag = 'W' then let
    val r = g1ofg0(as_index(get_val(vals, 0), 0, steps))
  in
    if cnt = 5 then
      (if r >= 0 then (if r < 128 then (fill_step_row(wv, r, 0, 4, vals, 1); @(0, steps, nf))
                       else @(~1, steps, nf)) else @(~1, steps, nf))
    else @(~1, steps, nf)
  end
  else if tag = 'V' then let
    val r = g1ofg0(as_index(get_val(vals, 0), 0, steps))
  in
    if cnt = 3 then
      (if r >= 0 then (if r < 128 then (fill_step_row(wv, r, 4, 2, vals, 1); @(0, steps, nf))
                       else @(~1, steps, nf)) else @(~1, steps, nf))
    else @(~1, steps, nf)
  end
  else if tag = 'F' then let
    val row = g1ofg0(nf)
    val kind = as_index(get_val(vals, 1), 0, 10)
    val chan = as_index(get_val(vals, 2), 0, 2)
  in
    if cnt = 4 then
      (if row >= 0 then
         (if row < 16 then
            (if kind >= 0 then
               (if chan >= 0 then let
                  val s = get_val(vals, 0)
                  val k1 = get_val(vals, 1)
                  val c1 = get_val(vals, 2)
                  val p1 = get_val(vals, 3)
                  val () = matrixptr_set_at(fl, row, 4, 0, s)
                  val () = matrixptr_set_at(fl, row, 4, 1, k1)
                  val () = matrixptr_set_at(fl, row, 4, 2, c1)
                  val () = matrixptr_set_at(fl, row, 4, 3, p1 / 1.0e9)
                in @(0, steps, nf + 1) end
                else @(~1, steps, nf))
             else @(~1, steps, nf))
          else @(~1, steps, nf))
       else @(~1, steps, nf))
    else @(~1, steps, nf)
  end
  else @(0, steps, nf)   (* # comments and the expected M H G E T lines are not consumed here *)

fun skip_line {l:nat | l <= 65536} {i:nat | i <= l} .<l-i>.
  (buf: !arrayptr(char, 65536), len: int(l), i: int(i)): [k:nat | k <= l] int(k) =
  if i < len then
    (if arrayptr_get_at(buf, i) = '\n' then i + 1 else skip_line(buf, len, i + 1))
  else len

fun parse_all {l:nat | l <= 65536} {i:nat | i <= l} .<l-i>.
  (buf: !arrayptr(char, 65536), len: int(l), i: int(i), vals: !arrayptr(double, 160),
   a: !matrixptr(double, 4, 4), b: !matrixptr(double, 4, 2), c: !matrixptr(double, 2, 4),
   kk: !matrixptr(double, 2, 4), l2: !matrixptr(double, 4, 2),
   wv: !matrixptr(double, 128, 6), fl: !matrixptr(double, 16, 4), x0: !arrayptr(double, 4),
   steps: int, nf: int): @(int, int, int) =
  if i >= len then @(0, steps, nf)
  else let
    val tag = arrayptr_get_at(buf, i)
    val skipped = skip_line(buf, len, i)
  in
    if tag = '#' then
      (if skipped > i then parse_all(buf, len, skipped, vals, a, b, c, kk, l2, wv, fl, x0, steps, nf)
       else @(~1, steps, nf))
    else let
    val @(next, cnt) = read_nums(buf, len, i + 1, vals, 0, 0.0, false, false)
  in
    if cnt < 0 then @(~1, steps, nf)
    else let
      val @(st, steps1, nf1) = record(tag, vals, cnt, a, b, c, kk, l2, wv, fl, x0, steps, nf)
    in
      if st < 0 then @(~1, steps, nf)
      else if next > i then parse_all(buf, len, next, vals, a, b, c, kk, l2, wv, fl, x0, steps1, nf1)
      else @(~1, steps, nf)
    end
    end
  end

(* ---- entry ---------------------------------------------------------------- *)

fun reject (reason: string): void = println! ("REJECT ", reason)

implement cfg_free (cfg) = let
  val ~CFG(a, b, c, k, l, wv, fl, x0, _, _) = cfg
in
  matrixptr_free(a); matrixptr_free(b); matrixptr_free(c); matrixptr_free(k);
  matrixptr_free(l); matrixptr_free(wv); matrixptr_free(fl); arrayptr_free(x0)
end

fun stage (path: string, buf: !arrayptr(char, 65536), vals: !arrayptr(double, 160),
           a: !matrixptr(double, 4, 4), b: !matrixptr(double, 4, 2), c: !matrixptr(double, 2, 4),
           k: !matrixptr(double, 2, 4), l: !matrixptr(double, 4, 2),
           wv: !matrixptr(double, 128, 6), fl: !matrixptr(double, 16, 4), x0: !arrayptr(double, 4))
  : @(int, int, int) = let
  val n = read_file(path, buf, 65536)
  val len = g1ofg0(n)
in
  if n = ~1 then (reject("unreadable fixture"); @(~1, 0, 0))
  else if n = ~2 then (reject("fixture exceeds the 65536 byte input capacity"); @(~1, 0, 0))
  else if len >= 0 then
    (if len <= 65536 then let
       val v = verify(buf, len, 0, 0x811C9DC5u)
     in
       if v < 0 then (reject("missing Z checksum line"); @(~1, 0, 0))
       else if v = 0 then (reject("checksum mismatch"); @(~1, 0, 0))
       else let
         val r = parse_all(buf, len, 0, vals, a, b, c, k, l, wv, fl, x0, 0, 0)
       in
         (if r.0 < 0 then reject("malformed or out-of-shape record"); r)
       end
     end else (reject("fixture exceeds the 65536 byte input capacity"); @(~1, 0, 0)))
  else (reject("unreadable fixture"); @(~1, 0, 0))
end

implement load_fixture (path) = let
  val buf = arrayptr_make_elt<char>(i2sz(65536), '\000')
  val vals = arrayptr_make_elt<double>(i2sz(160), 0.0)
  val a = matrixptr_make_elt<double>(i2sz(4), i2sz(4), 0.0)
  val b = matrixptr_make_elt<double>(i2sz(4), i2sz(2), 0.0)
  val c = matrixptr_make_elt<double>(i2sz(2), i2sz(4), 0.0)
  val k = matrixptr_make_elt<double>(i2sz(2), i2sz(4), 0.0)
  val l = matrixptr_make_elt<double>(i2sz(4), i2sz(2), 0.0)
  val wv = matrixptr_make_elt<double>(i2sz(128), i2sz(6), 0.0)
  val fl = matrixptr_make_elt<double>(i2sz(16), i2sz(4), 0.0)
  val x0 = arrayptr_make_elt<double>(i2sz(4), 0.0)
  val @(st, steps, nf) = stage(path, buf, vals, a, b, c, k, l, wv, fl, x0)
  val () = arrayptr_free(buf)
  val () = arrayptr_free(vals)
in
  if st < 0 then let
    val () = (matrixptr_free(a); matrixptr_free(b); matrixptr_free(c); matrixptr_free(k))
    val () = (matrixptr_free(l); matrixptr_free(wv); matrixptr_free(fl); arrayptr_free(x0))
  in None_vt() end
  else Some_vt(CFG(a, b, c, k, l, wv, fl, x0, steps, nf))
end
