(* Modes are static integers: Boot 0, SelfTest 1, Calibrating 2, Ready 3,
   Running 4, Degraded 5, Safe 6, Fault 7. LEGAL is a proof with one constructor
   per allowed transition; Safe and Fault have no outgoing constructor other than
   staying. Proofs are erased at runtime, so the table costs nothing. *)

dataprop LEGAL(from:int, to:int) =
  | {m:int} LEGAL_STAY(m, m)
  | LEGAL_BOOT_SELFTEST(0, 1)
  | LEGAL_SELFTEST_CALIBRATING(1, 2)
  | LEGAL_CALIBRATING_READY(2, 3)
  | LEGAL_READY_RUNNING(3, 4)
  | LEGAL_RUNNING_DEGRADED(4, 5)
  | LEGAL_DEGRADED_RUNNING(5, 4)
  | LEGAL_RUNNING_SAFE(4, 6)
  | LEGAL_DEGRADED_SAFE(5, 6)
  | LEGAL_READY_SAFE(3, 6)
  | LEGAL_BOOT_FAULT(0, 7)
  | LEGAL_SELFTEST_FAULT(1, 7)
  | LEGAL_CALIBRATING_FAULT(2, 7)

(* Health: Healthy 0, Suspect 1, Degraded 2, Unsafe 3. Flag bits: meas 1,
   estimator 2, timing 4, ctrl_sat 8, numeric 16. *)
fun classify (mask: int): [h:nat | h <= 3] int(h)

(* The successor mode comes packaged with a proof it is a legal successor. *)
fun decide_mode {m:nat | m <= 7}
  (m: int(m), health: int, miss: bool, healthy: int, bad: int)
  : [m1:nat | m1 <= 7] (LEGAL(m, m1) | int(m1))
