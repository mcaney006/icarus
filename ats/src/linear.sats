fun vec_make {n:nat} (n: int(n)): arrayptr(double, n)
fun mat_make {r,c:nat} (r: int(r), c: int(c)): matrixptr(double, r, c)

fun vcopy {n:nat} (dst: !arrayptr(double, n), src: !arrayptr(double, n), n: int(n)): void
fun vzero {n:nat} (v: !arrayptr(double, n), n: int(n)): void
fun vadd {n:nat} (out: !arrayptr(double, n), a: !arrayptr(double, n), b: !arrayptr(double, n), n: int(n)): void
fun vsub {n:nat} (out: !arrayptr(double, n), a: !arrayptr(double, n), b: !arrayptr(double, n), n: int(n)): void
fun vneg {n:nat} (out: !arrayptr(double, n), a: !arrayptr(double, n), n: int(n)): void
fun vscale {n:nat} (out: !arrayptr(double, n), s: double, a: !arrayptr(double, n), n: int(n)): void
fun dot {n:nat} (a: !arrayptr(double, n), b: !arrayptr(double, n), n: int(n)): double
fun norm2 {n:nat} (a: !arrayptr(double, n), n: int(n)): double
fun clamp_all {n:nat} (v: !arrayptr(double, n), n: int(n), lim: double): void

fun matvec {r,c:nat}
  (out: !arrayptr(double, r), m: !matrixptr(double, r, c), v: !arrayptr(double, c),
   r: int(r), c: int(c)): void

fun matmul {r,c,p:nat}
  (out: !matrixptr(double, r, p), a: !matrixptr(double, r, c), b: !matrixptr(double, c, p),
   r: int(r), c: int(c), p: int(p)): void

fun transpose {r,c:nat}
  (out: !matrixptr(double, c, r), a: !matrixptr(double, r, c), r: int(r), c: int(c)): void

fun identity {n:nat} (out: !matrixptr(double, n, n), n: int(n)): void
