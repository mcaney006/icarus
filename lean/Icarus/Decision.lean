import Icarus.Modes
import Icarus.Faults

set_option autoImplicit false

namespace Icarus

structure Monitor where
  mode : Mode
  healthy : Nat
  bad : Nat
deriving DecidableEq, Repr

def recoveryFrames : Nat := 3
def degradedLimit : Nat := 3

def operational : Mode → Bool
  | .ready | .running | .degraded | .safe => true
  | _ => false

namespace Monitor

def initial : Monitor := ⟨.ready, 0, 0⟩

def next (s : Monitor) (h : Health) (miss : Bool) : Monitor :=
  let healthy := if h = .healthy then s.healthy + 1 else 0
  match s.mode with
  | .ready => ⟨.running, healthy, s.bad⟩
  | .running =>
    if h = .unsafe_ then ⟨.safe, healthy, s.bad⟩
    else if h = .degraded ∨ miss then ⟨.degraded, healthy, 0⟩
    else ⟨.running, healthy, s.bad⟩
  | .degraded =>
    if h = .unsafe_ then ⟨.safe, healthy, s.bad⟩
    else if h = .healthy then ⟨if recoveryFrames ≤ s.healthy + 1 then .running else .degraded, healthy, s.bad⟩
    else ⟨if degradedLimit ≤ s.bad + 1 then .safe else .degraded, healthy, s.bad + 1⟩
  | m => ⟨m, healthy, s.bad⟩

def trigger (s : Monitor) (h : Health) (miss : Bool) : Trigger :=
  match s.mode with
  | .running =>
    if h = .unsafe_ then .crit else if h = .degraded ∨ miss then .degrade else .advance
  | .degraded =>
    if h = .unsafe_ then .crit
    else if h = .healthy then (if recoveryFrames ≤ s.healthy + 1 then .recover else .advance)
    else if degradedLimit ≤ s.bad + 1 then .repeated else .advance
  | _ => .advance

def run (s : Monitor) (frames : List (Health × Bool)) : Monitor :=
  frames.foldl (fun s (h, miss) => s.next h miss) s

end Monitor

syntax "monitor_cases " ident : tactic

macro_rules
  | `(tactic| monitor_cases $s) =>
    `(tactic| (obtain ⟨m, _, _⟩ := $s
               cases m <;> simp only [Monitor.next, Monitor.trigger] at * <;> repeat' split
               all_goals simp_all [legal, succs, step, operational]))

open Monitor

theorem next_legal (s : Monitor) (h : Health) (miss : Bool) : legal s.mode (s.next h miss).mode := by
  monitor_cases s

theorem safe_absorbs (s : Monitor) (h : Health) (miss : Bool) (hs : s.mode = .safe) :
    (s.next h miss).mode = .safe := by monitor_cases s

theorem fault_absorbs (s : Monitor) (h : Health) (miss : Bool) (hs : s.mode = .fault) :
    (s.next h miss).mode = .fault := by monitor_cases s

theorem unsafe_forces_safe (s : Monitor) (miss : Bool) (hs : s.mode = .running ∨ s.mode = .degraded) :
    (s.next .unsafe_ miss).mode = .safe := by monitor_cases s

theorem overrun_degrades (s : Monitor) (h : Health) (hs : s.mode = .running) (hn : h ≠ .unsafe_) :
    (s.next h true).mode = .degraded := by monitor_cases s

theorem recovers (s : Monitor) (hs : s.mode = .degraded) (hh : recoveryFrames ≤ s.healthy + 1) :
    (s.next .healthy false).mode = .running := by monitor_cases s

theorem repeated_bad_to_safe (s : Monitor) (h : Health) (hs : s.mode = .degraded) (hn : h ≠ .healthy)
    (hl : degradedLimit ≤ s.bad + 1) : (s.next h false).mode = .safe := by monitor_cases s

theorem next_operational (s : Monitor) (h : Health) (miss : Bool) (hs : operational s.mode) :
    operational (s.next h miss).mode := by monitor_cases s

theorem next_is_step (s : Monitor) (h : Health) (miss : Bool) (hs : operational s.mode) :
    (s.next h miss).mode = step s.mode (s.trigger h miss) := by monitor_cases s

theorem run_invariant (P : Mode → Prop)
    (preserved : ∀ (s : Monitor) (h : Health) (miss : Bool), P s.mode → P (s.next h miss).mode) :
    ∀ (s : Monitor) (frames : List (Health × Bool)), P s.mode → P (s.run frames).mode
  | _, [], hs => hs
  | s, (h, miss) :: rest, hs => run_invariant P preserved (s.next h miss) rest (preserved s h miss hs)

theorem safe_forever (s : Monitor) (frames : List (Health × Bool)) (hs : s.mode = .safe) :
    (s.run frames).mode = .safe :=
  run_invariant (· = .safe) (fun s h miss => safe_absorbs s h miss) s frames hs

theorem unsafe_is_permanent (s : Monitor) (miss : Bool) (rest : List (Health × Bool))
    (hs : s.mode = .running ∨ s.mode = .degraded) : (s.run ((.unsafe_, miss) :: rest)).mode = .safe :=
  safe_forever _ rest (unsafe_forces_safe s miss hs)

theorem runFrames_operational (s : Monitor) (frames : List (Health × Bool)) (hs : operational s.mode) :
    operational (s.run frames).mode :=
  run_invariant (operational · = true) next_operational s frames hs

theorem never_boot (frames : List (Health × Bool)) :
    (initial.run frames).mode ≠ .boot ∧ (initial.run frames).mode ≠ .fault := by
  have h := runFrames_operational initial frames rfl
  revert h; cases (initial.run frames).mode <;> decide

end Icarus
