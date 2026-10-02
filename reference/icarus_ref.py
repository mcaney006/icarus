#!/usr/bin/env python3
"""Executable oracle for the icarus abstract control system.

This module is the authoritative behavioural specification. The Lean/Idris/F*/ATS
implementations are checked for *observable* agreement with the trace this module
produces on a shared fixture. It deliberately uses plain Python lists and explicit
index-ordered arithmetic (no numpy, no FMA) so the four typed languages can mirror
its operation order exactly; cross-language agreement is then defined up to the
fixture tolerance rather than bit-identity.

Nothing here is physical. State components are dimensionless; the matrices are
synthetic constants from tools/gen_fixtures.py.
"""
from __future__ import annotations
import argparse, json, math, sys
from dataclasses import dataclass, field
from enum import Enum

# ----- discrete mode machine (mirrored in every implementation) ----------------
class Mode(str, Enum):
    Boot="Boot"; SelfTest="SelfTest"; Calibrating="Calibrating"; Ready="Ready"
    Running="Running"; Degraded="Degraded"; Safe="Safe"; Fault="Fault"

# Legal transitions. The reference never performs a transition outside this set;
# tools/crosscheck and the self-check assert that the emitted sequence respects it.
LEGAL = {
    Mode.Boot:       {Mode.SelfTest, Mode.Fault, Mode.Boot},
    Mode.SelfTest:   {Mode.Calibrating, Mode.Fault, Mode.SelfTest},
    Mode.Calibrating:{Mode.Ready, Mode.Fault, Mode.Calibrating},
    Mode.Ready:      {Mode.Running, Mode.Safe, Mode.Ready},
    Mode.Running:    {Mode.Running, Mode.Degraded, Mode.Safe},
    Mode.Degraded:   {Mode.Degraded, Mode.Running, Mode.Safe},
    Mode.Safe:       {Mode.Safe},
    Mode.Fault:      {Mode.Fault},
}

class Health(str, Enum):
    Healthy="Healthy"; Suspect="Suspect"; Degraded="Degraded"; Unsafe="Unsafe"

class Fault(str, Enum):
    MeasurementDropout="MeasurementDropout"
    StaleMeasurement="StaleMeasurement"
    BiasedMeasurement="BiasedMeasurement"
    StuckChannel="StuckChannel"
    OutOfRange="OutOfRange"
    TimingOverrun="TimingOverrun"
    NumericSaturation="NumericSaturation"
    CorruptFixture="CorruptFixture"
    EstimatorDisagreement="EstimatorDisagreement"
    ControlSaturation="ControlSaturation"

# ----- artificial constants (documented in ASSUMPTIONS.md) ----------------------
MEAS_LIMIT   = 50.0    # normalization clamp on each measurement component
INNOV_THRESH = 10.0    # ||y - C xhat|| above this flags estimator disagreement
STATE_BOUND  = 1.0e3   # |state component| above this (or non-finite) is Unsafe
CTRL_LIMIT   = 1.0     # abstract actuator interval is [-CTRL_LIMIT, CTRL_LIMIT]
DEGRADED_CTRL= 0.5     # reduced authority while Degraded
RECOVERY_FRAMES = 3    # consecutive Healthy frames needed Degraded -> Running
DEGRADED_LIMIT  = 3    # consecutive Degraded frames forcing Degraded -> Safe
STUCK_VALUE  = 7.0     # value a stuck synthetic channel reports

FRAME_BUDGET = 1000
STAGE_BUDGET = {"Acquire":120,"Normalize":80,"Estimate":220,"Decide":180,
                "Control":160,"Validate":90,"Record":50}

# ----- small fixed-dimension linear algebra (index-ordered) ---------------------
def matvec(M, v):
    return [sum(M[i][j]*v[j] for j in range(len(v))) for i in range(len(M))]
def vadd(a,b): return [a[i]+b[i] for i in range(len(a))]
def vsub(a,b): return [a[i]-b[i] for i in range(len(a))]
def vneg(a):   return [-x for x in a]
def vnorm2(a): return math.sqrt(sum(x*x for x in a))
def sat(v, lim): return [max(-lim, min(lim, x)) for x in v]
def median3(a,b,c):
    return a+b+c - max(a,b,c) - min(a,b,c)

# ----- plant + fixture ----------------------------------------------------------
@dataclass
class Plant:
    n:int; m:int; p:int
    A:list; B:list; C:list; K:list; L:list
    ctrl_limit:float = CTRL_LIMIT

def load_plant(path)->Plant:
    d=json.load(open(path))
    dm=d["dims"]
    return Plant(dm["n"],dm["m"],dm["p"],d["A"],d["B"],d["C"],d["K"],d["L"],
                 d.get("control_limit",CTRL_LIMIT))

@dataclass
class FrameRecord:
    k:int; mode:str; health:str; u:list; y:list; xhat:list; x:list
    flags:list; frame_cost:int; deadline_miss:bool

def _active(faults, k):
    return [f for f in faults if f.get("step")==k]

def saturated(raw, lim):
    return any(abs(x)>lim+1e-12 for x in raw)

def run(plant:Plant, fixture:dict, fixed_point:bool=False):
    """Run the deterministic frame loop. Returns (trace, summary)."""
    arith = FixedPoint(fixture.get("fixed_scale",65536)) if fixed_point else Float()
    n,m,p = plant.n, plant.m, plant.p
    steps = fixture["steps"]
    x    = list(fixture["initial_state"])          # hidden true state
    xhat = [0.0]*n                                  # estimator starts at origin
    u_prev=[0.0]*m
    last_meas=[0.0]*p
    mode=Mode.Ready
    healthy_streak=0; degraded_bad=0
    trace=[]; mode_seq=[mode.value]

    faults = fixture.get("faults",[])
    for k in range(steps):
        act=_active(faults,k)
        kinds={f["kind"] for f in act}
        flags=set()

        # --- Acquire: three redundant channels, per-component median vote -------
        v = fixture["noise"][k]
        true_meas = matvec(plant.C, x)
        base = vadd(true_meas, v)
        ch = [list(base), list(base), list(base)]     # 3 identical healthy channels
        for f in act:
            c=f.get("channel",0)
            if f["kind"]==Fault.BiasedMeasurement:   ch[0][c]+=f.get("amount",20.0); flags.add("meas")
            elif f["kind"]==Fault.StuckChannel:      ch[0][c]=STUCK_VALUE; flags.add("meas")
            elif f["kind"]==Fault.OutOfRange:        ch[0][c]=f.get("value",1.0e6); flags.add("meas")
            elif f["kind"]==Fault.MeasurementDropout:
                for t in range(3): ch[t][c]=last_meas[c]
                flags.add("meas")
        y=[median3(ch[0][i],ch[1][i],ch[2][i]) for i in range(p)]
        if Fault.StaleMeasurement in kinds:
            y=list(last_meas); flags.add("meas")

        # --- Normalize: clamp to sensor range ----------------------------------
        y_pre=list(y)
        y=sat(y, MEAS_LIMIT)
        if any(abs(a) > MEAS_LIMIT+1e-12 for a in y_pre): flags.add("meas")
        last_meas=list(y)

        # --- Estimate: Luenberger observer; large innovation flags disagreement -
        innov = vsub(y, matvec(plant.C, xhat))
        if vnorm2(innov) > INNOV_THRESH or Fault.EstimatorDisagreement in kinds:
            flags.add("estimator")
        xhat = vadd(vadd(matvec(plant.A,xhat), matvec(plant.B,u_prev)),
                    matvec(plant.L, innov))

        # --- timing / deadline --------------------------------------------------
        frame_cost=sum(STAGE_BUDGET.values())
        deadline_miss=False
        if Fault.TimingOverrun in kinds:
            frame_cost += next((f.get("overrun",250) for f in act
                                if f["kind"]==Fault.TimingOverrun),250)
            if frame_cost>FRAME_BUDGET: deadline_miss=True; flags.add("timing")

        # --- Control (depends on mode) -----------------------------------------
        if mode in (Mode.Running, Mode.Degraded):
            raw=vneg(matvec(plant.K, xhat))
            lim = plant.ctrl_limit if mode==Mode.Running else DEGRADED_CTRL
            if saturated(raw, lim) or Fault.ControlSaturation in kinds: flags.add("ctrl_sat")
            u=sat(raw, lim)
        else:
            u=[0.0]*m

        # --- Validate: numeric range -------------------------------------------
        if any((not math.isfinite(a)) or abs(a)>STATE_BOUND for a in xhat) \
           or Fault.NumericSaturation in kinds:
            flags.add("numeric")

        # --- Health monitor (deterministic) ------------------------------------
        if "numeric" in flags:      health=Health.Unsafe
        elif len(flags)>=2:         health=Health.Degraded
        elif len(flags)==1:         health=Health.Suspect
        else:                       health=Health.Healthy

        # --- Decide: next mode --------------------------------------------------
        # Recovery (consecutive Healthy frames) wins over the Safe fallback, which
        # fires only on repeated *bad* frames inside one Degraded episode.
        nxt=mode
        if mode==Mode.Ready:
            nxt=Mode.Running
        elif mode==Mode.Running:
            if health==Health.Unsafe: nxt=Mode.Safe
            elif health==Health.Degraded or deadline_miss:
                nxt=Mode.Degraded; degraded_bad=0
        elif mode==Mode.Degraded:
            if health==Health.Unsafe:
                nxt=Mode.Safe
            elif health==Health.Healthy:
                nxt=Mode.Running if healthy_streak+1>=RECOVERY_FRAMES else Mode.Degraded
            else:
                degraded_bad+=1
                nxt=Mode.Safe if degraded_bad>=DEGRADED_LIMIT else Mode.Degraded
        assert nxt in LEGAL[mode], f"illegal transition {mode}->{nxt}"

        healthy_streak = healthy_streak+1 if health==Health.Healthy else 0

        trace.append(FrameRecord(k,mode.value,health.value,list(u),list(y),
                     list(xhat),list(x),sorted(flags),frame_cost,deadline_miss))
        mode=nxt; mode_seq.append(mode.value)

        # --- plant update (hidden world) ---------------------------------------
        w=fixture["disturbance"][k]
        x=vadd(vadd(matvec(plant.A,x), matvec(plant.B,u)), w)
        u_prev=list(u)

    summary={"mode_sequence":mode_seq,
             "final_state":x,"final_estimate":xhat,"final_mode":mode.value}
    return trace, summary

# ----- arithmetic back-ends (float reference vs fixed-point experiment) ---------
class Float:  pass
class FixedPoint:
    def __init__(self, scale): self.scale=scale

# ----- self-check (runs with: python3 reference/icarus_ref.py --selfcheck) ------
def _selfcheck():
    # minimal 2-state plant, hand-stable closed loop, no faults
    # closed-loop poles {0.8,0.7}, observer poles {0.5,0.4}, verified by hand
    plant=Plant(2,1,1,
        A=[[1.1,0.1],[0.0,1.05]], B=[[0.0],[0.5]], C=[[1.0,0.0]],
        K=[[2.4,1.3]], L=[[1.25],[3.575]])
    fx={"steps":20,"initial_state":[0.3,-0.2],
        "disturbance":[[0.0,0.0]]*20,"noise":[[0.0]]*20,"faults":[]}
    trace,summ=run(plant,fx)
    # invariants
    for r in trace:
        for uc in r.u: assert -CTRL_LIMIT-1e-9<=uc<=CTRL_LIMIT+1e-9, "control out of interval"
    for a,b in zip(summ["mode_sequence"], summ["mode_sequence"][1:]):
        assert Mode(b) in LEGAL[Mode(a)], f"illegal {a}->{b}"
    assert sum(STAGE_BUDGET.values())<=FRAME_BUDGET, "budget overflow"
    assert median3(100.0,1.0,1.0)==1.0, "single divergent channel dominated median"
    assert median3(1.0,2.0,3.0)==2.0
    assert summ["mode_sequence"][0]=="Ready" and summ["mode_sequence"][1]=="Running"
    # closed loop with stable gains must shrink the state
    assert vnorm2(summ["final_state"])<vnorm2(fx["initial_state"]), "did not converge"
    print("selfcheck OK:",
          f"final_state={[round(z,4) for z in summ['final_state']]}",
          f"modes={summ['mode_sequence'][0]}..{summ['mode_sequence'][-1]}")

def main(argv=None):
    ap=argparse.ArgumentParser()
    ap.add_argument("--plant",default="fixtures/plant.json")
    ap.add_argument("--fixture")
    ap.add_argument("--trace",action="store_true")
    ap.add_argument("--fixed-point",action="store_true")
    ap.add_argument("--selfcheck",action="store_true")
    ap.add_argument("--canonical",action="store_true",help="print ICF canonical output lines")
    a=ap.parse_args(argv)
    if a.selfcheck: _selfcheck(); return 0
    plant=load_plant(a.plant); fx=json.load(open(a.fixture))
    trace,summ=run(plant,fx,fixed_point=a.fixed_point)
    if a.canonical:
        MC={m:i for i,m in enumerate(["Boot","SelfTest","Calibrating","Ready","Running","Degraded","Safe","Fault"])}
        HC={h:i for i,h in enumerate(["Healthy","Suspect","Degraded","Unsafe"])}
        FB={"meas":1,"estimator":2,"timing":4,"ctrl_sat":8,"numeric":16}
        print("M "+" ".join(str(MC[x]) for x in summ["mode_sequence"]))
        print("H "+" ".join(str(HC[r.health]) for r in trace))
        print("G "+" ".join(str(sum(FB[f] for f in r.flags)) for r in trace))
        print("X "+" ".join(str(int(round(z*1e9))) for z in summ["final_state"]))
        return 0
    if a.trace:
        for r in trace:
            print(f"k={r.k:02d} {r.mode:9s} {r.health:8s} "
                  f"u={[round(z,4) for z in r.u]} flags={r.flags} "
                  f"miss={int(r.deadline_miss)}")
    print(json.dumps({"final_mode":summ["final_mode"],
                      "final_state":[round(z,6) for z in summ["final_state"]],
                      "modes":summ["mode_sequence"]}, indent=2))
    return 0

if __name__=="__main__":
    sys.exit(main())
