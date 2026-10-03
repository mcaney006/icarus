(* The deterministic simulation. Runs the Acquire, Normalize, Estimate, Decide,
   Control, Validate, Record schedule once per step against fixed-capacity
   storage, prints the canonical M H G X lines (spec/ICF.md) and returns the
   number of allocator calls observed inside the frame loop, which must be 0. *)
staload "./fixture.sats"

fun run_sim (cfg: !cfg_vt): lint

(* Runs the frame loop `reps` times from the fixture's initial state, timing only
   the loop. Returns (nanoseconds, allocator calls) summed over the timed regions. *)
fun sim_bench (cfg: !cfg_vt, reps: int): @(lint, lint)
