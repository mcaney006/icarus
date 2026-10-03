(* ABSTRACT COST MODEL. Not a worst-case execution time analysis: the costs below
   are artificial weights on source-level operations, chosen to compare algorithms
   and to check the abstract stage budgets of Icarus.Timing. No processor, memory
   system or compiler is modelled, and nothing here predicts a duration. *)
module Icarus.Cost

open Icarus.Timing

type model = { add: nat; mul: nat; load: nat; store: nat; branch: nat }

(* Every primitive costs one abstract tick. *)
let unit_model : model = { add = 1; mul = 1; load = 1; store = 1; branch = 1 }

(* A deliberately different weighting, to show how conclusions depend on the model. *)
let heavy_model : model = { add = 1; mul = 3; load = 2; store = 2; branch = 2 }

(* One matrix element operation: two loads, a multiply and an add. *)
let elem (m:model) : nat = 2 * m.load + m.mul + m.add

let matvec (m:model) (r c:nat) : nat = r * c * (elem m + m.branch) + r * m.store
let matmul (m:model) (r c p:nat) : nat = r * p * (c * (elem m + m.branch) + m.store)
let vbin   (m:model) (n:nat) : nat = n * (2 * m.load + m.add + m.store + m.branch)
let vcopy  (m:model) (n:nat) : nat = n * (m.load + m.store + m.branch)
let vclamp (m:model) (n:nat) : nat = n * (m.load + 3 * m.branch + m.store)
let vany   (m:model) (n:nat) : nat = n * (m.load + 3 * m.branch)
let vsel   (m:model) (n:nat) : nat = n * (2 * m.load + 2 * m.branch + m.store)
let vnorm  (m:model) (n:nat) : nat = n * (m.load + m.mul + m.add + m.branch)
let vote   (m:model) (p:nat) : nat = p * (3 * m.load + 5 * m.branch + m.store)
let fscan  (m:model) (slots:nat) : nat = slots * (4 * m.load + 2 * m.branch)
let ring_push (m:model) : nat = 2 * m.load + 3 * m.store + 3 * m.branch
let decide_logic (m:model) : nat = 12 * m.branch + 6 * m.load + 4 * m.store

(* The plant has n = 4 states, m = 2 controls, p = 2 measurements. `slots` is how many
   fault-table rows a frame inspects: 16 scans the whole fixed table, 2 follows a
   per-step cursor. *)
let acquire  (m:model) (slots:nat) : nat =
  matvec m 2 4 + vbin m 2 + 2 * vcopy m 2 + fscan m slots + vote m 2 + vsel m 2
let normalize (m:model) : nat = vany m 2 + vclamp m 2 + vcopy m 2

(* Observer as implemented: innovation kept so the disagreement monitor can read it. *)
let estimate (m:model) : nat =
  matvec m 2 4 + vbin m 2 + vnorm m 2 + matvec m 4 4 + matvec m 4 2 + vbin m 4
  + matvec m 4 2 + vbin m 4

(* Observer with (A - L C) folded into one matrix: no innovation is formed. *)
let estimate_merged (m:model) : nat =
  matvec m 4 4 + matvec m 4 2 + matvec m 4 2 + vbin m 4 + vbin m 4

let decide_stage (m:model) (slots:nat) : nat = fscan m slots + decide_logic m
let control  (m:model) : nat = matvec m 2 4 + vcopy m 2 + vany m 2 + vclamp m 2 + vsel m 2
let validate (m:model) : nat = vany m 4 + 10 * m.branch + 6 * m.load
let record   (m:model) : nat = ring_push m + 3 * m.store

let stage_cost (m:model) (slots:nat) (s:stage) : nat =
  match s with
  | Acquire -> acquire m slots
  | Normalize -> normalize m
  | Estimate -> estimate m
  | Decide -> decide_stage m slots
  | Control -> control m
  | Validate -> validate m
  | Record -> record m

let rec frame_cost (m:model) (slots:nat) (l:list stage) : nat =
  match l with | [] -> 0 | s :: r -> stage_cost m slots s + frame_cost m slots r

(* ---- machine-checked statements about the model ------------------------------- *)

(* With the whole 16-row table scanned, Acquire does not fit its budget of 120. *)
let scan_all_acquire_exceeds : squash (acquire unit_model 16 > budget Acquire) =
  assert_norm (acquire unit_model 16 > budget Acquire)

(* Following a per-step cursor (at most 2 rows live) brings it back under. *)
let cursor_acquire_fits : squash (acquire unit_model 2 <= budget Acquire) =
  assert_norm (acquire unit_model 2 <= budget Acquire)

(* The observer as implemented exceeds its 220 budget regardless of scan policy. *)
let estimate_exceeds : squash (estimate unit_model > budget Estimate) =
  assert_norm (estimate unit_model > budget Estimate)

(* The merged observer fits, but only because it omits C x, the innovation and its
   norm: exactly what the estimator-disagreement monitor reads. *)
let merged_estimate_fits : squash (estimate_merged unit_model <= budget Estimate) =
  assert_norm (estimate_merged unit_model <= budget Estimate)

let merged_saving_is_the_monitor
  : squash (estimate unit_model - estimate_merged unit_model
            = matvec unit_model 2 4 + vbin unit_model 2 + vnorm unit_model 2) =
  assert_norm (estimate unit_model - estimate_merged unit_model
               = matvec unit_model 2 4 + vbin unit_model 2 + vnorm unit_model 2)

(* The modelled whole frame stays under the frame budget under both scan policies,
   even though one stage exceeds its own allotment. Per-stage budgets and the frame
   budget are different claims. *)
let frame_fits_scan_all : squash (frame_cost unit_model 16 stages <= frame_budget) =
  assert_norm (frame_cost unit_model 16 stages <= frame_budget)
let frame_fits_cursor : squash (frame_cost unit_model 2 stages <= frame_budget) =
  assert_norm (frame_cost unit_model 2 stages <= frame_budget)

(* Costs grow with every dimension. *)
let matvec_monotone (m:model) (r c r' c':nat)
  : Lemma (requires r <= r' /\ c <= c') (ensures matvec m r c <= matvec m r' c') =
  FStar.Math.Lemmas.lemma_mult_le_right c r r';
  FStar.Math.Lemmas.lemma_mult_le_left r' c c';
  FStar.Math.Lemmas.lemma_mult_le_right (elem m + m.branch) (r * c) (r' * c');
  FStar.Math.Lemmas.lemma_mult_le_right m.store r r'
