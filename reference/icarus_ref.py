#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import math
import random
import sys
from collections import defaultdict
from collections.abc import Iterable, Iterator, Sequence
from dataclasses import dataclass, replace
from enum import IntEnum, IntFlag
from itertools import pairwise
from pathlib import Path
from typing import Protocol, TypeVar

Vector = list[float]
Matrix = list[list[float]]
Word = TypeVar("Word", float, int)

ROOT = Path(__file__).resolve().parents[1]
PLANT_PATH = ROOT / "fixtures" / "plant.json"

MEAS_LIMIT = 50.0
INNOV_THRESH = 10.0
STATE_BOUND = 1.0e3
CTRL_LIMIT = 1.0
DEGRADED_CTRL = 0.5
RECOVERY_FRAMES = 3
DEGRADED_LIMIT = 3
STUCK_VALUE = 7.0
EXCEEDANCE_TOLERANCE = 1e-12
CHANNELS = 3
FRAME_BUDGET = 1000
STAGE_BUDGET = {
    "Acquire": 120,
    "Normalize": 80,
    "Estimate": 220,
    "Decide": 180,
    "Control": 160,
    "Validate": 90,
    "Record": 50,
}
NOMINAL_FRAME_COST = sum(STAGE_BUDGET.values())
CANONICAL_SCALE = 10**9
U64 = (1 << 64) - 1
FNV_OFFSET = 0x811C9DC5
FNV_PRIME = 0x01000193
U32 = (1 << 32) - 1


class FixtureError(ValueError):
    pass


class Mode(IntEnum):
    Boot = 0
    SelfTest = 1
    Calibrating = 2
    Ready = 3
    Running = 4
    Degraded = 5
    Safe = 6
    Fault = 7


LEGAL: dict[Mode, frozenset[Mode]] = {
    Mode.Boot: frozenset({Mode.Boot, Mode.SelfTest, Mode.Fault}),
    Mode.SelfTest: frozenset({Mode.SelfTest, Mode.Calibrating, Mode.Fault}),
    Mode.Calibrating: frozenset({Mode.Calibrating, Mode.Ready, Mode.Fault}),
    Mode.Ready: frozenset({Mode.Ready, Mode.Running, Mode.Safe}),
    Mode.Running: frozenset({Mode.Running, Mode.Degraded, Mode.Safe}),
    Mode.Degraded: frozenset({Mode.Degraded, Mode.Running, Mode.Safe}),
    Mode.Safe: frozenset({Mode.Safe}),
    Mode.Fault: frozenset({Mode.Fault}),
}


class Health(IntEnum):
    Healthy = 0
    Suspect = 1
    Degraded = 2
    Unsafe = 3


class Flag(IntFlag):
    MEAS = 1
    ESTIMATOR = 2
    TIMING = 4
    CTRL_SAT = 8
    NUMERIC = 16

    @property
    def labels(self) -> list[str]:
        return sorted(member.name.lower() for member in self)


class Fault(IntEnum):
    MeasurementDropout = 0
    StaleMeasurement = 1
    BiasedMeasurement = 2
    StuckChannel = 3
    OutOfRange = 4
    TimingOverrun = 5
    NumericSaturation = 6
    CorruptFixture = 7
    EstimatorDisagreement = 8
    ControlSaturation = 9


@dataclass(frozen=True, slots=True)
class FaultEvent:
    step: int
    kind: Fault
    channel: int = 0
    amount: float = 20.0
    value: float = 1.0e6
    overrun: int = 250

    @classmethod
    def parse(cls, record: dict) -> FaultEvent:
        try:
            return cls(**{**record, "kind": Fault[record["kind"]]})
        except (KeyError, TypeError) as error:
            raise FixtureError(f"malformed fault {record!r}: {error}") from None

    @property
    def parameter(self) -> float:
        match self.kind:
            case Fault.BiasedMeasurement:
                return self.amount
            case Fault.OutOfRange:
                return self.value
            case Fault.TimingOverrun:
                return float(self.overrun)
            case _:
                return 0.0


def matvec(m: Matrix, v: Sequence[float]) -> Vector:
    return [sum(a * b for a, b in zip(row, v, strict=True)) for row in m]


def vadd(a: Sequence[float], b: Sequence[float]) -> Vector:
    return [x + y for x, y in zip(a, b, strict=True)]


def vsub(a: Sequence[float], b: Sequence[float]) -> Vector:
    return [x - y for x, y in zip(a, b, strict=True)]


def vneg(a: Sequence[float]) -> Vector:
    return [-x for x in a]


def norm2(a: Sequence[float]) -> float:
    return math.sqrt(sum(x * x for x in a))


def clamp(v: Sequence[float], limit: float) -> Vector:
    return [max(-limit, min(limit, x)) for x in v]


def exceeds(v: Sequence[float], limit: float) -> bool:
    return any(abs(x) > limit + EXCEEDANCE_TOLERANCE for x in v)


def median3(a: float, b: float, c: float) -> float:
    return max(min(a, b), min(max(a, b), c))


def fnv1a(data: bytes) -> int:
    digest = FNV_OFFSET
    for byte in data:
        digest = ((digest ^ byte) * FNV_PRIME) & U32
    return digest


def seal(lines: Iterable[str]) -> str:
    body = "".join(f"{line}\n" for line in lines)
    return f"{body}Z {fnv1a(body.encode())}\n"


def lcg(seed: int) -> Iterator[int]:
    state = seed & U64
    while True:
        state = (state * 6364136223846793005 + 1442695040888963407) & U64
        yield state


def finite_json(text: str) -> dict:
    def reject(constant: str) -> float:
        raise FixtureError(f"non-finite number {constant} in JSON")

    return json.loads(text, parse_constant=reject)


def shaped(matrix: Matrix, rows: int, columns: int, name: str) -> Matrix:
    if len(matrix) != rows or any(len(row) != columns for row in matrix):
        raise FixtureError(f"{name} must be {rows}x{columns}")
    if not all(math.isfinite(entry) for row in matrix for entry in row):
        raise FixtureError(f"{name} has a non-finite entry")
    return matrix


@dataclass(frozen=True, slots=True)
class Plant:
    A: Matrix
    B: Matrix
    C: Matrix
    K: Matrix
    L: Matrix
    control_limit: float = CTRL_LIMIT

    def __post_init__(self) -> None:
        n, m, p = len(self.A), len(self.B[0]) if self.B else 0, len(self.C)
        if not (n and m and p):
            raise FixtureError("plant dimensions must be positive")
        for matrix, rows, columns, name in (
            (self.A, n, n, "A"),
            (self.B, n, m, "B"),
            (self.C, p, n, "C"),
            (self.K, m, n, "K"),
            (self.L, n, p, "L"),
        ):
            shaped(matrix, rows, columns, name)

    @classmethod
    def load(cls, path: Path | str = PLANT_PATH) -> Plant:
        spec = finite_json(Path(path).read_text())
        return cls(spec["A"], spec["B"], spec["C"], spec["K"], spec["L"], spec.get("control_limit", CTRL_LIMIT))

    @property
    def states(self) -> int:
        return len(self.A)

    @property
    def inputs(self) -> int:
        return len(self.B[0])

    @property
    def outputs(self) -> int:
        return len(self.C)


@dataclass(frozen=True, slots=True)
class Fixture:
    steps: int
    initial_state: Vector
    disturbance: Matrix
    noise: Matrix
    faults: tuple[FaultEvent, ...]

    @classmethod
    def parse(cls, record: dict, plant: Plant) -> Fixture:
        try:
            steps, initial = record["steps"], record["initial_state"]
            disturbance, noise = record["disturbance"], record["noise"]
        except KeyError as missing:
            raise FixtureError(f"fixture lacks {missing}") from None
        if not isinstance(steps, int) or steps < 0:
            raise FixtureError(f"steps must be a non-negative integer, got {steps!r}")
        shaped([initial], 1, plant.states, "initial_state")
        shaped(disturbance, steps, plant.states, "disturbance")
        shaped(noise, steps, plant.outputs, "noise")
        faults = tuple(map(FaultEvent.parse, record.get("faults", [])))
        for event in faults:
            if not 0 <= event.step < steps:
                raise FixtureError(f"fault at step {event.step} lies outside 0..{steps - 1}")
            if not 0 <= event.channel < plant.outputs:
                raise FixtureError(f"fault channel {event.channel} lies outside 0..{plant.outputs - 1}")
        return cls(steps, initial, disturbance, noise, faults)

    @classmethod
    def load(cls, path: Path | str, plant: Plant) -> Fixture:
        try:
            return cls.parse(finite_json(Path(path).read_text()), plant)
        except FixtureError as error:
            raise FixtureError(f"{path}: {error}") from None


class Arithmetic(Protocol[Word]):
    def lift(self, v: Sequence[float]) -> list[Word]: ...
    def lift_matrix(self, m: Matrix) -> list[list[Word]]: ...
    def lower(self, v: Sequence[Word]) -> Vector: ...
    def matvec(self, m: Sequence[Sequence[Word]], v: Sequence[Word]) -> list[Word]: ...
    def add(self, a: Sequence[Word], b: Sequence[Word]) -> list[Word]: ...
    def sub(self, a: Sequence[Word], b: Sequence[Word]) -> list[Word]: ...
    def neg(self, a: Sequence[Word]) -> list[Word]: ...
    def clamp(self, v: Sequence[Word], limit: float) -> list[Word]: ...
    def overflow(self, v: Sequence[Word]) -> list[Word]: ...
    def stats(self) -> dict[str, int]: ...


class FloatArithmetic:
    @staticmethod
    def lift(v: Sequence[float]) -> Vector:
        return list(v)

    @staticmethod
    def lift_matrix(m: Matrix) -> Matrix:
        return m

    @staticmethod
    def lower(v: Sequence[float]) -> Vector:
        return list(v)

    @staticmethod
    def matvec(m: Matrix, v: Sequence[float]) -> Vector:
        return matvec(m, v)

    @staticmethod
    def add(a: Sequence[float], b: Sequence[float]) -> Vector:
        return vadd(a, b)

    @staticmethod
    def sub(a: Sequence[float], b: Sequence[float]) -> Vector:
        return vsub(a, b)

    @staticmethod
    def neg(a: Sequence[float]) -> Vector:
        return vneg(a)

    @staticmethod
    def clamp(v: Sequence[float], limit: float) -> Vector:
        return clamp(v, limit)

    @staticmethod
    def overflow(v: Sequence[float]) -> Vector:
        return list(v)

    @staticmethod
    def stats() -> dict[str, int]:
        return {}


class FixedArithmetic:
    SCALE = 65536
    MIN_RAW = -(2**31)
    MAX_RAW = 2**31 - 1
    OVERFLOW_PROBE = 1.0e5

    def __init__(self) -> None:
        self.sat_events = 0
        self.ops = 0

    def saturate(self, raw: int) -> int:
        bounded = min(max(raw, self.MIN_RAW), self.MAX_RAW)
        self.sat_events += bounded != raw
        return bounded

    def quantize(self, x: float) -> int:
        return self.saturate(math.floor(x * self.SCALE + 0.5))

    def mul(self, a: int, b: int) -> int:
        self.ops += 1
        return self.saturate((a * b + self.SCALE // 2) // self.SCALE)

    def plus(self, a: int, b: int) -> int:
        self.ops += 1
        return self.saturate(a + b)

    def minus(self, a: int, b: int) -> int:
        self.ops += 1
        return self.saturate(a - b)

    def lift(self, v: Sequence[float]) -> list[int]:
        return [self.quantize(x) for x in v]

    def lift_matrix(self, m: Matrix) -> list[list[int]]:
        return [self.lift(row) for row in m]

    def lower(self, v: Sequence[int]) -> Vector:
        return [raw / self.SCALE for raw in v]

    def matvec(self, m: Sequence[Sequence[int]], v: Sequence[int]) -> list[int]:
        def dot(row: Sequence[int]) -> int:
            total = 0
            for a, b in zip(row, v, strict=True):
                total = self.plus(total, self.mul(a, b))
            return total

        return [dot(row) for row in m]

    def add(self, a: Sequence[int], b: Sequence[int]) -> list[int]:
        return [self.plus(x, y) for x, y in zip(a, b, strict=True)]

    def sub(self, a: Sequence[int], b: Sequence[int]) -> list[int]:
        return [self.minus(x, y) for x, y in zip(a, b, strict=True)]

    def neg(self, a: Sequence[int]) -> list[int]:
        return [self.saturate(-x) for x in a]

    def clamp(self, v: Sequence[int], limit: float) -> list[int]:
        bound = self.quantize(limit)
        return [max(-bound, min(bound, raw)) for raw in v]

    def overflow(self, v: Sequence[int]) -> list[int]:
        return [self.quantize(self.OVERFLOW_PROBE), *v[1:]]

    def stats(self) -> dict[str, int]:
        return {"sat_events": self.sat_events, "fixed_ops": self.ops}


def classify(flags: Flag) -> Health:
    return Health.Unsafe if Flag.NUMERIC in flags else Health(min(flags.bit_count(), Health.Degraded))


@dataclass(frozen=True, slots=True)
class Monitor:
    mode: Mode = Mode.Ready
    healthy_streak: int = 0
    degraded_bad: int = 0

    def decide(self, health: Health, deadline_miss: bool) -> Monitor:
        mode, bad = self.mode, self.degraded_bad
        match mode, health:
            case Mode.Ready, _:
                mode = Mode.Running
            case ((Mode.Running | Mode.Degraded), Health.Unsafe):
                mode = Mode.Safe
            case Mode.Running, _ if health is Health.Degraded or deadline_miss:
                mode, bad = Mode.Degraded, 0
            case Mode.Degraded, Health.Healthy:
                mode = Mode.Running if self.healthy_streak + 1 >= RECOVERY_FRAMES else Mode.Degraded
            case Mode.Degraded, _:
                bad += 1
                mode = Mode.Safe if bad >= DEGRADED_LIMIT else Mode.Degraded
        if mode not in LEGAL[self.mode]:
            raise RuntimeError(f"illegal transition {self.mode.name} -> {mode.name}")
        streak = self.healthy_streak + 1 if health is Health.Healthy else 0
        return replace(self, mode=mode, healthy_streak=streak, degraded_bad=bad)


@dataclass(frozen=True, slots=True)
class FrameRecord:
    k: int
    mode: Mode
    health: Health
    u: tuple[float, ...]
    y: tuple[float, ...]
    xhat: tuple[float, ...]
    x: tuple[float, ...]
    flags: Flag
    frame_cost: int
    deadline_miss: bool


@dataclass(frozen=True, slots=True)
class Run:
    trace: list[FrameRecord]
    modes: list[Mode]
    final_state: Vector
    final_estimate: Vector
    arithmetic: dict[str, int]

    @property
    def final_mode(self) -> Mode:
        return self.modes[-1]

    def canonical(self) -> dict[str, list[int]]:
        return {
            "M": [int(mode) for mode in self.modes],
            "H": [int(frame.health) for frame in self.trace],
            "G": [int(frame.flags) for frame in self.trace],
            "X": [round(z * CANONICAL_SCALE) for z in self.final_state],
        }

    def canonical_lines(self) -> list[str]:
        return [" ".join(map(str, (tag, *values))) for tag, values in self.canonical().items()]


def acquire(clean: Vector, events: Sequence[FaultEvent], last: Vector) -> tuple[Vector, Flag]:
    channels = [list(clean) for _ in range(CHANNELS)]
    flags = Flag(0)
    for event in events:
        lane = event.channel
        match event.kind:
            case Fault.BiasedMeasurement:
                channels[0][lane] += event.amount
            case Fault.StuckChannel:
                channels[0][lane] = STUCK_VALUE
            case Fault.OutOfRange:
                channels[0][lane] = event.value
            case Fault.MeasurementDropout:
                for channel in channels:
                    channel[lane] = last[lane]
            case _:
                continue
        flags |= Flag.MEAS
    if any(event.kind is Fault.StaleMeasurement for event in events):
        return list(last), flags | Flag.MEAS
    return [median3(*samples) for samples in zip(*channels, strict=True)], flags


def run(plant: Plant, fixture: Fixture, arithmetic: Arithmetic | None = None) -> Run:
    arith = FloatArithmetic() if arithmetic is None else arithmetic
    A, B, C, K, L = map(arith.lift_matrix, (plant.A, plant.B, plant.C, plant.K, plant.L))
    schedule: defaultdict[int, list[FaultEvent]] = defaultdict(list)
    for event in fixture.faults:
        schedule[event.step].append(event)

    x = list(fixture.initial_state)
    xhat = arith.lift([0.0] * plant.states)
    u_prev = arith.lift([0.0] * plant.inputs)
    last = [0.0] * plant.outputs
    monitor = Monitor()
    trace: list[FrameRecord] = []
    modes = [monitor.mode]

    for step, (noise, disturbance) in enumerate(zip(fixture.noise, fixture.disturbance, strict=True)):
        events = schedule.get(step, [])
        kinds = {event.kind for event in events}

        voted, flags = acquire(vadd(matvec(plant.C, x), noise), events, last)
        y = clamp(voted, MEAS_LIMIT)
        if exceeds(voted, MEAS_LIMIT):
            flags |= Flag.MEAS
        last = y

        innovation = arith.sub(arith.lift(y), arith.matvec(C, xhat))
        if norm2(arith.lower(innovation)) > INNOV_THRESH or Fault.EstimatorDisagreement in kinds:
            flags |= Flag.ESTIMATOR
        xhat = arith.add(arith.add(arith.matvec(A, xhat), arith.matvec(B, u_prev)), arith.matvec(L, innovation))
        if Fault.NumericSaturation in kinds:
            xhat = arith.overflow(xhat)

        overrun = next((event.overrun for event in events if event.kind is Fault.TimingOverrun), 0)
        frame_cost = NOMINAL_FRAME_COST + overrun
        deadline_miss = frame_cost > FRAME_BUDGET
        if deadline_miss:
            flags |= Flag.TIMING

        if monitor.mode in (Mode.Running, Mode.Degraded):
            raw = arith.neg(arith.matvec(K, xhat))
            limit = plant.control_limit if monitor.mode is Mode.Running else DEGRADED_CTRL
            if exceeds(arith.lower(raw), limit) or Fault.ControlSaturation in kinds:
                flags |= Flag.CTRL_SAT
            u = arith.clamp(raw, limit)
        else:
            u = arith.lift([0.0] * plant.inputs)

        estimate = arith.lower(xhat)
        if Fault.NumericSaturation in kinds or any(not math.isfinite(z) or abs(z) > STATE_BOUND for z in estimate):
            flags |= Flag.NUMERIC

        health = classify(flags)
        applied = arith.lower(u)
        trace.append(
            FrameRecord(
                k=step,
                mode=monitor.mode,
                health=health,
                u=tuple(applied),
                y=tuple(y),
                xhat=tuple(estimate),
                x=tuple(x),
                flags=flags,
                frame_cost=frame_cost,
                deadline_miss=deadline_miss,
            )
        )
        monitor = monitor.decide(health, deadline_miss)
        modes.append(monitor.mode)

        x = vadd(vadd(matvec(plant.A, x), matvec(plant.B, applied)), disturbance)
        u_prev = u

    return Run(trace, modes, x, arith.lower(xhat), arith.stats())


def require(condition: bool, failure: str) -> None:
    if not condition:
        raise AssertionError(failure)


def selfcheck() -> str:
    plant = Plant(A=[[1.1, 0.1], [0.0, 1.05]], B=[[0.0], [0.5]], C=[[1.0, 0.0]], K=[[2.4, 1.3]], L=[[1.25], [3.575]])
    initial = [0.3, -0.2]
    fixture = Fixture.parse(
        {"steps": 20, "initial_state": initial, "disturbance": [[0.0, 0.0]] * 20, "noise": [[0.0]] * 20}, plant
    )
    result = run(plant, fixture)

    require(all(abs(z) <= CTRL_LIMIT + 1e-9 for frame in result.trace for z in frame.u), "control left [-1, 1]")
    require(all(after in LEGAL[before] for before, after in pairwise(result.modes)), "illegal transition")
    require(NOMINAL_FRAME_COST <= FRAME_BUDGET, "stage budgets exceed the frame")
    require(result.modes[:2] == [Mode.Ready, Mode.Running], "did not engage from Ready")
    require(norm2(result.final_state) < norm2(initial), "stable closed loop did not shrink the state")
    require(median3(100.0, 1.0, 1.0) == 1.0, "one divergent channel moved the vote")
    require(median3(1.0, 2.0, 3.0) == 2.0, "vote is not the median")

    rng = random.Random(20261002)
    for _ in range(20000):
        triple = [rng.choice([rng.uniform(-1e6, 1e6), rng.uniform(-1, 1) * 1e-300, 0.0, -0.0, 1e308]) for _ in range(3)]
        vote = median3(*triple)
        require(vote in triple and vote == sorted(triple)[1], f"median3{tuple(triple)} = {vote}")

    return (
        f"selfcheck OK: final_state={[round(z, 4) for z in result.final_state]} "
        f"modes={result.modes[0].name}..{result.final_mode.name}"
    )


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--plant", type=Path, default=PLANT_PATH)
    parser.add_argument("--fixture", type=Path)
    parser.add_argument("--fixed-point", action="store_true")
    output = parser.add_mutually_exclusive_group()
    output.add_argument("--trace", action="store_true")
    output.add_argument("--canonical", action="store_true")
    output.add_argument("--selfcheck", action="store_true")
    args = parser.parse_args(argv)

    if args.selfcheck:
        print(selfcheck())
        return 0
    if args.fixture is None:
        parser.error("--fixture is required")
    try:
        plant = Plant.load(args.plant)
        result = run(plant, Fixture.load(args.fixture, plant), FixedArithmetic() if args.fixed_point else None)
    except (OSError, FixtureError) as error:
        parser.exit(2, f"icarus_ref: {error}\n")

    if args.canonical:
        print("\n".join(result.canonical_lines()))
        return 0
    if args.trace:
        for frame in result.trace:
            print(
                f"k={frame.k:02d} {frame.mode.name:9s} {frame.health.name:8s} "
                f"u={[round(z, 4) for z in frame.u]} flags={frame.flags.labels} miss={int(frame.deadline_miss)}"
            )
    print(
        json.dumps(
            {
                "final_mode": result.final_mode.name,
                "final_state": [round(z, 6) for z in result.final_state],
                "modes": [mode.name for mode in result.modes],
            },
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
