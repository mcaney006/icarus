# Assumptions

Every result in PROOFS.md, REPORT.md and docs/ holds only under the assumptions
below. Other documents cite them by ID.

## Trusted base

**A1. Tool soundness.** The following are trusted, not verified here:

- the Lean 4 kernel (v4.34.1)
- F\* (2026.09.27) together with its bundled Z3
- the Idris 2 (0.8.0) type checker
- the ATS2 (0.4.2) type checker `patsopt`
- the code generators and compilers below them: clang, OCaml 5.3.0, Chez
  Scheme, and the Lean C backend

**A2. Trusted code.** These pieces are outside every proof. The hole audit
(`tools/audit-holes.sh`, `tools/holes.allow`) lists each of them:

- `ats/src/pool.dats`: the four lease-pool bodies use `$UN` and `castvwtp`
  behind the linear signatures in `pool.sats`.
- `ats/src/io_shim.c` (file read, monotonic clock) and `ats/src/alloc_user.c`
  (counting allocator). These are plain C.
- `idris/src/Main.idr` `main` and `withFixture` are `partial` because the library `readFile` is
  not total.
- The F\* drivers in `fstar/driver/*.ml` and the F\* ML runtime (`FStar.IO`,
  string primitives) that extracted code links against.
- The Lean `Main.lean` IO wrapper. It is ordinary Lean, but no theorem refers
  to it.
- `reference/icarus_ref.py`, the oracle. It is tested, never proved. When an
  implementation disagrees with it, the cross-check fails, but that does not
  show which side is wrong.

## Numerical model

**A3. Lean works over ℤ.** `Vec`, `Mat`, `sat`, `control`, and `observe` are
defined on `Int`. The theorems say nothing about real numbers or IEEE doubles.
Nothing proves closed-loop stability, observer convergence, or any bound on
the state. The spectral radii (open loop 1.1566, closed loop 0.8131, observer
0.815) come from numpy in `tools/gen_fixtures.py`, which asserts them at
generation time. They are computed, not proved.

**A4. IEEE-754 binary64, round to nearest, no fused multiply-add.** Exact
agreement between the reference, ATS and Idris requires the same operations
in the same order. ATS compiles with `-ffp-contract=off`. Python and Chez
Scheme do not contract. Agreement is tested on the fixtures, not proved, and a
different compiler or architecture may break it.

**A5. Fixed point.** The format is signed, with 65536 raw units per 1.0 and
raw range [−2³¹, 2³¹ − 1]. Products are rounded half up and every operation
saturates. F\* proves the refinements of `Icarus.Sat`. The reference
`FixedArith` agrees with it on 6972 vectors (`tools/satcheck.py`). The two are
not proved equal. The fixed-point simulator is compared with the float one
statistically (docs/results/fixed_point.md), and no equivalence is claimed.

## Faults and monitoring

**A6. Channel faults are detected by assumption.**

- For BiasedMeasurement, StuckChannel and OutOfRange, the injector itself
  raises the `meas` flag. Icarus contains no detector that would notice a
  biased or stuck channel on its own.
- What is proved is that the vote masks one such channel (`Icarus.Vote`).
- These flags come from real checks inside the loop:
  - the out-of-band clamp in Normalize
  - the innovation threshold for the estimator flag
  - the timing ledger
  - the state bound for the numeric flag (NumericSaturation also sets it
    directly)

**A7. Voting assumptions.**

- Each measurement component comes from three channels.
- At most one channel per component is faulty in any frame, and channel
  values are totally ordered (no NaN).
- The F\* theorems are over `int`. The double implementations use the same
  selection formula, and a 20,000-triple property check covers them.
- A fault common to all three channels (dropout) is not masked. The vote then
  returns the common value, which is the held sample.

**A8. Health is memoryless.** `classify` reads only the current frame's flags.
The only memory in the decision layer is the healthy streak and the bad-frame
counter of the current Degraded episode. The history ring buffer is written
every frame, but no decision reads it.

**A9. Safe is absorbing by design.** Nothing returns from Safe or Fault. Safe
removes control authority (u = 0). It is not a claim that the plant becomes
safe. The plant is open-loop unstable and diverges after Safe.

**A10. Start-up modes are not simulated.** Simulations begin in Ready. Boot,
SelfTest and Calibrating, and their transitions to Fault, exist in every
transition relation and in the Lean proofs (`Modes.boot_reaches_running`).
No fixture exercises them.

## Timing

**A11. Abstract ticks, single thread, no preemption.**

- A frame is 1000 abstract ticks.
- Every frame charges the nominal stage budgets, 900 in total.
- An overrun is a number injected by a fixture. Nothing measures it.
- The cyclic executive is a sequential loop: no interrupts, no concurrency,
  no clock.
- The cost model (`Icarus.AbstractCost`) is an abstract operation count. It is not a
  WCET analysis and predicts no duration.

## Plant and data

**A12. Synthetic plant.** A, B, C, K and L are dimensionless matrices chosen
for their spectral properties. Disturbance w and noise v are bounded
sequences from a fixed-seed linear congruential generator, stored inside each
fixture. They model no physical system, sensor or actuator.

**A13. Interchange integrity, not authenticity.** The ICF checksum is 32-bit
FNV-1a. It catches accidental corruption (the cross-check tests flips,
truncation and a missing checksum). Deliberate tampering defeats it.

**A14. The F\* and Lean executables check only the decision layer.** They
take the flag masks recorded in a fixture and recompute health and mode. A
mistake in how the simulators *produce* flags would not show up there. It
shows up as an M/H/G disagreement between ATS or Idris and the reference.
