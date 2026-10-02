/-
The decision layer: health and streak counters in, next mode out. `decide` is the
function the reference and the F*/ATS/Idris implementations realise; the theorems
establish that it only ever takes legal transitions, that it is the abstract
`Modes.step` machine driven by a trigger, and that the modeled faults force the
specified safety transitions.
-/
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

def initial : Monitor := ⟨Mode.ready, 0, 0⟩

/-- One frame of the mode manager, written exactly as in the reference. -/
def decide (s : Monitor) (h : Health) (miss : Bool) : Monitor :=
  let healthy' := if h = Health.healthy then s.healthy + 1 else 0
  match s.mode with
  | Mode.ready => ⟨Mode.running, healthy', s.bad⟩
  | Mode.running =>
    if h = Health.unsafe_ then ⟨Mode.safe, healthy', s.bad⟩
    else if h = Health.degraded ∨ miss = true then ⟨Mode.degraded, healthy', 0⟩
    else ⟨Mode.running, healthy', s.bad⟩
  | Mode.degraded =>
    if h = Health.unsafe_ then ⟨Mode.safe, healthy', s.bad⟩
    else if h = Health.healthy then
      (if recoveryFrames ≤ s.healthy + 1 then ⟨Mode.running, healthy', s.bad⟩
       else ⟨Mode.degraded, healthy', s.bad⟩)
    else
      (if degradedLimit ≤ s.bad + 1 then ⟨Mode.safe, healthy', s.bad + 1⟩
       else ⟨Mode.degraded, healthy', s.bad + 1⟩)
  | m => ⟨m, healthy', s.bad⟩

/-- Every frame takes a legal transition. -/
theorem decide_legal (s : Monitor) (h : Health) (miss : Bool) :
    legal s.mode (decide s h miss).mode = true := by
  rcases s with ⟨m, a, b⟩
  cases m <;> simp only [decide] <;> (try split) <;> (try split) <;> (try split) <;> simp [legal, succs]

theorem safe_absorbs (s : Monitor) (h : Health) (miss : Bool) (hs : s.mode = Mode.safe) :
    (decide s h miss).mode = Mode.safe := by
  rcases s with ⟨m, a, b⟩; simp at hs; subst hs; simp [decide]

theorem fault_absorbs (s : Monitor) (h : Health) (miss : Bool) (hs : s.mode = Mode.fault) :
    (decide s h miss).mode = Mode.fault := by
  rcases s with ⟨m, a, b⟩; simp at hs; subst hs; simp [decide]

/-- A numeric-saturation fault (the Unsafe class) forces Safe from Running or Degraded. -/
theorem unsafe_forces_safe (s : Monitor) (miss : Bool)
    (hs : s.mode = Mode.running ∨ s.mode = Mode.degraded) :
    (decide s Health.unsafe_ miss).mode = Mode.safe := by
  rcases s with ⟨m, a, b⟩
  rcases hs with hs | hs <;> simp at hs <;> subst hs <;> simp [decide]

/-- A deadline miss while Running (and not Unsafe) degrades. -/
theorem overrun_degrades (s : Monitor) (h : Health) (hs : s.mode = Mode.running)
    (hn : h ≠ Health.unsafe_) : (decide s h true).mode = Mode.degraded := by
  rcases s with ⟨m, a, b⟩; simp at hs; subst hs; simp [decide, hn]

/-- Enough consecutive healthy frames recover Degraded to Running. -/
theorem recovers (s : Monitor) (hs : s.mode = Mode.degraded)
    (hh : recoveryFrames ≤ s.healthy + 1) : (decide s Health.healthy false).mode = Mode.running := by
  rcases s with ⟨m, a, b⟩; simp at hs; subst hs; simp [decide, hh]

/-- Repeated bad frames in one Degraded episode end in Safe. -/
theorem repeated_bad_to_safe (s : Monitor) (h : Health) (hs : s.mode = Mode.degraded)
    (hn : h ≠ Health.healthy) (hl : degradedLimit ≤ s.bad + 1) :
    (decide s h false).mode = Mode.safe := by
  rcases s with ⟨m, a, b⟩; simp at hs; subst hs
  by_cases hu : h = Health.unsafe_ <;> simp [decide, hn, hu, hl]

def runFrames (s : Monitor) (fs : List (Health × Bool)) : Monitor :=
  fs.foldl (fun st f => decide st f.1 f.2) s

theorem foldl_safe (fs : List (Health × Bool)) (s : Monitor) (hs : s.mode = Mode.safe) :
    (runFrames s fs).mode = Mode.safe := by
  induction fs generalizing s with
  | nil => exact hs
  | cons f fs ih => exact ih _ (safe_absorbs s f.1 f.2 hs)

/-- Once Safe, no sequence of frames leaves it. -/
theorem safe_forever (s : Monitor) (fs : List (Health × Bool)) (hs : s.mode = Mode.safe) :
    (runFrames s fs).mode = Mode.safe := foldl_safe fs s hs

/-- An Unsafe frame while Running makes Safe permanent, whatever follows. -/
theorem unsafe_is_permanent (s : Monitor) (miss : Bool) (rest : List (Health × Bool))
    (hs : s.mode = Mode.running ∨ s.mode = Mode.degraded) :
    (runFrames s ((Health.unsafe_, miss) :: rest)).mode = Mode.safe := by
  unfold runFrames
  rw [List.foldl_cons]
  exact foldl_safe rest _ (unsafe_forces_safe s miss hs)

/-- Operational modes: the only ones reachable from Ready. -/
def operational : Mode → Bool
  | Mode.ready | Mode.running | Mode.degraded | Mode.safe => true
  | _ => false

theorem decide_operational (s : Monitor) (h : Health) (miss : Bool)
    (hs : operational s.mode = true) : operational (decide s h miss).mode = true := by
  rcases s with ⟨m, a, b⟩
  cases m <;> simp [operational] at hs <;> simp only [decide] <;>
    (try split) <;> (try split) <;> (try split) <;> simp [operational]

theorem runFrames_operational (s : Monitor) (fs : List (Health × Bool))
    (hs : operational s.mode = true) : operational (runFrames s fs).mode = true := by
  induction fs generalizing s with
  | nil => exact hs
  | cons f fs ih => exact ih _ (decide_operational s f.1 f.2 hs)

/-- Invalid controller modes cannot appear: from Ready, Boot/SelfTest/Calibrating/Fault are unreachable. -/
theorem never_boot (fs : List (Health × Bool)) :
    (runFrames initial fs).mode ≠ Mode.boot ∧ (runFrames initial fs).mode ≠ Mode.fault := by
  have h := runFrames_operational initial fs (by decide)
  generalize (runFrames initial fs).mode = m at h
  cases m <;> simp [operational] at h ⊢

/-- The decision logic is the abstract machine of Modes.lean driven by a trigger. -/
def trigger (s : Monitor) (h : Health) (miss : Bool) : Trigger :=
  match s.mode with
  | Mode.ready => Trigger.advance
  | Mode.running =>
    if h = Health.unsafe_ then Trigger.crit
    else if h = Health.degraded ∨ miss = true then Trigger.degrade
    else Trigger.advance
  | Mode.degraded =>
    if h = Health.unsafe_ then Trigger.crit
    else if h = Health.healthy then
      (if recoveryFrames ≤ s.healthy + 1 then Trigger.recover else Trigger.advance)
    else (if degradedLimit ≤ s.bad + 1 then Trigger.repeated else Trigger.advance)
  | _ => Trigger.advance

/-- For every mode the frame loop can be in (it starts at Ready), the decision logic is
the abstract machine driven by `trigger`. It is deliberately *not* claimed for Boot,
SelfTest or Calibrating: the frame loop never runs there, so `decide` leaves them
unchanged while `step` would advance them. -/
theorem decide_is_step (s : Monitor) (h : Health) (miss : Bool)
    (hs : operational s.mode = true) :
    (decide s h miss).mode = step s.mode (trigger s h miss) := by
  rcases s with ⟨m, a, b⟩
  cases m <;> simp [operational] at hs <;> simp only [decide, trigger] <;>
    (try split) <;> (try split) <;> (try split) <;> simp [step]

end Icarus
