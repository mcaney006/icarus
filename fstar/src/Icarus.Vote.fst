module Icarus.Vote

let med (a b c:int) : int = FStar.Math.Lib.max (FStar.Math.Lib.min a b)
                              (FStar.Math.Lib.min (FStar.Math.Lib.max a b) c)

let med_is_a_member (a b c:int)
  : Lemma (med a b c = a \/ med a b c = b \/ med a b c = c) = ()

let divergent_cannot_escape (x b c:int)
  : Lemma (FStar.Math.Lib.min b c <= med x b c /\ med x b c <= FStar.Math.Lib.max b c) = ()

let two_agree_first (x b:int) : Lemma (med x b b = b) = ()
let two_agree_second (x b:int) : Lemma (med b x b = b) = ()
let two_agree_third (x b:int) : Lemma (med b b x = b) = ()

let unanimous (b:int) : Lemma (med b b b = b) = ()

let symmetric (a b c:int)
  : Lemma (med a b c = med b a c /\ med a b c = med a c b /\ med a b c = med c b a) = ()
