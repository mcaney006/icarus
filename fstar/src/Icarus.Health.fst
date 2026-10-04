module Icarus.Health

type health = | Healthy | Suspect | Degraded | Unsafe

type flags = { meas: bool; est: bool; timing: bool; ctrl_sat: bool; numeric: bool }

let indicator (b:bool) : n:nat{n <= 1} = if b then 1 else 0

let count (f:flags) : n:nat{n <= 5} =
  indicator f.meas + indicator f.est + indicator f.timing + indicator f.ctrl_sat + indicator f.numeric

let classify (f:flags) : health =
  if f.numeric then Unsafe
  else if count f >= 2 then Degraded
  else if count f = 1 then Suspect
  else Healthy

let health_code (h:health) : n:nat{n <= 3} =
  match h with | Healthy -> 0 | Suspect -> 1 | Degraded -> 2 | Unsafe -> 3

let bit (m:nat) (place:pos) : bool = (m / place) % 2 = 1

type mask = m:nat{m < 32}

let of_mask (m:mask) : flags =
  { meas = bit m 1; est = bit m 2; timing = bit m 4; ctrl_sat = bit m 8; numeric = bit m 16 }

let to_mask (f:flags) : mask =
  indicator f.meas + 2 * indicator f.est + 4 * indicator f.timing + 8 * indicator f.ctrl_sat
  + 16 * indicator f.numeric

let mask_roundtrip (m:mask) : Lemma (to_mask (of_mask m) = m) = ()

let numeric_dominates (f:flags) : Lemma (f.numeric ==> classify f = Unsafe) = ()

let no_flags_healthy (f:flags) : Lemma (count f = 0 ==> classify f = Healthy) = ()

let leq (f g:flags) : bool =
  (not f.meas || g.meas) && (not f.est || g.est) && (not f.timing || g.timing)
  && (not f.ctrl_sat || g.ctrl_sat) && (not f.numeric || g.numeric)

let monotone (f g:flags)
  : Lemma (requires leq f g) (ensures health_code (classify f) <= health_code (classify g)) = ()
