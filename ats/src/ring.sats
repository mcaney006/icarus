(* Fixed-capacity history of ints. The write index and occupied length carry
   their bounds in their types (head < cap, len <= cap), so neither can leave
   range, and a read refuses ages beyond what has been written. *)

absvtype ring_vt(cap:int) = ptr

fun ring_make {cap:pos} (cap: int(cap)): ring_vt(cap)
fun ring_push {cap:pos} (r: !ring_vt(cap), cap: int(cap), x: int): void
fun ring_len {cap:pos} (r: !ring_vt(cap)): [l:nat | l <= cap] int(l)
fun ring_peek {cap:pos} (r: !ring_vt(cap), cap: int(cap), age: int): int
fun ring_free {cap:pos} (r: ring_vt(cap)): void
