#include "share/atspre_staload.hats"
staload "./linear.sats"

fun good (out: !matrixptr(double, 4, 2), a: !matrixptr(double, 4, 3), b: !matrixptr(double, 3, 2)): void =
  matmul(out, a, b, 4, 3, 2)

implement main0 () = ()
