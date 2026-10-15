"""Re-evaluate the retained D11f Weissinger reference at matching alpha values.

This imports the original independent model unchanged and calls its loads() function.
It is a comparison probe, not a replacement reference and not physical validation.
"""
from __future__ import annotations

import contextlib
import hashlib
import io
import json
import math
from pathlib import Path
import runpy


ROOT = next(parent for parent in Path(__file__).resolve().parents
	if (parent / "research/aero/d11f/wing_yaw_damping.py").is_file())
REFERENCE = ROOT / "research/aero/d11f/wing_yaw_damping.py"
source_hash = hashlib.sha256(REFERENCE.read_bytes()).hexdigest()
with contextlib.redirect_stdout(io.StringIO()):
    reference = runpy.run_path(str(REFERENCE))

V = float(reference["V"])
S = float(reference["S"])
b = float(reference["b"])
qS = 0.5 * V * V * S
h = 0.05
profile = -float(reference["CD0"]) / 3.0 * (1.0 - 1.0 / (4.0 * int(reference["n_side"]) ** 2))
rows = []
for alpha_deg in (4.0, 10.0, 11.0):
    alpha = math.radians(alpha_deg)
    lift_0, _ = reference["loads"](alpha, 0.0)
    _, moment_plus = reference["loads"](alpha, h)
    _, moment_minus = reference["loads"](alpha, -h)
    cl = lift_0 / qS
    cnr = (moment_plus - moment_minus) / (2.0 * h) / (qS * b * b / (2.0 * V))
    rows.append({
        "alpha_deg": alpha_deg,
        "wing_CL": cl,
        "Cnr_total": cnr,
        "Cnr_profile_formula": profile,
        "Cnr_lift_induced_residual": cnr - profile,
        "lift_induced_over_CL_squared": (cnr - profile) / (cl * cl),
    })

print(json.dumps({
    "reference_path": "research/aero/d11f/wing_yaw_damping.py",
    "reference_sha256": source_hash,
    "method": "unchanged D11f Weissinger/horseshoe model; central yaw-rate difference",
    "rate_step_rad_s": h,
    "normalization": "q*S*b^2/(2*V)",
    "inputs": {
        "speed_mps": V,
        "area_m2": S,
        "span_m": b,
        "aspect_ratio": float(reference["AR"]),
        "strips_per_side": int(reference["n_side"]),
        "section_slope_per_rad": float(reference["a0"]),
        "profile_CD0": float(reference["CD0"]),
        "camber_or_strip_CL0": "none in original reference",
        "induced_force": "circulation and trailing downwash in Kutta-Joukowski load",
    },
    "rows": rows,
    "interpretation": "This isolates the retained reference output; it does not make its camber, drag-vector, or induced-force assumptions identical to the current R02 model.",
}, indent=2))
