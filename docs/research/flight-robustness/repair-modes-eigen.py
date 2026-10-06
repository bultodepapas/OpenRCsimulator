#!/usr/bin/env python3
"""NumPy eigenanalysis of the full flight-repair Jacobians exported by Godot."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np

STATE_ORDER = ["u_mps", "v_mps", "w_mps", "p_rad_s", "q_rad_s", "r_rad_s", "phi_rad", "theta_rad"]


def analyze_row(row: dict) -> dict:
    if not row.get("ok"):
        return {"V_mps": row["V_mps"], "ok": False, "message": row.get("message", "trim failed")}

    matrix = np.asarray(row["full_jacobian"], dtype=np.float64)
    values, vectors = np.linalg.eig(matrix)
    order = np.lexsort((values.imag, values.real))
    eigs = [
        {"real_s-1": float(values[i].real), "imag_s-1": float(values[i].imag)}
        for i in order
    ]
    dominant_index = int(np.argmax(values.real))
    dominant = values[dominant_index]
    real_part = float(dominant.real)
    tau = None if abs(real_part) < 1.0e-12 else -1.0 / real_part
    vector = np.abs(vectors[:, dominant_index])
    scale = float(vector.max())
    normalized = vector / scale if scale else vector
    return {
        "V_mps": row["V_mps"],
        "ok": True,
        "alpha_deg": row["alpha_deg"],
        "projected_spiral_tau_s": row["projected_spiral_tau_s"],
        "projected_lateral_eigenvalues": row["projected_lateral_eigenvalues"],
        "full_jacobian_eigenvalues_s-1": eigs,
        "dominant_real_part_s-1": real_part,
        "dominant_mode_tau_s_negative_means_divergence": tau,
        "dominant_mode_eigenvector_abs_max_normalized": {
            name: float(normalized[i]) for i, name in enumerate(STATE_ORDER)
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    raw = args.input.read_bytes()
    data = json.loads(raw)
    report = {
        "format": "openrc-flight-repair-modal-analysis v1",
        "input_sha256": hashlib.sha256(raw).hexdigest(),
        "method": "numpy.linalg.eig on full 8x8 FlightModes Jacobian; frozen control angles; propeller gyro is included by Dynamics.evaluate",
        "state_order": STATE_ORDER,
        "interpretation": (
            "Diagnostic only. The historical spiral_tau is a 4x4 lateral projection. The full 8x8 coupled matrix can have a different sign. "
            "These are trim-local eigenvalues, not a validated hands-off flight result; Cnb is derived from estimated tail geometry and most lateral derivatives remain borrowed."
        ),
        "rows": [analyze_row(row) for row in data["rows"]],
    }
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"wrote {args.output}")


if __name__ == "__main__":
    main()
