#define ATS_DYNLOADFLAG 0
#include "share/atspre_staload.hats"
staload "libats/libc/SATS/math.sats"
staload "./linear.sats"

implement vec_make {n} (n) = arrayptr_make_elt<double>(i2sz(n), 0.0)
implement mat_make {r,c} (r, c) = matrixptr_make_elt<double>(i2sz(r), i2sz(c), 0.0)

(* Every loop is indexed by a bounded counter, so each access is proved in range. *)
implement vcopy {n} (dst, src, n) = let
  fun loop {i:nat | i <= n} .<n-i>.
    (dst: !arrayptr(double, n), src: !arrayptr(double, n), n: int(n), i: int(i)): void =
    if i < n then (arrayptr_set_at(dst, i, arrayptr_get_at(src, i)); loop(dst, src, n, i+1))
in loop(dst, src, n, 0) end

implement vzero {n} (v, n) = let
  fun loop {i:nat | i <= n} .<n-i>. (v: !arrayptr(double, n), n: int(n), i: int(i)): void =
    if i < n then (arrayptr_set_at(v, i, 0.0); loop(v, n, i+1))
in loop(v, n, 0) end

implement vadd {n} (out, a, b, n) = let
  fun loop {i:nat | i <= n} .<n-i>.
    (out: !arrayptr(double, n), a: !arrayptr(double, n), b: !arrayptr(double, n),
     n: int(n), i: int(i)): void =
    if i < n then
      (arrayptr_set_at(out, i, arrayptr_get_at(a, i) + arrayptr_get_at(b, i)); loop(out, a, b, n, i+1))
in loop(out, a, b, n, 0) end

implement vsub {n} (out, a, b, n) = let
  fun loop {i:nat | i <= n} .<n-i>.
    (out: !arrayptr(double, n), a: !arrayptr(double, n), b: !arrayptr(double, n),
     n: int(n), i: int(i)): void =
    if i < n then
      (arrayptr_set_at(out, i, arrayptr_get_at(a, i) - arrayptr_get_at(b, i)); loop(out, a, b, n, i+1))
in loop(out, a, b, n, 0) end

implement vneg {n} (out, a, n) = let
  fun loop {i:nat | i <= n} .<n-i>.
    (out: !arrayptr(double, n), a: !arrayptr(double, n), n: int(n), i: int(i)): void =
    if i < n then (arrayptr_set_at(out, i, ~(arrayptr_get_at(a, i))); loop(out, a, n, i+1))
in loop(out, a, n, 0) end

implement vscale {n} (out, s, a, n) = let
  fun loop {i:nat | i <= n} .<n-i>.
    (out: !arrayptr(double, n), s: double, a: !arrayptr(double, n), n: int(n), i: int(i)): void =
    if i < n then (arrayptr_set_at(out, i, s * arrayptr_get_at(a, i)); loop(out, s, a, n, i+1))
in loop(out, s, a, n, 0) end

implement dot {n} (a, b, n) = let
  fun loop {i:nat | i <= n} .<n-i>.
    (a: !arrayptr(double, n), b: !arrayptr(double, n), n: int(n), i: int(i), acc: double): double =
    if i < n then loop(a, b, n, i+1, acc + arrayptr_get_at(a, i) * arrayptr_get_at(b, i)) else acc
in loop(a, b, n, 0, 0.0) end

implement norm2 {n} (a, n) = let
  fun loop {i:nat | i <= n} .<n-i>.
    (a: !arrayptr(double, n), n: int(n), i: int(i), acc: double): double =
    if i < n then let val x = arrayptr_get_at(a, i) in loop(a, n, i+1, acc + x * x) end else acc
in sqrt_double(loop(a, n, 0, 0.0)) end

(* Same evaluation order as the reference: min against +lim first, then max against -lim. *)
implement clamp_all {n} (v, n, lim) = let
  fun loop {i:nat | i <= n} .<n-i>. (v: !arrayptr(double, n), n: int(n), lim: double, i: int(i)): void =
    if i < n then let
      val x = arrayptr_get_at(v, i)
      val y = (if x < lim then x else lim): double
      val z = (if y > ~lim then y else ~lim): double
      val () = arrayptr_set_at(v, i, z)
    in loop(v, n, lim, i+1) end
in loop(v, n, lim, 0) end

fun mrow_dot {r,c:nat} {i:nat | i < r} {j:nat | j <= c} .<c-j>.
  (m: !matrixptr(double, r, c), v: !arrayptr(double, c), c: int(c), i: int(i), j: int(j), acc: double): double =
  if j < c then
    mrow_dot(m, v, c, i, j+1, acc + matrixptr_get_at(m, i, c, j) * arrayptr_get_at(v, j))
  else acc

implement matvec {r,c} (out, m, v, r, c) = let
  fun rows {i:nat | i <= r} .<r-i>.
    (out: !arrayptr(double, r), m: !matrixptr(double, r, c), v: !arrayptr(double, c),
     r: int(r), c: int(c), i: int(i)): void =
    if i < r then
      (arrayptr_set_at(out, i, mrow_dot(m, v, c, i, 0, 0.0)); rows(out, m, v, r, c, i+1))
in rows(out, m, v, r, c, 0) end

fun mcell {r,c,p:nat} {i:nat | i < r} {k:nat | k < p} {j:nat | j <= c} .<c-j>.
  (a: !matrixptr(double, r, c), b: !matrixptr(double, c, p), c: int(c), p: int(p),
   i: int(i), k: int(k), j: int(j), acc: double): double =
  if j < c then
    mcell(a, b, c, p, i, k, j+1, acc + matrixptr_get_at(a, i, c, j) * matrixptr_get_at(b, j, p, k))
  else acc

implement matmul {r,c,p} (out, a, b, r, c, p) = let
  fun cols {i:nat | i < r} {k:nat | k <= p} .<p-k>.
    (out: !matrixptr(double, r, p), a: !matrixptr(double, r, c), b: !matrixptr(double, c, p),
     c: int(c), p: int(p), i: int(i), k: int(k)): void =
    if k < p then
      (matrixptr_set_at(out, i, p, k, mcell(a, b, c, p, i, k, 0, 0.0)); cols(out, a, b, c, p, i, k+1))
  fun rows {i:nat | i <= r} .<r-i>.
    (out: !matrixptr(double, r, p), a: !matrixptr(double, r, c), b: !matrixptr(double, c, p),
     r: int(r), c: int(c), p: int(p), i: int(i)): void =
    if i < r then (cols(out, a, b, c, p, i, 0); rows(out, a, b, r, c, p, i+1))
in rows(out, a, b, r, c, p, 0) end

implement transpose {r,c} (out, a, r, c) = let
  fun cols {i:nat | i < r} {j:nat | j <= c} .<c-j>.
    (out: !matrixptr(double, c, r), a: !matrixptr(double, r, c), r: int(r), c: int(c), i: int(i), j: int(j)): void =
    if j < c then
      (matrixptr_set_at(out, j, r, i, matrixptr_get_at(a, i, c, j)); cols(out, a, r, c, i, j+1))
  fun rows {i:nat | i <= r} .<r-i>.
    (out: !matrixptr(double, c, r), a: !matrixptr(double, r, c), r: int(r), c: int(c), i: int(i)): void =
    if i < r then (cols(out, a, r, c, i, 0); rows(out, a, r, c, i+1))
in rows(out, a, r, c, 0) end

implement identity {n} (out, n) = let
  fun cols {i:nat | i < n} {j:nat | j <= n} .<n-j>.
    (out: !matrixptr(double, n, n), n: int(n), i: int(i), j: int(j)): void =
    if j < n then
      (matrixptr_set_at(out, i, n, j, (if i = j then 1.0 else 0.0): double); cols(out, n, i, j+1))
  fun rows {i:nat | i <= n} .<n-i>.
    (out: !matrixptr(double, n, n), n: int(n), i: int(i)): void =
    if i < n then (cols(out, n, i, 0); rows(out, n, i+1))
in rows(out, n, 0) end
