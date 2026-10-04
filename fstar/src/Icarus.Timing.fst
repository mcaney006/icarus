module Icarus.Timing

let frame_budget : nat = 1000

type stage = | Acquire | Normalize | Estimate | Decide | Control | Validate | Record

let budget (s:stage) : nat =
  match s with
  | Acquire -> 120 | Normalize -> 80 | Estimate -> 220 | Decide -> 180
  | Control -> 160 | Validate -> 90 | Record -> 50

let stages : list stage = [Acquire; Normalize; Estimate; Decide; Control; Validate; Record]

let rec sum_budgets (l:list stage) : nat =
  match l with
  | [] -> 0
  | s :: rest -> budget s + sum_budgets rest

let schedule_fits : squash (sum_budgets stages <= frame_budget) = assert_norm (sum_budgets stages <= frame_budget)

let margin : nat = frame_budget - sum_budgets stages

let margin_is_100 : squash (margin = 100) = assert_norm (margin = 100)

type ticks = t:nat{t <= frame_budget}

type ledger = { used: ticks }

let frame (before after:ticks) (a:Type) = l:ledger{l.used = before} -> (a & l':ledger{l'.used = after})

let ( let! ) (#a #b:Type) (#t0 #t1 #t2:ticks) (m:frame t0 t1 a) (k:a -> frame t1 t2 b) : frame t0 t2 b =
  fun l -> let (x, l') = m l in k x l'

let idle (#t:ticks) : frame t t unit = fun l -> ((), l)

let run_stage (s:stage) (#t:ticks{t + budget s <= frame_budget}) : frame t (t + budget s) unit =
  fun l -> ((), { used = l.used + budget s })

let rec run_stages (#t:ticks) (ss:list stage{t + sum_budgets ss <= frame_budget})
  : Tot (frame t (t + sum_budgets ss) unit) (decreases ss) =
  match ss with
  | [] -> idle
  | s :: rest -> let! () = run_stage s #t in run_stages #(t + budget s) rest

let nominal : frame 0 (sum_budgets stages) unit = run_stages stages

let nominal_uses_900 : squash ((snd (nominal { used = 0 })).used = 900) = assert_norm (sum_budgets stages = 900)

type outcome =
  | Charged : l:ledger -> outcome
  | Overrun : excess:pos -> outcome

let charge (l:ledger) (cost:nat)
  : o:outcome{(Charged? o ==> (Charged?.l o).used = l.used + cost) /\
              (Overrun? o ==> l.used + cost = frame_budget + Overrun?.excess o)} =
  if l.used + cost <= frame_budget then Charged { used = l.used + cost } else Overrun (l.used + cost - frame_budget)

let after_nominal : ledger = { used = 900 }

let overrun_larger_than_margin_detected (extra:nat)
  : Lemma (requires extra > margin)
          (ensures Overrun? (charge after_nominal extra) /\ Overrun?.excess (charge after_nominal extra) = extra - margin) =
  assert_norm (margin = 100)

let overrun_within_margin_absorbed (extra:nat)
  : Lemma (requires extra <= margin) (ensures Charged? (charge after_nominal extra)) =
  assert_norm (margin = 100)

let deadline_miss (overrun:nat) : bool = Overrun? (charge after_nominal overrun)

let miss_iff_beyond_margin (overrun:nat) : Lemma (deadline_miss overrun <==> overrun > margin) =
  assert_norm (margin = 100)
