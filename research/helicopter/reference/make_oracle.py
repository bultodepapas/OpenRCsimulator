"""Reproducibly write or check the small Johnson inflow oracle JSON."""

from __future__ import annotations

import argparse
import difflib
import json
import math
from pathlib import Path
import sys

from johnson_inflow import normalized, target


HERE = Path(__file__).resolve().parent
OUTPUT = HERE / "oracle.json"


ANCHOR_CASES = (
    ("hover", {"vz": 0.0, "vx": 0.0}),
    ("axial_climb_1", {"vz": 1.0, "vx": 0.0}),
    ("forward_hover_1", {"vz": 0.0, "vx": 1.0}),
    ("windmill_branch", {"vz": -2.5, "vx": 0.0}),
    ("baseline_midcurve", {"vz": -1.8, "vx": 0.0, "instability": 0.0}),
    ("vrs_n_suppressed", {"vz": -0.45, "vx": 0.0, "instability": 0.0}),
    ("vrs_n_full", {"vz": -0.45, "vx": 0.0, "instability": 1.0}),
    ("vrs_x_full", {"vz": -1.5, "vx": 0.0, "instability": 1.0}),
    (
        "vrs_forward_blend",
        {"vz": -0.8, "vx": 0.5, "instability": 0.65, "loss": 1.1},
    ),
    (
        "vrs_crossflow_extension",
        {"vz": -0.8, "vx": 0.85, "instability": 1.0},
    ),
    (
        "vrs_outer_limit",
        {"vz": -0.8, "vx": 0.95, "instability": 1.0},
    ),
)


# A compact Cartesian slice exercises descent, climb, crossflow, the baseline
# range, and both suppressed/full VRS corrections for independent port checks.
GRID_Z = (-2.2, -1.8, -1.3, -0.7, -0.45, -0.2)
GRID_X = (0.0, 0.25, 0.5, 0.74, 0.85, 1.0)
GRID_F = (0.0, 1.0)
GRID_CASES = tuple(
    (
        f"grid_z{z_index}_x{x_index}_f{int(f)}",
        {"vz": z, "vx": x, "instability": f},
    )
    for z_index, z in enumerate(GRID_Z)
    for x_index, x in enumerate(GRID_X)
    for f in GRID_F
)

BOUNDARY_CASES = (
    (
        "boundary_c_below",
        {"vz": -1.428, "vx": 0.75 - 1.0e-9, "instability": 0.0},
    ),
    (
        "boundary_c_above",
        {"vz": -1.428, "vx": 0.75 + 1.0e-9, "instability": 0.0},
    ),
    (
        "boundary_m_below_z_m1p3",
        {"vz": -1.3, "vx": 0.95 - 1.0e-10},
    ),
    (
        "boundary_m_above_z_m1p3",
        {"vz": -1.3, "vx": 0.95 + 1.0e-10},
    ),
    (
        "boundary_m_below_z_m0p7",
        {"vz": -0.7, "vx": 0.95 - 1.0e-10},
    ),
    (
        "boundary_m_above_z_m0p7",
        {"vz": -0.7, "vx": 0.95 + 1.0e-10},
    ),
)

CASES = ANCHOR_CASES + GRID_CASES + BOUNDARY_CASES


TARGET_CASES = (
    (
        "positive_hover_ige",
        {
            "thrust": 100.0,
            "density": 1.225,
            "radius": 1.0,
            "climb": 0.0,
            "crossflow": 0.0,
            "height_over_radius": 1.0,
        },
    ),
    (
        "positive_thrust_mirror",
        {
            "thrust": 100.0,
            "density": 1.225,
            "radius": 1.0,
            "climb": 2.0,
            "crossflow": 1.5,
            "height_over_radius": 0.5,
        },
    ),
    (
        "negative_thrust_mirror",
        {
            "thrust": -100.0,
            "density": 1.225,
            "radius": 1.0,
            "climb": -2.0,
            "crossflow": 1.5,
            "height_over_radius": 0.5,
        },
    ),
    (
        "positive_crossflow_off_ground",
        {
            "thrust": 80.4,
            "density": 1.225,
            "radius": 0.7,
            "climb": 3.2,
            "crossflow": 1.7,
            "height_over_radius": -1.0,
        },
    ),
    (
        "negative_crossflow_off_ground",
        {
            "thrust": -80.4,
            "density": 1.225,
            "radius": 0.7,
            "climb": -3.2,
            "crossflow": 1.7,
            "height_over_radius": -1.0,
        },
    ),
    (
        "positive_forward_ige",
        {
            "thrust": 100.0,
            "density": 1.225,
            "radius": 1.0,
            "climb": 2.0,
            "crossflow": 1.5,
            "height_over_radius": 1.0,
        },
    ),
)


def _rounded(value: float) -> float:
    return round(float(value), 12)


def build_document() -> dict[str, object]:
    normalized_rows = []
    for name, inputs in CASES:
        result = normalized(**inputs)
        if not result["ok"]:
            raise RuntimeError(f"{name}: {result.get('error', 'reference failed')}")
        normalized_rows.append({
            "name": name,
            "inputs": inputs,
            "expected_ratio": _rounded(float(result["ratio"])),
        })

    target_rows = []
    for name, inputs in TARGET_CASES:
        result = target(**inputs)
        if not result["ok"]:
            raise RuntimeError(f"{name}: {result.get('error', 'reference failed')}")
        target_rows.append({
            "name": name,
            "inputs": inputs,
            "expected": {
                "velocity": _rounded(float(result["velocity"])),
                "hover": _rounded(float(result["hover"])),
                "ground_factor": _rounded(float(result["ground_factor"])),
            },
        })

    # Guard source-derived anchors before allowing the oracle to be rewritten.
    by_name = {row["name"]: row["expected_ratio"] for row in normalized_rows}
    anchors = {
        "hover": 1.0,
        "axial_climb_1": (math.sqrt(5.0) - 1.0) / 2.0,
        "forward_hover_1": math.sqrt((math.sqrt(5.0) - 1.0) / 2.0),
        "windmill_branch": 0.5,
        "vrs_n_suppressed": 1.25,
        "vrs_n_full": 1.3,
        "vrs_x_full": 2.75,
    }
    for name, expected in anchors.items():
        if not math.isclose(by_name[name], expected, rel_tol=0.0, abs_tol=5.0e-12):
            raise RuntimeError(
                f"source/analytic anchor {name} drifted: "
                f"{by_name[name]} != {expected}"
            )

    return {
        "format": "openrc-johnson-inflow-oracle-v1",
        "model": "NASA/TP-2005-213477 steady mean inflow; Hayden hover factor",
        "velocity_convention": {
            "vz": "positive climb, normalized by v_h",
            "vx": "crossflow magnitude, normalized by v_h",
            "ratio": "induced velocity v/v_h, positive downward",
        },
        "normalized_cases": normalized_rows,
        "dimensional_target_cases": target_rows,
    }


def render() -> str:
    return json.dumps(build_document(), indent=2, sort_keys=True) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--check",
        action="store_true",
        help="fail if oracle.json is not exactly the generated output",
    )
    args = parser.parse_args()
    generated = render()

    if args.check:
        current = OUTPUT.read_text(encoding="utf-8") if OUTPUT.exists() else ""
        if current == generated:
            print(f"oracle check: OK ({OUTPUT.name})")
            return 0
        diff = difflib.unified_diff(
            current.splitlines(keepends=True),
            generated.splitlines(keepends=True),
            fromfile=str(OUTPUT),
            tofile="generated",
        )
        sys.stdout.writelines(diff)
        print("oracle check: FAILED; run make_oracle.py to regenerate")
        return 1

    OUTPUT.write_text(generated, encoding="utf-8", newline="\n")
    print(f"wrote {OUTPUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
