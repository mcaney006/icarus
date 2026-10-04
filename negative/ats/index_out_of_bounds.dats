#include "share/atspre_staload.hats"

fun bad (v: !arrayptr(double, 4)): double = arrayptr_get_at(v, 4)

implement main0 () = ()
