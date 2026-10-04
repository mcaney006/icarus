module Icarus.SatCheck

open FStar.All
open Icarus.Wire
open Icarus.Sat

module L = FStar.List.Tot
module S = FStar.String

let to_fx (i:int) : option fx =
  if min_raw <= i && i <= max_raw then Some i else None

let apply (op:string) (a b:int) : option result =
  match to_fx a, to_fx b with
  | Some x, Some y ->
    if op = "a" then Some (add x y)
    else if op = "s" then Some (sub x y)
    else if op = "m" then Some (mul x y)
    else None
  | _, _ -> None

let one (line:string) : ML string =
  match L.filter (fun t -> t <> "") (S.split [' '] line) with
  | [op; a; b] ->
    (match dec_int (S.list_of_string a), dec_int (S.list_of_string b) with
     | Some x, Some y ->
       (match apply op x y with
        | Some r -> S.string_of_list (enc_int r.v) ^ " " ^ (if r.sat then "1" else "0")
        | None -> "ERR operand out of range")
     | _, _ -> "ERR malformed operand")
  | _ -> "ERR malformed line"

let run (content:string) : ML int =
  let lines = L.filter (fun l -> l <> "") (S.split ['\n'] content) in
  List.iter (fun l -> FStar.IO.print_string (one l ^ "\n")) lines;
  0
