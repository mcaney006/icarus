absvtype pool_vt(n:int, avail:int) = ptr

fun pool_make {n:nat} (n: int(n)): pool_vt(n, 1)
fun pool_take {n:nat} (p: pool_vt(n, 1)): @(pool_vt(n, 0), arrayptr(double, n))
fun pool_give {n:nat} (p: pool_vt(n, 0), lease: arrayptr(double, n)): pool_vt(n, 1)
fun pool_free {n:nat} (p: pool_vt(n, 1)): void
