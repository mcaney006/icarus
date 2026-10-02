(* ICF 2 reader (spec/ICF.md) into fixed-capacity storage. The state dimensions
   4, 2, 2 are compiled into the types, so a fixture declaring any other shape is
   rejected rather than reshaped. Capacities: 65536 input bytes, 128 steps,
   16 fault events. *)

datavtype cfg_vt =
  | CFG of (
      matrixptr(double, 4, 4),     (* A *)
      matrixptr(double, 4, 2),     (* B *)
      matrixptr(double, 2, 4),     (* C *)
      matrixptr(double, 2, 4),     (* K *)
      matrixptr(double, 4, 2),     (* L *)
      matrixptr(double, 128, 6),   (* per-step disturbance (4) then noise (2) *)
      matrixptr(double, 16, 4),    (* fault events: step, kind, channel, param *)
      arrayptr(double, 4),         (* initial state *)
      int,                         (* steps *)
      int)                         (* fault events *)

fun load_fixture (path: string): Option_vt(cfg_vt)
fun cfg_free (c: cfg_vt): void
