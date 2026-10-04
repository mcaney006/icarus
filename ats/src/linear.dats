#define ATS_DYNLOADFLAG 0
#include "share/atspre_staload.hats"
staload "libats/libc/SATS/math.sats"
staload "./linear.sats"

implement vec_make {n} (n) = arrayptr_make_elt<double>(i2sz(n), 0.0)
implement mat_make {r,c} (r, c) = matrixptr_make_elt<double>(i2sz(r), i2sz(c), 0.0)

extern fun {} zip$op (x: double, y: double): double
extern fun {} map$op (x: double): double

fun {} vzip {n:nat} (out: !arrayptr(double, n), a: !arrayptr(double, n), b: !arrayptr(double, n), n: int(n)): void = let
  fun loop {i:nat | i <= n} .<n-i>. (out: !arrayptr(double, n), a: !arrayptr(double, n), b: !arrayptr(double, n), i: int(i)): void =
    if i < n then (arrayptr_set_at(out, i, zip$op<>(arrayptr_get_at(a, i), arrayptr_get_at(b, i))); loop(out, a, b, i + 1))
in loop(out, a, b, 0) end

fun {} vmap {n:nat} (out: !arrayptr(double, n), a: !arrayptr(double, n), n: int(n)): void = let
  fun loop {i:nat | i <= n} .<n-i>. (out: !arrayptr(double, n), a: !arrayptr(double, n), i: int(i)): void =
    if i < n then (arrayptr_set_at(out, i, map$op<>(arrayptr_get_at(a, i))); loop(out, a, i + 1))
in loop(out, a, 0) end

fun {} vmap_inplace {n:nat} (v: !arrayptr(double, n), n: int(n)): void = let
  fun loop {i:nat | i <= n} .<n-i>. (v: !arrayptr(double, n), i: int(i)): void =
    if i < n then let val x = arrayptr_get_at(v, i) in arrayptr_set_at(v, i, map$op<>(x)); loop(v, i + 1) end
in loop(v, 0) end

implement vcopy {n} (dst, src, n) = let implement map$op<> (x) = x in vmap<>(dst, src, n) end
implement vzero {n} (v, n) = let implement map$op<> (_) = 0.0 in vmap_inplace<>(v, n) end
implement vadd {n} (out, a, b, n) = let implement zip$op<> (x, y) = x + y in vzip<>(out, a, b, n) end
implement vsub {n} (out, a, b, n) = let implement zip$op<> (x, y) = x - y in vzip<>(out, a, b, n) end
implement vneg {n} (out, a, n) = let implement map$op<> (x) = ~x in vmap<>(out, a, n) end
implement vscale {n} (out, s, a, n) = let implement map$op<> (x) = s * x in vmap<>(out, a, n) end

implement clamp_all {n} (v, n, limit) = let
  implement map$op<> (x) = let val capped = (if x < limit then x else limit): double in
    if capped > ~limit then capped else ~limit end
in vmap_inplace<>(v, n) end

implement dot {n} (a, b, n) = let
  fun loop {i:nat | i <= n} .<n-i>. (a: !arrayptr(double, n), b: !arrayptr(double, n), i: int(i), acc: double): double =
    if i < n then loop(a, b, i + 1, acc + arrayptr_get_at(a, i) * arrayptr_get_at(b, i)) else acc
in loop(a, b, 0, 0.0) end

implement norm2 {n} (a, n) = let
  fun loop {i:nat | i <= n} .<n-i>. (a: !arrayptr(double, n), i: int(i), acc: double): double =
    if i < n then let val x = arrayptr_get_at(a, i) in loop(a, i + 1, acc + x * x) end else acc
in sqrt_double(loop(a, 0, 0.0)) end

fun row_dot {r,c:nat} {i:nat | i < r} {j:nat | j <= c} .<c-j>.
  (m: !matrixptr(double, r, c), v: !arrayptr(double, c), c: int(c), i: int(i), j: int(j), acc: double): double =
  if j < c then row_dot(m, v, c, i, j + 1, acc + matrixptr_get_at(m, i, c, j) * arrayptr_get_at(v, j)) else acc

implement matvec {r,c} (out, m, v, r, c) = let
  fun rows {i:nat | i <= r} .<r-i>. (out: !arrayptr(double, r), m: !matrixptr(double, r, c), v: !arrayptr(double, c), i: int(i)): void =
    if i < r then (arrayptr_set_at(out, i, row_dot(m, v, c, i, 0, 0.0)); rows(out, m, v, i + 1))
in rows(out, m, v, 0) end

fun cell {r,c,p:nat} {i:nat | i < r} {k:nat | k < p} {j:nat | j <= c} .<c-j>.
  (a: !matrixptr(double, r, c), b: !matrixptr(double, c, p), c: int(c), p: int(p), i: int(i), k: int(k), j: int(j), acc: double): double =
  if j < c then cell(a, b, c, p, i, k, j + 1, acc + matrixptr_get_at(a, i, c, j) * matrixptr_get_at(b, j, p, k)) else acc

implement matmul {r,c,p} (out, a, b, r, c, p) = let
  fun columns {i:nat | i < r} {k:nat | k <= p} .<p-k>.
    (out: !matrixptr(double, r, p), a: !matrixptr(double, r, c), b: !matrixptr(double, c, p), i: int(i), k: int(k)): void =
    if k < p then (matrixptr_set_at(out, i, p, k, cell(a, b, c, p, i, k, 0, 0.0)); columns(out, a, b, i, k + 1))
  fun rows {i:nat | i <= r} .<r-i>. (out: !matrixptr(double, r, p), a: !matrixptr(double, r, c), b: !matrixptr(double, c, p), i: int(i)): void =
    if i < r then (columns(out, a, b, i, 0); rows(out, a, b, i + 1))
in rows(out, a, b, 0) end

implement transpose {r,c} (out, a, r, c) = let
  fun columns {i:nat | i < r} {j:nat | j <= c} .<c-j>. (out: !matrixptr(double, c, r), a: !matrixptr(double, r, c), i: int(i), j: int(j)): void =
    if j < c then (matrixptr_set_at(out, j, r, i, matrixptr_get_at(a, i, c, j)); columns(out, a, i, j + 1))
  fun rows {i:nat | i <= r} .<r-i>. (out: !matrixptr(double, c, r), a: !matrixptr(double, r, c), i: int(i)): void =
    if i < r then (columns(out, a, i, 0); rows(out, a, i + 1))
in rows(out, a, 0) end

implement identity {n} (out, n) = let
  fun columns {i:nat | i < n} {j:nat | j <= n} .<n-j>. (out: !matrixptr(double, n, n), i: int(i), j: int(j)): void =
    if j < n then (matrixptr_set_at(out, i, n, j, (if i = j then 1.0 else 0.0): double); columns(out, i, j + 1))
  fun rows {i:nat | i <= n} .<n-i>. (out: !matrixptr(double, n, n), i: int(i)): void =
    if i < n then (columns(out, i, 0); rows(out, i + 1))
in rows(out, 0) end
