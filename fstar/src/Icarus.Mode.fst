(* Mode manager. `decide` returns a state whose mode is *refined* to be a legal
   successor of the current one, so every branch must justify its transition to
   the verifier. Mirrors reference/icarus_ref.py and lean/Icarus/Modes.lean. *)
module Icarus.Mode
open Icarus.Health

type mode =
  | Boot | SelfTest | Calibrating | Ready | Running | Degraded | Safe | Fault

let legal (a b:mode) : bool =
  match a, b with
  | Boot, SelfTest | Boot, Boot | Boot, Fault -> true
  | SelfTest, Calibrating | SelfTest, SelfTest | SelfTest, Fault -> true
  | Calibrating, Ready | Calibrating, Calibrating | Calibrating, Fault -> true
  | Ready, Running | Ready, Ready | Ready, Safe -> true
  | Running, Running | Running, Degraded | Running, Safe -> true
  | Degraded, Degraded | Degraded, Running | Degraded, Safe -> true
  | Safe, Safe -> true
  | Fault, Fault -> true
  | _, _ -> false

let mode_code (m:mode) : n:nat{n <= 7} =
  match m with
  | Boot -> 0 | SelfTest -> 1 | Calibrating -> 2 | Ready -> 3
  | Running -> 4 | Degraded -> 5 | Safe -> 6 | Fault -> 7

let recovery_frames : pos = 3
let degraded_limit : pos = 3

type st = { mode: mode; healthy: nat; bad: nat }

let initial : st = { mode = Ready; healthy = 0; bad = 0 }

(* The next monitor state; its mode is a legal successor by construction. *)
let decide (s:st) (h:health) (miss:bool)
  : Tot (s':st{legal s.mode s'.mode})
  = let healthy' = if h = Healthy then s.healthy + 1 else 0 in
    match s.mode with
    | Ready -> { mode = Running; healthy = healthy'; bad = s.bad }
    | Running ->
      if h = Unsafe then { mode = Safe; healthy = healthy'; bad = s.bad }
      else if h = Icarus.Health.Degraded || miss then { mode = Degraded; healthy = healthy'; bad = 0 }
      else { mode = Running; healthy = healthy'; bad = s.bad }
    | Degraded ->
      if h = Unsafe then { mode = Safe; healthy = healthy'; bad = s.bad }
      else if h = Healthy then
        (if s.healthy + 1 >= recovery_frames
         then { mode = Running; healthy = healthy'; bad = s.bad }
         else { mode = Degraded; healthy = healthy'; bad = s.bad })
      else
        (if s.bad + 1 >= degraded_limit
         then { mode = Safe; healthy = healthy'; bad = s.bad + 1 }
         else { mode = Degraded; healthy = healthy'; bad = s.bad + 1 })
    | m -> { mode = m; healthy = healthy'; bad = s.bad }

(* ---- properties ---------------------------------------------------------- *)

let safe_absorbs (s:st) (h:health) (miss:bool)
  : Lemma (requires s.mode = Safe) (ensures (decide s h miss).mode = Safe) = ()

let fault_absorbs (s:st) (h:health) (miss:bool)
  : Lemma (requires s.mode = Fault) (ensures (decide s h miss).mode = Fault) = ()

let unsafe_forces_safe (s:st) (miss:bool)
  : Lemma (requires s.mode = Running \/ s.mode = Degraded)
          (ensures (decide s Unsafe miss).mode = Safe) = ()

let overrun_degrades (s:st) (h:health)
  : Lemma (requires s.mode = Running /\ h <> Unsafe)
          (ensures (decide s h true).mode = Degraded) = ()

let recovers (s:st)
  : Lemma (requires s.mode = Degraded /\ s.healthy + 1 >= recovery_frames)
          (ensures (decide s Healthy false).mode = Running) = ()

let ready_engages (s:st) (h:health) (miss:bool)
  : Lemma (requires s.mode = Ready) (ensures (decide s h miss).mode = Running) = ()

(* The spec's illegal transitions are rejected by the table itself. *)
let illegal_examples ()
  : Lemma (legal Boot Running = false /\ legal Safe Running = false
           /\ legal Fault Ready = false /\ legal Safe Degraded = false) = ()

(* Once Safe, no sequence of frames can leave it. *)
let rec run (s:st) (frames:list (health & bool)) : Tot st (decreases frames) =
  match frames with
  | [] -> s
  | (h, miss) :: rest -> run (decide s h miss) rest

let rec safe_stays_safe (s:st) (frames:list (health & bool))
  : Lemma (requires s.mode = Safe) (ensures (run s frames).mode = Safe)
          (decreases frames)
  = match frames with
    | [] -> ()
    | (h, miss) :: rest -> safe_stays_safe (decide s h miss) rest

(* An Unsafe frame while Running forces Safe permanently, whatever follows. *)
let unsafe_is_permanent (s:st) (rest:list (health & bool)) (miss:bool)
  : Lemma (requires s.mode = Running \/ s.mode = Degraded)
          (ensures (run s ((Unsafe, miss) :: rest)).mode = Safe)
  = unsafe_forces_safe s miss;
    safe_stays_safe (decide s Unsafe miss) rest

(* From Ready only operational modes are reachable: Boot, SelfTest, Calibrating
   and Fault can never reappear once the controller is running. *)
let operational (m:mode) : bool =
  m = Ready || m = Running || m = Degraded || m = Safe

let decide_operational (s:st) (h:health) (miss:bool)
  : Lemma (requires operational s.mode) (ensures operational (decide s h miss).mode) = ()

let rec run_operational (s:st) (frames:list (health & bool))
  : Lemma (requires operational s.mode) (ensures operational (run s frames).mode)
          (decreases frames)
  = match frames with
    | [] -> ()
    | (h, miss) :: rest -> decide_operational s h miss; run_operational (decide s h miss) rest

let initial_operational ()
  : Lemma (operational initial.mode) = ()
