(* Executable driver for the discrete decision layer. Reads an ICF fixture,
   verifies its FNV-1a checksum, takes the per-frame flag masks and runs the
   verified health classifier and mode manager from Ready. Prints the canonical
   M and H lines (spec/ICF.md). Everything with a proof lives in the Icarus.*
   modules this imports; only the string plumbing here is unproved. *)
module Icarus.Decide

open Icarus.Health
open Icarus.Mode
open Icarus.Wire
open FStar.All

module L = FStar.List.Tot
module S = FStar.String
module U32 = FStar.UInt32

let tokens (line:string) : list string =
  L.filter (fun t -> t <> "") (S.split [' '] line)

let rec parse_ints (ts:list string) : option (list int) =
  match ts with
  | [] -> Some []
  | t :: rest ->
    (match dec_int (S.list_of_string t), parse_ints rest with
     | Some v, Some vs -> Some (v :: vs)
     | _, _ -> None)

type scan = {
  hash: U32.t;
  masks: option (list int);
  checked: option bool;
}

let scan_line (acc:scan) (line:string) : scan =
  match tokens line with
  | "Z" :: [v] ->
    (match dec_int (S.list_of_string v) with
     | Some z -> { acc with checked = Some (z = U32.v acc.hash) }
     | None -> { acc with checked = Some false })
  | "G" :: rest ->
    { acc with hash = fnv_line acc.hash (S.list_of_string line);
               masks = parse_ints rest }
  | _ -> { acc with hash = fnv_line acc.hash (S.list_of_string line) }

let rec scan_all (acc:scan) (ls:list string) : Tot scan (decreases ls) =
  match ls with
  | [] -> acc
  | l :: rest -> scan_all (scan_line acc l) rest

let rec simulate (s:st) (masks:list int) (modes:list int) (healths:list int)
  : ML (list int & list int)
  = match masks with
    | [] -> (L.rev (mode_code s.mode :: modes), L.rev healths)
    | m :: rest ->
      if m < 0 || m >= 32 then (failwith "mask out of range")
      else begin
        let h = classify (of_mask m) in
        let miss = (of_mask m).timing in
        let s' = decide s h miss in
        simulate s' rest (mode_code s.mode :: modes) (health_code h :: healths)
      end

let render (tag:string) (xs:list int) : string =
  S.concat " " (tag :: L.map (fun x -> S.string_of_list (enc_int x)) xs)

let run (content:string) : ML int =
  let lines = S.split ['\n'] content in
  let r = scan_all { hash = fnv_offset; masks = None; checked = None } lines in
  match r.checked, r.masks with
  | Some true, Some masks ->
    let (modes, healths) = simulate initial masks [] [] in
    FStar.IO.print_string (render "M" modes ^ "\n");
    FStar.IO.print_string (render "H" healths ^ "\n");
    0
  | Some false, _ -> FStar.IO.print_string "REJECT checksum mismatch\n"; 3
  | None, _ -> FStar.IO.print_string "REJECT missing Z checksum line\n"; 3
  | _, None -> FStar.IO.print_string "REJECT missing or malformed G record\n"; 3
