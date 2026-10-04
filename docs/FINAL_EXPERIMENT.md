# Final experiment: one hostile run, traced to the specifications

Fixture: `fixtures/final_experiment.{json,icf}` (seed and generator in
`tools/gen_fixtures.py`). 48 frames, x0 = (0.5, −0.3, 0.4, −0.2), and five
injected faults:

| Step | Fault | Parameters |
|---:|---|---|
| 8 | BiasedMeasurement | channel 0 of the triple, component 0, +18 |
| 12 | MeasurementDropout | component 1 |
| 13 | MeasurementDropout | component 1 |
| 20 | TimingOverrun | +260 ticks |
| 28 | NumericSaturation | — |

## Reproduce

```bash
python3 reference/icarus_ref.py --fixture fixtures/final_experiment.json --trace
python3 tools/crosscheck.py --strict
```

## Agreement across implementations

Canonical output of the reference (spec/ICF.md: `M` is the mode at the start of
each frame plus the final mode, `H` health per frame, `G` flag mask per frame,
`X` final state scaled by 10⁹):

```
M 3 4 4 4 4 4 4 4 4 4 4 4 4 4 4 4 4 4 4 4 4 5 5 5 4 4 4 4 4 6 6 6 6 6 6 6 6 6 6 6 6 6 6 6 6 6 6 6 6
H 0 1 0 0 0 0 0 0 1 0 0 0 1 1 0 0 0 0 0 0 1 0 0 0 0 0 0 0 3 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
G 0 8 0 0 0 0 0 0 1 0 0 0 1 1 0 0 0 0 0 0 4 0 0 0 0 0 0 0 16 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
X -445221753 -299148819 -238628843 -213035707
```

| Implementation | Lines compared | Result |
|---|---|---|
| ATS `ats/build/icarus_sim` | M H G X | byte-identical to the reference |
| Idris `idris/build/exec/icarus` | M H G X | byte-identical to the reference |
| F\* `fstar/out/icarus_decide` | M H (recomputed from G) | byte-identical |
| Lean `lean/.lake/build/bin/icarus` | M H (recomputed from G) | byte-identical |

The F\* and Lean executables take the reference's flag masks (`G`) as input and
recompute health and mode with their verified `classify` and decision functions. They
check the decision layer, not the arithmetic. The `X` agreement between ATS,
Idris and the reference is exact here. The comparison tolerance (1e-6) did not
have to absorb any difference on this fixture.

## Frame-by-frame mapping

Mode codes: 3 Ready, 4 Running, 5 Degraded, 6 Safe. Health codes: 0 Healthy,
1 Suspect, 2 Degraded, 3 Unsafe. Flag bits: meas 1, estimator 2, timing 4,
ctrl_sat 8, numeric 16. A decision taken in frame k appears in `M` at k+1.

### k = 0: Ready → Running

- Every frame leaves Ready unconditionally.
- Lean: `Monitor.next` (Ready branch), `Modes.ready_to_running`.
- F\*: `Icarus.Mode.ready_engages`.
- Idris: `decideMode Ready` returns `(Running ** Engage)`.
- ATS: `LEGAL_READY_RUNNING`.

### k = 1: control saturates, health Suspect, stays Running

- The first active control `u = −K x̂` exceeds the authority limit and is
  clamped to (−1.0, −0.9822). The `ctrl_sat` flag (8) raises health to Suspect.
- Bound: Lean `Controller.control_bounded` and `Numeric.control_in_interval`
  (over ℤ). F\* `Icarus.Sat.clamp` refinement (fixed-point path). ATS self-test
  "vector: clamp stays inside the interval". On doubles, this is tested, not
  proved.
- One flag gives Suspect: Lean `Faults.classify`, F\* `Icarus.Health.classify`,
  and self-tests "health: one flag suspect" (ATS).
- Suspect does not change the mode. This is a case of the decision function that no theorem
  isolates. The cross-check covers it.

### k = 8: biased channel, masked by the vote

- Channel 0 of component 0 reads +18 off. The other two channels agree, so the
  per-component median selects their value exactly.
- F\*: `Icarus.Vote.two_agree_first` (med x b b = b) and
  `divergent_cannot_escape`.
- Health is Suspect because the `meas` flag is set. **The injector sets that
  flag, not a detector.** Icarus assumes a channel-fault detector exists
  (ASSUMPTIONS.md A6). What is proved is the masking, not the detection.

### k = 12, 13: dropout, all channels hold the last sample

- All three channels repeat the previous component-1 value, and the vote returns
  it unchanged (F\* `Icarus.Vote.unanimous`). The `meas` flag gives Suspect.
- The observer runs on a held sample. The innovation stays below
  `INNOV_THRESH`, so the estimator flag is not raised.

### k = 20: overrun, deadline miss, Running → Degraded

- The nominal schedule uses 900 of 1000 ticks (F\* `Icarus.Timing.nominal_uses_900`,
  `margin_is_100`; Lean `Numeric.budget_fits`, `budget_margin`). An overrun of
  260 exceeds the 100-tick margin.
- F\*: `Icarus.Timing.miss_iff_beyond_margin` (miss ⇔ overrun > 100),
  `overrun_larger_than_margin_detected`. The overrun ticks are injected, not
  derived from the cost model (docs/results/cost_model.md).
- Running with a miss and no Unsafe flag → Degraded:
  - Lean `Decision.overrun_degrades`
  - F\* `Icarus.Mode.overrun_degrades`
  - Idris `Degrade`
  - ATS `LEGAL_RUNNING_DEGRADED`
- The episode's bad-frame counter resets to 0 on entry.

### k = 21–23: Degraded at half authority, three healthy frames

- The control limit is `DEGRADED_CTRL` = 0.5. The actual |u| < 0.07, so nothing
  saturates.
- Frames 21, 22 and 23 are Healthy. In frame 23, the streak including the
  current frame reaches `RECOVERY_FRAMES` = 3, and the decision is Running.
- Lean `Decision.recovers`, F\* `Icarus.Mode.recovers`, Idris `Recover`, ATS
  `LEGAL_DEGRADED_RUNNING`. Self-tests: "mode: third healthy frame recovers"
  (ATS and Idris).

### k = 24–27: Running, nominal

### k = 28: numeric fault, Unsafe, Running → Safe

- The `numeric` flag (16) forces Unsafe regardless of the other flags:
  - Lean `Faults.numeric_dominates`
  - F\* `Icarus.Health.numeric_dominates`
  - self-tests "health: numeric dominates" (ATS) and "health: numeric flag
    dominates" (Idris)
- Unsafe in Running → Safe:
  - Lean `Decision.unsafe_forces_safe`
  - F\* `Icarus.Mode.unsafe_forces_safe`
  - Idris `RunUnsafe`
  - ATS `LEGAL_RUNNING_SAFE`
- In the float backend this fault only sets the flag. In the fixed-point
  backend it writes a genuine out-of-range value into x̂[0], and the saturating
  arithmetic reports 3 saturation events (docs/results/fixed_point.md).

### k = 29–47: Safe absorbs, control off

- Health returns to Healthy, but the mode stays Safe:
  - Lean `Decision.safe_absorbs`, `safe_forever`, `unsafe_is_permanent`,
    `Modes.safe_absorbing`
  - F\* `Icarus.Mode.safe_absorbs`, `safe_stays_safe`, `unsafe_is_permanent`
- No path back exists in any language:
  - Idris has no `Legal Safe Running` constructor (negative/idris/safe_to_running.idr).
  - Lean `Modes.safe_terminal` (negative/lean/safe_escape.lean).
  - ATS has no `LEGAL(6, 4)` (negative/ats/illegal_transition.dats).
  - F\* rejects `IllegalTransition.fst`.
- u = 0 outside Running and Degraded. This is implementation behaviour. The
  cross-checked final state `X` covers it, and no theorem states it.
- The plant is open-loop unstable (ρ(A) = 1.1566). After control stops, ‖x‖ grows
  until the run ends. Safe means no control authority. It does not mean the
  plant is safe.

## Whole-run invariants

| Invariant | Where it holds |
|---|---|
| Every transition is legal | Lean `Decision.next_legal`; F\* return type of `Icarus.Mode.decide` (`legal s.mode s'.mode`); Idris `decideMode : … -> (m' ** Legal m m')`; ATS `decide_mode : … -> (LEGAL(m, m1) \| int(m1))` |
| From Ready, the run never reaches Boot, SelfTest or Calibrating | Lean `Decision.never_boot`, `runFrames_operational`; F\* `run_operational` |
| No allocation in the ATS frame loop | runtime check in `icarus_sim` (exit 4), benchmark rows at 0 allocator calls |
| Frame buffers leased and returned exactly once | ATS linear `pool_vt` types; negative/ats/lease_leak.dats, lease_double_release.dats |
| History never exceeds capacity | F\* `Icarus.Ring.len_never_exceeds_capacity`; Idris `Ring (S c)` index; ATS `ring_vt(cap)` |
| Matrix dimensions agree | static indices in Lean (`Mat r c`), Idris (`Matrix r c`), ATS (`matrixptr(double, r, c)`); negative tests in all three |

## Fixed-point replay

The same fixture under the saturating fixed-point backend (65536 raw units per
1.0) produces the same `M` line. `H` and `G` agree through frame 27 and then
diverge:

- Frame 28: G = 24 instead of 16. The overflowed estimate also saturates the
  control.
- Frames 29–47: G = 18 (numeric + estimator) and H = 3 every frame, against
  G = 0 and H = 0 in float. The saturated x̂[0] stays out of range and keeps
  producing a large innovation.

The mode is already Safe, so the decisions do not change. This fixture shows
the one asymmetry between the backends: the float backend raises the
numeric-fault flag without corrupting state, while the fixed-point backend
corrupts state and keeps re-detecting it.

The state differs from float by at most 7.9 LSB before the overflow and by
31,537 LSB (0.481) one step after it. The growth after that is the open-loop
plant amplifying the difference (docs/results/fixed_point.md, exploratory section). The two
simulators are not claimed to be equivalent.
