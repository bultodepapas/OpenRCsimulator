#!/usr/bin/env python3
"""D8b-R2d analog evidence: digitize the NASA FASER (Hangar 9 Ultra Stick 120) wind-tunnel lift curve and compare its
post-stall retention with the Ugly Stik's legacy blend and the D8b-R2 synthetic candidates.

Usage (repository root):
  python3 -I research/flight-robustness/d8b-r2/analog/faser_cl.py [--pdf references/rc-aero-data/faser-2006-aiaa-2006-3306-owens-cox-morelli.pdf]

Source: Owens, Cox, Morelli, AIAA 2006-3306, Fig. 2a (whole aircraft, static, q = 2 psf), page 3. The PDF is a local-only
reference; its SHA-256 must match docs/research/flight-dynamics/rc-aero-data-sources.json. The page is rendered at 400 dpi
with pdftoppm; the axes are calibrated from the alpha = 0 axis and the right frame (alpha 30 deg) and from the CL = 0 line
and the top frame (CL 1.0); the blue curve's centre is the median of its pixels within +/-0.3 deg of each integer angle.
Calibration uncertainty is about +/-0.2 deg and +/-0.015 CL. Writes faser_cl.csv beside this script and prints the
retention table CL(alpha)/CLmax against docs/research/flight-robustness/D8b-R2/implementation/candidate-screen.json.
An analog airframe at its own Reynolds number: a bound on shape, not a Jensen measurement.
"""
import argparse
import csv
import hashlib
import json
import statistics
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
MANIFEST = ROOT / "docs/research/flight-dynamics/rc-aero-data-sources.json"
SCREEN = ROOT / "docs/research/flight-robustness/D8b-R2/implementation/candidate-screen.json"
PDF = "references/rc-aero-data/faser-2006-aiaa-2006-3306-owens-cox-morelli.pdf"
DPI = 400
ANGLES = range(-4, 31)
COMPARE = (14, 15, 16, 17, 18, 20, 22, 25, 28, 30)


def dark(c):
    return c[0] < 80 and c[1] < 80 and c[2] < 80


def blue(c):
    return c[2] > 150 and c[0] < 140 and c[2] - c[0] > 50


def lines(px, x0, x1, y0, y1, vertical):
    """Centres of runs of nearly full-length dark lines inside the box."""
    span = (y1 - y0) if vertical else (x1 - x0)
    hits = []
    for k in range(x0, x1) if vertical else range(y0, y1):
        count = sum(dark(px[k, j]) for j in range(y0, y1)) if vertical else sum(dark(px[j, k]) for j in range(x0, x1))
        if count > 0.6 * span:
            hits.append(k)
    groups, run = [], []
    for k in hits:
        if run and k - run[-1] > 1:
            groups.append(sum(run) / len(run))
            run = []
        run.append(k)
    if run:
        groups.append(sum(run) / len(run))
    return groups


def digitize(pdf):
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run(["pdftoppm", "-f", "3", "-l", "3", "-r", str(DPI), "-png", str(pdf), f"{tmp}/p"], check=True,
                       stderr=subprocess.DEVNULL)
        image = Image.open(next(Path(tmp).glob("p*.png"))).convert("RGB")
    px = image.load()
    w, h = image.size
    # Search box around the CL panel of Fig. 2a (page fractions); the frame and axis lines inside it set the calibration.
    x0, x1, y0, y1 = int(0.195 * w), int(0.48 * w), int(0.32 * h), int(0.545 * h)
    v = lines(px, x0, x1, y0, y1, True)   # left frame, alpha-0 axis, right frame
    hz = lines(px, x0, x1, y0, y1, False)  # top frame, CL-0 line, bottom frame
    if len(v) != 3 or len(hz) != 3:
        sys.exit(f"axis detection failed: vertical {v}, horizontal {hz}")
    x_axis, x_right = v[1], v[2]
    y_top, y_zero = hz[0], hz[1]
    sx, sy = (x_right - x_axis) / 30.0, (y_zero - y_top) / 1.0
    points = []
    for x in range(int(v[0]) + 4, int(x_right) - 3):
        ys = [y for y in range(int(y_top) + 4, int(hz[2]) - 3) if blue(px[x, y])]
        if ys:
            points.append(((x - x_axis) / sx, (y_zero - statistics.median(ys)) / sy))
    rows = []
    for a in ANGLES:
        near = [cl for alpha, cl in points if abs(alpha - a) <= 0.3]
        if near:
            rows.append((a, statistics.median(near), len(near)))
    return rows, {"x_axis_px": x_axis, "x_right_px": x_right, "y_top_px": y_top, "y_zero_px": y_zero}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--pdf", default=PDF)
    args = parser.parse_args()
    pdf = ROOT / args.pdf
    digest = hashlib.sha256(pdf.read_bytes()).hexdigest()
    expected = {f["path"]: f["sha256"] for f in json.loads(MANIFEST.read_text())["files"]}.get(PDF)
    if digest != expected:
        sys.exit(f"{pdf}: SHA-256 {digest} does not match the manifest ({expected})")
    rows, calibration = digitize(pdf)
    out = HERE / "faser_cl.csv"
    with out.open("w", newline="\n") as fh:
        fh.write(f"# NASA FASER (Ultra Stick 120) whole-aircraft CL, Owens, Cox, Morelli AIAA 2006-3306 Fig. 2a; pdf sha256 {digest}\n")
        fh.write(f"# digitized by faser_cl.py at {DPI} dpi; calibration px {json.dumps(calibration)}; uncertainty about +/-0.2 deg, +/-0.015 CL\n")
        writer = csv.writer(fh, lineterminator="\n")
        writer.writerow(["alpha_deg", "cl", "pixels"])
        for a, cl, n in rows:
            writer.writerow([a, f"{cl:.3f}", n])
    faser = {a: cl for a, cl, _ in rows}
    peak_alpha = max(faser, key=faser.get)
    peak = faser[peak_alpha]
    slope = (faser[10] - faser[0]) / 10.0
    print(f"FASER: CL(0) {faser[0]:.3f}, slope 0-10 deg {slope:.4f}/deg, CLmax {peak:.3f} at {peak_alpha} deg; wrote {out.relative_to(ROOT)}")
    screen = json.loads(SCREEN.read_text())
    curves = {"FASER (measured, analog)": (faser, peak)}
    for m in screen["models"]:
        table = {round(r["alpha_deg"], 1): r["total_cl"] for r in m["rows"]}
        curves[f"Stik {m['name']}"] = ({a: table[float(a)] for a in COMPARE}, m["maximum_cl"])
    print("| Polar | CLmax | " + " | ".join(f"{a}°" for a in COMPARE) + " |")
    print("| --- | --- | " + " | ".join("---" for _ in COMPARE) + " |")
    for name, (curve, cmax) in curves.items():
        print(f"| {name} | {cmax:.3f} | " + " | ".join(f"{curve[a] / cmax:.2f}" for a in COMPARE) + " |")
    print("Cells are CL(alpha)/CLmax; the Stik rows are whole-aircraft totals from candidate-screen.json (25 m/s, controls neutral).")


if __name__ == "__main__":
    main()
