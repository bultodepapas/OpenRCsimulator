"""Coupled eigenvalues of the full Jacobians written by handling.gd (AC-12 research).

physics/flight_modes.gd reports 4x4 block projections, which drop the longitudinal-lateral
coupling of the propeller. This reducer solves the full 9-state matrix (u, v, w, p, q, r,
roll, pitch, downwash lag) with NumPy. Usage: python -I eigenvalues.py <dir>/jacobians.json
"""
import json
import sys

import numpy as np


def main() -> int:
    data = json.load(open(sys.argv[1], encoding="utf-8"))
    for name, entry in data.items():
        matrix = np.array(entry["jacobian"], dtype=float)
        parts = []
        for value in sorted(np.linalg.eigvals(matrix), key=lambda z: (-abs(z.imag), z.real)):
            if value.imag > 1e-7:
                natural = abs(value)
                parts.append("%.4f Hz zeta %.3f" % (natural / (2.0 * np.pi), -value.real / natural))
            elif abs(value.imag) <= 1e-7:
                parts.append("real %+.4f 1/s" % value.real)
        print("%s (n=%d, %.2f m/s): %s" % (name, matrix.shape[0], entry["speed"], "; ".join(parts)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
