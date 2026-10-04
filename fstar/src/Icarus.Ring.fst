module Icarus.Ring

module Seq = FStar.Seq

type ring (a:Type) (cap:pos) = {
  buf: s:Seq.seq a{Seq.length s = cap};
  head: i:nat{i < cap};
  len: l:nat{l <= cap};
}

let create (#a:Type) (cap:pos) (fill:a) : ring a cap =
  { buf = Seq.create cap fill; head = 0; len = 0 }

let push (#a:Type) (#cap:pos) (r:ring a cap) (x:a) : ring a cap =
  { buf = Seq.upd r.buf r.head x;
    head = (r.head + 1) % cap;
    len = (if r.len < cap then r.len + 1 else cap) }

let slot (#a:Type) (#cap:pos) (r:ring a cap) (age:nat{age < cap}) : i:nat{i < cap} =
  (r.head + cap - 1 - age) % cap

let get (#a:Type) (#cap:pos) (r:ring a cap) (age:nat{age < r.len}) : a =
  Seq.index r.buf (slot r age)

let push_len (#a:Type) (#cap:pos) (r:ring a cap) (x:a)
  : Lemma ((push r x).len = (if r.len < cap then r.len + 1 else cap)) = ()

let len_never_exceeds_capacity (#a:Type) (#cap:pos) (r:ring a cap) (x:a)
  : Lemma ((push r x).len <= cap /\ (push r x).head < cap) = ()

let slot_of_newest (#a:Type) (#cap:pos) (r:ring a cap) (x:a)
  : Lemma (slot (push r x) 0 = r.head)
  = if r.head + 1 < cap
    then FStar.Math.Lemmas.modulo_lemma (r.head + 1) cap
    else FStar.Math.Lemmas.modulo_lemma r.head cap

let get_newest (#a:Type) (#cap:pos) (r:ring a cap) (x:a)
  : Lemma (get (push r x) 0 == x)
  = slot_of_newest r x;
    assert (Seq.index (Seq.upd r.buf r.head x) r.head == x)

let slot_shift (#a:Type) (#cap:pos) (r:ring a cap) (x:a) (age:nat{age + 1 < cap})
  : Lemma (slot (push r x) (age + 1) = slot r age /\ slot r age <> r.head)
  = ()

let get_older (#a:Type) (#cap:pos) (r:ring a cap) (x:a) (age:nat{age < r.len /\ age + 1 < cap})
  : Lemma (age + 1 < (push r x).len /\ get (push r x) (age + 1) == get r age)
  = slot_shift r x age
