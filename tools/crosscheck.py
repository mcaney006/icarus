#!/usr/bin/env python3
"""Cross-language observable-behaviour check.

For every fixture, the Python reference's canonical output is the oracle. Each
implementation that has been built is run on the same fixture and must agree on
the lines it declares it emits: M, H, G exactly, X within the fixture tolerance
T. Implementations that own only the discrete decision layer (Lean, F*) emit M
and H; the full-numerics simulators (Idris, ATS) emit all four.

Also applies two corruption mutations to a fixture and requires every
implementation to reject each (exit code 3 and a REJECT line).
"""
import glob, os, subprocess, sys, shutil, tempfile

ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT,"reference"))
STRICT = "--strict" in sys.argv

IMPLS = {
  "ats":   dict(cmd=[f"{ROOT}/ats/build/icarus_sim"],               emits="MHGX"),
  "idris": dict(cmd=[f"{ROOT}/idris/build/exec/icarus"],            emits="MHGX"),
  "fstar": dict(cmd=[f"{ROOT}/fstar/out/icarus_decide"],            emits="MH"),
  "lean":  dict(cmd=[f"{ROOT}/lean/.lake/build/bin/icarus"],        emits="MH"),
}

def run(cmd, path):
    r=subprocess.run(cmd+[path],capture_output=True,text=True,timeout=120)
    return r.returncode, r.stdout, r.stderr

def parse(out):
    d={}
    for line in out.splitlines():
        if line[:1] in "MHGX" and line[1:2]==" ":
            d[line[0]]=[int(t) for t in line[2:].split()]
    return d

def reference(path):
    js=path.replace(".icf",".json")
    rc,out,err=run([sys.executable,f"{ROOT}/reference/icarus_ref.py","--canonical","--fixture"],js)
    assert rc==0, err
    return parse(out)

def tolerance(path):
    for line in open(path):
        if line.startswith("T "): return int(line.split()[1])
    raise SystemExit("fixture has no T line")

def compare(name, got, ref, emits, tol, tag):
    errs=[]
    for k in emits:
        if k not in got: errs.append(f"missing {k} line"); continue
        if k=="X":
            if len(got[k])!=len(ref[k]) or any(abs(a-b)>tol for a,b in zip(got[k],ref[k])):
                errs.append(f"X mismatch got={got[k]} ref={ref[k]} tol={tol}")
        elif got[k]!=ref[k]:
            i=next((j for j,(a,b) in enumerate(zip(got[k],ref[k])) if a!=b), min(len(got[k]),len(ref[k])))
            errs.append(f"{k} differs first at index {i}")
    return errs

def corrupt_variants(path, tmp):
    text=open(path).read()
    flip=text.replace("\nW 3 ","\nW 3 9",1)               # alter a payload, keep Z stale
    nochk="\n".join(l for l in text.splitlines() if not l.startswith("Z "))+"\n"
    out=[]
    for tag,body in (("payload-flip",flip),("missing-checksum",nochk)):
        p=os.path.join(tmp,f"{tag}.icf"); open(p,"w").write(body); out.append((tag,p))
    return out

def main():
    fixtures=sorted(glob.glob(f"{ROOT}/fixtures/*.icf"))
    assert fixtures, "no fixtures; run make bootstrap"
    bad=0; ran=0; skipped=[]
    # 1. fixture self-consistency: reference reproduces the baked expectations
    for f in fixtures:
        ref=reference(f); exp={}
        for line in open(f):
            if line[:2] in ("M ","H ","G ","E "):
                exp["X" if line[0]=="E" else line[0]]=[int(t) for t in line[2:].split()]
        errs=compare("reference",ref,exp,"MHGX",tolerance(f),"self")
        print(f"[ref ] {os.path.basename(f):28s} {'OK' if not errs else 'FAIL '+str(errs)}")
        bad+=bool(errs)
    # 2. each built implementation against the reference
    for name,impl in IMPLS.items():
        exe=impl["cmd"][0]
        if not os.path.exists(exe):
            skipped.append(name); print(f"[{name:5s}] SKIP (not built: {os.path.relpath(exe,ROOT)})"); continue
        for f in fixtures:
            rc,out,err=run(impl["cmd"],f); ref=reference(f)
            errs=[f"exit {rc}: {err.strip()[:80]}"] if rc!=0 else compare(name,parse(out),ref,impl["emits"],tolerance(f),"impl")
            print(f"[{name:5s}] {os.path.basename(f):28s} {'OK' if not errs else 'FAIL '+'; '.join(errs)}")
            bad+=bool(errs); ran+=1
        with tempfile.TemporaryDirectory() as tmp:
            for tag,p in corrupt_variants(fixtures[0],tmp):
                rc,out,err=run(impl["cmd"],p)
                ok = rc==3 and out.lstrip().startswith("REJECT")
                print(f"[{name:5s}] corrupt:{tag:18s} {'REJECTED ok' if ok else f'FAIL exit={rc} out={out[:40]!r}'}")
                bad+=(not ok); ran+=1
    print(f"crosscheck: {ran} implementation runs, {bad} failures, skipped={skipped or 'none'}")
    if bad or (STRICT and skipped): sys.exit(1)

if __name__=="__main__": main()
