# Cross-language correspondence

Five artifacts describe one system. This file says which construct in each
corresponds to which concept, and how each correspondence is checked. A
correspondence marked **tested** holds on the fixtures. One marked **by
inspection** depends on a human reading both sides. None of them is a proof
of equivalence between languages: no tool here relates a Lean term to an ATS
function.

## Who owns what

| Layer | Owner | Role |
|---|---|---|
| Mathematical specification and proofs | Lean 4 (`lean/Icarus/`) | Exact integer model of the plant, saturation, modes, decision logic, observer error |
| Executable domain model | Idris 2 (`idris/src/`) | Dimension-indexed simulation in which illegal shapes, units and transitions do not typecheck |
| Refinement-verified components | F\* (`fstar/src/`) | Saturating arithmetic, voting, counter, timing ledger, ring buffer, health and mode manager, wire encoding, cost model |
| Deterministic runtime | ATS2 (`ats/src/`) | Linear, fixed-capacity frame loop with no allocation after start-up |
| Oracle | Python (`reference/icarus_ref.py`) | The behaviour every other executable is compared against |

The only data that crosses a language boundary is the ICF 2 file format
(`spec/ICF.md`). No language calls another.

## Concepts

| Concept | Lean | Idris | F\* | ATS | Reference |
|---|---|---|---|---|---|
| Scalar | `Int` (exact) | `Double` | `int` (unbounded); `fx` (bounded raw word) | `double` | `float`; `FixedArith` raw int |
| Vector of n | `Vec n` = `Fin n → Int` | `Vect n Double` | — | `arrayptr(double, n)` | `list` |
| r×c matrix | `Mat r c` | `Matrix r c Double` | — | `matrixptr(double, r, c)` | `list` of rows |
| Plant x⁺ = Ax + Bu + w | `Linear.plantStep` | `Plant.advance` | — | end of `do_frame` | end of `run` loop |
| Measurement y = Cx + v | `Linear.measure` | `vadd (matVec cMat x) v` in `frame` | — | Acquire block of `do_frame` | `vadd(matvec(C, x), v)` |
| Observer update | `Controller.observe` | `Plant.observe` | — | Estimate block of `do_frame` | Estimate block |
| Control u = sat(−K x̂) | `Controller.control` | `clampAll` in `frame` | `Sat.clamp` (fixed-point word) | `clamp_all` | `A.clamp` |
| Mode | `Modes.Mode` | `Types.Mode` | `Icarus.Mode.mode` | static int 0–7 | `Mode` enum |
| Legal transition | `Modes.legal` (Bool) | `Legal m m'` (type family) | `legal` (bool, in `decide`'s return type) | `dataprop LEGAL(m, m1)` | `LEGAL` table |
| Fault kind | `Faults.FaultKind` | `Types.FaultKind` (codes derived by `Codes.enumeration`) | — (sees flags only) | int code from the fixture | `Fault` enum |
| Health | `Faults.Health` | `Types.Health` | `Icarus.Health.health` | int 0–3 | `Health` enum |
| Fault flags | `Faults.Flags` | `Plant.Flags` | `Icarus.Health.flags` | bit mask int | `set` of names |
| Classification | `Faults.classify` | `Plant.classify` | `Icarus.Health.classify` | `classify` (mode.dats) | Health block |
| Decision state | `Decision.Monitor` | `Plant.Monitor` | `Icarus.Mode.st` | `ctl` array in `st_vt` | locals `mode`, `healthy_streak`, `degraded_bad` |
| Decision function | `Monitor.next` | `Plant.next` (via `decideMode`) | `Icarus.Mode.decide` | `decide_mode` | Decide block |
| Three-channel vote | — | `Plant.median3` | `Icarus.Vote.med` (over `int`) | `median3` | `median3` |
| History buffer | `Ring α cap` (newest-first list model) | `Ring (S c) a` | `ring a cap` | `ring_vt(cap)` | — |
| Frame timing | `Numeric.stageBudgets` | `nominalFrameCost`, `frameBudget` | `Icarus.Timing` | `900 + over > 1000` | `STAGE_BUDGET`, `FRAME_BUDGET` |
| Units | — | `Dim.Quantity` (dimension-indexed) | — | — | — |
| Buffer ownership | — | — | — | `pool_vt(n, avail)` linear leases | — |

## Constants

Every executable copies the same artificial constants. Nothing derives them
from one source, so this table is maintained by inspection, and the
cross-check fails if a copy drifts in a way the fixtures exercise.

| Constant | Value | Reference | Idris | F\* | Lean | ATS |
|---|---|---|---|---|---|---|
| Measurement clamp | 50 | `MEAS_LIMIT` | `measLimit` | — | — | `MEAS_LIMIT` |
| Innovation threshold | 10 | `INNOV_THRESH` | `innovThresh` | — | — | `INNOV_THRESH` |
| State bound | 1000 | `STATE_BOUND` | `stateBound` | — | — | `STATE_BOUND` |
| Control limit (Running) | 1 | `ctrl_limit` | argument to `frame` | — | `Numeric.ctrlLimit` | `CTRL_LIMIT` |
| Control limit (Degraded) | 0.5 | `DEGRADED_CTRL` | `degradedCtrl` | — | — | `DEGRADED_CTRL` |
| Recovery frames | 3 | `RECOVERY_FRAMES` | `recoveryFrames` | `recovery_frames` | `recoveryFrames` | literal in `decide_mode` |
| Degraded limit | 3 | `DEGRADED_LIMIT` | `degradedLimit` | `degraded_limit` | `degradedLimit` | literal in `decide_mode` |
| Frame budget | 1000 ticks | `FRAME_BUDGET` | `frameBudget` | `frame_budget` | `frameBudget` | literal |
| Stage budgets | 120/80/220/180/160/90/50 | `STAGE_BUDGET` | `stageSum` = 900 | `budget` | `stageBudgets` | literal 900 |
| Fixed-point scale | 65536 | `FixedArith.SCALE` | — | `Sat.scale` | — | — |

## How each correspondence is checked

| Correspondence | Check | Kind |
|---|---|---|
| Reference ↔ ATS, Idris: modes, health, flags, final state | `tools/crosscheck.py` on 13 fixtures, exact M/H/G, X within 1e-6 | tested |
| Reference ↔ F\*, Lean: health and mode from flags | `tools/crosscheck.py`, exact M/H | tested |
| Reference `FixedArith` ↔ F\* `Sat` | `tools/satcheck.py`, 6972 vectors, exact | tested |
| Reference float ↔ fixed-point | `tools/fixed_point_experiment.py`, measured deviation | measured; not claimed equal |
| All parsers reject corrupt input | 4 corruption variants of the first fixture (payload flip, missing checksum, truncation; wrong dimensions with a valid checksum for ATS and Idris) | tested |
| Lean `Monitor.next` ↔ F\* `decide` ↔ Idris `next` ↔ ATS `decide_mode` | Same case structure, same constants; the cross-check exercises every branch on some fixture | by inspection + tested |
| Lean integer model ↔ float executables | none | **not checked**. The Lean theorems are about ℤ. |
| Stage budgets ↔ actual stage work | `Icarus.Cost` (abstract operation counts, transcribed by hand) | by inspection; see docs/results/cost_model.md |

## Deliberate differences

- **Lean computes over ℤ, not ℝ or IEEE doubles.** Its observer-error identity
  and control bound hold exactly for integers. They transfer to the float
  implementations only as design intent.
- **F\* and Lean executables run only the decision layer.** They read the flag
  masks from a fixture's expected output and recompute health and mode. They do
  not simulate the plant.
- **Idris keeps the general dimension indices** (`Fixture n m p`) and accepts
  any consistent shape. ATS fixes n = 4, m = 2, p = 2 in its types and rejects
  every other shape with exit code 3.
- **The reference applies a NumericSaturation fault differently per backend.**
  Float sets only the flag. Fixed-point writes a real out-of-range word.
