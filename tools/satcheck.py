#!/usr/bin/env python3
"""The verified F* saturating arithmetic against the Python fixed-point backend.

Both realise the same word (Q15.16 style, 2^16 raw units per 1.0, raw range
[-2^31, 2^31-1], round-half-up rescale). Vectors: every pairing of the boundary
values, plus pseudo-random pairs at several magnitudes from a fixed seed.
"""
import os, subprocess, sys, tempfile
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "reference"))
import icarus_ref as ref

EXE = os.path.join(ROOT, "fstar", "out", "icarus_sat")
LO, HI = ref.FixedArith.MIN_RAW, ref.FixedArith.MAX_RAW
EDGES = [LO, LO + 1, -65536 * 32768, -65537, -65536, -32769, -32768, -1, 0, 1, 32767, 32768,
         65535, 65536, 65537, 65536 * 32767, HI - 1, HI]

class Lcg:
    def __init__(self, s): self.s = s
    def next(self, lo, hi):
        self.s = (self.s * 6364136223846793005 + 1442695040888963407) & (2**64 - 1)
        return lo + (self.s >> 11) % (hi - lo + 1)

def vectors():
    v = [(op, a, b) for op in "asm" for a in EDGES for b in EDGES]
    g = Lcg(20261002)
    for width in (2**8, 2**16, 2**24, 2**31):
        for op in "asm":
            for _ in range(500):
                v.append((op, g.next(max(LO, -width), min(HI, width - 1)),
                              g.next(max(LO, -width), min(HI, width - 1))))
    return v

def python_result(op, a, b):
    f = ref.FixedArith()
    r = {"a": f.add, "s": f.sub, "m": f.mul}[op](a, b)
    return r, int(f.sat_events > 0)

def main():
    if not os.path.exists(EXE):
        print("satcheck: SKIP (build fstar first)"); return 0 if "--strict" not in sys.argv else 1
    vs = vectors()
    with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False) as t:
        t.write("".join(f"{op} {a} {b}\n" for op, a, b in vs)); path = t.name
    out = subprocess.run([EXE, path], capture_output=True, text=True, check=True).stdout.split("\n")[:-1]
    os.unlink(path)
    bad = [(v, o) for v, o in zip(vs, out) if tuple(map(int, o.split())) != python_result(*v)]
    sat = sum(int(o.split()[1]) for o in out)
    print(f"satcheck: {len(vs)} vectors ({sat} saturating), {len(bad)} disagreements")
    for v, o in bad[:5]: print("  ", v, "fstar:", o, "python:", python_result(*v))
    return 1 if bad or len(out) != len(vs) else 0

if __name__ == "__main__": sys.exit(main())
