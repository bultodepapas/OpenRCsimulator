"""Independent R02 Stik mode reference: Godot manual loads + SciPy eigensolver."""

from __future__ import annotations

import hashlib
import json
import math
import subprocess
from pathlib import Path

import numpy as np
import scipy
from scipy.linalg import eigvals


ROOT = Path(__file__).resolve().parents[5]
EVIDENCE = Path(__file__).resolve().parent
GODOT = ROOT / ".tools" / "Godot_v4.7.2-stable_win64_console.exe"
PROBE = EVIDENCE / "manual_mode_probe.gd"
OLD_BANDS = {
    10.0: {"phugoid_zeta": 0.08278454, "spiral_eigenvalue_1_s": 0.45051607},
    15.0: {"phugoid_zeta": 0.30299182},
    25.0: {},
}
LONGITUDINAL = [0, 2, 4, 7, 8]
LATERAL = [1, 3, 5, 6]
STEP_KEYS = ["1.0e-05", "1.0e-06", "1.0e-07"]


def _metrics(jacobian: np.ndarray, speed: float, length: float) -> dict[str, float]:
    lon = jacobian[np.ix_(LONGITUDINAL, LONGITUDINAL)]
    lat = jacobian[np.ix_(LATERAL, LATERAL)]
    lon_roots = eigvals(lon)
    lat_roots = eigvals(lat)
    lon_osc = sorted(
        (root for root in lon_roots if root.imag > 1e-8),
        key=lambda root: abs(root),
        reverse=True,
    )
    lat_osc = [root for root in lat_roots if root.imag > 1e-8]
    lon_real = sorted(float(root.real) for root in lon_roots if abs(root.imag) <= 1e-8)
    lat_real = sorted(float(root.real) for root in lat_roots if abs(root.imag) <= 1e-8)
    if len(lat_osc) != 1 or len(lat_real) != 2:
        raise RuntimeError(
            f"unexpected eigenvalue structure at {speed:g} m/s: "
            f"longitudinal={lon_roots}, lateral={lat_roots}"
        )

    def oscillatory(root: complex) -> dict[str, float]:
        wn = abs(root)
        return {"frequency_hz": wn / (2.0 * math.pi), "zeta": -root.real / wn}

    if len(lon_osc) == 2 and len(lon_real) == 1:
        short = oscillatory(lon_osc[0])
        phugoid = oscillatory(lon_osc[1])
        lag_root = lon_real[0]
    elif len(lon_osc) == 1 and len(lon_real) == 3:
        lag_root = min(lon_real, key=lambda root: abs(root + speed / length))
        short_roots = [root for root in lon_real if root != lag_root]
        product = short_roots[0] * short_roots[1]
        if product <= 0.0:
            raise RuntimeError(f"nonnegative overdamped short-period product: {short_roots}")
        short_wn = math.sqrt(product)
        short = {
            "frequency_hz": short_wn / (2.0 * math.pi),
            "zeta": -(short_roots[0] + short_roots[1]) / (2.0 * short_wn),
        }
        phugoid = oscillatory(lon_osc[0])
    else:
        raise RuntimeError(
            f"unexpected longitudinal eigenvalue structure at {speed:g} m/s: {lon_roots}"
        )
    if len(lat_real) != 2:
        raise RuntimeError("lateral real-root structure changed")
    return {
        "short_period_frequency_hz": short["frequency_hz"],
        "short_period_zeta": short["zeta"],
        "phugoid_frequency_hz": phugoid["frequency_hz"],
        "phugoid_zeta": phugoid["zeta"],
        "roll_tau_s": -1.0 / lat_real[0],
        "dutch_roll_frequency_hz": oscillatory(lat_osc[0])["frequency_hz"],
        "dutch_roll_zeta": oscillatory(lat_osc[0])["zeta"],
        "spiral_eigenvalue_1_s": lat_real[1],
        "wake_lag_eigenvalue_1_s": lag_root,
        "longitudinal_eigenvalues": [
            [float(root.real), float(root.imag)] for root in sorted(lon_roots, key=lambda z: (z.real, z.imag))
        ],
        "lateral_eigenvalues": [
            [float(root.real), float(root.imag)] for root in sorted(lat_roots, key=lambda z: (z.real, z.imag))
        ],
    }


def main() -> None:
    if not GODOT.is_file():
        raise SystemExit(f"Godot 4.7.2 not found: {GODOT}")
    command = [
        str(GODOT),
        "--headless",
        "--path",
        str(ROOT / "app"),
        "--audio-driver",
        "Dummy",
        "--script",
        str(PROBE),
    ]
    completed = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, check=False)
    if completed.returncode:
        print(completed.stdout)
        print(completed.stderr)
        raise SystemExit(f"Godot probe exited {completed.returncode}")
    records = []
    for line in completed.stdout.splitlines():
        if line.startswith("MODE_REF_JSON="):
            records.append(json.loads(line.partition("=")[2]))
    if len(records) != 3:
        print(completed.stdout)
        raise SystemExit(f"expected three MODE_REF_JSON rows, got {len(records)}")

    result = {
        "method": "Godot manual Air/Aero/Propulsion/RigidBody composition; central differences; SciPy dense eigensolver",
        "versions": {"numpy": np.__version__, "scipy": scipy.__version__},
        "state_order": ["u_mps", "v_mps", "w_mps", "p_radps", "q_radps", "r_radps", "phi_rad", "theta_rad", "wake_mps"],
        "projection_indices": {"longitudinal": LONGITUDINAL, "lateral": LATERAL},
        "records": [],
    }
    for record in records:
        speed = float(record["speed_mps"])
        by_step = {}
        for step in STEP_KEYS:
            matrix = np.asarray(record["jacobians"][step], dtype=np.float64)
            if matrix.shape != (9, 9) or not np.isfinite(matrix).all():
                raise RuntimeError(f"invalid Jacobian for {speed:g} m/s, step {step}: {matrix.shape}")
            by_step[step] = matrix
        production_jacobian = np.asarray(record["production_jacobian"], dtype=np.float64)
        if production_jacobian.shape != (9, 9) or not np.isfinite(production_jacobian).all():
            raise RuntimeError(f"invalid production Jacobian for {speed:g} m/s: {production_jacobian.shape}")
        record["manual_vs_production_jacobian_inf_norm"] = float(
            np.linalg.norm(by_step["1.0e-06"] - production_jacobian, ord=np.inf)
        )
        metrics = {step: _metrics(matrix, speed, float(record["wake_length_m"])) for step, matrix in by_step.items()}
        reference = metrics["1.0e-06"]
        metric_names = [
            "short_period_frequency_hz",
            "short_period_zeta",
            "phugoid_frequency_hz",
            "phugoid_zeta",
            "roll_tau_s",
            "dutch_roll_frequency_hz",
            "dutch_roll_zeta",
            "spiral_eigenvalue_1_s",
            "wake_lag_eigenvalue_1_s",
        ]
        record["scipy_vs_flight_modes_metric_deltas"] = {
            key: reference[key] - float(record["production_modes"][key]) for key in metric_names
        }
        deltas = {}
        for step in ("1.0e-05", "1.0e-07"):
            other = metrics[step]
            deltas[step] = {
                key: abs(other[key] - reference[key])
                for key in reference
                if key.endswith("_hz") or key.endswith("_zeta") or key in {"roll_tau_s", "spiral_eigenvalue_1_s", "wake_lag_eigenvalue_1_s"}
            }
        record["analysis"] = {"by_step": metrics, "absolute_metric_deltas_vs_1e-6": deltas}
        record["jacobian_inf_norm_deltas_vs_1e-6"] = {
            step: float(np.linalg.norm(by_step[step] - by_step["1.0e-06"], ord=np.inf))
            for step in ("1.0e-05", "1.0e-07")
        }
        old = OLD_BANDS[speed]
        record["old_band_comparison"] = {
            key: {
                "old_reference": value,
                "independent_reference": reference[key],
                "relative_change_percent": 100.0 * (reference[key] - value) / value,
            }
            for key, value in old.items()
        }
        result["records"].append(record)

    source_paths = [
        "app/physics/air_data.gd",
        "app/physics/aero.gd",
        "app/physics/dynamics.gd",
        "app/physics/flight_modes.gd",
        "app/physics/propulsion.gd",
        "app/physics/rigid_body.gd",
        "app/physics/trim.gd",
        "app/tests/test_modes.gd",
        "app/data/aircraft/jensen_ugly_stik_60.json",
        str(PROBE.relative_to(ROOT)),
    ]
    result["source_sha256"] = {
        path: hashlib.sha256((ROOT / path).read_bytes()).hexdigest().upper() for path in source_paths
    }
    output = EVIDENCE / "mode-reference-results.json"
    output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    print(f"NumPy {np.__version__}; SciPy {scipy.__version__}")
    print("Manual Jacobian composed without FlightModes/Linearize; SciPy eigvals on 5x5 longitudinal and 4x4 lateral projections.")
    for record in result["records"]:
        speed = record["speed_mps"]
        base = record["analysis"]["by_step"]["1.0e-06"]
        print(
            f"{speed:g} m/s trim alpha={math.degrees(record['trim_alpha_rad']):.6f} deg "
            f"beta={math.degrees(record['trim_beta_rad']):.6f} deg rpm={record['trim_rpm']:.3f} "
            f"wake={record['wake_state_mps']:.9f} m/s"
        )
        print(
            f"  SP {base['short_period_frequency_hz']:.9f} Hz ζ={base['short_period_zeta']:.9f}; "
            f"phugoid {base['phugoid_frequency_hz']:.9f} Hz ζ={base['phugoid_zeta']:.9f}; "
            f"roll τ={base['roll_tau_s']:.9f} s; DR {base['dutch_roll_frequency_hz']:.9f} Hz "
            f"ζ={base['dutch_roll_zeta']:.9f}; spiral λ={base['spiral_eigenvalue_1_s']:.9f} 1/s; "
            f"wake λ={base['wake_lag_eigenvalue_1_s']:.9f} 1/s"
        )
        print(f"  Jacobian infinity-norm deltas from h=1e-6: {record['jacobian_inf_norm_deltas_vs_1e-6']}")
        print(f"  Manual vs FlightModes Jacobian infinity norm: {record['manual_vs_production_jacobian_inf_norm']:.9g}")
        print(f"  SciPy minus FlightModes metric deltas: {record['scipy_vs_flight_modes_metric_deltas']}")
        print(f"  Old requested-band comparisons: {record['old_band_comparison']}")
    print(f"Wrote {output.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
