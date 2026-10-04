set_option autoImplicit false

namespace Icarus

structure Ring (α : Type) (cap : Nat) where
  slots : List α
  bound : slots.length ≤ cap

namespace Ring

variable {α : Type} {cap : Nat}

def empty : Ring α cap := ⟨[], Nat.zero_le _⟩

def len (r : Ring α cap) : Nat := r.slots.length

def push (r : Ring α cap) (x : α) : Ring α cap := ⟨(x :: r.slots).take cap, by simp [Nat.min_le_left]⟩

def get (r : Ring α cap) (age : Nat) (h : age < r.len) : α := r.slots[age]

def pushAll (r : Ring α cap) (xs : List α) : Ring α cap := xs.foldl push r

theorem len_le_cap (r : Ring α cap) : r.len ≤ cap := r.bound

theorem empty_len : (empty : Ring α cap).len = 0 := rfl

theorem push_len (r : Ring α cap) (x : α) : (r.push x).len = min (r.len + 1) cap := by
  simp [push, len]; omega

theorem push_len_saturates (r : Ring α cap) (x : α) (h : r.len = cap) : (r.push x).len = cap := by
  rw [push_len]; omega

theorem get_newest (r : Ring α cap) (x : α) (hc : 0 < cap) :
    (r.push x).get 0 (by rw [push_len]; omega) = x := by
  obtain ⟨c, rfl⟩ := Nat.exists_eq_succ_of_ne_zero (Nat.pos_iff_ne_zero.mp hc)
  rfl

theorem get_older (r : Ring α cap) (x : α) (age : Nat) (ha : age < r.len) (hc : age + 1 < cap) :
    (r.push x).get (age + 1) (by rw [push_len]; omega) = r.get age ha := by
  simp [get, push]; rfl

theorem pushAll_slots (r : Ring α cap) (xs : List α) : (r.pushAll xs).slots = (xs.reverse ++ r.slots).take cap := by
  induction xs generalizing r with
  | nil => simp [pushAll, List.take_of_length_le r.bound]
  | cons y ys ih =>
    show ((r.push y).pushAll ys).slots = _
    simp only [ih, push, List.reverse_cons, List.append_assoc, List.singleton_append, List.take_append,
      List.take_take, Nat.min_eq_left (Nat.sub_le _ _)]

theorem read_was_written (xs : List α) (age : Nat) (h : age < ((empty : Ring α cap).pushAll xs).len) :
    ((empty : Ring α cap).pushAll xs).get age h ∈ xs := by
  have written : ∀ z ∈ ((empty : Ring α cap).pushAll xs).slots, z ∈ xs := by
    simpa [pushAll_slots, empty] using fun z hz => List.mem_reverse.mp (List.mem_of_mem_take hz)
  exact written _ (List.getElem_mem h)

theorem read_order (xs : List α) (age : Nat) (hc : age < cap) :
    ((empty : Ring α cap).pushAll xs).slots[age]? = xs.reverse[age]? := by
  simp [pushAll_slots, empty, hc]

end Ring

end Icarus
