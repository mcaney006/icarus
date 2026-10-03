#!/usr/bin/env python3
"""Benchmark: per-operation throughput, allocation, end-to-end runs, binary size,
compile time and proof/check time. Writes docs/results/benchmark.{md,json}.

Usage: tools/benchmark.py [--no-rebuild] [--repeats N]

The numbers describe these implementations on this machine. They are not a
ranking of languages: the executables do different amounts of work (the F* and
Lean executables run only the decision layer), use different data structures,
and the Idris and ATS loops are written to match each other, not to be fast.
"""
import json, os, platform, shutil, statistics, subprocess, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIXTURE = os.path.join(ROOT, "fixtures", "final_experiment.icf")
OUT = os.path.join(ROOT, "docs", "results")


def sh(cmd, cwd=ROOT, check=True):
    r = subprocess.run(cmd, cwd=cwd, shell=isinstance(cmd, str), capture_output=True, text=True)
    if check and r.returncode != 0:
        sys.exit(f"benchmark: command failed: {cmd}\n{r.stdout}\n{r.stderr}")
    return r


def tool(name):
    return sh(["bash", "tools/detect-toolchains.sh", "--path", name]).stdout.strip()


def timed(cmd, cwd=ROOT):
    t0 = time.perf_counter()
    sh(cmd, cwd)
    return time.perf_counter() - t0


def du(path):
    if os.path.isfile(path):
        return os.path.getsize(path)
    return sum(os.path.getsize(os.path.join(d, f)) for d, _, fs in os.walk(path) for f in fs)


def micro(repeats):
    """Median over `repeats` runs of each harness; rows keyed by (lang, op)."""
    harnesses = {
        "ats": [os.path.join(ROOT, "ats/build/icarus_bench"), FIXTURE, "20000"],
        "idris": [os.path.join(ROOT, "idris/build/exec/icarus"), "--bench", FIXTURE, "2000"],
    }
    rows = {}
    for lang, cmd in harnesses.items():
        if not os.path.exists(cmd[0]):
            print(f"[bench] SKIP {lang} microbenchmarks (not built)")
            continue
        for _ in range(repeats):
            for line in sh(cmd).stdout.splitlines():
                f = line.split(",")
                if f[0] == lang:
                    rows.setdefault((lang, f[1]), []).append((int(f[2]), int(f[3]), int(f[4])))
    out = []
    for (lang, op), runs in rows.items():
        iters = runs[0][0]
        ns = statistics.median(r[1] for r in runs)
        alloc = statistics.median(r[2] for r in runs)
        out.append({"lang": lang, "op": op, "iterations": iters, "runs": len(runs),
                    "ns_per_op": ns / iters, "ops_per_sec": iters / (ns / 1e9),
                    "ns_min": min(r[1] for r in runs) / iters, "ns_max": max(r[1] for r in runs) / iters,
                    "alloc_per_op": alloc / iters,
                    "alloc_unit": "allocator calls" if lang == "ats" else "bytes (Chez sstats)"})
    return out


def end_to_end(repeats):
    py = sys.executable
    runs = [
        ("reference", "full simulation (Python oracle)", [py, "reference/icarus_ref.py", "--canonical", "--fixture", "fixtures/final_experiment.json"]),
        ("ats", "full simulation", ["ats/build/icarus_sim", FIXTURE]),
        ("idris", "full simulation", ["idris/build/exec/icarus", FIXTURE]),
        ("fstar", "decision layer only", ["fstar/out/icarus_decide", FIXTURE]),
        ("lean", "decision layer only", ["lean/.lake/build/bin/icarus", FIXTURE]),
    ]
    out = []
    for name, scope, cmd in runs:
        if not os.path.exists(os.path.join(ROOT, cmd[0]) if not os.path.isabs(cmd[0]) else cmd[0]):
            print(f"[bench] SKIP {name} end-to-end (not built)")
            continue
        ts = [timed(cmd) for _ in range(repeats)]
        out.append({"impl": name, "scope": scope, "runs": repeats, "median_ms": statistics.median(ts) * 1e3,
                    "min_ms": min(ts) * 1e3, "max_ms": max(ts) * 1e3})
    return out


def sizes():
    items = [
        ("ats", "ats/build/icarus_sim"),
        ("idris", "idris/build/exec/icarus_app"),
        ("fstar", "fstar/out/icarus_decide"),
        ("lean", "lean/.lake/build/bin/icarus"),
    ]
    return [{"impl": n, "path": p, "bytes": du(os.path.join(ROOT, p))}
            for n, p in items if os.path.exists(os.path.join(ROOT, p))]


def rebuild():
    """Clean build per language. 'check' is proof or type checking; 'build' is the
    rest (code generation, C/OCaml/Scheme compilation, linking)."""
    out = []
    lake, idris2, fstar = tool("lake"), tool("idris2"), tool("fstar")
    if lake:
        shutil.rmtree(os.path.join(ROOT, "lean/.lake/build"), ignore_errors=True)
        out.append({"lang": "lean", "stage": "check+build (lake build: elaboration and kernel checking of every proof, plus the executable)",
                    "seconds": timed([lake, "build"], cwd=os.path.join(ROOT, "lean"))})
    if idris2:
        shutil.rmtree(os.path.join(ROOT, "idris/build"), ignore_errors=True)
        out.append({"lang": "idris", "stage": "check+build (type checking and Chez Scheme code generation)",
                    "seconds": timed([idris2, "--build", "icarus.ipkg"], cwd=os.path.join(ROOT, "idris"))})
    if fstar:
        shutil.rmtree(os.path.join(ROOT, "fstar/out"), ignore_errors=True)
        out.append({"lang": "fstar", "stage": "check (verify all modules with Z3)",
                    "seconds": timed(["make", "-C", "fstar", "verify", f"FSTAR={fstar}"])})
        out.append({"lang": "fstar", "stage": "build (OCaml extraction, compilation and linking)",
                    "seconds": timed(["make", "-C", "fstar", "build", f"FSTAR={fstar}"])})
    patscc = tool("patscc")
    if patscc:
        srcs = sorted(f for f in os.listdir(os.path.join(ROOT, "ats/src")) if f.endswith(".dats"))
        t0 = time.perf_counter()
        for f in srcs:
            sh([patscc, "-tcats", f], cwd=os.path.join(ROOT, "ats/src"))
        out.append({"lang": "ats", "stage": "check (patscc -tcats on every .dats: linear and dependent type checking)",
                    "seconds": time.perf_counter() - t0})
        shutil.rmtree(os.path.join(ROOT, "ats/build"), ignore_errors=True)
        out.append({"lang": "ats", "stage": "check+build (patsopt to C, clang -O2, link; three executables)",
                    "seconds": timed(["make", "-C", "ats", f"PATSCC={patscc}"])})
    return out


def machine():
    cpu = sh(["sysctl", "-n", "machdep.cpu.brand_string"], check=False).stdout.strip() or platform.processor()
    return {"os": f"{platform.system()} {platform.release()}", "machine": platform.machine(), "cpu": cpu,
            "python": platform.python_version()}


def report(data):
    m = data["machine"]
    L = ["# Benchmark", "",
         "Generated by `make benchmark` (`tools/benchmark.py`). Machine: "
         f"{m['cpu']}, {m['os']} ({m['machine']}).", "",
         "These numbers describe these programs on this machine. They do not rank the",
         "languages. The loops are written to match one another, not to be fast. The",
         "F\\* and Lean executables run only the decision layer. Allocation is counted",
         "in different units (ATS: calls into the counting allocator; Idris: bytes",
         "reported by the Chez Scheme collector). Wall-clock times include process",
         "start-up and fixture parsing.", "",
         "## Per-operation throughput", "",
         f"Median of {data['repeats']} runs of each harness (`ats/src/bench.dats`, `idris/src/Main.idr --bench`).",
         "All vectors and matrices are 4 and 4×4. `frame` is one full Acquire to Record cycle",
         "of the simulator on `final_experiment`.", "",
         "| Lang | Operation | ns/op (median) | ns/op range | ops/s | alloc/op | alloc unit |",
         "|---|---|---:|---:|---:|---:|---|"]
    for r in data["micro"]:
        L.append(f"| {r['lang']} | {r['op']} | {r['ns_per_op']:.1f} | {r['ns_min']:.1f}–{r['ns_max']:.1f} | "
                 f"{r['ops_per_sec']:.3g} | {r['alloc_per_op']:.3g} | {r['alloc_unit']} |")
    L += ["", "## End-to-end process runs on `final_experiment.icf` (48 frames)", "",
          "| Impl | Scope | median ms | min–max ms |", "|---|---|---:|---:|"]
    for r in data["e2e"]:
        L.append(f"| {r['impl']} | {r['scope']} | {r['median_ms']:.1f} | {r['min_ms']:.1f}–{r['max_ms']:.1f} |")
    L += ["", "## Binary size", "", "| Impl | Artifact | bytes |", "|---|---|---:|"]
    for r in data["sizes"]:
        L.append(f"| {r['impl']} | `{r['path']}` | {r['bytes']} |")
    L += ["", "The Idris figure is the compiled Scheme program only. It needs a Chez Scheme",
          "installation at run time, and that is not counted. The other three artifacts are",
          "native executables with their runtimes linked in."]
    if data["rebuild"]:
        L += ["", "## Clean build and check times (one run each)", "",
              "| Lang | Stage | seconds |", "|---|---|---:|"]
        for r in data["rebuild"]:
            L.append(f"| {r['lang']} | {r['stage']} | {r['seconds']:.1f} |")
        L += ["", "The stages are not equivalent across languages. Lean and Idris check and",
              "compile in one step. F\\* and ATS separate them, so those rows are reported",
              "separately. A single run per stage gives no estimate of variance."]
    ats = [r for r in data["micro"] if r["lang"] == "ats"]
    idr = [r for r in data["micro"] if r["lang"] == "idris"]
    L += ["", "## Observations", ""]
    if ats:
        zero = [r["op"] for r in ats if r["alloc_per_op"] == 0]
        L.append(f"- ATS timed loops with zero allocator calls: {', '.join(zero) or 'none'} "
                 f"(of {len(ats)}). `icarus_sim` makes the same check on every run and exits 4 if it fails.")
    if idr:
        L.append(f"- Idris loops that allocate: {sum(r['alloc_per_op'] > 0 for r in idr)} of {len(idr)}. "
                 "`Vect` is a linked structure, so every result is a fresh value. That comes "
                 "from how the domain model is written and says nothing about the language in general.")
    return "\n".join(L) + "\n"


def main():
    rebuild_on = "--no-rebuild" not in sys.argv
    repeats = int(sys.argv[sys.argv.index("--repeats") + 1]) if "--repeats" in sys.argv else 5
    data = {"machine": machine(), "repeats": repeats, "rebuild": rebuild() if rebuild_on else []}
    data["micro"] = micro(repeats)
    data["e2e"] = end_to_end(max(repeats, 10))
    data["sizes"] = sizes()
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, "benchmark.json"), "w") as f:
        json.dump(data, f, indent=2)
    md = report(data)
    with open(os.path.join(OUT, "benchmark.md"), "w") as f:
        f.write(md)
    print(md)


if __name__ == "__main__":
    main()
