(* EXPECT: unsolved constraint|mismatch|cannot be resolved *)
(* Multiplying a 4x3 matrix by a 2x4 matrix: the inner dimensions 3 and 2 differ. *)
#include "share/atspre_staload.hats"
staload "./linear.sats"

fun bad (out: !matrixptr(double, 4, 4), a: !matrixptr(double, 4, 3), b: !matrixptr(double, 2, 4)): void =
  matmul(out, a, b, 4, 3, 4)

implement main0 () = ()
