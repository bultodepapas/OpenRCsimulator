"""Independent raw-source P51 area check; no candidate geometry imports.

Unscrambled Sobol sampling is a numerical cross-check, not an error certificate.
Coordinates here remain LE (aft, right, up), independently of the candidate's
FRD conversion and analytic cylinder/plane slicing.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import platform
from pathlib import Path

import numpy as np
import scipy
from scipy.stats import qmc


ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def review() -> dict:
    paths = {
        "aircraft": ROOT / "app/data/aircraft/p51d_mustang_120.json",
        "candidate_results": HERE / "candidate-results.json",
        "reviewer": Path(__file__).resolve(),
    }
    before = {key: digest(path) for key, path in paths.items()}
    data = json.loads(paths["aircraft"].read_text(encoding="utf-8"))
    reference = json.loads(paths["candidate_results"].read_text(encoding="utf-8"))
    if reference["sha256"]["aircraft_json"] != before["aircraft"]:
        raise ValueError("candidate and review aircraft identities differ")
    ref, prop = data["reference"], data["propulsion"]["propeller"]
    span = ref["wing_span"]["value"]
    root, tip = ref["root_chord"]["value"], ref["tip_chord"]["value"]
    half = span / 2.0
    slope = (tip - root) / half
    area = ref["wing_area"]["value"]
    hub = np.asarray(prop["slipstream"]["hub"]["value"], dtype=np.float64)
    plane_z = ref["aero_reference_point"]["value"][2]
    down, right = np.deg2rad(prop["thrust_angles"]["value"])
    axis = np.array([math.cos(down) * math.cos(right),
                     -math.cos(down) * math.sin(right), math.sin(down)])
    radius = prop["diameter"]["value"] * 0.5 * 0.7071
    # Rationalized equal-area inverse, independently from candidate subtraction.
    right_edges = [0.0] + [
        2.0 * (area * i / 6.0) / (root + math.sqrt(root * root + 2.0 * slope * area * i / 6.0))
        for i in (1, 2, 3)
    ]
    edges = [-right_edges[3], -right_edges[2], -right_edges[1], 0.0, *right_edges[1:]]
    rows = []
    for index in range(6):
        uv = qmc.Sobol(d=2, scramble=False).random_base2(20)
        y = edges[index] + uv[:, 0] * (edges[index + 1] - edges[index])
        chord = root + slope * np.abs(y)
        x = chord * uv[:, 1]
        diff = np.column_stack((x - hub[0], y - hub[1], np.full(len(y), plane_z - hub[2])))
        axial = diff @ axis
        radial2 = np.einsum("ij,ij->i", diff, diff) - axial * axial
        inside = (axial >= 0.0) & (radial2 <= radius * radius)
        weights = chord * (edges[index + 1] - edges[index])
        measured = float(np.mean(inside * weights))
        target = reference["p51_static_geometry"]["strip_rows"][index]["hard_tube_overlap_m2"]
        rows.append({"strip": index, "samples": len(y), "hits": int(inside.sum()),
                     "sobol_area_m2": measured, "candidate_area_m2": target,
                     "difference_m2": measured - target})
    after = {key: digest(path) for key, path in paths.items()}
    if before != after:
        raise ValueError("review inputs changed during the run")
    return {
        "status": "numerical cross-check only; no statistical or rigorous error bound",
        "method": "raw-source LE coordinates; deterministic unscrambled 2D Sobol; uniform span and conditional chord sampling",
        "numeric_environment": {"python": platform.python_version(), "numpy": np.__version__, "scipy": scipy.__version__},
        "input_sha256_before": before, "input_sha256_after": after,
        "wake_axis_le": axis.tolist(), "radius_m": radius, "strip_edges_le_m": edges,
        "rows": rows, "sum_sobol_area_m2": math.fsum(row["sobol_area_m2"] for row in rows),
        "max_absolute_difference_m2": max(abs(row["difference_m2"]) for row in rows),
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError(f"refusing to overwrite evidence: {args.output}")
    result = review()
    with args.output.open("x", encoding="utf-8", newline="\n") as stream:
        stream.write(json.dumps(result, indent=2, ensure_ascii=False) + "\n")
    print(json.dumps({"output": str(args.output), "sha256": digest(args.output),
                      "max_absolute_difference_m2": result["max_absolute_difference_m2"]}))
