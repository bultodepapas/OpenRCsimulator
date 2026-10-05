"""Flight modes of the simulator, linearized at level trim (plan review #3, 2026-10-05).

Runs modes.gd on the REAL simulation equations (aero + propulsion + rigid body, controls and rpm frozen
at trim), then prints eigenvalues: short period, phugoid, roll subsidence, dutch roll, spiral.
Usage (repo root): python3 research/flight-modes/modes.py [speeds...]   Needs numpy and app/get-godot.sh.
"""
import math, os, subprocess, sys
import numpy as np

root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
godot = subprocess.run([os.path.join(root, "app/get-godot.sh")], capture_output=True, text=True, check=True).stdout.strip()
script = os.path.join(root, "research/flight-modes/modes.gd")

def describe(ev):
    out = []
    for e in sorted(ev, key=lambda z: -abs(z)):
        if abs(e.imag) > 1e-9:
            if e.imag > 0:
                wn = abs(e)
                out.append(f"osc {wn / (2 * math.pi):.2f} Hz, zeta {-e.real / wn:.2f}")
        elif e.real < 0:
            out.append(f"real tau {-1 / e.real:.2f} s")
        else:
            out.append(f"real UNSTABLE, doubles in {math.log(2) / e.real:.1f} s")
    return " | ".join(out)

for V in (sys.argv[1:] or ["10", "15", "25"]):
    run = subprocess.run([godot, "--headless", "--path", os.path.join(root, "app"), "--audio-driver", "Dummy", "--script", script],
                         capture_output=True, text=True, timeout=60, env={**os.environ, "V": V})
    lines = run.stdout.splitlines()
    cols = [list(map(float, l[4:].split(","))) for l in lines if l.startswith("COL ")]
    if len(cols) != 8:
        sys.exit(f"modes.gd failed at V={V}:\n{run.stdout}\n{run.stderr}")
    A = np.array(cols).T  # x = [u, v, w, p, q, r, phi, theta]
    print(next(l for l in lines if l.startswith("# trim")))
    print("  longitudinal [u w q theta]:", describe(np.linalg.eigvals(A[np.ix_([0, 2, 4, 7], [0, 2, 4, 7])])))
    print("  lateral      [v p r phi]:  ", describe(np.linalg.eigvals(A[np.ix_([1, 3, 5, 6], [1, 3, 5, 6])])))
