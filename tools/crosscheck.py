#!/usr/bin/env python3
from __future__ import annotations

import argparse
import subprocess
import sys
import tempfile
from collections.abc import Iterator
from dataclasses import dataclass
from functools import cache
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "reference"))
import icarus_ref as ref

REJECTED = 3
TIMEOUT_SECONDS = 120
CANONICAL_TAGS = "MHGX"

Lines = dict[str, list[int]]


class OutputError(ValueError):
    pass


@dataclass(frozen=True)
class Implementation:
    name: str
    executable: Path
    emits: str
    checks_shape: bool

    def execute(self, fixture: Path) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [self.executable, fixture], capture_output=True, text=True, errors="replace", timeout=TIMEOUT_SECONDS
        )


IMPLEMENTATIONS = (
    Implementation("ats", ref.ROOT / "ats/build/icarus_sim", "MHGX", True),
    Implementation("idris", ref.ROOT / "idris/build/exec/icarus", "MHGX", True),
    Implementation("fstar", ref.ROOT / "fstar/out/icarus_decide", "MH", False),
    Implementation("lean", ref.ROOT / "lean/.lake/build/bin/icarus", "MH", False),
)


def parse(output: str, tags: str = CANONICAL_TAGS) -> Lines:
    lines: Lines = {}
    for line in output.splitlines():
        tag, _, values = line.partition(" ")
        if len(tag) != 1 or tag not in tags:
            continue
        if tag in lines:
            raise OutputError(f"duplicate {tag} line")
        try:
            lines[tag] = [int(token) for token in values.split()]
        except ValueError:
            raise OutputError(f"non-integer {tag} line: {line[:60]!r}") from None
    return lines


@cache
def plant() -> ref.Plant:
    return ref.Plant.load()


@cache
def oracle(fixture: Path) -> Lines:
    return ref.run(plant(), ref.Fixture.load(fixture.with_suffix(".json"), plant())).canonical()


@cache
def recorded(fixture: Path) -> tuple[Lines, int]:
    text = fixture.read_text()
    lines = parse(text, "MHGE")
    lines["X"] = lines.pop("E")
    tolerances = parse(text, "T").get("T", [])
    if len(tolerances) != 1:
        raise OutputError(f"{fixture.name} needs exactly one T value")
    return lines, tolerances[0]


def mismatches(got: Lines, expected: Lines, tags: str, tolerance: int) -> list[str]:
    errors = []
    for tag in tags:
        if tag not in got:
            errors.append(f"missing {tag} line")
        elif tag == "X":
            if len(got[tag]) != len(expected[tag]) or any(
                abs(a - b) > tolerance for a, b in zip(got[tag], expected[tag], strict=True)
            ):
                errors.append(f"X mismatch got={got[tag]} ref={expected[tag]} tol={tolerance}")
        elif got[tag] != expected[tag]:
            first = next(
                (i for i, (a, b) in enumerate(zip(got[tag], expected[tag], strict=False)) if a != b),
                min(len(got[tag]), len(expected[tag])),
            )
            errors.append(f"{tag} differs first at index {first}")
    return errors


def compare(implementation: Implementation, fixture: Path) -> list[str]:
    try:
        result = implementation.execute(fixture)
        if result.returncode:
            return [f"exit {result.returncode}: {result.stderr.strip()[:80]}"]
        return mismatches(parse(result.stdout), oracle(fixture), implementation.emits, recorded(fixture)[1])
    except (OSError, subprocess.TimeoutExpired, OutputError) as error:
        return [f"{type(error).__name__}: {error}"]


def rejects(implementation: Implementation, variant: Path) -> str | None:
    try:
        result = implementation.execute(variant)
    except (OSError, subprocess.TimeoutExpired) as error:
        return f"{type(error).__name__}: {error}"
    if result.returncode == REJECTED and result.stdout.lstrip().startswith("REJECT"):
        return None
    return f"exit={result.returncode} out={result.stdout[:40]!r}"


def corruptions(fixture: Path, checks_shape: bool) -> Iterator[tuple[str, str]]:
    text = fixture.read_text()
    unsealed = [line for line in text.splitlines() if not line.startswith("Z ")]
    yield "payload-flip", text.replace("\nW 3 ", "\nW 3 9", 1)
    yield "missing-checksum", "\n".join(unsealed) + "\n"
    yield "truncated", text[: len(text) // 2]
    if checks_shape:
        yield (
            "wrong-dimensions",
            ref.seal(["D 3 2 2 " + line.split(" ", 4)[4] if line.startswith("D ") else line for line in unsealed]),
        )


def verdict(errors: list[str]) -> str:
    return "OK" if not errors else "FAIL " + "; ".join(errors)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--strict", action="store_true")
    args = parser.parse_args()

    fixtures = sorted((ref.ROOT / "fixtures").glob("*.icf"))
    if not fixtures:
        parser.exit(1, "crosscheck: no fixtures; run make bootstrap\n")
    failures = runs = 0
    skipped: list[str] = []

    for fixture in fixtures:
        expected, tolerance = recorded(fixture)
        errors = mismatches(oracle(fixture), expected, CANONICAL_TAGS, tolerance)
        print(f"[ref ] {fixture.name:28s} {verdict(errors)}")
        failures += bool(errors)

    for implementation in IMPLEMENTATIONS:
        label = f"[{implementation.name:5s}]"
        if not implementation.executable.exists():
            skipped.append(implementation.name)
            print(f"{label} SKIP (not built: {implementation.executable.relative_to(ref.ROOT)})")
            continue
        for fixture in fixtures:
            errors = compare(implementation, fixture)
            print(f"{label} {fixture.name:28s} {verdict(errors)}")
            failures += bool(errors)
            runs += 1
        with tempfile.TemporaryDirectory() as scratch:
            for tag, body in corruptions(fixtures[0], implementation.checks_shape):
                variant = Path(scratch, f"{tag}.icf")
                variant.write_text(body)
                problem = rejects(implementation, variant)
                print(f"{label} corrupt:{tag:18s} {'REJECTED ok' if problem is None else f'FAIL {problem}'}")
                failures += problem is not None
                runs += 1

    print(f"crosscheck: {runs} implementation runs, {failures} failures, skipped={skipped or 'none'}")
    return int(bool(failures) or (args.strict and bool(skipped)))


if __name__ == "__main__":
    sys.exit(main())
