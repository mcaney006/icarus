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
  | running,     degrade  => degraded
  | running,     crit     => safe
  | degraded,    recover  => running
  | degraded,    repeated => safe
  | degraded,    crit     => safe
  | m,           _        => m

def succs : Mode → List Mode
  | boot        => [boot, selfTest, fault]
  | selfTest    => [selfTest, calibrating, fault]
  | calibrating => [calibrating, ready, fault]
  | ready       => [ready, running, safe]
  | running     => [running, degraded, safe]
  | degraded    => [degraded, running, safe]
  | safe        => [safe]
  | fault       => [fault]

def legal (s d : Mode) : Bool := d ∈ succs s

theorem step_legal (m : Mode) (t : Trigger) : legal m (step m t) := by
  cases m <;> cases t <;> decide

theorem safe_terminal (t : Trigger) : step safe t = safe := by cases t <;> rfl
theorem fault_terminal (t : Trigger) : step fault t = fault := by cases t <;> rfl

theorem running_crit_to_safe : step running crit = safe := rfl
theorem degraded_crit_to_safe : step degraded crit = safe := rfl
theorem degraded_repeated_to_safe : step degraded repeated = safe := rfl
theorem ready_to_running : step ready advance = running := rfl

theorem no_boot_to_running (t : Trigger) : step boot t ≠ running := by cases t <;> decide

theorem boot_running_illegal : legal boot running = false := rfl
theorem safe_running_illegal : legal safe running = false := rfl
theorem fault_ready_illegal : legal fault ready = false := rfl

def runList (m : Mode) (ts : List Trigger) : Mode := ts.foldl step m

theorem boot_reaches_running : runList boot [advance, advance, advance, advance] = running := rfl

theorem safe_absorbing (ts : List Trigger) : runList safe ts = safe := by
  induction ts with
  | nil => rfl
  | cons t ts ih => simpa [runList, safe_terminal] using ih

theorem crit_forces_safe (ts : List Trigger) : runList running (crit :: ts) = safe :=
  safe_absorbing ts

end Icarus
