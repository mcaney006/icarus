# icarus

icarus is a formal-methods laboratory for a deliberately artificial, unstable
discrete-time control system implemented across **ATS**, **Idris 2**, **F\***, and
**Lean 4**. It exists to examine how dependent types, linear types, refinement
types, and theorem proving each eliminate a different class of control-software
defect *before* execution, and to measure where those guarantees overlap.

> **This is not flight software.** It cannot and must not be used to control any
> physical rocket, missile, aircraft, drone, or launch vehicle. The plant is
> dimensionless, every constant is synthetic and chosen for mathematical
> testing, and there are no sensors, actuators, drivers, or hardware interfaces
> of any kind. The nearest thing to "reality" here is a `.json` fixture. See
> [REPORT.md](REPORT.md) §2 for why the system is intentionally nonphysical.

## The system under study

A generic linear discrete-time plant with synthetic matrices:

```
x[k+1] = A x[k] + B u[k] + w[k]      (abstract state evolution)
y[k]   = C x[k] + v[k]               (synthetic measurement)
u[k]   = sat(-K x_hat[k])            (abstract stabilising feedback, clamped)
x_hat  = observer(y, u)              (abstract deterministic state estimate)
```

`x` is a dimensionless state (position-like, rate-like, orientation-like,
angular-rate-like terms with **no** physical geometry attached), `u` an abstract
control in `[-1, 1]`, `w`/`v` synthetic disturbance and noise. The open-loop
`A` is unstable by construction; the point is to study the *software*, not to
stabilise anything real.

## Who owns what

| Language | Owns | Guarantee it contributes |
|----------|------|--------------------------|
| **Lean 4** | mathematical specification + proofs | the model's properties are *true* (dimension, mode closure, bounded arithmetic, invariants) |
| **Idris 2** | dependently-typed executable domain model | illegal dimensions and illegal mode transitions *do not typecheck* |
| **F\***    | refinement-typed data structures + state machines | buffers, counters, timing budgets satisfy *explicit postconditions* |
| **ATS**    | linear-typed deterministic simulation runtime | fixed-capacity resources, no GC in the loop, each resource consumed *once* |

The same toy system is built four times, on purpose. The research question is
*which class of defect each discipline makes unrepresentable.*

## Layout

```
spec/            cross-language concept correspondence
fixtures/        deterministic interchange files (plant + scenarios)
reference/       Python executable oracle (defines expected behaviour)
lean/   idris/   fstar/   ats/     the four implementations
negative/        programs that MUST fail to compile (one per discipline)
tools/           toolchain detection + fixture generation + cross-check
PROOFS.md        every formal claim, its status, and its runnable counterpart
ASSUMPTIONS.md   every assumption the proofs rest on
TOOLCHAINS.md    pinned toolchain versions + how they were obtained
REPORT.md        the research write-up
```

## Build

```
make bootstrap    # detect toolchains, generate fixtures
make build        # compile every implementation whose toolchain is present
make test         # unit + fixture tests
make verify       # run the provers / type-checkers (proofs + negative tests)
make simulate     # run the reference + ATS simulation on a fixture
make crosscheck   # compare all implementations against the reference
make benchmark    # micro-benchmarks
make clean
```

Missing toolchains are reported and skipped, never silently passed. See
[TOOLCHAINS.md](TOOLCHAINS.md) for versions and [PROOFS.md](PROOFS.md) for what
is actually mechanically checked today.
