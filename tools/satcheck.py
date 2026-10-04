#!/usr/bin/env python3
from __future__ import annotations

import argparse
import subprocess
import sys
from collections.abc import Callable
from itertools import product
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "reference"))
import icarus_ref as ref

EXECUTABLE = ref.ROOT / "fstar" / "out" / "icarus_sat"
FIXED = ref.FixedArithmetic
LO, HI = FIXED.MIN_RAW, FIXED.MAX_RAW
OPERATIONS: dict[str, Callable[[ref.FixedArithmetic], Callable[[int, int], int]]] = {
    "a": lambda word: word.plus,
    "s": lambda word: word.minus,
    "m": lambda word: word.mul,
}
EDGES = (
    LO,
    LO + 1,
    -65536 * 32768,
    -65537,
    -65536,
    -32769,
    -32768,
    -1,
    0,
    1,
    32767,
    32768,
    65535,
    65536,
    65537,
    65536 * 32767,
    HI - 1,
    HI,
)
WIDTHS = (2**8, 2**16, 2**24, 2**31)
SAMPLES_PER_WIDTH = 500
TIMEOUT_SECONDS = 120

Case = tuple[str, int, int]
Outcome = tuple[int, int]


def cases() -> list[Case]:
    states = ref.lcg(20261002)

    def uniform(lo: int, hi: int) -> int:
        return lo + (next(states) >> 11) % (hi - lo + 1)

    def pair(width: int) -> tuple[int, int]:
        lo, hi = max(LO, -width), min(HI, width - 1)
        return uniform(lo, hi), uniform(lo, hi)

    return [
        *product(OPERATIONS, EDGES, EDGES),
        *((op, *pair(width)) for width in WIDTHS for op in OPERATIONS for _ in range(SAMPLES_PER_WIDTH)),
    ]


def reference(op: str, a: int, b: int) -> Outcome:
    word = FIXED()
    return OPERATIONS[op](word)(a, b), int(word.sat_events > 0)


def outcomes(stdout: str) -> list[Outcome]:
    parsed = []
    for line in stdout.splitlines():
        fields = line.split()
        if len(fields) != 2 or not all(field.lstrip("-").isdigit() for field in fields):
            raise ValueError(f"malformed icarus_sat line {line[:60]!r}")
        parsed.append((int(fields[0]), int(fields[1])))
    return parsed


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--strict", action="store_true")
    args = parser.parse_args()

    if not EXECUTABLE.exists():
        print("satcheck: SKIP (build fstar first)")
        return int(args.strict)
    vectors = cases()
    expected = [reference(*case) for case in vectors]
    try:
        result = subprocess.run(
            [EXECUTABLE, "/dev/stdin"],
            input="".join(f"{op} {a} {b}\n" for op, a, b in vectors),
            capture_output=True,
            text=True,
            timeout=TIMEOUT_SECONDS,
        )
        if result.returncode:
            raise ValueError(f"icarus_sat exited {result.returncode}: {result.stderr.strip()[:200]}")
        got = outcomes(result.stdout)
    except (OSError, subprocess.TimeoutExpired, ValueError) as error:
        print(f"satcheck: {error}")
        return 1
    if len(got) != len(vectors):
        print(f"satcheck: icarus_sat answered {len(got)} of {len(vectors)} vectors")
        return 1

    disagreements = [
        (case, actual, wanted) for case, actual, wanted in zip(vectors, got, expected, strict=True) if actual != wanted
    ]
    print(
        f"satcheck: {len(vectors)} vectors ({sum(flag for _, flag in expected)} saturating), "
        f"{len(disagreements)} disagreements"
    )
    for case, actual, wanted in disagreements[:5]:
        print("  ", case, "fstar:", actual, "python:", wanted)
    return int(bool(disagreements))


if __name__ == "__main__":
    sys.exit(main())
