(* Three-channel median voting on a totally ordered value. The median is
   *selected*, never computed, so identical healthy channels vote to exactly
   their common value. The theorems are about integer (fixed-point) channels,
   which are totally ordered; they presuppose no NaN. The double implementations
   use the same selection formula and are covered only by the 20,000-triple
   property check in `reference/icarus_ref.py --selfcheck`. *)
module Icarus.Vote

let med (a b c:int) : int = FStar.Math.Lib.max (FStar.Math.Lib.min a b)
                              (FStar.Math.Lib.min (FStar.Math.Lib.max a b) c)

let med_is_a_member (a b c:int)
  : Lemma (med a b c = a \/ med a b c = b \/ med a b c = c) = ()

(* Whatever the third channel reports, the vote stays inside the interval the
   other two span: a single divergent channel cannot drag it outside. *)
let divergent_cannot_escape (x b c:int)
  : Lemma (FStar.Math.Lib.min b c <= med x b c /\ med x b c <= FStar.Math.Lib.max b c) = ()

(* If two channels agree the vote equals them, in any channel position. *)
let two_agree_first (x b:int) : Lemma (med x b b = b) = ()
let two_agree_second (x b:int) : Lemma (med b x b = b) = ()
let two_agree_third (x b:int) : Lemma (med b b x = b) = ()

(* All three agree: the vote is the common value (no floating-point drift). *)
let unanimous (b:int) : Lemma (med b b b = b) = ()

(* Symmetry: channel order does not change the vote. *)
let symmetric (a b c:int)
  : Lemma (med a b c = med b a c /\ med a b c = med a c b /\ med a b c = med c b a) = ()
