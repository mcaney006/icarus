/-!
Mathematical model of the fixed-capacity history buffer that F* (`Icarus.Ring`),
Idris (`Icarus.Ring`) and ATS (`ring.sats`) implement over a physical array. The
model keeps the retained elements newest-first; the physical implementations must
agree with it at every age they allow a read.
-/
set_option autoImplicit false

namespace Icarus.Ring

structure Ring (α : Type) (cap : Nat) where
  slots : List α
  bound : slots.length ≤ cap

variable {α : Type} {cap : Nat}

def empty : Ring α cap := ⟨[], Nat.zero_le _⟩

def Ring.len (r : Ring α cap) : Nat := r.slots.length

def push (r : Ring α cap) (x : α) : Ring α cap :=
  ⟨(x :: r.slots).take cap, by rw [List.length_take]; omega⟩

/-- A read must name an age below the occupied length, so no unwritten slot is reachable. -/
def get (r : Ring α cap) (age : Nat) (h : age < r.len) : α := r.slots[age]'h

def pushAll (r : Ring α cap) (xs : List α) : Ring α cap := xs.foldl push r

theorem len_le_cap (r : Ring α cap) : r.len ≤ cap := r.bound

theorem empty_len : (empty : Ring α cap).len = 0 := rfl

theorem push_len (r : Ring α cap) (x : α) : (push r x).len = min (r.len + 1) cap := by
  simp [push, Ring.len, List.length_take]; omega

theorem push_len_saturates (r : Ring α cap) (x : α) (h : r.len = cap) : (push r x).len = cap := by
  rw [push_len]; omega

theorem get_newest (r : Ring α cap) (x : α) (hc : 0 < cap) :
    get (push r x) 0 (by rw [push_len]; omega) = x := by
  cases cap with
  | zero => omega
  | succ c => simp [get, push]

theorem get_older (r : Ring α cap) (x : α) (age : Nat) (ha : age < r.len) (hc : age + 1 < cap) :
    get (push r x) (age + 1) (by rw [push_len]; omega) = get r age ha := by
  simp [get, push]; rfl

/-- After any sequence of pushes the buffer holds exactly the most recent `cap` of them,
newest first. -/
theorem pushAll_slots (r : Ring α cap) (xs : List α) :
    (pushAll r xs).slots = (xs.reverse ++ r.slots).take cap := by
  induction xs generalizing r with
  | nil => simp [pushAll, List.take_of_length_le r.bound]
  | cons y ys ih =>
    show (pushAll (push r y) ys).slots = _
    rw [ih, List.reverse_cons, List.append_assoc, List.singleton_append]
    simp only [push, List.take_append, List.take_take]
    rw [Nat.min_eq_left (Nat.sub_le _ _)]

/-- Every value a read returns was written: no uninitialised element is reachable. -/
theorem read_was_written (xs : List α) (age : Nat) (h : age < (pushAll (empty : Ring α cap) xs).len) :
    get (pushAll (empty : Ring α cap) xs) age h ∈ xs := by
  have hs : (pushAll (empty : Ring α cap) xs).slots = xs.reverse.take cap := by
    rw [pushAll_slots]; simp [empty]
  have hsub : ∀ z ∈ (pushAll (empty : Ring α cap) xs).slots, z ∈ xs := by
    rw [hs]; intro z hz; exact List.mem_reverse.mp (List.mem_of_mem_take hz)
  exact hsub _ (List.getElem_mem h)

/-- Reads return pushes in reverse order of writing. -/
theorem read_order (xs : List α) (age : Nat) (hc : age < cap) :
    (pushAll (empty : Ring α cap) xs).slots[age]? = xs.reverse[age]? := by
  rw [pushAll_slots]; simp [empty, hc]

end Icarus.Ring
