(* Prints the cost model as CSV: model, scan slots, stage, modelled cost, budget. *)
module Icarus.CostReport

open FStar.All
open Icarus.Cost
open Icarus.Timing
open Icarus.Wire

module L = FStar.List.Tot
module S = FStar.String

let show (n:int) : string = S.string_of_list (enc_int n)

let name (s:stage) : string =
  match s with
  | Acquire -> "Acquire" | Normalize -> "Normalize" | Estimate -> "Estimate"
  | Decide -> "Decide" | Control -> "Control" | Validate -> "Validate" | Record -> "Record"

let row (label:string) (m:model) (slots:nat) (s:stage) : ML unit =
  FStar.IO.print_string
    (label ^ "," ^ show slots ^ "," ^ name s ^ "," ^ show (stage_cost m slots s) ^ ","
     ^ show (budget s) ^ "\n")

let emit (label:string) (m:model) (slots:nat) : ML unit =
  List.iter (row label m slots) stages;
  FStar.IO.print_string
    (label ^ "," ^ show slots ^ ",TOTAL," ^ show (frame_cost m slots stages) ^ ","
     ^ show frame_budget ^ "\n")

let run (_:string) : ML int =
  emit "unit" unit_model 16; emit "unit" unit_model 2;
  emit "heavy" heavy_model 16; emit "heavy" heavy_model 2;
  FStar.IO.print_string ("estimate_merged,0,Estimate,"
    ^ show (estimate_merged unit_model) ^ "," ^ show (budget Estimate) ^ "\n");
  0
