(* Telemetry wire layer: decimal encode/decode with a proved round trip, plus
   the FNV-1a checksum used by the ICF format (spec/ICF.md). Digits are a
   refined type, so an encoder can never emit a value outside 0..9. *)
module Icarus.Wire

module L = FStar.List.Tot
module LP = FStar.List.Tot.Properties
module U32 = FStar.UInt32

type digit = d:nat{d < 10}

let rec enc_nat (n:nat) : Tot (l:list digit{Cons? l}) (decreases n) =
  if n < 10 then [n] else L.append (enc_nat (n / 10)) [n % 10]

let dec_digits (acc:nat) (l:list digit) : nat =
  L.fold_left (fun (a:nat) (d:digit) -> a * 10 + d) acc l

let rec enc_dec_digits (n:nat)
  : Lemma (ensures dec_digits 0 (enc_nat n) = n) (decreases n)
  = if n < 10 then ()
    else begin
      enc_dec_digits (n / 10);
      LP.fold_left_append (fun (a:nat) (d:digit) -> a * 10 + d) (enc_nat (n / 10)) [n % 10]
    end

let digit_char (d:digit) : FStar.Char.char =
  match d with
  | 0 -> '0' | 1 -> '1' | 2 -> '2' | 3 -> '3' | 4 -> '4'
  | 5 -> '5' | 6 -> '6' | 7 -> '7' | 8 -> '8' | _ -> '9'

let char_digit (c:FStar.Char.char) : option digit =
  match c with
  | '0' -> Some 0 | '1' -> Some 1 | '2' -> Some 2 | '3' -> Some 3 | '4' -> Some 4
  | '5' -> Some 5 | '6' -> Some 6 | '7' -> Some 7 | '8' -> Some 8 | '9' -> Some 9
  | _ -> None

let char_digit_inverts (d:digit) : Lemma (char_digit (digit_char d) = Some d) = ()

let enc_chars (n:nat) : l:list FStar.Char.char{Cons? l} = L.map digit_char (enc_nat n)

let rec dec_acc (acc:nat) (l:list FStar.Char.char) : Tot (option nat) (decreases l) =
  match l with
  | [] -> Some acc
  | c :: r ->
    (match char_digit c with
     | None -> None
     | Some d -> dec_acc (acc * 10 + d) r)

let rec dec_acc_of_digits (acc:nat) (ds:list digit)
  : Lemma (ensures dec_acc acc (L.map digit_char ds) = Some (dec_digits acc ds))
          (decreases ds)
  = match ds with
    | [] -> ()
    | d :: rest -> char_digit_inverts d; dec_acc_of_digits (acc * 10 + d) rest

(* Decoding what was encoded returns the original number. *)
let roundtrip (n:nat) : Lemma (dec_acc 0 (enc_chars n) = Some n)
  = dec_acc_of_digits 0 (enc_nat n); enc_dec_digits n

let enc_int (i:int) : list FStar.Char.char =
  if i < 0 then '-' :: enc_chars (- i) else enc_chars i

let dec_int (l:list FStar.Char.char) : option int =
  match l with
  | [] -> None
  | c :: rest ->
    if c = '-'
    then (match rest with
          | [] -> None
          | _ -> (match dec_acc 0 rest with Some n -> Some (- n) | None -> None))
    else (match dec_acc 0 l with Some n -> Some n | None -> None)

let digit_char_is_not_minus (d:digit) : Lemma (digit_char d <> '-') = ()

let roundtrip_int (i:int) : Lemma (dec_int (enc_int i) = Some i)
  = if i < 0 then roundtrip (- i)
    else begin
      roundtrip i;
      match enc_nat i with
      | d :: _ -> digit_char_is_not_minus d
    end

(* ---- FNV-1a over characters ------------------------------------------- *)
let fnv_offset : U32.t = 0x811C9DC5ul
let fnv_prime  : U32.t = 0x01000193ul

let fnv_step (h:U32.t) (c:FStar.Char.char) : U32.t =
  U32.mul_mod (U32.logxor h (FStar.Char.u32_of_char c)) fnv_prime

let fnv_line (h:U32.t) (line:list FStar.Char.char) : U32.t =
  fnv_step (L.fold_left fnv_step h line) '\n'
