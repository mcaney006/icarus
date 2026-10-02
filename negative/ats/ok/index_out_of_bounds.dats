#include "share/atspre_staload.hats"

fun good (v: !arrayptr(double, 4)): double = arrayptr_get_at(v, 3)

implement main0 () = ()
