module Icarus.AbstractCost

open Icarus.Timing

type model = { add: nat; mul: nat; load: nat; store: nat; branch: nat }

let unit_model : model = { add = 1; mul = 1; load = 1; store = 1; branch = 1 }

let heavy_model : model = { add = 1; mul = 3; load = 2; store = 2; branch = 2 }

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

let acquire  (m:model) (slots:nat) : nat =
  matvec m 2 4 + vbin m 2 + 2 * vcopy m 2 + fscan m slots + vote m 2 + vsel m 2
let normalize (m:model) : nat = vany m 2 + vclamp m 2 + vcopy m 2

let estimate (m:model) : nat =
  matvec m 2 4 + vbin m 2 + vnorm m 2 + matvec m 4 4 + matvec m 4 2 + vbin m 4
  + matvec m 4 2 + vbin m 4

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

let scan_all_acquire_exceeds : squash (acquire unit_model 16 > budget Acquire) =
  assert_norm (acquire unit_model 16 > budget Acquire)

let cursor_acquire_fits : squash (acquire unit_model 2 <= budget Acquire) =
  assert_norm (acquire unit_model 2 <= budget Acquire)

let estimate_exceeds : squash (estimate unit_model > budget Estimate) =
  assert_norm (estimate unit_model > budget Estimate)

let merged_estimate_fits : squash (estimate_merged unit_model <= budget Estimate) =
  assert_norm (estimate_merged unit_model <= budget Estimate)

let merged_saving_is_the_monitor
  : squash (estimate unit_model - estimate_merged unit_model
            = matvec unit_model 2 4 + vbin unit_model 2 + vnorm unit_model 2) =
  assert_norm (estimate unit_model - estimate_merged unit_model
               = matvec unit_model 2 4 + vbin unit_model 2 + vnorm unit_model 2)

let frame_fits_scan_all : squash (frame_cost unit_model 16 stages <= frame_budget) =
  assert_norm (frame_cost unit_model 16 stages <= frame_budget)
let frame_fits_cursor : squash (frame_cost unit_model 2 stages <= frame_budget) =
  assert_norm (frame_cost unit_model 2 stages <= frame_budget)

let matvec_monotone (m:model) (r c r' c':nat)
  : Lemma (requires r <= r' /\ c <= c') (ensures matvec m r c <= matvec m r' c') =
  FStar.Math.Lemmas.lemma_mult_le_right c r r';
  FStar.Math.Lemmas.lemma_mult_le_left r' c c';
  FStar.Math.Lemmas.lemma_mult_le_right (elem m + m.branch) (r * c) (r' * c');
  FStar.Math.Lemmas.lemma_mult_le_right m.store r r'
