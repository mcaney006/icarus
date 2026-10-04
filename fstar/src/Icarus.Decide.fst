module Icarus.Decide

open FStar.All
open Icarus.Health
open Icarus.Mode
open Icarus.Wire

module L = FStar.List.Tot
module S = FStar.String
module U32 = FStar.UInt32

let tokens (line:string) : list string = L.filter (fun t -> t <> "") (S.split [' '] line)

let rec parse_ints (ts:list string) : option (list int) =
  match ts with
  | [] -> Some []
  | t :: rest ->
    (match dec_int (S.list_of_string t), parse_ints rest with
     | Some v, Some vs -> Some (v :: vs)
     | _, _ -> None)

let rec as_masks (xs:list int) : option (list mask) =
  match xs with
  | [] -> Some []
  | x :: rest ->
    if 0 <= x && x < 32
    then (match as_masks rest with Some ms -> Some (x :: ms) | None -> None)
    else None

type scan = { hash: U32.t; masks: option (list int); sealed: option bool }

let scan_line (acc:scan) (line:string) : scan =
  match tokens line with
  | ["Z"; digest] -> { acc with sealed = Some (dec_int (S.list_of_string digest) = Some (U32.v acc.hash)) }
  | "G" :: masks -> { acc with hash = fnv_line acc.hash (S.list_of_string line); masks = parse_ints masks }
  | _ -> { acc with hash = fnv_line acc.hash (S.list_of_string line) }

type replay_state = { monitor: st; modes: list int; healths: list int }

let replay_frame (r:replay_state) (m:mask) : replay_state =
  let f = of_mask m in
  let h = classify f in
  { monitor = decide r.monitor h f.timing;
    modes = mode_code r.monitor.mode :: r.modes;
    healths = health_code h :: r.healths }

let replay (masks:list mask) : list int & list int =
  let r = L.fold_left replay_frame { monitor = initial; modes = []; healths = [] } masks in
  (L.rev (mode_code r.monitor.mode :: r.modes), L.rev r.healths)

let render (tag:string) (xs:list int) : string = S.concat " " (tag :: L.map (fun x -> S.string_of_list (enc_int x)) xs)

let reject (reason:string) : ML int = FStar.IO.print_string ("REJECT " ^ reason ^ "\n"); 3

let run (content:string) : ML int =
  let r = L.fold_left scan_line { hash = fnv_offset; masks = None; sealed = None } (S.split ['\n'] content) in
  match r.sealed, r.masks with
  | None, _ -> reject "missing Z checksum line"
  | Some false, _ -> reject "checksum mismatch"
  | Some true, None -> reject "missing or malformed G record"
  | Some true, Some ints ->
    match as_masks ints with
    | None -> reject "flag mask out of range"
    | Some masks ->
      let (modes, healths) = replay masks in
      FStar.IO.print_string (render "M" modes ^ "\n" ^ render "H" healths ^ "\n");
      0
