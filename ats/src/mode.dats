#define ATS_DYNLOADFLAG 0
#include "share/atspre_staload.hats"
staload "./mode.sats"

implement classify (mask) = let
  val b0 = mask mod 2
  val b1 = (mask / 2) mod 2
  val b2 = (mask / 4) mod 2
  val b3 = (mask / 8) mod 2
  val b4 = (mask / 16) mod 2
  val count = b0 + b1 + b2 + b3 + b4
in
  if b4 = 1 then 3
  else if count >= 2 then 2
  else if count = 1 then 1
  else 0
end

implement decide_mode {m} (m, health, miss, healthy, bad) =
  if m = 3 then (LEGAL_READY_RUNNING() | 4)
  else if m = 4 then
    (if health = 3 then (LEGAL_RUNNING_SAFE() | 6)
     else if health = 2 || miss then (LEGAL_RUNNING_DEGRADED() | 5)
     else (LEGAL_STAY() | 4))
  else if m = 5 then
    (if health = 3 then (LEGAL_DEGRADED_SAFE() | 6)
     else if health = 0 then
       (if healthy + 1 >= 3 then (LEGAL_DEGRADED_RUNNING() | 4) else (LEGAL_STAY() | 5))
     else
       (if bad + 1 >= 3 then (LEGAL_DEGRADED_SAFE() | 6) else (LEGAL_STAY() | 5)))
  else (LEGAL_STAY() | m)
