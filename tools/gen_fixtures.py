#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from collections.abc import Iterator, Sequence
from itertools import islice
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "reference"))
import icarus_ref as ref

FIXTURES = ref.ROOT / "fixtures"
INITIAL_STATE = [0.5, -0.3, 0.4, -0.2]
TOLERANCE = 1e-6

A = np.array([[1.00, 0.20, 0.00, 0.00], [0.00, 1.05, 0.10, 0.00], [0.00, 0.00, 1.00, 0.20], [0.05, 0.00, 0.00, 1.08]])
B = np.array([[0.0, 0.0], [0.5, 0.0], [0.0, 0.0], [0.0, 0.5]])
C = np.array([[1.0, 0.0, 0.0, 0.0], [0.0, 0.0, 1.0, 0.0]])
DIMS = dict(zip("nmp", (A.shape[0], B.shape[1], C.shape[0]), strict=True))


def dlqr(
    a: np.ndarray, b: np.ndarray, q: np.ndarray, r: np.ndarray, iterations: int = 4000, tolerance: float = 1e-12
) -> np.ndarray:
    def gain(p: np.ndarray) -> np.ndarray:
        return np.linalg.solve(r + b.T @ p @ b, b.T @ p @ a)

    p = q.copy()
    for _ in range(iterations):
        p_next = q + a.T @ p @ a - a.T @ p @ b @ gain(p)
        converged = np.max(np.abs(p_next - p)) < tolerance
        p = p_next
        if converged:
            return gain(p)
    raise RuntimeError(f"Riccati iteration did not converge within {iterations} steps")


def spectral_radius(m: np.ndarray) -> float:
    return float(np.max(np.abs(np.linalg.eigvals(m))))


def design() -> tuple[np.ndarray, np.ndarray, dict[str, float]]:
    K = dlqr(A, B, np.eye(DIMS["n"]), np.eye(DIMS["m"]))
    L = dlqr(A.T, C.T, np.eye(DIMS["n"]), np.eye(DIMS["p"])).T
    radii = {
        "open_loop_rho": spectral_radius(A),
        "closed_loop_rho": spectral_radius(A - B @ K),
        "observer_rho": spectral_radius(A - L @ C),
    }
    if not radii["open_loop_rho"] > 1.0 > max(radii["closed_loop_rho"], radii["observer_rho"]):
        raise RuntimeError(f"plant must be open-loop unstable with a stable closed loop and observer: {radii}")
    return np.round(K, 9), np.round(L, 9), radii


def plant_spec(K: np.ndarray, L: np.ndarray, radii: dict[str, float]) -> dict:
    word = ref.FixedArithmetic
    frac_bits = word.SCALE.bit_length() - 1
    return {
        "dims": DIMS,
        "A": A.tolist(),
        "B": B.tolist(),
        "C": C.tolist(),
        "K": K.tolist(),
        "L": L.tolist(),
        "control_limit": ref.CTRL_LIMIT,
        "fixed_point": {
            "frac_bits": frac_bits,
            "int_bits": word.MAX_RAW.bit_length() - frac_bits,
            "scale": word.SCALE,
            "min": word.MIN_RAW / word.SCALE,
            "max": word.MAX_RAW / word.SCALE,
            "note": "artificial Q15.16; not a hardware word size",
        },
        "budget": {
            "frame": ref.FRAME_BUDGET,
            "stages": ref.STAGE_BUDGET,
            "margin": ref.FRAME_BUDGET - ref.NOMINAL_FRAME_COST,
        },
        "eigen": {name: round(rho, 6) for name, rho in radii.items()},
        "note": "Dimensionless synthetic plant. Not derived from any real vehicle.",
    }


def centered(states: Iterator[int], amplitude: float) -> Iterator[float]:
    for state in states:
        yield round(((state >> 11) / float(1 << 53) * 2.0 - 1.0) * amplitude, 9)


def fault(step: int, kind: ref.Fault, **parameters: float) -> dict:
    return {"step": step, "kind": kind.name, **parameters}


def overrun(step: int, ticks: int) -> dict:
    return fault(step, ref.Fault.TimingOverrun, overrun=ticks)


CASCADE = [
    overrun(10, 300),
    *(
        fault(step, kind)
        for step in (11, 12, 13)
        for kind in (ref.Fault.EstimatorDisagreement, ref.Fault.ControlSaturation)
    ),
]


def scenario(
    name: str, seed: int, steps: int, faults: list[dict], disturbance: float = 0.01, noise: float = 0.01
) -> dict:
    states = ref.lcg(seed)

    def draw(dim: int, amplitude: float) -> list[list[float]]:
        return [list(islice(centered(states, amplitude), dim)) for _ in range(steps)]

    disturbances = draw(DIMS["n"], disturbance)
    noises = draw(DIMS["p"], noise)
    return {
        "name": name,
        "dims": DIMS,
        "steps": steps,
        "seed": seed,
        "initial_state": INITIAL_STATE,
        "disturbance": disturbances,
        "noise": noises,
        "faults": faults,
        "tolerance": TOLERANCE,
        "fixed_scale": ref.FixedArithmetic.SCALE,
    }


def scaled(values: Sequence[float]) -> str:
    return " ".join(str(round(v * ref.CANONICAL_SCALE)) for v in values)


def icf(spec: dict, fixture: dict, events: Sequence[ref.FaultEvent], result: ref.Run) -> str:
    dims, canonical = spec["dims"], result.canonical()
    return ref.seal(
        [
            f"# icarus fixture {fixture['name']}",
            f"D {dims['n']} {dims['m']} {dims['p']} {fixture['steps']}",
            *(f"{tag} {scaled([v for row in spec[tag] for v in row])}" for tag in "ABCKL"),
            f"X {scaled(fixture['initial_state'])}",
            f"T {scaled([fixture['tolerance']])}",
            *(f"W {k} {scaled(w)}" for k, w in enumerate(fixture["disturbance"])),
            *(f"V {k} {scaled(v)}" for k, v in enumerate(fixture["noise"])),
            *(f"F {e.step} {int(e.kind)} {e.channel} {scaled([e.parameter])}" for e in events),
            *(" ".join(map(str, (tag, *canonical[tag]))) for tag in "MHG"),
            f"E {scaled(result.final_state)}",
        ]
    )


def suite() -> list[tuple[str, dict]]:
    def single(name: str, seed: int, *faults: dict) -> tuple[str, dict]:
        return name, scenario(name, seed, 30, list(faults))

    F = ref.Fault
    return [
        ("fixture_01_nominal", scenario("nominal", 20261002, 40, [])),
        (
            "fixture_02_faults",
            scenario(
                "faults",
                20261003,
                40,
                [
                    fault(10, F.BiasedMeasurement, channel=0, amount=25.0),
                    fault(15, F.MeasurementDropout, channel=1),
                    overrun(20, 300),
                ],
            ),
        ),
        (
            "final_experiment",
            scenario(
                "final_experiment",
                20261004,
                48,
                [
                    fault(8, F.BiasedMeasurement, channel=0, amount=18.0),
                    fault(12, F.MeasurementDropout, channel=1),
                    fault(13, F.MeasurementDropout, channel=1),
                    overrun(20, 260),
                    fault(28, F.NumericSaturation),
                ],
                disturbance=0.015,
                noise=0.02,
            ),
        ),
        single(
            "fault_dropout",
            20261101,
            fault(10, F.MeasurementDropout, channel=0),
            fault(11, F.MeasurementDropout, channel=0),
        ),
        single("fault_stale", 20261102, fault(10, F.StaleMeasurement), fault(11, F.StaleMeasurement)),
        single("fault_bias", 20261103, fault(10, F.BiasedMeasurement, channel=0, amount=25.0)),
        single("fault_stuck", 20261104, fault(10, F.StuckChannel, channel=1)),
        single("fault_range", 20261105, fault(10, F.OutOfRange, channel=0, value=1.0e6)),
        single("fault_overrun", 20261106, overrun(10, 300)),
        single("fault_numeric", 20261107, fault(10, F.NumericSaturation)),
        single("fault_estimator", 20261108, fault(10, F.EstimatorDisagreement)),
        single("fault_ctrlsat", 20261109, fault(10, F.ControlSaturation)),
        single("fault_cascade", 20261110, *CASCADE),
    ]


def main() -> None:
    K, L, radii = design()
    spec = plant_spec(K, L, radii)
    ref.PLANT_PATH.write_text(json.dumps(spec, indent=2))
    plant = ref.Plant.load()

    for stem, fixture in suite():
        parsed = ref.Fixture.parse(fixture, plant)
        result = ref.run(plant, parsed)
        fixture["expected"] = {
            "mode_sequence": [mode.name for mode in result.modes],
            "final_state": [round(z, 9) for z in result.final_state],
            "final_estimate": [round(z, 9) for z in result.final_estimate],
            "final_mode": result.final_mode.name,
        }
        (FIXTURES / f"{stem}.json").write_text(json.dumps(fixture, indent=2))
        (FIXTURES / f"{stem}.icf").write_text(icf(spec, fixture, parsed.faults, result))
        final = fixture["expected"]["final_state"]
        print(
            f"{fixture['name']:16s} steps={fixture['steps']:3d} "
            f"modes:{result.modes[0].name}..{result.final_mode.name} final_mode={result.final_mode.name} "
            f"|x_final|={sum(z * z for z in final) ** 0.5:.4f}"
        )

    print("eigen:", {name: round(rho, 4) for name, rho in radii.items()})
    print("gains K=", np.round(K, 4).tolist())
    print("gains L=", np.round(L, 4).tolist())


if __name__ == "__main__":
    main()
