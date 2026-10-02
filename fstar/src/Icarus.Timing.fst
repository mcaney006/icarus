(* Abstract timing ledger. Ticks are fictional; nothing here is a clock or a
   real WCET. The frame invariant sum(stage budgets) <= frame budget is a
   verification obligation: enlarging a stage until the frame is infeasible makes
   this module fail to check. *)
module Icarus.Timing

let frame_budget : nat = 1000

type stage = | Acquire | Normalize | Estimate | Decide | Control | Validate | Record

let budget (s:stage) : nat =
  match s with
  | Acquire -> 120 | Normalize -> 80 | Estimate -> 220 | Decide -> 180
  | Control -> 160 | Validate -> 90 | Record -> 50

let stages : list stage =
  [Acquire; Normalize; Estimate; Decide; Control; Validate; Record]

let rec sum_budgets (l:list stage) : nat =
  match l with | [] -> 0 | s :: r -> budget s + sum_budgets r

(* The schedule fits its frame. Change a stage budget above so that this stops
   being true and the module no longer verifies. *)
let schedule_fits : squash (sum_budgets stages <= frame_budget) =
  assert_norm (sum_budgets stages <= frame_budget)

let margin : nat = frame_budget - sum_budgets stages

let margin_is_100 : squash (margin = 100) = assert_norm (margin = 100)

(* A ledger can never record more ticks than the frame holds. *)
type ledger = { used: n:nat{n <= frame_budget} }

type outcome =
  | Charged : l:ledger -> outcome
  | Overrun : excess:pos -> outcome

let charge (l:ledger) (cost:nat)
  : o:outcome{
      (Charged? o ==> (Charged?.l o).used = l.used + cost) /\
      (Overrun? o ==> l.used + cost = frame_budget + Overrun?.excess o) }
  = if l.used + cost <= frame_budget
    then Charged ({ used = l.used + cost })
    else Overrun (l.used + cost - frame_budget)

let empty : ledger = { used = 0 }

(* The nominal schedule charges every stage and lands on the declared margin. *)
let rec charge_all (l:ledger) (ss:list stage) : Tot (option ledger) (decreases ss) =
  match ss with
  | [] -> Some l
  | s :: rest ->
    (match charge l (budget s) with
     | Charged l' -> charge_all l' rest
     | Overrun _ -> None)

let nominal_completes : squash (Some? (charge_all empty stages)) =
  assert_norm (Some? (charge_all empty stages))

let nominal_uses_900 : squash ((Some?.v (charge_all empty stages)).used = 900) =
  assert_norm ((Some?.v (charge_all empty stages)).used = 900)

(* An injected overrun larger than the margin is always reported, with the
   exact excess; one within the margin is absorbed. *)
let overrun_larger_than_margin_detected (extra:nat)
  : Lemma (requires extra > 100)
          (ensures (let l : ledger = { used = 900 } in
                    Overrun? (charge l extra) /\ Overrun?.excess (charge l extra) = extra - 100))
  = ()

let overrun_within_margin_absorbed (extra:nat)
  : Lemma (requires extra <= 100)
          (ensures (let l : ledger = { used = 900 } in Charged? (charge l extra)))
  = ()

(* The reference's deadline_miss is exactly "Overrun" of the nominal frame. *)
let deadline_miss (overrun_ticks:nat) : bool =
  Overrun? (charge ({ used = 900 }) overrun_ticks)

let miss_iff_beyond_margin (t:nat) : Lemma (deadline_miss t <==> t > 100) = ()
