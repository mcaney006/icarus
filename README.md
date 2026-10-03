# icarus

icarus is a formal-methods laboratory for a deliberately artificial unstable
discrete-time control system implemented across ATS, Idris 2, F\*, and Lean 4.
It exists to examine how dependent types, linear types, refinement types, and
theorem proving can eliminate classes of control-software defects before
execution.

> **Not flight software. Not suitable for physical vehicle control.** The plant
> is dimensionless, every constant is synthetic, and there are no sensors,
> actuators, drivers or hardware interfaces. REPORT.md §2 explains why.

## The system

```
x[k+1] = A x[k] + B u[k] + w[k]     synthetic unstable plant, 4 states
y[k]   = C x[k] + v[k]              2 measurements, each from 3 voted channels
x̂      = observer(y, u)             Luenberger observer
u[k]   = sat(-K x̂[k]) ∈ [-1, 1]     2 controls
```

The loop also includes:

- a health monitor (Healthy, Suspect, Degraded, Unsafe)
- an eight-mode state machine
- a 1000-tick cyclic executive with stage budgets
- typed injection of ten fault kinds

## Who owns what

| Language | Owns |
|---|---|
| Lean 4 | mathematical specification and proofs (over ℤ) |
| Idris 2 | dimension-indexed executable model; illegal shapes, units and transitions do not typecheck |
| F\* | refinement-verified arithmetic, voting, ring buffer, timing ledger, health and mode manager, cost model |
| ATS2 | linear, fixed-capacity simulation runtime with no allocation in the frame loop |
| Python | the oracle every executable is compared against |

## Status

- `make ci` passes locally.
- 72 Lean theorems and 59 F\* lemmas and checked facts.
- 24 negative programs, all rejected.
- 0 unlisted proof holes.
- ATS, Idris, F\* and Lean match the oracle on 13 fixtures plus corruption
  variants: 66 runs, 0 failures.

Read PROOFS.md for exactly what is checked, ASSUMPTIONS.md for what it rests on,
and REPORT.md §12 for what is not proved. The biggest gap is that nothing proves
stability or anything about floating point.

## Build

```bash
make bootstrap    # detect toolchains, regenerate fixtures
make build        # build all four implementations
make verify       # proofs, type checks, negative programs, hole audit
make test         # self-tests, cross-check, fixed-point vs F* arithmetic
make simulate     # ATS simulation of the final experiment
make benchmark    # docs/results/benchmark.md
make ci           # all of the above; fails on any missing toolchain or skip
```

Toolchains and versions: TOOLCHAINS.md. Results: docs/results/. Final
experiment trace: docs/FINAL_EXPERIMENT.md. Correspondence across languages:
spec/CORRESPONDENCE.md.

## Layout

```
lean/ idris/ fstar/ ats/   the four implementations
reference/                 Python oracle
fixtures/                  deterministic scenarios (JSON and ICF)
spec/                      interchange format, cross-language correspondence
negative/                  programs each type checker must reject
tools/                     fixture generation, cross-check, experiments, benchmark, audit
docs/                      final experiment trace, measured results
```
