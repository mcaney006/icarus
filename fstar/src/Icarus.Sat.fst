module Icarus.Sat

let scale : pos = 65536
let min_raw : int = -2147483648
let max_raw : int = 2147483647

type fx = x:int{min_raw <= x /\ x <= max_raw}

type result = { v: fx; sat: bool }

let clamp (x:int)
  : r:result{
      (min_raw <= x /\ x <= max_raw ==> r.v = x /\ r.sat = false) /\
      (x < min_raw ==> r.v = min_raw /\ r.sat = true) /\
      (x > max_raw ==> r.v = max_raw /\ r.sat = true) }
  = if x < min_raw then { v = min_raw; sat = true }
    else if x > max_raw then { v = max_raw; sat = true }
    else { v = x; sat = false }

let add (a b:fx)
  : r:result{ r.sat = false ==> r.v = a + b }
  = clamp (a + b)

let sub (a b:fx)
  : r:result{ r.sat = false ==> r.v = a - b }
  = clamp (a - b)

let neg (a:fx) : r:result{ r.sat = false ==> r.v = - a } = clamp (- a)

let round_div (p:int) : int = (p + 32768) / scale

let mul (a b:fx)
  : r:result{
      r.sat = false ==>
        (-32768 <= a * b - scale * r.v /\ a * b - scale * r.v < 32768) }
  = clamp (round_div (a * b))

let of_units (n:int) : result = clamp (n * scale)

let of_units_exact (n:int)
  : Lemma (requires min_raw <= n * scale /\ n * scale <= max_raw)
          (ensures (of_units n).sat = false /\ (of_units n).v = n * scale) = ()

let max_units : int = max_raw / scale
let range_units () : Lemma (max_units = 32767) = assert_norm (max_units = 32767)
