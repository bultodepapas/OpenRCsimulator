#!/usr/bin/env python3
"""D8b-R2d analog evidence: digitize the NASA FASER (Hangar 9 Ultra Stick 120) wind-tunnel lift curve and roll damping,
and the static lateral derivatives Clbeta and Cnbeta (Fig. 2b, written for D10-R5), and compare the lift curve's
post-stall retention with the Ugly Stik's legacy blend and the D8b-R2 synthetic candidates.

Usage (repository root):
  python3 -I research/flight-robustness/d8b-r2/analog/faser_cl.py [--pdf references/rc-aero-data/faser-2006-aiaa-2006-3306-owens-cox-morelli.pdf]

Source: Owens, Cox, Morelli, AIAA 2006-3306, Fig. 2a (whole aircraft, static, q = 2 psf), page 3. The PDF is a local-only
reference; its SHA-256 must match docs/research/flight-dynamics/rc-aero-data-sources.json. The page is rendered at 400 dpi
with pdftoppm; the axes are calibrated from the alpha = 0 axis and the right frame (alpha 30 deg) and from the CL = 0 line
and the top frame (CL 1.0); the blue curve's centre is the median of its pixels within +/-0.3 deg of each integer angle.
Calibration uncertainty is about +/-0.2 deg and +/-0.015 CL. Writes faser_cl.csv beside this script and prints the
retention table CL(alpha)/CLmax against docs/research/flight-robustness/D8b-R2/implementation/candidate-screen.json.
Roll damping: Hoe, Owens, Denham, AIAA 2012-4645, Fig. 14 (left), forced oscillation, single-point method, page 9. The
panel's dotted grid (10 deg, 0.1) calibrates both axes; the blue polyline is sampled at the listed angles (median of its
pixels in a 5-pixel column); about +/-0.3 deg and +/-0.01. Writes faser_clp.csv.
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
PDF_FO = "references/rc-aero-data/faser-2012-aiaa-2012-4645-forced-oscillation.pdf"
CLP_ANGLES = (-5, 0, 5, 10, 12, 13.5, 15, 16, 17.5, 19, 20, 22.5, 25, 27.5, 30, 32.5, 35, 37.5, 40)
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


def render(pdf, page):
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run(["pdftoppm", "-f", str(page), "-l", str(page), "-r", str(DPI), "-png", str(pdf), f"{tmp}/p"],
                       check=True, stderr=subprocess.DEVNULL)
        return Image.open(next(Path(tmp).glob("p*.png"))).convert("RGB")


def digitize_panel(image, box, top_value, angles=ANGLES):
    """One Fig. 2 panel: its frame and zero/axis lines set the calibration (alpha 0 axis to the right frame at 30 deg,
    zero line to the top frame at top_value); the blue curve's centre is the median of its pixels within +/-0.3 deg."""
    px = image.load()
    w, h = image.size
    x0, x1, y0, y1 = int(box[0] * w), int(box[1] * w), int(box[2] * h), int(box[3] * h)
    v = lines(px, x0, x1, y0, y1, True)   # left frame, alpha-0 axis, right frame
    hz = lines(px, x0, x1, y0, y1, False)  # top frame, zero line, bottom frame
    if len(v) != 3 or len(hz) != 3:
        sys.exit(f"axis detection failed in {box}: vertical {v}, horizontal {hz}")
    x_axis, x_right = v[1], v[2]
    y_top, y_zero = hz[0], hz[1]
    sx, sy = (x_right - x_axis) / 30.0, (y_zero - y_top) / top_value
    points = []
    for x in range(int(v[0]) + 4, int(x_right) - 3):
        ys = [y for y in range(int(y_top) + 4, int(hz[2]) - 3) if blue(px[x, y])]
        if ys:
            points.append(((x - x_axis) / sx, (y_zero - statistics.median(ys)) / sy))
    rows = []
    for a in angles:
        near = [value for alpha, value in points if abs(alpha - a) <= 0.3]
        if near:
            rows.append((a, statistics.median(near), len(near)))
    return rows, {"x_axis_px": x_axis, "x_right_px": x_right, "y_top_px": y_top, "y_zero_px": y_zero}


def digitize(pdf):
    # Search box around the CL panel of Fig. 2a (page fractions).
    return digitize_panel(render(pdf, 3), (0.195, 0.48, 0.32, 0.545), 1.0)


def grid(counts, spacing, minimum):
    """Peaks of a gray/dark count profile on a regular grid of about `spacing` pixels; lines hidden by the legend or the
    curve leave gaps. Returns (pixel, index) pairs, index counted in grid steps from the first line."""
    peaks = []
    limit = 0.25 * max(counts)
    for i in range(1, len(counts) - 1):
        if counts[i] >= limit and counts[i] >= counts[i - 1] and counts[i] >= counts[i + 1]:
            if peaks and i - peaks[-1] <= 8:
                if counts[i] > counts[peaks[-1]]:
                    peaks[-1] = i
            else:
                peaks.append(i)
    best = []
    for start in peaks:
        chain = [(start, 0)]
        for p in peaks:
            if p <= start:
                continue
            steps = round((p - start) / spacing)
            if steps >= 1 and abs((p - start) - steps * spacing) < 0.04 * spacing * steps and steps > chain[-1][1]:
                chain.append((p, steps))
        if len(chain) > len(best):
            best = chain
    if len(best) < minimum:
        sys.exit(f"grid detection failed: {peaks}")
    return best


def digitize_clp(pdf):
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run(["pdftoppm", "-f", "9", "-l", "9", "-r", str(DPI), "-png", str(pdf), f"{tmp}/p"], check=True,
                       stderr=subprocess.DEVNULL)
        image = Image.open(next(Path(tmp).glob("p*.png"))).convert("RGB")
    w, h = image.size
    panel = image.crop((int(0.2085 * w), int(0.6157 * h), int(0.4865 * w), int(0.785 * h)))
    px = panel.load()
    pw, ph = panel.size
    gray = lambda c: (120 < c[0] < 215 and abs(c[0] - c[1]) < 12 and abs(c[1] - c[2]) < 12) or max(c) < 110
    columns = grid([sum(gray(px[x, y]) for y in range(ph)) for x in range(pw)], 161.0, 5)
    rows = grid([sum(gray(px[x, y]) for x in range(pw)) for y in range(ph)], 66.6, 8)
    # Columns are alpha -10..40 every 10 deg from the left frame; rows are 0.5 (top frame) down to -0.5 in 0.1 steps.
    if columns[-1][1] != 5 or rows[-1][1] != 10:
        sys.exit(f"unexpected grid: columns {columns}, rows {rows}")
    x0, dx = columns[0][0], (columns[-1][0] - columns[0][0]) / columns[-1][1]
    y0, dy = rows[0][0], (rows[-1][0] - rows[0][0]) / rows[-1][1]
    blue = lambda c: c[2] > 140 and c[0] < 110 and c[1] < 130 and c[2] - c[0] > 60
    out = []
    for a in CLP_ANGLES:
        x = int(round(x0 + (a + 10.0) / 10.0 * dx))
        ys = [y for xx in range(x - 2, x + 3) for y in range(ph) if 0 <= xx < pw and blue(px[xx, y])
              and not (y < y0 + 4.5 * dy and x < x0 + 3.5 * dx)]  # skip the legend box
        if ys:
            out.append((a, 0.5 - (statistics.median(ys) - y0) / dy * 0.1))
    return out, {"columns_px": columns, "rows_px": rows}


def check_sha(path, key):
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    expected = {f["path"]: f["sha256"] for f in json.loads(MANIFEST.read_text())["files"]}.get(key)
    if digest != expected:
        sys.exit(f"{path}: SHA-256 {digest} does not match the manifest ({expected})")
    return digest


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--pdf", default=PDF)
    args = parser.parse_args()
    pdf = ROOT / args.pdf
    digest = check_sha(pdf, PDF)
    rows, calibration = digitize(pdf)
    # D10-R5: Fig. 2b static lateral derivatives (per degree), from beta sweeps: like-for-like with a model's dCl/dbeta.
    page = render(pdf, 3)
    for name, box, top in (("clb", (0.575, 0.86, 0.435, 0.565), 0.001), ("cnb", (0.575, 0.86, 0.565, 0.695), 0.004)):
        lateral, lateral_calibration = digitize_panel(page, box, top, range(-4, 31))
        with (HERE / f"faser_{name}.csv").open("w", newline="\n") as fh:
            fh.write(f"# NASA FASER (Ultra Stick 120) static {'Cl' if name == 'clb' else 'Cn'}beta, Owens, Cox, Morelli AIAA 2006-3306 Fig. 2b; pdf sha256 {digest}\n")
            fh.write(f"# digitized by faser_cl.py at {DPI} dpi; calibration px {json.dumps(lateral_calibration)}; per degree; uncertainty about +/-0.2 deg, +/-0.00006 per deg\n")
            writer = csv.writer(fh, lineterminator="\n")
            writer.writerow(["alpha_deg", f"{name}_per_deg", f"{name}_per_rad", "pixels"])
            for a, value, n in lateral:
                writer.writerow([a, f"{value:.6f}", f"{value * 57.29578:.4f}", n])
        print(f"FASER {name} per rad: " + ", ".join(f"{a}: {v * 57.29578:+.3f}" for a, v, _ in lateral if a % 2 == 0))
    fo_digest = check_sha(ROOT / PDF_FO, PDF_FO)
    clp, clp_calibration = digitize_clp(ROOT / PDF_FO)
    with (HERE / "faser_clp.csv").open("w", newline="\n") as fh:
        fh.write(f"# NASA FASER (Ultra Stick 120) roll damping, Hoe, Owens, Denham AIAA 2012-4645 Fig. 14 (left), forced oscillation, single-point method; pdf sha256 {fo_digest}\n")
        fh.write(f"# digitized by faser_cl.py at {DPI} dpi; grid px {json.dumps(clp_calibration)}; uncertainty about +/-0.3 deg, +/-0.01\n")
        writer = csv.writer(fh, lineterminator="\n")
        writer.writerow(["alpha_deg", "clp"])
        for a, value in clp:
            writer.writerow([a, f"{value:.3f}"])
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
    print("FASER roll damping (faser_clp.csv): " + ", ".join(f"{a:g}: {v:+.3f}" for a, v in clp))


if __name__ == "__main__":
    main()
