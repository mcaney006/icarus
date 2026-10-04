#!/usr/bin/env python3
from __future__ import annotations

import json
import math
import sys
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "reference"))
sys.path.insert(0, str(Path(__file__).resolve().parent))
import gen_fixtures as fixtures
import icarus_ref as ref

SEEDS = 200
LSB = 1.0 / ref.FixedArithmetic.SCALE
BOOTSTRAP_SEED = 20261002
RESAMPLES = 10000
MIN_SAFE_FRAMES = 10
SETTLING_FRAMES = 3
PROPAGATION_GAP = 1e-6
RESULTS = ref.ROOT / "docs" / "results"
FINAL_EXPERIMENT = ref.ROOT / "fixtures" / "final_experiment.json"


@dataclass(frozen=True)
class Pair:
    reference: ref.Run
    fixed: ref.Run
    deviation: list[float]

    @classmethod
    def of(cls, plant: ref.Plant, record: dict) -> Pair:
        fixture = ref.Fixture.parse(record, plant)
        reference = ref.run(plant, fixture)
        fixed = ref.run(plant, fixture, ref.FixedArithmetic())
        deviation = [
            max(abs(a - b) for a, b in zip(r.x, q.x, strict=True))
            for r, q in zip(reference.trace, fixed.trace, strict=True)
        ]
        return cls(reference, fixed, deviation)

    @property
    def agrees(self) -> bool:
        def observables(run: ref.Run) -> tuple[list, list, list]:
            return run.modes, [frame.health for frame in run.trace], [frame.flags for frame in run.trace]

        return observables(self.reference) == observables(self.fixed)


@dataclass
class Experiment:
    plant: ref.Plant
    rng: np.random.Generator

    def seeded(self, seed: int, steps: int, faults: list[dict]) -> Pair:
        return Pair.of(self.plant, fixtures.scenario(f"seed{seed}", seed, steps, faults))

    def bootstrap(self, values: np.ndarray, statistic: Callable = np.median) -> tuple[float, float]:
        if not len(values):
            raise ValueError("bootstrap of an empty sample")
        draws = statistic(values[self.rng.integers(0, len(values), (RESAMPLES, len(values)))], axis=1)
        return float(np.percentile(draws, 2.5)), float(np.percentile(draws, 97.5))

    def scenario(self, name: str, steps: int, faults: list[dict], first_seed: int) -> dict:
        pairs = [self.seeded(first_seed + i, steps, faults) for i in range(SEEDS)]
        dmax = np.array([max(pair.deviation) / LSB for pair in pairs])
        disagreements = sum(not pair.agrees for pair in pairs)
        return {
            "name": name,
            "steps": steps,
            "n": SEEDS,
            "dmax_median": float(np.median(dmax)),
            "dmax_ci": self.bootstrap(dmax),
            "dmax_p95": float(np.percentile(dmax, 95)),
            "dmax_max": float(dmax.max()),
            "sat_total": sum(pair.fixed.arithmetic["sat_events"] for pair in pairs),
            "disagree": disagreements,
            "disagree_ci": wilson(disagreements, SEEDS),
        }

    def growth_after_safe(self) -> dict:
        A = np.array(self.plant.A)
        slopes, predicted_slopes, worst_gap = [], [], 0.0
        for i in range(SEEDS):
            pair = self.seeded(30000 + i, 60, fixtures.CASCADE)
            safe = [frame.k for frame in pair.reference.trace if frame.mode is ref.Mode.Safe]
            if len(safe) < MIN_SAFE_FRAMES:
                continue
            entry = safe[0]
            e0 = np.array(pair.fixed.trace[entry].x) - np.array(pair.reference.trace[entry].x)
            predicted = [np.max(np.abs(np.linalg.matrix_power(A, k - entry) @ e0)) for k in safe]
            measured = [pair.deviation[k] for k in safe]
            if min(measured) <= 0.0 or min(predicted) <= 0.0:
                continue
            worst_gap = max(
                worst_gap, max(abs(math.log(m) - math.log(q)) for m, q in zip(measured, predicted, strict=True))
            )
            window = np.array(safe[SETTLING_FRAMES:])
            slopes.append(np.polyfit(window, np.log(measured[SETTLING_FRAMES:]), 1)[0])
            predicted_slopes.append(np.polyfit(window, np.log(predicted[SETTLING_FRAMES:]), 1)[0])
        observed = np.array(slopes)
        if len(observed) < 2:
            raise ValueError(f"only {len(observed)} seeds reached a usable Safe window")
        return {
            "n": len(observed),
            "mean": float(observed.mean()),
            "ci": self.bootstrap(observed, np.mean),
            "sd": float(observed.std(ddof=1)),
            "pred_mean": float(np.mean(predicted_slopes)),
            "max_log_gap": float(worst_gap),
        }

    def overflow_event(self) -> dict:
        pair = Pair.of(self.plant, ref.finite_json(FINAL_EXPERIMENT.read_text()))
        first_unsafe = next((frame.k for frame in pair.fixed.trace if frame.health is ref.Health.Unsafe), None)
        if first_unsafe is None or not 0 < first_unsafe < len(pair.deviation) - 1:
            raise ValueError(f"final experiment has no interior Unsafe frame (found {first_unsafe})")
        return {
            "first_unsafe": first_unsafe,
            "sat_events": pair.fixed.arithmetic["sat_events"],
            "same_modes": pair.reference.modes == pair.fixed.modes,
            "dev_before": max(pair.deviation[:first_unsafe]) / LSB,
            "dev_after": pair.deviation[first_unsafe + 1] / LSB,
        }


def wilson(successes: int, trials: int, z: float = 1.96) -> tuple[float, float]:
    p = successes / trials
    denominator = 1 + z * z / trials
    centre = (p + z * z / (2 * trials)) / denominator
    half = z * math.sqrt(p * (1 - p) / trials + z * z / (4 * trials * trials)) / denominator
    return max(0.0, centre - half), min(1.0, centre + half)


def reading(results: dict) -> str:
    growth = results["growth"]
    below = growth["ci"][1] < results["ln_rho"]
    tracks = growth["max_log_gap"] < PROPAGATION_GAP
    if below and tracks:
        return (
            "Reading: the measured slope sits below ln(rho) because a finite window is dominated by the transient "
            "of the sub-dominant modes, not because fixed-point arithmetic changes the dynamics. The deviation "
            "after Safe is the entry deviation propagated by A, so this part of the experiment measures the "
            "plant, not the arithmetic."
        )
    return (
        f"Reading: slope interval below ln(rho): {below}; measured deviation tracks A^k e0 within "
        f"{PROPAGATION_GAP:g}: {tracks}. The propagation argument does not hold for this run."
    )


def render(results: dict) -> str:
    final, growth = results["final"], results["growth"]
    lines = [
        "# Fixed-point experiment results",
        "",
        f"Generated by `tools/fixed_point_experiment.py` (numpy {results['numpy']}, python {results['python']}, "
        f"bootstrap seed {BOOTSTRAP_SEED}, {RESAMPLES} resamples). Units: 1 LSB = 2^-16. "
        f"N = {SEEDS} seeds per scenario.",
        "",
        "| scenario | steps | median dmax (LSB) | 95% bootstrap CI | p95 | max | saturations | disagreements (Wilson 95%) |",
        "|---|---|---|---|---|---|---|---|",
    ]
    lines += [
        f"| {r['name']} | {r['steps']} | {r['dmax_median']:.2f} | [{r['dmax_ci'][0]:.2f}, {r['dmax_ci'][1]:.2f}] | "
        f"{r['dmax_p95']:.2f} | {r['dmax_max']:.2f} | {r['sat_total']} | {r['disagree']}/{r['n']} "
        f"([{100 * r['disagree_ci'][0]:.1f}%, {100 * r['disagree_ci'][1]:.1f}%]) |"
        for r in results["scenarios"]
    ]
    lines += [
        "",
        "## One genuine overflow (final experiment, deterministic)",
        "",
        f"- first Unsafe frame: step {final['first_unsafe']}; saturation events: {final['sat_events']}",
        f"- mode sequence identical to float: {final['same_modes']}",
        f"- max state deviation before the overflow: {final['dev_before']:.1f} LSB",
        f"- state deviation one step after: {final['dev_after']:.0f} LSB "
        f"({final['dev_after'] * LSB:.3f} in state units)",
        "",
        "## Exploratory: deviation growth after Safe",
        "",
        f"Open-loop spectral radius of A is {results['rho_open_loop']:.4f}, so the asymptotic rate is "
        f"ln = {results['ln_rho']:.4f} per step.",
        f"Fitted log-slope of the measured deviation while Safe, {growth['n']} seeds: mean {growth['mean']:.4f}, "
        f"95% bootstrap CI [{growth['ci'][0]:.4f}, {growth['ci'][1]:.4f}], sd {growth['sd']:.4f}.",
        f"The same fit applied to the exact prediction ||A^k e0||: mean {growth['pred_mean']:.4f}.",
        "Largest gap between measured and exactly propagated log-deviation over every Safe frame of every seed: "
        f"{growth['max_log_gap']:.2e}.",
        "",
        reading(results),
    ]
    return "\n".join(lines) + "\n"


def main() -> None:
    experiment = Experiment(ref.Plant.load(), np.random.default_rng(BOOTSTRAP_SEED))
    rho = fixtures.spectral_radius(np.array(experiment.plant.A))
    scenarios = [
        experiment.scenario("nominal (closed loop, no faults)", 40, [], 10000),
        experiment.scenario(
            "measurement faults and an overrun, recovers",
            40,
            [
                fixtures.fault(10, ref.Fault.BiasedMeasurement, channel=0, amount=25.0),
                fixtures.fault(15, ref.Fault.MeasurementDropout, channel=1),
                fixtures.overrun(20, 300),
            ],
            20000,
        ),
    ]
    results = {
        "lsb": LSB,
        "rho_open_loop": rho,
        "ln_rho": math.log(rho),
        "scenarios": scenarios,
        "final": experiment.overflow_event(),
        "growth": experiment.growth_after_safe(),
        "numpy": np.__version__,
        "python": sys.version.split()[0],
    }
    RESULTS.mkdir(parents=True, exist_ok=True)
    (RESULTS / "fixed_point.json").write_text(json.dumps(results, indent=2))
    report = render(results)
    (RESULTS / "fixed_point.md").write_text(report)
    print(report, end="")


if __name__ == "__main__":
    main()
