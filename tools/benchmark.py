#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import platform
import shlex
import shutil
import statistics
import subprocess
import sys
import time
from collections import defaultdict
from collections.abc import Iterable, Sequence
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "fixtures" / "final_experiment.icf"
RESULTS = ROOT / "docs" / "results"
MIN_END_TO_END_RUNS = 10
ALLOCATION_UNITS = {"ats": "allocator calls", "idris": "bytes (Chez sstats)"}


@dataclass(frozen=True)
class Target:
    name: str
    scope: str
    command: tuple[str | Path, ...]

    @property
    def built(self) -> bool:
        return Path(self.command[0]).exists()


HARNESSES = (
    Target("ats", "microbenchmarks", (ROOT / "ats/build/icarus_bench", FIXTURE, "20000")),
    Target("idris", "microbenchmarks", (ROOT / "idris/build/exec/icarus", "--bench", FIXTURE, "2000")),
)
END_TO_END = (
    Target(
        "reference",
        "full simulation (Python oracle)",
        (
            sys.executable,
            ROOT / "reference/icarus_ref.py",
            "--canonical",
            "--fixture",
            ROOT / "fixtures/final_experiment.json",
        ),
    ),
    Target("ats", "full simulation", (ROOT / "ats/build/icarus_sim", FIXTURE)),
    Target("idris", "full simulation", (ROOT / "idris/build/exec/icarus", FIXTURE)),
    Target("fstar", "decision layer only", (ROOT / "fstar/out/icarus_decide", FIXTURE)),
    Target("lean", "decision layer only", (ROOT / "lean/.lake/build/bin/icarus", FIXTURE)),
)
ARTIFACTS = {
    "ats": "ats/build/icarus_sim",
    "idris": "idris/build/exec/icarus_app",
    "fstar": "fstar/out/icarus_decide",
    "lean": "lean/.lake/build/bin/icarus",
}


def sh(command: Sequence[str | Path], cwd: Path = ROOT, check: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(command, cwd=cwd, capture_output=True, text=True)
    if check and result.returncode:
        sys.exit(f"benchmark: command failed: {shlex.join(map(str, command))}\n{result.stdout}\n{result.stderr}")
    return result


def seconds(command: Sequence[str | Path], cwd: Path = ROOT) -> float:
    start = time.perf_counter()
    sh(command, cwd)
    return time.perf_counter() - start


def toolchain(name: str) -> str:
    return sh(["bash", "tools/detect-toolchains.sh", "--path", name]).stdout.strip()


def footprint(path: Path) -> int:
    return path.stat().st_size if path.is_file() else sum(f.stat().st_size for f in path.rglob("*") if f.is_file())


def microbenchmarks(repeats: int) -> list[dict]:
    samples: defaultdict[tuple[str, str], list[tuple[int, int, int]]] = defaultdict(list)
    for harness in HARNESSES:
        if not harness.built:
            print(f"[bench] SKIP {harness.name} microbenchmarks (not built)")
            continue
        for _ in range(repeats):
            for row in sh(harness.command).stdout.splitlines():
                lang, operation, *numbers = row.split(",")
                if lang != harness.name:
                    continue
                if len(numbers) != 3 or not all(n.isdigit() for n in numbers) or int(numbers[0]) == 0:
                    sys.exit(f"benchmark: malformed {harness.name} row {row!r}")
                iterations, nanos, allocations = map(int, numbers)
                samples[lang, operation].append((iterations, max(nanos, 1), allocations))
    rows = []
    for (lang, operation), runs in samples.items():
        iterations = runs[0][0]
        nanos = [ns for _, ns, _ in runs]
        median_ns = statistics.median(nanos)
        rows.append(
            {
                "lang": lang,
                "op": operation,
                "iterations": iterations,
                "runs": len(runs),
                "ns_per_op": median_ns / iterations,
                "ops_per_sec": iterations / (median_ns / 1e9),
                "ns_min": min(nanos) / iterations,
                "ns_max": max(nanos) / iterations,
                "alloc_per_op": statistics.median(alloc for *_, alloc in runs) / iterations,
                "alloc_unit": ALLOCATION_UNITS[lang],
            }
        )
    return rows


def end_to_end(repeats: int) -> list[dict]:
    rows = []
    for target in END_TO_END:
        if not target.built:
            print(f"[bench] SKIP {target.name} end-to-end (not built)")
            continue
        times = [seconds(target.command) for _ in range(repeats)]
        rows.append(
            {
                "impl": target.name,
                "scope": target.scope,
                "runs": repeats,
                "median_ms": statistics.median(times) * 1e3,
                "min_ms": min(times) * 1e3,
                "max_ms": max(times) * 1e3,
            }
        )
    return rows


def sizes() -> list[dict]:
    return [
        {"impl": name, "path": path, "bytes": footprint(ROOT / path)}
        for name, path in ARTIFACTS.items()
        if (ROOT / path).exists()
    ]


def clean_build(*paths: str) -> None:
    for path in map(ROOT.joinpath, paths):
        if path.exists():
            shutil.rmtree(path)


def rebuild() -> list[dict]:
    rows = []

    def record(lang: str, stage: str, elapsed: float) -> None:
        rows.append({"lang": lang, "stage": stage, "seconds": elapsed})

    if lake := toolchain("lake"):
        clean_build("lean/.lake/build")
        record(
            "lean",
            "check+build (lake build: elaboration and kernel checking of every proof, plus the executable)",
            seconds([lake, "build"], ROOT / "lean"),
        )
    if idris2 := toolchain("idris2"):
        clean_build("idris/build")
        record(
            "idris",
            "check+build (type checking and Chez Scheme code generation)",
            seconds([idris2, "--build", "icarus.ipkg"], ROOT / "idris"),
        )
    if fstar := toolchain("fstar"):
        clean_build("fstar/out")
        record(
            "fstar", "check (verify all modules with Z3)", seconds(["make", "-C", "fstar", "verify", f"FSTAR={fstar}"])
        )
        record(
            "fstar",
            "build (OCaml extraction, compilation and linking)",
            seconds(["make", "-C", "fstar", "build", f"FSTAR={fstar}"]),
        )
    if patscc := toolchain("patscc"):
        sources = ROOT / "ats/src"
        start = time.perf_counter()
        for source in sorted(sources.glob("*.dats")):
            sh([patscc, "-tcats", source.name], sources)
        record(
            "ats",
            "check (patscc -tcats on every .dats: linear and dependent type checking)",
            time.perf_counter() - start,
        )
        clean_build("ats/build")
        record(
            "ats",
            "check+build (patsopt to C, clang -O2, link; three executables)",
            seconds(["make", "-C", "ats", f"PATSCC={patscc}"]),
        )
    return rows


def machine() -> dict:
    cpu = sh(["sysctl", "-n", "machdep.cpu.brand_string"], check=False).stdout.strip() or platform.processor()
    return {
        "os": f"{platform.system()} {platform.release()}",
        "machine": platform.machine(),
        "cpu": cpu,
        "python": platform.python_version(),
    }


def table(columns: dict[str, str], rows: list[list[object]]) -> list[str]:
    def line(cells: Iterable[object]) -> str:
        return "| " + " | ".join(map(str, cells)) + " |"

    return [line(columns), "|" + "|".join(columns.values()) + "|", *map(line, rows)]


def report(data: dict) -> str:
    host = data["machine"]
    lines = [
        "# Benchmark",
        "",
        f"Generated by `make benchmark` (`tools/benchmark.py`). Machine: {host['cpu']}, {host['os']} "
        f"({host['machine']}).",
        "",
        "These numbers describe these programs on this machine. They do not rank the",
        "languages. The loops are written to match one another, not to be fast. The",
        "F\\* and Lean executables run only the decision layer. Allocation is counted",
        "in different units (ATS: calls into the counting allocator; Idris: bytes",
        "reported by the Chez Scheme collector). Wall-clock times include process",
        "start-up and fixture parsing.",
        "",
        "## Per-operation throughput",
        "",
        f"Median of {data['repeats']} runs of each harness (`ats/src/bench.dats`, `idris/src/Main.idr --bench`).",
        "All vectors and matrices are 4 and 4×4. `frame` is one full Acquire to Record cycle",
        "of the simulator on `final_experiment`.",
        "",
        *table(
            {
                "Lang": "---",
                "Operation": "---",
                "ns/op (median)": "---:",
                "ns/op range": "---:",
                "ops/s": "---:",
                "alloc/op": "---:",
                "alloc unit": "---",
            },
            [
                [
                    r["lang"],
                    r["op"],
                    f"{r['ns_per_op']:.1f}",
                    f"{r['ns_min']:.1f}–{r['ns_max']:.1f}",
                    f"{r['ops_per_sec']:.3g}",
                    f"{r['alloc_per_op']:.3g}",
                    r["alloc_unit"],
                ]
                for r in data["micro"]
            ],
        ),
        "",
        "## End-to-end process runs on `final_experiment.icf` (48 frames)",
        "",
        *table(
            {"Impl": "---", "Scope": "---", "median ms": "---:", "min–max ms": "---:"},
            [
                [r["impl"], r["scope"], f"{r['median_ms']:.1f}", f"{r['min_ms']:.1f}–{r['max_ms']:.1f}"]
                for r in data["e2e"]
            ],
        ),
        "",
        "## Binary size",
        "",
        *table(
            {"Impl": "---", "Artifact": "---", "bytes": "---:"},
            [[r["impl"], f"`{r['path']}`", r["bytes"]] for r in data["sizes"]],
        ),
        "",
        "The Idris figure is the compiled Scheme program only. It needs a Chez Scheme",
        "installation at run time, and that is not counted. The other three artifacts are",
        "native executables with their runtimes linked in.",
    ]
    if data["rebuild"]:
        lines += [
            "",
            "## Clean build and check times (one run each)",
            "",
            *table(
                {"Lang": "---", "Stage": "---", "seconds": "---:"},
                [[r["lang"], r["stage"], f"{r['seconds']:.1f}"] for r in data["rebuild"]],
            ),
            "",
            "The stages are not equivalent across languages. Lean and Idris check and",
            "compile in one step. F\\* and ATS separate them, so those rows are reported",
            "separately. A single run per stage gives no estimate of variance.",
        ]
    by_lang: defaultdict[str, list[dict]] = defaultdict(list)
    for row in data["micro"]:
        by_lang[row["lang"]].append(row)
    lines += ["", "## Observations", ""]
    if ats := by_lang["ats"]:
        zero = ", ".join(r["op"] for r in ats if r["alloc_per_op"] == 0) or "none"
        lines.append(
            f"- ATS timed loops with zero allocator calls: {zero} (of {len(ats)}). "
            "`icarus_sim` makes the same check on every run and exits 4 if it fails."
        )
    if idris := by_lang["idris"]:
        lines.append(
            f"- Idris loops that allocate: {sum(r['alloc_per_op'] > 0 for r in idris)} of {len(idris)}. "
            "`Vect` is a linked structure, so every result is a fresh value. That comes "
            "from how the domain model is written and says nothing about the language in general."
        )
    return "\n".join(lines) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--no-rebuild", action="store_true")
    parser.add_argument("--repeats", type=int, default=5)
    args = parser.parse_args()
    if args.repeats < 1:
        parser.error("--repeats must be positive")

    data = {"machine": machine(), "repeats": args.repeats, "rebuild": [] if args.no_rebuild else rebuild()}
    data["micro"] = microbenchmarks(args.repeats)
    data["e2e"] = end_to_end(max(args.repeats, MIN_END_TO_END_RUNS))
    data["sizes"] = sizes()
    RESULTS.mkdir(parents=True, exist_ok=True)
    (RESULTS / "benchmark.json").write_text(json.dumps(data, indent=2))
    markdown = report(data)
    (RESULTS / "benchmark.md").write_text(markdown)
    print(markdown, end="")


if __name__ == "__main__":
    main()
