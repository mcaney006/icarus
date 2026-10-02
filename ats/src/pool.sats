(* A pool owning exactly one preallocated buffer. The second index is how many
   buffers are currently free: taking from an empty pool is a type error, a lease
   is a linear array that must be handed back exactly once, and a pool can only be
   freed when every lease has been returned. Nothing here allocates after
   pool_make. *)

absvtype pool_vt(n:int, avail:int) = ptr

fun pool_make {n:nat} (n: int(n)): pool_vt(n, 1)
fun pool_take {n:nat} (p: pool_vt(n, 1)): @(pool_vt(n, 0), arrayptr(double, n))
fun pool_give {n:nat} (p: pool_vt(n, 0), lease: arrayptr(double, n)): pool_vt(n, 1)
fun pool_free {n:nat} (p: pool_vt(n, 1)): void
