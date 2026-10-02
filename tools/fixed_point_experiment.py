#!/usr/bin/env python3
"""Float versus saturating Q15.16 realisation of the controller path.

Pre-specified design (written before any run):
  Question  How far does the fixed-point controller path deviate from the float
            reference, and does it ever change a discrete observable
            (mode sequence, health, flag mask)?
  Sample    N seeds per scenario; disturbance and noise realisations differ by seed.
  Metrics   dmax   = max_k || x_fixed[k] - x_float[k] ||_inf, in LSB (1/65536)
            sat    = saturation events in the fixed run
            agree  = identical M, H and G sequences
  Report    median with a bootstrap 95% interval, 95th percentile, maximum, and a
            Wilson interval on the disagreement rate. No significance test: there is
            no null hypothesis here, only a measurement.
  Exploratory (labelled as such): the error growth rate after the controller enters
            Safe, compared with ln of the open-loop spectral radius.
"""
import json, math, os, sys
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "reference")); sys.path.insert(0, os.path.join(ROOT, "tools"))
import icarus_ref as ref
import gen_fixtures as gf

N = 200
LSB = 1.0 / 65536
RNG = np.random.default_rng(20261002)
plant = ref.load_plant(os.path.join(ROOT, "fixtures", "plant.json"))
X0 = [0.5, -0.3, 0.4, -0.2]

def make(seed, steps, faults, amp_w=0.01, amp_v=0.01):
    return gf.build(f"seed{seed}", seed, steps, X0, amp_w, amp_v, faults)

def modes_health_masks(trace, summ):
    fb = gf.FLAGBIT
    return (summ["mode_sequence"], [r.health for r in trace],
            [sum(fb[f] for f in r.flags) for r in trace])

def paired(fx):
    tf, sf = ref.run(plant, fx)
    tx, sx = ref.run(plant, fx, arith=ref.FixedArith())
    d = [max(abs(a - b) for a, b in zip(rf.x, rx.x)) for rf, rx in zip(tf, tx)]
    return tf, sf, tx, sx, d

def boot_ci(v, stat=np.median, B=10000):
    v = np.asarray(v); idx = RNG.integers(0, len(v), (B, len(v)))
    s = stat(v[idx], axis=1)
    return float(np.percentile(s, 2.5)), float(np.percentile(s, 97.5))

def wilson(k, n, z=1.96):
    p = k / n; den = 1 + z * z / n
    c = (p + z * z / (2 * n)) / den
    h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / den
    return max(0.0, c - h), min(1.0, c + h)

def scenario(name, steps, faults, seed0):
    dmax, sat, agree, finals = [], [], [], []
    for i in range(N):
        fx = make(seed0 + i, steps, faults)
        tf, sf, tx, sx, d = paired(fx)
        dmax.append(max(d) / LSB); sat.append(sx["arith"]["sat_events"])
        agree.append(modes_health_masks(tf, sf) == modes_health_masks(tx, sx))
        finals.append(d[-1] / LSB)
    dmax = np.array(dmax); lo, hi = boot_ci(dmax)
    dis = N - sum(agree); wlo, whi = wilson(dis, N)
    return dict(name=name, steps=steps, n=N, dmax_median=float(np.median(dmax)), dmax_ci=(lo, hi),
                dmax_p95=float(np.percentile(dmax, 95)), dmax_max=float(dmax.max()),
                sat_total=int(sum(sat)), disagree=dis, disagree_ci=(wlo, whi))

def growth_after_safe():
    """Exploratory. After Safe both plants run open loop in floating point, so the
    deviation must obey e[k+1] = A e[k] exactly. Test that, and compare the fitted
    window slope with both the asymptotic rate ln(rho) and the exact prediction."""
    A = np.array(plant.A)
    faults = [{"step": 10, "kind": "TimingOverrun", "overrun": 300}] + [
        {"step": k, "kind": kind} for k in (11, 12, 13)
        for kind in ("EstimatorDisagreement", "ControlSaturation")]
    slopes, pred_slopes, worst = [], [], 0.0
    for i in range(N):
        fx = make(30000 + i, 60, faults)
        tf, sf, tx, sx, d = paired(fx)
        safe = [k for k, r in enumerate(tf) if r.mode == "Safe"]
        if len(safe) < 10: continue
        k0 = safe[0]
        e0 = np.array(tx[k0].x) - np.array(tf[k0].x)
        if np.max(np.abs(e0)) == 0: continue
        pred = [np.max(np.abs(np.linalg.matrix_power(A, k - k0) @ e0)) for k in safe]
        meas = [d[k] for k in safe]
        worst = max(worst, max(abs(math.log(m) - math.log(q)) for m, q in zip(meas, pred)))
        ks = np.array(safe[3:])
        slopes.append(np.polyfit(ks, np.log(meas[3:]), 1)[0])
        pred_slopes.append(np.polyfit(ks, np.log(pred[3:]), 1)[0])
    s = np.array(slopes); lo, hi = boot_ci(s, np.mean)
    return dict(n=len(s), mean=float(s.mean()), ci=(lo, hi), sd=float(s.std(ddof=1)),
                pred_mean=float(np.mean(pred_slopes)), max_log_gap=float(worst))

def main():
    rho = max(abs(np.linalg.eigvals(np.array(plant.A))))
    res = [
        scenario("nominal (closed loop, no faults)", 40, [], 10000),
        scenario("measurement faults and an overrun, recovers", 40, [
            {"step": 10, "kind": "BiasedMeasurement", "channel": 0, "amount": 25.0},
            {"step": 15, "kind": "MeasurementDropout", "channel": 1},
            {"step": 20, "kind": "TimingOverrun", "overrun": 300}], 20000),
    ]
    # Single genuine overflow event: the final experiment, one deterministic run.
    fx = json.load(open(os.path.join(ROOT, "fixtures", "final_experiment.json")))
    tf, sf, tx, sx, d = paired(fx)
    ev = [k for k, r in enumerate(tx) if r.health == "Unsafe"][0]
    final = dict(first_unsafe=ev, sat_events=sx["arith"]["sat_events"],
                 same_modes=sf["mode_sequence"] == sx["mode_sequence"],
                 dev_before=max(d[:ev]) / LSB, dev_after=d[ev + 1] / LSB)
    g = growth_after_safe()
    out = dict(lsb=LSB, rho_open_loop=float(rho), ln_rho=math.log(rho), scenarios=res,
               final=final, growth=g, numpy=np.__version__, python=sys.version.split()[0])
    json.dump(out, open(os.path.join(ROOT, "docs/results/fixed_point.json"), "w"), indent=2)

    L = ["# Fixed-point experiment results", "",
         f"Generated by `tools/fixed_point_experiment.py` (numpy {np.__version__}, python {out['python']}, "
         f"bootstrap seed 20261002, 10000 resamples). Units: 1 LSB = 2^-16. N = {N} seeds per scenario.", "",
         "| scenario | steps | median dmax (LSB) | 95% bootstrap CI | p95 | max | saturations | disagreements (Wilson 95%) |",
         "|---|---|---|---|---|---|---|---|"]
    for r in res:
        L.append(f"| {r['name']} | {r['steps']} | {r['dmax_median']:.2f} | [{r['dmax_ci'][0]:.2f}, {r['dmax_ci'][1]:.2f}] | "
                 f"{r['dmax_p95']:.2f} | {r['dmax_max']:.2f} | {r['sat_total']} | {r['disagree']}/{r['n']} "
                 f"([{100*r['disagree_ci'][0]:.1f}%, {100*r['disagree_ci'][1]:.1f}%]) |")
    L += ["", "## One genuine overflow (final experiment, deterministic)", "",
          f"- first Unsafe frame: step {final['first_unsafe']}; saturation events: {final['sat_events']}",
          f"- mode sequence identical to float: {final['same_modes']}",
          f"- max state deviation before the overflow: {final['dev_before']:.1f} LSB",
          f"- state deviation one step after: {final['dev_after']:.0f} LSB "
          f"({final['dev_after']*LSB:.3f} in state units)", "",
          "## Exploratory: deviation growth after Safe", "",
          f"Open-loop spectral radius of A is {rho:.4f}, so the asymptotic rate is ln = {out['ln_rho']:.4f} per step.",
          f"Fitted log-slope of the measured deviation while Safe, {g['n']} seeds: mean {g['mean']:.4f}, "
          f"95% bootstrap CI [{g['ci'][0]:.4f}, {g['ci'][1]:.4f}], sd {g['sd']:.4f}.",
          f"The same fit applied to the exact prediction ||A^k e0||: mean {g['pred_mean']:.4f}.",
          f"Largest gap between measured and exactly propagated log-deviation over every Safe frame of every seed: "
          f"{g['max_log_gap']:.2e}.", "",
          "Reading: the measured slope sits below ln(rho) because a finite window is dominated by the transient "
          "of the sub-dominant modes, not because fixed-point arithmetic changes the dynamics. The deviation after "
          "Safe is the entry deviation propagated by A, so this part of the experiment measures the plant, not the "
          "arithmetic."]
    open(os.path.join(ROOT, "docs/results/fixed_point.md"), "w").write("\n".join(L) + "\n")
    print("\n".join(L))

if __name__ == "__main__":
    main()
