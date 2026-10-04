# icarus: report

## 1. Problem definition

One small deterministic control system is built four times: in Lean 4, Idris 2,
F\* and ATS2, with a Python oracle alongside. The question is which classes of
control-software defect each language rules out before the program runs, and
what a mechanical check costs in each.

The system:

- **Plant.** A four-state linear plant, x[k+1] = A x + B u + w, with two control
  inputs and two measurements, y = C x + v.
- **Estimator.** A Luenberger observer.
- **Control.** Saturating state feedback, u = sat(−K x̂) clamped to [−1, 1].
- **Measurement.** A median vote over three redundant channels.
- **Monitoring.** A health monitor with four levels and a mode machine with
  eight modes.
- **Schedule.** A cyclic executive with a 1000-tick frame and seven stage budgets.
- **Faults.** Typed fault injection for ten fault kinds.

Every implementation reads the same fixtures and must reproduce the oracle's
observable behaviour.

The output that matters is not the controller. It is a mechanically checked
list of what each discipline caught (PROOFS.md), together with an honest list
of what nothing caught (§12).

## 2. Why the system is deliberately nonphysical

- **Synthetic matrices.** A, B and C were chosen for their spectra: open-loop
  spectral radius 1.1566 (unstable), and the LQR gains give closed-loop 0.8131
  and observer 0.815. They have no units. Nothing relates the four state
  components to geometry, mass or any physical quantity.
- **Synthetic signals.** Disturbance and noise come from a fixed-seed linear
  congruential generator stored in the fixtures.
- **No hardware.** There are no sensors, actuators, drivers, buses or hardware
  timing. Ticks are abstract units, and the cost model counts abstract
  operations.

This is a design requirement, and it also improves the research:

1. Every claim can be checked exactly, because inputs and arithmetic are fully
   determined. Floating-point agreement across three languages is exact on all
   13 fixtures.
2. No result depends on a physical model being right, so none can be misread
   as a statement about a vehicle.
3. Safe here means "control authority removed". The plant is open-loop unstable
   and diverges after Safe (the final experiment shows it). In a physical
   system that would be a hazard. Here it is a visible reminder that a correct
   mode machine does not make a plant safe.

The system is not flight software and is not suitable for physical vehicle
control.

## 3. Language roles

| Language | Role | Why this language |
|---|---|---|
| Lean 4 (core only, no Mathlib) | Mathematical specification: plant step, measurement, saturation, matrix algebra, fault classification, decision logic, observer error, history-buffer model | Theorems about all inputs, checked by a small kernel |
| Idris 2 | Executable domain model: full simulator over `Vect`/`Matrix`, indexed by dimension | Illegal shapes, unit mixes and mode transitions are type errors |
| F\* | Saturating fixed-point arithmetic, voting, counters, timing ledger, ring buffer, health and mode manager, wire encoding, abstract cost model; extracted to OCaml for the decision executable | SMT-discharged refinements on results, plus extraction to running code |
| ATS2 | Deterministic runtime: full simulator over linear arrays with static dimensions, lease pools, no allocation in the frame loop | Linear types make buffer misuse a type error; output is C with no GC |
| Python | Oracle and experiment harness | Easy to read and to change; never proved |

Sizes (lines including comments): Lean 798, Idris 970, F\* 796 (with OCaml
drivers), ATS 1323 (with C shims), reference 361.

## 4. Type-level invariants

These invariants are enforced by the type checker. Each has a program in
`negative/` that must be rejected and a well-typed twin that must compile.
That is 24 programs in all, run by `make verify`.

| Invariant | Idris | ATS | Lean | F\* |
|---|---|---|---|---|
| Matrix product dimensions agree | `matmul_dim_mismatch` | `matmul_dim_mismatch` | `mul_dim_mismatch`, `matvec_dim_mismatch` | — |
| Index in range | `index_out_of_bounds` | `index_out_of_bounds` | — | — |
| Illegal mode transition rejected | `illegal_transition`, `safe_to_running` | `illegal_transition` | `illegal_transition`, `safe_escape` | `IllegalTransition` |
| History read needs proof the slot was written | `ring_unproven_read` | — (runtime refusal) | `ring_unwritten_read` | `RingReadUnwritten` |
| Units do not mix | `unit_mismatch` | — | — | — |
| Lease used once, returned once, never taken from empty | — | `lease_double_release`, `lease_leak`, `empty_pool_take` | — | — |
| Saturation must be reported | — | — | — | `SaturationUnreported` |
| Counter cannot wrap | — | — | — | `CounterWraps` |
| Budgets fit the frame | — | — | `budget_overflow` | budget mutation (Estimate 220 → 400) |
| Control bound is non-strict | — | — | `strict_control_bound` | — |

What each language did naturally:

- **Idris** made the mode relation a type family, `Legal m m'`. The decision
  function returns `(m' ** Legal m m')`, so a wrong branch fails to compile, not
  to test. Dimension-indexed `Vect` and `Matrix` remove shape errors without
  ceremony. The ring buffer's read takes an erased proof `LTE (S age)
  (occupied r)`, which costs nothing at run time and forbids reading an
  unwritten slot.
- **ATS** is the only language here where *ownership* is checked. A frame
  takes three leases (measurement, control, estimator scratch) and must return
  each exactly once, or the frame loop does not typecheck. The mode proof
  (`LEGAL`) is a dataprop that is erased in the C output.
- **F\*** stated postconditions on results: an unsaturated multiply is within
  half an LSB, a ledger never exceeds the frame, `bump` reports exhaustion
  instead of wrapping. These are the claims a reviewer would otherwise check by
  hand.
- **Lean** stated universal properties: associativity of matrix product,
  observer error independent of u, Safe absorbing for every trigger sequence.
  No type in the other three languages expresses these.

Where the types were weaker than intended:

- **Idris units stay in their own module.** `Icarus.Dim` gives dimension
  vectors, `qadd` on equal dimensions only, and type-level multiplication and
  division. The simulator, however, runs on homogeneous `Vect n Double`,
  because one vector holding four different dimensions would need a
  heterogeneous structure the matrices do not support. Unit safety is
  demonstrated by `Dim`, its self-tests and the negative test. It does not run
  through the simulation.
- **ATS checks bounds only at load time.** The fixture reader validates every
  fault record once and stores kinds and lanes as bounded types (`natLt(10)`,
  `natLt(2)`), with step and fault counts as `natLte(128)` and `natLte(16)`.
  After that, every index in the frame loop is proved in range statically and
  no runtime clamp remains. The reader's own buffer accesses still go through
  an explicit range check, because their offsets are products the ATS
  constraint solver cannot reason about.
- **ATS ring reads.** `ring_peek` takes a plain `int` age and refuses
  out-of-range ages at run time (returns −1), where Idris, F\* and the Lean model
  require a proof. The in-range index arithmetic inside it is checked statically.

## 5. Proof strategy

- **Lean without Mathlib, over ℤ.** Real analysis would have needed Mathlib.
  Integers keep the build to 6 s and every proof inside core Lean (`decide`,
  `omega`, `simp`, structural induction). The cost is stated in §12: nothing
  about doubles or reals follows. `Mat.sumFin` is a structural finite sum,
  written so that linearity, swap, identity and associativity proofs go
  through by induction on the dimension.
- **F\* with concrete normalisation.** Budget and cost facts are
  `assert_norm` over closed terms. Data-structure facts are refinements
  discharged by Z3. Extraction makes the verified `decide` the code that
  actually runs in `icarus_decide`. No `admit`, `assume` or `--admit_smt_queries`
  appears.
- **Idris: proof by construction.** Most guarantees are a type that has no
  value for the bad case. Proof terms are erased (`auto 0`). Every module is
  total.
- **ATS: dataprops plus linear views.** A trusted kernel of four functions
  (`pool.dats`) is the only place casts appear. Everything else is checked.
- **Redundancy is deliberate.** "Safe is absorbing" holds in four forms:
  - Lean theorems `safe_absorbing`, `safe_forever` and `unsafe_is_permanent`
  - F\* lemmas `safe_stays_safe` and `unsafe_is_permanent`
  - Idris, where no `Legal Safe Running` constructor exists
  - ATS, where no `LEGAL(6, 4)` constructor exists
- **Hole audit.** `tools/audit-holes.sh` fails the build on any `sorry`,
  `admit`, `axiom`, `native_decide`, `assume`, `believe_me`, `assert_total`,
  `partial`, `$UN`, `castvwtp`, … outside an allow-list. The allow-list has
  three entries: the Idris IO `main` and the ATS pool kernel's two constructs.

## 6. Resource model

- **Allocation.** ATS allocates every buffer when the simulation starts:
  - the state vectors and scratch vectors
  - three single-buffer pools
  - a four-slot history ring
  - output arrays sized to 128 steps

  The fixture parser uses a fixed 65,536-byte buffer and fixed-capacity
  matrices (128 steps, 16 fault events).
- **Leases.** `pool_vt(n, avail)` tracks in its index whether the buffer is out.
  Taking from an empty pool, dropping a lease and returning one twice are all
  type errors (three negative tests).
- **Zero allocation is measured.** ATS is built with
  `-DATS_MEMALLOC_USER` and a counting allocator. `icarus_sim` reads the count
  before and after the frame loop and exits 4 if it changed. The benchmark runs
  960,000 frames and every microbenchmark loop: 0 allocator calls.
- **Trusted.** The pool kernel uses `$UN` casts behind the linear signature.
  The counting allocator is C (A2).
- **Contrast.** The Idris simulator allocates about 11 kB per frame (Chez
  collector), because `Vect` results are fresh values. Nobody tried to make it
  allocate less. This is the shape of the domain model, not a benchmark
  verdict.

## 7. Timing model

- **Budgets.** A frame is 1000 abstract ticks. The stage budgets are Acquire
  120, Normalize 80, Estimate 220, Decide 180, Control 160, Validate 90 and
  Record 50, which sum to 900 and leave a margin of 100.
- **Checked twice.** Lean (`budget_fits`, `budget_margin`, `budget_overflow`)
  and F\* (`schedule_fits`, `margin_is_100`) both prove the sum fits. A mutation
  test raises Estimate to 400 and requires F\* to reject the module.
- **Ledger.** F\* runs the schedule in a state monad graded by ticks:
  `frame before after a`. Each stage requires `before + budget ≤ 1000`, and
  the nominal schedule must have type `frame 0 (sum_budgets stages)`. A stage
  that overflows the frame is a type error, not a test failure. This F\*
  release has removed indexed effects, so the monad is an ordinary dependent
  type with a custom `let!` binder rather than a declared effect. A
  dynamically injected overrun goes through `charge`, which returns either the
  exact use or the exact excess.
- **Deadline misses.** An overrun is injected per frame. A miss happens exactly
  when the overrun exceeds the margin (`miss_iff_beyond_margin`), and a miss in
  Running degrades.
- **What the abstract cost model found.** The cost model
  (`Icarus.AbstractCost`, docs/results/cost_model.md) counts operations in each stage as
  implemented. Under unit weights:
  - Acquire costs 188 against its 120 budget and Estimate 272 against 220.
  - The frame total, 721, still fits.
  - Acquire's excess comes from scanning all 16 fault rows. A two-row cursor
    would fit.
  - Estimate fits only if the observer is merged into (A − LC), and that
    removes exactly the innovation the estimator monitor reads.

  So the budgets proved consistent with each other are not consistent with the
  work, under this model. Under heavier weights the frame itself overruns
  (1430). The budget proofs say nothing about the work. The cost model says it
  does not fit, and both statements are mechanically checked.

## 8. Fault model

Ten fault kinds are enumerated types in Lean, Idris and the reference. ATS
reads them as integer codes from the fixture, and F\* sees only the flags they
produce. An ATS datatype for fault kinds would have been easy, but it was not
written.

| Fault | Effect | How it is flagged |
|---|---|---|
| MeasurementDropout | all three channels hold the last sample | injector |
| StaleMeasurement | voted value replaced by last sample | injector |
| BiasedMeasurement | one channel offset | injector; masked by the vote |
| StuckChannel | one channel fixed at 7 | injector; masked by the vote |
| OutOfRange | one channel at 10⁶ | injector; masked by the vote |
| TimingOverrun | extra ticks this frame | ledger: miss iff > 100 |
| NumericSaturation | float: flag only; fixed point: real overflow in x̂ | state bound check |
| CorruptFixture | file rejected before simulation | checksum and shape checks (exit 3) |
| EstimatorDisagreement | estimator flag | injector, or innovation norm > 10 |
| ControlSaturation | control-saturation flag | injector, or raw control beyond the limit |

**Health.** Health is computed from the current frame's flags only. A numeric
flag makes it Unsafe. Two or more flags make it Degraded, one makes it Suspect,
and none leaves it Healthy.

**Modes.** The mode responses are:

- Running → Degraded on a Degraded health level or a deadline miss.
- Degraded → Running after three consecutive Healthy frames.
- Degraded → Safe after three non-Healthy frames in one Degraded episode.
- Unsafe in Running or Degraded → Safe.
- Safe and Fault never change.

An earlier version counted total frames in Degraded. Under that rule Safe
always pre-empted recovery, so the count was changed to bad frames per
episode.

**Fixtures.** Nine of the kinds have a single-fault fixture. CorruptFixture is
covered by the corruption variants in the cross-check. `fault_cascade`
reaches Safe through repeated bad frames, and the final experiment
(docs/FINAL_EXPERIMENT.md) combines bias, dropout, overrun and numeric
saturation.

**Honest gap.** For channel faults the injector sets the flag. No detector in
Icarus would notice a biased channel by itself (A6). The vote theorems prove
masking, not detection.

## 9. Cross-language correspondence

The only shared artefact is the ICF 2 file format (`spec/ICF.md`): integer
encoding, tagged lines and an FNV-1a checksum. spec/CORRESPONDENCE.md maps every
concept and constant across the five artefacts and says how each mapping is
checked.

| Check | Result |
|---|---|
| ATS and Idris vs reference, 13 fixtures, `M H G` exact and `X` within 1e-6 | all exact, with `X` identical to the last digit (10⁻⁹ units) |
| F\* and Lean decision executables vs reference `M H` | all exact |
| Corruption variants (flip, missing checksum, truncation, wrong dimensions) | all rejected with exit 3 |
| Total implementation runs | 66, 0 failures, none skipped |
| F\* `Sat` vs reference `FixedArith` | 6972 vectors, 1047 saturating, 0 disagreements |

Exact float agreement between Python, Chez Scheme and clang-compiled C rests on
identical operation order and no fused multiply-add (A4). It is tested, not
guaranteed. A different compiler, flag or architecture could break it, and
then the 1e-6 tolerance would be the contract.

## 10. Results

**Proof inventory.** All figures are in PROOFS.md:

- 74 Lean theorems
- 57 F\* lemmas and checked facts, plus the refinement types on every
  verified definition
- 24 negative programs
- 3 allow-listed trusted constructs

**Fixed point vs float** (docs/results/fixed_point.md; pre-specified design,
N = 200 seeds per scenario, bootstrap CIs):

| Scenario | Median max deviation | 95% CI | Max | Saturations | Decision disagreements |
|---|---:|---|---:|---:|---|
| Nominal | 5.91 LSB | [5.68, 6.17] | 10.62 | 0 | 0/200 (Wilson [0.0%, 1.9%]) |
| Faults and recovery | 5.61 LSB | [5.40, 6.04] | 10.89 | 0 | 0/200 (Wilson [0.0%, 1.9%]) |

With 0 disagreements in 200 runs, a disagreement rate up to 1.9% is
statistically consistent with the data. Equivalence is not claimed.

The final experiment shows one genuine overflow:

- 3 saturation events, and the same mode sequence as float.
- After Safe, the deviation grows at the plant's rate: a log-slope of 0.1279
  against an exact-propagation prediction of 0.1279, with a maximum gap of
  7e-11.
- That growth measures the plant, not the arithmetic.

**Final experiment** (docs/FINAL_EXPERIMENT.md):

1. Ready → Running.
2. A biased channel is masked.
3. Dropout is held.
4. An overrun degrades the mode.
5. Three healthy frames recover it.
6. A numeric fault makes the mode Safe, permanently.

All four implementations reproduce the trace, and every transition is mapped to
a theorem, refinement or constructor.

**Benchmark** (docs/results/benchmark.md):

- ATS: about 70 ns per frame, with 0 allocations. Removing the runtime index
  clamps from the frame loop took it down from about 106 ns.
- Idris: about 1.1 µs per frame, with about 11 kB allocated per frame.
- Clean check and build, per language, takes 2 to 8 s.

These numbers come from loops written to match each other, not to be fast. The
F\* and Lean executables run only the decision layer, and the allocation units
differ. The numbers say nothing about the languages in general.

## 11. Limitations

- **Fixed point exists only in the reference.** The fixed-point frame loop
  runs only in the Python reference. Its primitives agree exactly with the
  verified F\* `Sat` operations on 6972 vectors, but no verified language runs
  the whole loop in fixed point.
- **Small and fixed.** The system has n = 4, m = 2 and p = 2. ATS hard-codes
  these sizes. The checks do not cover larger systems.
- **Start-up not simulated.** Boot, SelfTest and Calibrating appear in every
  transition relation, but no simulation runs through them.
- **Unused history.** The history buffer is written every frame, but no
  decision reads it. Control-saturation history enters health only as the
  current frame's flag.
- **Frame-level misses only.** Stage-level deadlines exist in the F\* ledger
  but not in the simulators.
- **Hand-transcribed cost model.** The operation counts in the cost model were
  transcribed by hand from the code. No tool checks the transcription.
- **No common source for the spec.** The four decision functions are separate
  transcriptions of one rule. They agree on every fixture, and every branch is
  exercised by some fixture, but nothing proves them equal.
- **Fixture regeneration may not be portable.** CI regenerates the fixtures and
  compares them byte for byte. The LQR gains are rounded to 9 decimals, so a
  different BLAS could, rarely, change a digit and fail CI. That failure would
  be correct, but noisy.
- **CI is unproven.** CI runs on macOS arm64 to match the development machine.
  It has not yet run on GitHub.
- **One machine.** Every measurement is from one Apple silicon machine.

## 12. What could not be proved

- **Stability.** No theorem says the closed loop is stable, that the state
  stays bounded, or that the observer converges. The spectral radii are numpy
  eigenvalues asserted at generation time. Proving them would need real
  analysis (Mathlib) or verified interval arithmetic over the matrix entries.
  Neither was attempted.
- **Anything about doubles.** The Lean theorems are over ℤ, and the F\* vote
  and arithmetic theorems are over integers. The double implementations rest
  on tests: 13 fixtures, and 20,000 random triples for the vote.
- **Equivalence of the implementations.** Correspondence is checked on
  fixtures, not proved. No tool here can relate an Idris term to ATS-generated
  C.
- **Equivalence of float and fixed point.** It is measured, and it fails by
  design after an injected overflow.
- **Detection of channel faults.** That capability is assumed (A6). Only
  masking is proved.
- **Execution time.** The cost model counts abstract operations and predicts
  nothing about real hardware.
- **The trusted base.** The ATS pool kernel, the C shims, the OCaml drivers,
  the Idris and Lean IO wrappers, the toolchains themselves, and the Python
  oracle (A1, A2).
