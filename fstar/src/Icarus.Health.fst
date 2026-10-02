(* Deterministic health monitor over the five fault-flag sources. The mask
   encoding is shared with the ICF fixture format (spec/ICF.md). *)
module Icarus.Health

type health = | Healthy | Suspect | Degraded | Unsafe

type flags = {
  meas: bool;
  est: bool;
  timing: bool;
  ctrl_sat: bool;
  numeric: bool;
}

let b2n (b:bool) : n:nat{n <= 1} = if b then 1 else 0

let count (f:flags) : n:nat{n <= 5} =
  b2n f.meas + b2n f.est + b2n f.timing + b2n f.ctrl_sat + b2n f.numeric

let classify (f:flags) : health =
  if f.numeric then Unsafe
  else if count f >= 2 then Degraded
  else if count f = 1 then Suspect
  else Healthy

let rank (h:health) : n:nat{n <= 3} =
  match h with | Healthy -> 0 | Suspect -> 1 | Degraded -> 2 | Unsafe -> 3

let health_code (h:health) : n:nat{n <= 3} = rank h

let bit (m:nat) (k:pos) : bool = (m / k) % 2 = 1

let of_mask (m:nat{m < 32}) : flags = {
  meas = bit m 1; est = bit m 2; timing = bit m 4;
  ctrl_sat = bit m 8; numeric = bit m 16;
}

let to_mask (f:flags) : n:nat{n < 32} =
  b2n f.meas + 2 * b2n f.est + 4 * b2n f.timing + 8 * b2n f.ctrl_sat + 16 * b2n f.numeric

let mask_roundtrip (m:nat{m < 32}) : Lemma (to_mask (of_mask m) = m) = ()

let numeric_dominates (f:flags) : Lemma (f.numeric ==> classify f = Unsafe) = ()

let no_flags_healthy (f:flags)
  : Lemma (count f = 0 ==> classify f = Healthy) = ()

(* Raising any flag never lowers the reported health. *)
let implies (a b:bool) : bool = not a || b
let leq (f g:flags) : bool =
  implies f.meas g.meas && implies f.est g.est && implies f.timing g.timing
  && implies f.ctrl_sat g.ctrl_sat && implies f.numeric g.numeric

let monotone (f g:flags)
  : Lemma (requires leq f g) (ensures rank (classify f) <= rank (classify g)) = ()
