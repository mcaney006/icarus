# Proofs and checks

Each row is a claim that a tool checks when `make verify` or `make test` runs.
Nothing aspirational is listed. Status values:

- **proved**: a theorem or lemma, checked by the Lean kernel or by F\* with Z3.
- **refinement**: an F\* refinement type on a definition's result, checked at
  every definition and use.
- **type-enforced**: violating programs do not typecheck. Each such row has a
  negative test (`negative/run.sh`) that must fail to compile, and a well-typed
  twin that must compile.
- **runtime-checked**: the executable checks it on every run and fails if it
  breaks.
- **tested**: holds on the fixtures and generated vectors, with no proof.

Assumption IDs refer to ASSUMPTIONS.md. Every row also assumes A1 (tool
soundness).

## Lean 4: mathematical specification (`lean/Icarus/`)

All Lean statements are over `Int` (A3).

| Property | Source | Status | Assumptions | Executable test counterpart |
|---|---|---|---|---|
| Every abstract mode step is a legal transition | `Modes.step_legal` | proved | A10 | reference self-check asserts legality of each transition in its own run |
| Safe and Fault are terminal for every trigger, and Safe absorbs any trigger sequence | `Modes.safe_terminal`, `fault_terminal`, `safe_absorbing` | proved | A9 | `negative/lean/safe_escape.lean` |
| Boot cannot step directly to Running | `Modes.no_boot_to_running` | proved | A10 | `negative/lean/illegal_transition.lean` |
| Running is reachable from Boot | `Modes.boot_reaches_running` | proved | A10 | — (start-up not simulated) |
| A critical trigger in Running forces Safe whatever follows | `Modes.crit_forces_safe` | proved | A9 | crosscheck `fault_numeric` |
| `sat lim x ∈ [−lim, lim]`, identity inside the interval, idempotent | `Numeric.sat_lb`, `sat_ub`, `sat_mem`, `sat_id`, `sat_idem` | proved | A3 | ATS self-test "vector: clamp stays inside the interval"; `negative/lean/strict_control_bound.lean` (the strict bound is false) |
| Control at limit 1 lies in [−1, 1] | `Numeric.control_in_interval` | proved | A3 | crosscheck (all fixtures) |
| Stage budgets sum to at most the frame (900 ≤ 1000) with margin exactly 100 | `Numeric.budget_fits`, `budget_margin` | proved | A11 | F\* `Icarus.Timing.schedule_fits` |
| Growing any stage by more than 100 makes the frame infeasible | `Numeric.budget_overflow` | proved | A11 | `negative/lean/budget_overflow.lean`; F\* budget mutation test |
| Matrix–vector and matrix–matrix products only exist at matching dimensions | `Mat r c`, `Vec n` indices | type-enforced | — | `negative/lean/matvec_dim_mismatch.lean`, `mul_dim_mismatch.lean` |
| Zero laws: `0·v = 0`, `M·0 = 0`, `0·B = 0`, `A·0 = 0` | `Linear.zero_mulVec`, `mulVec_zero`, `mul_zero_left`, `mul_zero_right` | proved | A3 | — |
| Identity: `I·v = v` for every n, `I·A = A` | `Linear.id_mulVec`, `mul_id_left` | proved | A3 | ATS and Idris self-tests "matrix: right identity" |
| Linearity of `M·v` in v, entrywise | `Linear.mulVec_add_apply`, `mulVec_sub_apply` | proved | A3 | — |
| Matrix product is associative | `Linear.mul_assoc'` | proved | A3 | — |
| Plant at the origin with zero input and disturbance stays at the origin | `Linear.plantStep_origin` | proved | A3, A12 | — |
| A numeric flag classifies as Unsafe, whatever else is set | `Faults.numeric_dominates` | proved | A8 | self-tests "health: numeric dominates" (ATS, Idris); crosscheck `fault_numeric` |
| No flags classifies as Healthy | `Faults.no_flags_healthy` | proved | A8 | self-tests "health: none healthy" |
| Classification is monotone in the flag set | `Faults.classify_monotone` | proved | A8 | — |
| Flag mask encoding round-trips for all 32 masks | `Faults.mask_roundtrip` | proved | — | crosscheck (`G` lines decoded by F\* and Lean) |
| Every decision is a legal transition | `Decision.next_legal` | proved | A10 | crosscheck (all fixtures) |
| Safe and Fault absorb any frame, and any sequence of frames | `Decision.safe_absorbs`, `fault_absorbs`, `safe_forever` | proved | A9 | self-test "mode: Safe absorbs"; crosscheck `final_experiment` |
| Unsafe in Running or Degraded forces Safe, permanently | `Decision.unsafe_forces_safe`, `unsafe_is_permanent` | proved | A9 | crosscheck `fault_numeric`, `final_experiment` |
| A deadline miss in Running (not Unsafe) degrades | `Decision.overrun_degrades` | proved | A11 | crosscheck `fault_overrun`, `final_experiment` |
| Three consecutive Healthy frames recover Degraded to Running | `Decision.recovers` | proved | — | self-test "mode: third healthy frame recovers" |
| Three non-Healthy frames in one Degraded episode force Safe | `Decision.repeated_bad_to_safe` | proved | — | self-test "mode: repeated bad frames -> Safe"; crosscheck `fault_cascade` |
| From an operational mode the loop never re-enters Boot, SelfTest or Calibrating | `Decision.next_operational`, `runFrames_operational`, `run_invariant`, `never_boot` | proved | A10 | crosscheck `M` lines |
| In operational modes, `Monitor.next` is the abstract machine `step` under a derived trigger | `Decision.next_is_step` | proved (operational modes only) | A10 | — |
| History buffer: length never exceeds capacity and saturates at it; a fresh buffer is empty | `Ring.len_le_cap`, `push_len`, `push_len_saturates`, `empty_len` | proved | — | ring self-tests (ATS, Idris) |
| History reads need `age < len`; the newest read is the last push, and older entries shift by one per push | `Ring.get`, `get_newest`, `get_older` | proved | — | `negative/lean/ring_unwritten_read.lean`; ring self-tests |
| After any pushes the buffer holds exactly the most recent `cap` values newest-first; every value read was written, in reverse write order | `Ring.pushAll_slots`, `read_was_written`, `read_order` | proved | — | ring self-tests "ring: oldest retained …" |
| Control `sat(−K x̂)` is bounded for every gain and estimate, and idempotent | `Controller.control_bounded`, `control_idempotent` | proved | A3 | crosscheck |
| Without disturbance or noise, observer error obeys `e⁺ = (A − LC) e`, independent of u | `Controller.observer_error` | proved | A3 | — |

## F\*: refinement-verified components (`fstar/src/`)

| Property | Source | Status | Assumptions | Executable test counterpart |
|---|---|---|---|---|
| Saturating clamp is exact in range and reports saturation outside it | `Icarus.Sat.clamp` | refinement | A5 | `tools/satcheck.py` (6972 vectors vs reference); `negative/fstar/SaturationUnreported.fst` |
| Unsaturated add, sub and neg are exact | `Icarus.Sat.add`, `sub`, `neg` | refinement | A5 | satcheck |
| Unsaturated multiply is within half an LSB of the exact product | `Icarus.Sat.mul` | refinement | A5 | satcheck |
| Whole units convert exactly when they fit; the range is ±32767 units | `Icarus.Sat.of_units_exact`, `range_units` | proved | A5 | satcheck |
| The median vote is one of its inputs, lies between any two inputs, equals two agreeing inputs in any position, and is symmetric | `Icarus.Vote.med_is_a_member`, `divergent_cannot_escape`, `two_agree_first/second/third`, `unanimous`, `symmetric` | proved (over `int`) | A7 | reference self-check: 20,000 double triples; crosscheck `fault_bias`, `fault_stuck`, `fault_range` |
| Sequence numbers never wrap: `bump` reports exhaustion at the limit | `Icarus.Counter.bump` | refinement | — | `negative/fstar/CounterWraps.fst` |
| `advance s n` is `s + n` or exhaustion | `Icarus.Counter.advance_monotone` | proved | — | — |
| Stage budgets fit the frame with margin 100 | `Icarus.Timing.schedule_fits`, `margin_is_100` | proved | A11 | budget mutation test in `negative/run.sh` |
| A ledger never records more than the frame; `charge` returns exact use or exact excess | `Icarus.Timing.ledger`, `charge` | refinement | A11 | — |
| The nominal schedule completes using 900 ticks | `Icarus.Timing.nominal_completes`, `nominal_uses_900` | proved | A11 | — |
| An overrun misses the deadline exactly when it exceeds the 100-tick margin | `Icarus.Timing.miss_iff_beyond_margin`, `overrun_larger_than_margin_detected`, `overrun_within_margin_absorbed` | proved | A11 | crosscheck `fault_overrun` |
| Ring length never exceeds capacity, and the write index stays in range | `Icarus.Ring.push_len`, `len_never_exceeds_capacity` | proved | — | self-tests "ring: length saturates at capacity" |
| Reads need `age < len`; the newest read returns the last push, and older entries shift by one | `Icarus.Ring.get` (refinement), `get_newest`, `slot_shift`, `get_older` | proved | — | `negative/fstar/RingReadUnwritten.fst`; ring self-tests |
| Health classification: mask round-trip, numeric dominates, no flags is Healthy, monotone | `Icarus.Health.mask_roundtrip`, `numeric_dominates`, `no_flags_healthy`, `monotone` | proved | A8 | crosscheck (F\* executable) |
| `decide` returns only legal successors | return type of `Icarus.Mode.decide` | refinement | A10 | `negative/fstar/IllegalTransition.fst`; crosscheck |
| Safe and Fault absorb; Unsafe forces Safe permanently; a miss degrades; recovery; Ready engages | `Icarus.Mode.safe_absorbs`, `fault_absorbs`, `safe_stays_safe`, `unsafe_forces_safe`, `unsafe_is_permanent`, `overrun_degrades`, `recovers`, `ready_engages` | proved | A9, A11 | crosscheck: the extracted `icarus_decide` matches the reference `M`/`H` on 13 fixtures |
| Boot→Running and Safe→Running are illegal | `Icarus.Mode.illegal_examples` | proved | A10 | — |
| Operational modes are closed under `decide` and `run` | `Icarus.Mode.decide_operational`, `run_operational` | proved | A10 | — |
| Decimal encoding of naturals and integers round-trips | `Icarus.Wire.roundtrip`, `roundtrip_int` | proved | — | crosscheck (extracted parser reads every fixture) |
| Abstract cost model: Acquire and Estimate exceed their budgets, the frame fits, the merged-observer saving equals the innovation monitor | `Icarus.Cost` (seven `assert_norm` facts, `matvec_monotone`) | proved | A11 | `fstar/out/icarus_cost` table (docs/results/cost_model.md) |

## Idris 2: dependently typed domain model (`idris/src/`)

| Property | Source | Status | Assumptions | Executable test counterpart |
|---|---|---|---|---|
| Only the 12 legal moves (plus `Stay`) are constructible; Safe has no exit | `Icarus.Mode.Legal`, `transition` | type-enforced | A9, A10 | `negative/idris/illegal_transition.idr`, `safe_to_running.idr` |
| Every decision carries its legality proof | `Icarus.Plant.next : (s : Monitor) -> … -> (s' : Monitor ** Legal s.mode s'.mode)` | type-enforced | A10 | crosscheck (all fixtures) |
| Mode, health and fault codes equal constructor order, so they cannot drift from the ICF numbering | `Icarus.Codes.enumeration` (elaborator reflection generates `modeCode`, `healthCode`, `faultOfCode`, …) | derived at compile time | A13 | crosscheck (codes in every `M`/`H`/`F` line) |
| Matrix products need matching inner dimensions | `Icarus.Linear.matMul`, `matVec` | type-enforced | — | `negative/idris/matmul_dim_mismatch.idr`; self-test "matrix: 2x3 * 3x2 product" |
| Vector indices are bounded | `Vect n`, `Fin n` | type-enforced | — | `negative/idris/index_out_of_bounds.idr` |
| A history read needs an erased proof that the age is below the occupied length | `Icarus.Ring.peek` | type-enforced | — | `negative/idris/ring_unproven_read.idr`; ring self-tests |
| Quantities of different dimension cannot be added | `Icarus.Dim.Quantity`, `qadd` | type-enforced | — | `negative/idris/unit_mismatch.idr`; self-tests "units: …" |
| Every function in `Icarus.*` is total | `%default total` | type-enforced | A2 (`Main.main` and `Main.withFixture` are partial) | `tools/audit-holes.sh` |
| A fixture whose vector or matrix lengths disagree with its declared dimensions is rejected | `Icarus.Fixture.exactVect`, `exactMatrix` | runtime-checked (a successful parse yields a `Vect` of the declared length) | A13 | crosscheck corruption `wrong-dimensions` |

## ATS2: linear deterministic runtime (`ats/src/`)

| Property | Source | Status | Assumptions | Executable test counterpart |
|---|---|---|---|---|
| `decide_mode` returns only legal successors | `dataprop LEGAL`, `decide_mode` (mode.sats) | type-enforced | A10 | `negative/ats/illegal_transition.dats`; crosscheck |
| Matrix operations need matching static dimensions | `matrixptr(double, r, c)` signatures (linear.sats) | type-enforced | — | `negative/ats/matmul_dim_mismatch.dats` |
| Array indices are statically bounded | `arrayptr(double, n)` with indexed ints | type-enforced | — | `negative/ats/index_out_of_bounds.dats` |
| Each frame buffer lease is returned exactly once; an empty pool cannot be taken from; pools are freed only when full | `pool_vt(n, avail)` (pool.sats) | type-enforced | A2 (trusted pool kernel) | `negative/ats/lease_leak.dats`, `lease_double_release.dats`, `empty_pool_take.dats`; self-test "pool: 1000 take/give cycles allocate nothing" |
| Ring write index < capacity and length ≤ capacity | `ring_` datavtype indices (ring.dats) | type-enforced | — | ring self-tests |
| The frame loop makes no allocator call | `run_sim` compares allocator counts (`main.dats` exits 4) | runtime-checked | A2 (counting allocator) | every `icarus_sim` run; benchmark rows (0 calls) |
| A fixture of any shape other than 4/2/2, or with a bad checksum, is rejected | `load_fixture` (fixture.dats) | runtime-checked | A13 | crosscheck corruption variants |

## Cross-language: tested, not proved

| Property | Check | Status | Assumptions |
|---|---|---|---|
| ATS and Idris reproduce the reference `M`, `H`, `G` exactly and `X` within 1e-6 on 13 fixtures | `tools/crosscheck.py --strict` | tested | A4, A12 |
| The F\* and Lean decision executables reproduce the reference `M` and `H` from `G` | `tools/crosscheck.py --strict` | tested | A14 |
| Every implementation rejects the corruption variants (exit 3) | `tools/crosscheck.py --strict` | tested | A13 |
| Reference `FixedArith` equals F\* `Sat` on 6972 vectors, 1047 of them saturating | `tools/satcheck.py` | tested | A5 |
| Fixed-point and float simulators make the same decisions on 400 random runs | `tools/fixed_point_experiment.py` | tested (0/400 disagreements) | A5 |
| No proof hole (sorry, admit, axiom, assume, believe_me, …) outside the allow-list | `tools/audit-holes.sh` | runtime-checked | A2 |

## Not proved

These are stated so nobody infers them from the tables above.

- **Stability.** Nothing proves the closed loop stable, the state bounded, or
  the observer convergent. The spectral radii are numerical (A3).
- **Float semantics.** No theorem covers IEEE doubles. The Lean results are
  over ℤ, and the F\* vote and arithmetic results are over integers.
- **Equivalence between languages.** Agreement is tested on 13 fixtures, not
  proved.
- **Stage work fits stage budgets.** The abstract cost model shows that it does
  not for Acquire and Estimate (docs/results/cost_model.md).
- **Termination of every ATS function.** Functions with a `.<…>.` metric are
  checked. Unmetricated ones (the benchmark loops, `sim_bench`) are not.
- **The trusted base.** Pool kernel, C shims, drivers and IO wrappers (A2).
