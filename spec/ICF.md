# ICF 2: icarus fixture interchange

ASCII, line oriented. A line is a one-letter tag followed by decimal integers
separated by single spaces. Lines starting with `#` are comments. There are no
floats and no strings: real values are stored as `round(v * 1e9)`, so every
language recovers the same IEEE double with one correctly rounded division.

```
# icarus fixture <name>
D <n> <m> <p> <steps>
A <n*n>   B <n*m>   C <p*n>   K <m*n>   L <n*p>      row-major, scaled
X <n>                      initial true state
T <tol>                    cross-language tolerance on final state (1e-9 units)
W <k> <n>                  disturbance for step k            (steps lines)
V <k> <p>                  sensor noise for step k           (steps lines)
F <step> <kind> <chan> <param>        fault injection (zero or more)
M <steps+1 mode codes>     expected mode before each step, plus final mode
H <steps health codes>     expected health per step
G <steps masks>            expected flag bitmask per step
E <n>                      expected final true state (scaled)
Z <uint32>                 FNV-1a over every byte before this line, newlines included
```

| code | mode        | health   | fault kind              | flag bit |
|------|-------------|----------|-------------------------|----------|
| 0    | Boot        | Healthy  | MeasurementDropout      | 1 meas       |
| 1    | SelfTest    | Suspect  | StaleMeasurement        | 2 estimator  |
| 2    | Calibrating | Degraded | BiasedMeasurement       | 4 timing     |
| 3    | Ready       | Unsafe   | StuckChannel            | 8 ctrl_sat   |
| 4    | Running     |          | OutOfRange              | 16 numeric   |
| 5    | Degraded    |          | TimingOverrun           |          |
| 6    | Safe        |          | NumericSaturation       |          |
| 7    | Fault       |          | CorruptFixture          |          |
|      |             |          | EstimatorDisagreement   |          |
|      |             |          | ControlSaturation       |          |

Fault kinds are numbered in the order listed (0..9). Fault params are scaled
like reals; `TimingOverrun` carries ticks times 1e9. A file whose `Z` does not
match, that omits `Z`, or that fails to parse is the `CorruptFixture` fault and
every consumer must reject it.

## Canonical output

Every executable prints exactly these lines for a fixture it accepts and exits 0.
A rejected fixture prints `REJECT <reason>` and exits 3.

```
M <steps+1 mode codes>
H <steps health codes>
G <steps flag masks>
X <n final true state, round(x * 1e9)>
```

`tools/crosscheck.py` compares `M H G` exactly and `X` within `T`.
