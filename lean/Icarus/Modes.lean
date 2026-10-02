/-
Abstract mode machine for icarus, specified and proved in Lean. `step` is total;
`succs` is the independently-written reachability table. The theorems establish
that every transition `step` can take is in the table, that Safe/Fault absorb,
that the critical-health trigger forces Safe from an operational mode, and that
Safe is inescapable thereafter. Mirrors reference/icarus_ref.py (the `crit`
trigger corresponds to Health.Unsafe there; `unsafe` is a Lean keyword).
-/
set_option autoImplicit false

namespace Icarus

inductive Mode
  | boot | selfTest | calibrating | ready | running | degraded | safe | fault
deriving DecidableEq, Repr

inductive Trigger
  | advance | degrade | recover | crit | repeated
deriving DecidableEq, Repr

open Mode Trigger

def step : Mode → Trigger → Mode
  | boot,        advance  => selfTest
  | selfTest,    advance  => calibrating
  | calibrating, advance  => ready
  | ready,       advance  => running
  | ready,       crit     => safe
  | running,     advance  => running
  | running,     degrade  => degraded
  | running,     crit     => safe
  | degraded,    advance  => degraded
  | degraded,    recover  => running
  | degraded,    repeated => safe
  | degraded,    crit     => safe
  | safe,        _        => safe
  | fault,       _        => fault
  | m,           _        => m

/-- Allowed successors per mode, written independently of `step`. -/
def succs : Mode → List Mode
  | boot        => [selfTest, boot, fault]
  | selfTest    => [calibrating, selfTest, fault]
  | calibrating => [ready, calibrating, fault]
  | ready       => [running, ready, safe]
  | running     => [running, degraded, safe]
  | degraded    => [degraded, running, safe]
  | safe        => [safe]
  | fault       => [fault]

def legal (s d : Mode) : Bool := decide (d ∈ succs s)

/-- Every transition the machine can take is in the legal table. -/
theorem step_legal (m : Mode) (t : Trigger) : legal m (step m t) = true := by
  cases m <;> cases t <;> decide

theorem safe_terminal (t : Trigger) : step safe t = safe := by cases t <;> rfl
theorem fault_terminal (t : Trigger) : step fault t = fault := by cases t <;> rfl

theorem running_crit_to_safe     : step running crit  = safe := rfl
theorem degraded_crit_to_safe    : step degraded crit = safe := rfl
theorem degraded_repeated_to_safe: step degraded repeated = safe := rfl
theorem ready_to_running         : step ready advance = running := rfl

/-- The spec's illegal transitions are rejected by construction. -/
theorem no_boot_to_running (t : Trigger) : step boot t ≠ running := by
  cases t <;> decide
example : legal boot running = false := by decide
example : legal safe running = false := by decide
example : legal fault ready  = false := by decide

def runList (m : Mode) (ts : List Trigger) : Mode := ts.foldl step m

/-- Running is reachable from Boot. -/
theorem boot_reaches_running :
    runList boot [advance, advance, advance, advance] = running := by decide

theorem foldl_step_safe (ts : List Trigger) : ts.foldl step safe = safe := by
  induction ts with
  | nil => rfl
  | cons t ts ih => rw [List.foldl_cons, safe_terminal]; exact ih

/-- Once Safe, always Safe, for any sequence of triggers. -/
theorem safe_absorbing (ts : List Trigger) : runList safe ts = safe := by
  unfold runList; exact foldl_step_safe ts

/-- A critical trigger in Running makes Safe inevitable regardless of what follows. -/
theorem crit_forces_safe (ts : List Trigger) :
    runList running (crit :: ts) = safe := by
  unfold runList; rw [List.foldl_cons, running_crit_to_safe]; exact foldl_step_safe ts

end Icarus
