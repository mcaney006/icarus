#!/usr/bin/env python3
"""Deterministic generator for the shared interchange files.

Produces fixtures/plant.json (synthetic matrices + gains designed here, once) and
the scenario fixtures. Gains come from a discrete-time LQR solved by Riccati
iteration (numpy, fixed Q/R) so the constants are reproducible and clearly
artificial. Disturbance/noise are drawn from a fixed-seed LCG and baked into the
fixtures as explicit arrays, so the four typed languages read identical inputs
without re-implementing any PRNG. The reference oracle then fills each fixture's
expected mode sequence and final state.
"""
import json, os, sys
import numpy as np

HERE=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(HERE,"reference"))
import icarus_ref as ref

np.set_printoptions(suppress=True)

# ----- synthetic plant (no physical meaning; chosen for mathematical testing) ---
A=np.array([[1.00,0.20,0.00,0.00],
            [0.00,1.05,0.10,0.00],
            [0.00,0.00,1.00,0.20],
            [0.05,0.00,0.00,1.08]])
B=np.array([[0.0,0.0],[0.5,0.0],[0.0,0.0],[0.0,0.5]])
C=np.array([[1.0,0.0,0.0,0.0],[0.0,0.0,1.0,0.0]])

def dlqr(A,B,Q,R,iters=4000,tol=1e-12):
    P=Q.copy()
    for _ in range(iters):
        K=np.linalg.solve(R+B.T@P@B, B.T@P@A)
        Pn=Q+A.T@P@A - A.T@P@B@K
        if np.max(np.abs(Pn-P))<tol: P=Pn; break
        P=Pn
    K=np.linalg.solve(R+B.T@P@B, B.T@P@A)
    return K

def spectral_radius(M): return float(np.max(np.abs(np.linalg.eigvals(M))))

def design():
    n=A.shape[0]; m=B.shape[1]; p=C.shape[0]
    K=dlqr(A,B,np.eye(n),np.eye(m))
    # observer gain via LQR on the dual system (A^T, C^T)
    Ko=dlqr(A.T,C.T,np.eye(n),np.eye(p))
    L=Ko.T
    rho_ol=spectral_radius(A)
    rho_cl=spectral_radius(A-B@K)
    rho_ob=spectral_radius(A-L@C)
    assert rho_ol>1.0,   f"plant must be open-loop unstable, got rho={rho_ol}"
    assert rho_cl<1.0,   f"closed loop must be stable, got rho={rho_cl}"
    assert rho_ob<1.0,   f"observer must be stable, got rho={rho_ob}"
    return K,L,dict(open_loop_rho=rho_ol,closed_loop_rho=rho_cl,observer_rho=rho_ob)

def write_plant(K,L,eig):
    plant=dict(
        dims=dict(n=4,m=2,p=2),
        A=A.tolist(), B=B.tolist(), C=C.tolist(),
        K=K.tolist(), L=L.tolist(),
        control_limit=ref.CTRL_LIMIT,
        fixed_point=dict(frac_bits=16,int_bits=15,scale=65536,
                         min=-32768.0, max=32767.0+65535/65536.0,
                         note="artificial Q15.16; not a hardware word size"),
        budget=dict(frame=ref.FRAME_BUDGET, stages=ref.STAGE_BUDGET,
                    margin=ref.FRAME_BUDGET-sum(ref.STAGE_BUDGET.values())),
        eigen={k:round(v,6) for k,v in eig.items()},
        note="Dimensionless synthetic plant. Not derived from any real vehicle.")
    json.dump(plant, open(f"{HERE}/fixtures/plant.json","w"), indent=2)
    return plant

class LCG:
    def __init__(self,seed): self.s=seed & ((1<<64)-1)
    def nxt(self):
        self.s=(self.s*6364136223846793005+1442695040888963407)&((1<<64)-1)
        return (self.s>>11)/float(1<<53)
    def centered(self,amp):  # value in [-amp, amp]
        return round((self.nxt()*2.0-1.0)*amp, 9)

def seq(rng,count,dim,amp):
    return [[rng.centered(amp) for _ in range(dim)] for _ in range(count)]

def build(name,seed,steps,x0,amp_w,amp_v,faults):
    rng=LCG(seed)
    return dict(name=name, dims=dict(n=4,m=2,p=2), steps=steps, seed=seed,
                initial_state=x0,
                disturbance=seq(rng,steps,4,amp_w),
                noise=seq(rng,steps,2,amp_v),
                faults=faults, tolerance=1e-6, fixed_scale=65536)


FLAGBIT={"meas":1,"estimator":2,"timing":4,"ctrl_sat":8,"numeric":16}
MODE_CODE={m:i for i,m in enumerate(["Boot","SelfTest","Calibrating","Ready","Running","Degraded","Safe","Fault"])}
HEALTH_CODE={h:i for i,h in enumerate(["Healthy","Suspect","Degraded","Unsafe"])}
FAULT_CODE={k:i for i,k in enumerate(["MeasurementDropout","StaleMeasurement","BiasedMeasurement",
  "StuckChannel","OutOfRange","TimingOverrun","NumericSaturation","CorruptFixture",
  "EstimatorDisagreement","ControlSaturation"])}
SC=10**9
def q(v): return int(round(v*SC))

def fnv1a(data:bytes)->int:
    h=0x811C9DC5
    for b in data:
        h=((h^b)*0x01000193)&0xFFFFFFFF
    return h

def write_icf(path, plant, fx, trace, summ):
    L=[f"# icarus fixture {fx['name']}"]
    n,m,p=plant["dims"]["n"],plant["dims"]["m"],plant["dims"]["p"]
    L.append(f"D {n} {m} {p} {fx['steps']}")
    flat=lambda M:" ".join(str(q(v)) for row in M for v in row)
    for tag in "ABCKL": L.append(f"{tag} "+flat(plant[tag]))
    L.append("X "+" ".join(str(q(v)) for v in fx["initial_state"]))
    L.append(f"T {q(fx['tolerance'])}")
    for k,w in enumerate(fx["disturbance"]): L.append(f"W {k} "+" ".join(str(q(v)) for v in w))
    for k,v in enumerate(fx["noise"]):       L.append(f"V {k} "+" ".join(str(q(z)) for z in v))
    for f in fx["faults"]:
        kind=f["kind"]; ch=f.get("channel",0)
        param={"BiasedMeasurement":f.get("amount",20.0),"OutOfRange":f.get("value",1.0e6),
               "TimingOverrun":float(f.get("overrun",250))}.get(kind,0.0)
        L.append(f"F {f['step']} {FAULT_CODE[kind]} {ch} {q(param)}")
    L.append("M "+" ".join(str(MODE_CODE[x]) for x in summ["mode_sequence"]))
    L.append("H "+" ".join(str(HEALTH_CODE[r.health]) for r in trace))
    L.append("G "+" ".join(str(sum(FLAGBIT[x] for x in r.flags)) for r in trace))
    L.append("E "+" ".join(str(q(v)) for v in summ["final_state"]))
    body="\n".join(L)+"\n"
    open(path,"w").write(body+f"Z {fnv1a(body.encode())}\n")

def finalize(plant_path, fx):
    plant=ref.load_plant(plant_path)
    _,summ=ref.run(plant, fx)
    fx["expected"]=dict(mode_sequence=summ["mode_sequence"],
                        final_state=[round(z,9) for z in summ["final_state"]],
                        final_estimate=[round(z,9) for z in summ["final_estimate"]],
                        final_mode=summ["final_mode"])
    return fx

def main():
    K,L,eig=design()
    K=np.round(K,9); L=np.round(L,9)
    write_plant(K,L,eig)
    pp=f"{HERE}/fixtures/plant.json"
    x0=[0.5,-0.3,0.4,-0.2]
    scenarios=[
        build("nominal", 20261002, 40, x0, 0.01, 0.01, []),
        build("faults",  20261003, 40, x0, 0.01, 0.01, [
            {"step":10,"kind":"BiasedMeasurement","channel":0,"amount":25.0},
            {"step":15,"kind":"MeasurementDropout","channel":1},
            {"step":20,"kind":"TimingOverrun","overrun":300},
        ]),
        build("final_experiment", 20261004, 48, x0, 0.015, 0.02, [
            {"step":8, "kind":"BiasedMeasurement","channel":0,"amount":18.0},
            {"step":12,"kind":"MeasurementDropout","channel":1},
            {"step":13,"kind":"MeasurementDropout","channel":1},
            {"step":20,"kind":"TimingOverrun","overrun":260},
            {"step":28,"kind":"NumericSaturation"},
        ]),
    ]
    def one(name, seed, faults, steps=30):
        return build(name, seed, steps, x0, 0.01, 0.01, faults)
    suite=[
      one("fault_dropout",    20261101, [{"step":10,"kind":"MeasurementDropout","channel":0},
                                         {"step":11,"kind":"MeasurementDropout","channel":0}]),
      one("fault_stale",      20261102, [{"step":10,"kind":"StaleMeasurement"},
                                         {"step":11,"kind":"StaleMeasurement"}]),
      one("fault_bias",       20261103, [{"step":10,"kind":"BiasedMeasurement","channel":0,"amount":25.0}]),
      one("fault_stuck",      20261104, [{"step":10,"kind":"StuckChannel","channel":1}]),
      one("fault_range",      20261105, [{"step":10,"kind":"OutOfRange","channel":0,"value":1.0e6}]),
      one("fault_overrun",    20261106, [{"step":10,"kind":"TimingOverrun","overrun":300}]),
      one("fault_numeric",    20261107, [{"step":10,"kind":"NumericSaturation"}]),
      one("fault_estimator",  20261108, [{"step":10,"kind":"EstimatorDisagreement"}]),
      one("fault_ctrlsat",    20261109, [{"step":10,"kind":"ControlSaturation"}]),
      # overrun degrades; two flags per frame keeps it Degraded and bad frames accumulate to Safe
      one("fault_cascade",    20261110, [{"step":10,"kind":"TimingOverrun","overrun":300},
                                         {"step":11,"kind":"EstimatorDisagreement"},{"step":11,"kind":"ControlSaturation"},
                                         {"step":12,"kind":"EstimatorDisagreement"},{"step":12,"kind":"ControlSaturation"},
                                         {"step":13,"kind":"EstimatorDisagreement"},{"step":13,"kind":"ControlSaturation"}]),
    ]
    scenarios=scenarios+suite
    names={"nominal":"fixture_01_nominal.json","faults":"fixture_02_faults.json",
           "final_experiment":"final_experiment.json"}
    for fx in suite: names[fx["name"]]=fx["name"]+".json"
    for fx in scenarios:
        fx=finalize(pp, fx)
        out=f"{HERE}/fixtures/{names[fx['name']]}"
        json.dump(fx, open(out,"w"), indent=2)
        plant_d=json.load(open(pp))
        plant_obj=ref.load_plant(pp)
        trace,summ=ref.run(plant_obj, fx)
        write_icf(out.replace(".json",".icf"), plant_d, fx, trace, summ)
        exp=fx["expected"]
        seq_modes=exp["mode_sequence"]
        print(f"{fx['name']:16s} steps={fx['steps']:3d} "
              f"modes:{seq_modes[0]}..{seq_modes[-1]} "
              f"final_mode={exp['final_mode']} "
              f"|x_final|={sum(z*z for z in exp['final_state'])**0.5:.4f}")
    print("eigen:", {k:round(v,4) for k,v in eig.items()})
    print("gains K=",np.round(K,4).tolist())
    print("gains L=",np.round(L,4).tolist())

if __name__=="__main__": main()
