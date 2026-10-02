(* The deterministic simulation. Runs the Acquire, Normalize, Estimate, Decide,
   Control, Validate, Record schedule once per step against fixed-capacity
   storage, prints the canonical M H G X lines (spec/ICF.md) and returns the
   number of allocator calls observed inside the frame loop, which must be 0. *)
staload "./fixture.sats"

fun run_sim (cfg: !cfg_vt): lint
