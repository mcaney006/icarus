module Icarus.Counter

let max_seq : nat = 4294967295

type seqno = n:nat{n <= max_seq}

let bump (s:seqno)
  : r:option seqno{
      (Some? r ==> Some?.v r = s + 1 /\ Some?.v r > s) /\
      (None? r ==> s = max_seq) }
  = if s < max_seq then Some (s + 1) else None

let rec advance (s:seqno) (n:nat) : Tot (option seqno) (decreases n) =
  if n = 0 then Some s
  else match bump s with
       | None -> None
       | Some s' -> advance s' (n - 1)

let rec advance_monotone (s:seqno) (n:nat)
  : Lemma (ensures (match advance s n with Some s' -> s' = s + n | None -> true))
          (decreases n)
  = if n = 0 then () else
    match bump s with
    | None -> ()
    | Some s' -> advance_monotone s' (n - 1)
