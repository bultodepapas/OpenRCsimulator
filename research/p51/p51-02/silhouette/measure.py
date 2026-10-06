#!/usr/bin/env python3
"""P51-02b: measure the P-51D from the public-domain AN 01-60-3 three-view by filled silhouettes.

Reads picks.json (crop boxes, exclusions, printed dimensions), writes metrology.json (full-size metres in the model
frame: z aft from the wing leading edge extrapolated to the centreline, y up from the fuselage reference line, x right)
and diagnostic overlays into --output (PNG, local review only). Nothing here touches the app; build_geometry.py reads
metrology.json for the measured groups.

    python3 research/p51/p51-02/silhouette/measure.py --output /tmp/p51-sil
    python3 research/p51/p51-02/silhouette/measure.py --check      # metrology.json up to date
"""
import argparse
import hashlib
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
IN = 0.0254
picks = json.loads((HERE / "picks.json").read_text())
DIM = picks["printed_dimensions_in"]


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def silhouette(dark, box, exclude, close_radius=3, open_radius=4):
    x0, y0, x1, y1 = box
    d = dark[y0:y1, x0:x1]
    d = ndi.binary_closing(d, structure=np.ones((2 * close_radius + 1,) * 2), border_value=0)
    lab, _ = ndi.label(~d)
    border = set(np.unique(np.r_[lab[0], lab[-1], lab[:, 0], lab[:, -1]])) - {0}
    inside = ~np.isin(lab, list(border))
    inside = ndi.binary_opening(inside, structure=np.ones((2 * open_radius + 1,) * 2))
    for ex in exclude:
        inside[max(ex[1] - y0, 0):ex[3] - y0, max(ex[0] - x0, 0):ex[2] - x0] = False
    lab2, n2 = ndi.label(inside)
    sizes = ndi.sum(inside, lab2, range(1, n2 + 1))
    body = lab2 == 1 + int(np.argmax(sizes))
    # The fill reaches the outer edge of the ~3 px ink line; the drawn outline is its centre: pull back 2 px.
    return ndi.binary_erosion(body, structure=np.ones((5, 5)), border_value=0)


def runs(mask_1d):
    """[(start, end_exclusive), ...] of True runs."""
    out, start = [], None
    for i, v in enumerate(mask_1d):
        if v and start is None:
            start = i
        if not v and start is not None:
            out.append((start, i))
            start = None
    if start is not None:
        out.append((start, len(mask_1d)))
    return out


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    drawing = ROOT / picks["drawing"]
    im = np.asarray(Image.open(drawing)).astype(np.uint8)
    dark = im < 140
    log = {}
    diag = {}

    # --- side view -------------------------------------------------------------------------------------------------
    v = picks["views"]["side"]
    S = silhouette(dark, v["box"], v["exclude"])
    bx, by = v["box"][0], v["box"][1]
    cols = np.where(S.any(axis=0))[0]
    x_nose, x_tail = cols.min(), cols.max()
    sx = (x_tail - x_nose) / DIM["length"]  # px per inch, horizontal
    # Fuselage reference line: the long horizontal dash-dot line near the hint row (most dark pixels in a +-8 row band).
    hint = v["frl_row_hint"] - by
    band = dark[by + hint - 8:by + hint + 9, bx:v["box"][2]].sum(axis=1)
    frl = hint - 8 + int(np.argmax(band))
    rows = np.where(S.any(axis=1))[0]
    fin_top = rows.min()
    sy = (frl - fin_top) / DIM["fin_top_above_frl"]  # px per inch, vertical
    log["side"] = {"px_per_in_x": sx, "px_per_in_y": sy, "anisotropy": sy / sx, "frl_row": frl + by, "x_nose": int(x_nose + bx), "x_tail": int(x_tail + bx)}
    # Top and bottom contours per column (inches from the spinner tip, inches above the FRL).
    top, bottom = [], []
    for x in range(x_nose, x_tail + 1):
        r = runs(S[:, x])
        if not r:
            continue
        z_in = (x - x_nose) / sx
        top.append((z_in, (frl - r[0][0]) / sy))
        bottom.append((z_in, (frl - (r[-1][1] - 1)) / sy))
    top, bottom = np.array(top), np.array(bottom)
    # Spinner: the thrust-line centre at the nose and the spinner back (where the top contour stops being a cone).
    spinner_axis_in = float(np.mean([(t[1] + b[1]) / 2 for t, b in zip(top[:8], bottom[:8])]))
    log["side"]["spinner_axis_above_frl_in"] = spinner_axis_in
    k_sp = int(np.argmin(np.abs(top[:, 0] - DIM["spinner_tip_to_prop_plane"])))
    log["side"]["spinner_radius_at_prop_plane_in"] = float((top[k_sp, 1] - bottom[k_sp, 1]) / 2)
    # Chord plane at the root from the front view is attached below; the side view gives the wing reference line: 26.5 in below the FRL (printed).
    diag["side"] = (S, bx, by, x_nose, frl, sx, sy)

    # --- top view --------------------------------------------------------------------------------------------------
    v = picks["views"]["top"]
    T = silhouette(dark, v["box"], v["exclude"])
    tbx, tby = v["box"][0], v["box"][1]
    tcols = np.where(T.any(axis=0))[0]
    tx = (tcols.max() - tcols.min()) / DIM["span"]
    trows = np.where(T.any(axis=1))[0]
    y_tail, y_nose = trows.min(), trows.max()  # nose at the bottom of the plan view
    ty = (y_nose - y_tail) / DIM["length"]
    # Symmetry axis: mean of left/right extremes over the fuselage rows between the wing and the stab.
    centres = []
    for y in range(y_tail, y_nose + 1):
        r = runs(T[y])
        if r:
            centres.append((r[0][0] + r[-1][1] - 1) / 2)
    xc = float(np.median(centres))
    log["top"] = {"px_per_in_x": tx, "px_per_in_y": ty, "anisotropy": ty / tx, "centre_col": xc + tbx, "y_nose": int(y_nose + tby), "y_tail": int(y_tail + tby)}
    # Per row: outline half-width at the row (fuselage where no wing/stab), and the full extent (wing/stab planform).
    plan = []
    for y in range(y_tail, y_nose + 1):
        r = runs(T[y])
        if not r:
            continue
        z_in = (y_nose - y) / ty
        # the run containing the centre is the fuselage (or fuselage + wing where the wing is attached)
        centre_run = next((a for a in r if a[0] <= xc <= a[1]), None)
        if centre_run is None:
            continue
        half_in = (centre_run[1] - 1 - centre_run[0]) / 2 / tx
        right_extent = (r[-1][1] - 1 - xc) / tx
        plan.append((z_in, half_in, right_extent))
    plan = np.array(plan)
    diag["top"] = (T, tbx, tby, xc, y_nose, tx, ty)

    # --- front view (left half) -----------------------------------------------------------------------------------
    v = picks["views"]["front"]
    F = silhouette(dark, v["box"], v["exclude"])
    fbx, fby = v["box"][0], v["box"][1]
    fcols = np.where(F.any(axis=0))[0]
    # the spinner centre column: the row with the fuselage (not the wing) ... use the top view centre scaled instead
    x_tip_left = fcols.min()
    # symmetry: the fuselage/spinner top point is the highest silhouette pixel of the centre body
    frows = np.where(F.any(axis=1))[0]
    # Horizontal scale from the left tip to the symmetry axis (the spinner's column, top of the silhouette).
    top_row = frows.min()
    # The three views share the symmetry column in the drawing (front under the side view, above the plan): the plan
    # view's centre is the robust one (the front view's topmost pixel is a propeller blade tip, not the spinner).
    xc_f = xc + tbx - fbx
    fx = (xc_f - x_tip_left) / (DIM["span"] / 2)
    # Wing chord-plane height along the span: mid of the wing run per column, outboard of the fuselage/scoop (|x| > 50 in)
    # and inboard of the tip rounding; the FRL row is the spinner axis row minus its printed/measured offset.
    mids = []
    for x in range(int(xc_f - 200 * fx), int(xc_f - 90 * fx), int(2 * fx)):  # outboard of the drop tank (hangs at ~65 in)
        r = runs(F[:, x])
        if not r:
            continue
        a = max(r, key=lambda q: q[1] - q[0])
        mids.append(((xc_f - x) / fx, (a[0] + a[1] - 1) / 2))
    mids = np.array(mids)
    fit = np.polyfit(mids[:, 0], mids[:, 1], 1)  # row = fit[0] * span_in + fit[1]
    fy_guess = fx  # vertical scale: assume the view is isotropic (checked by the dihedral below)
    dihedral_meas = float(np.degrees(np.arctan(-fit[0] / fy_guess)))
    # Spinner centre row: the widest rows of the spinner body near the top of the silhouette are ambiguous with the
    # blades; use the FRL from the side view: the spinner axis is spinner_axis_in above the FRL.
    spinner_rows = [y for y in range(top_row, top_row + int(40 * fx)) if F[y, int(xc_f)]]
    row_axis = top_row + int(26.0 * fx)  # spinner radius ~26 in (printed spinner dia not given; measured from the side view below)
    log["front"] = {"x_left_tip": int(x_tip_left + fbx), "centre_col": xc_f + fbx, "px_per_in_x": fx, "dihedral_fit_deg": dihedral_meas,
                    "chord_plane_row_at_centreline": float(fit[1]) + fby, "top_row": int(top_row + fby)}
    diag["front"] = (F, fbx, fby)

    # --- Wing leading/trailing edges from the plan view -----------------------------------------------------------
    # Rows whose right extent is beyond the fuselage are wing or stab; the wing is the big block.
    # z_in is inches aft of the spinner tip; in the plan image the nose is at the bottom, so a column run's high-index
    # end is its leading edge. Scan columns from the fuselage side to the tip.
    le_pts, te_pts = [], []
    for x in range(int(xc) + int(20 * tx), tcols.max() - int(2 * tx), int(2 * tx)):
        r = runs(T[:, x])
        # the wing run is the longest run in the lower half (nose side) of the image
        # wing runs: nose-side end within 150 in of the spinner tip and at least 20 in long (the stab is beyond 300 in)
        cand = [a for a in r if (y_nose - (a[1] - 1)) / ty < 150 and (a[1] - a[0]) / ty > 20]
        if not cand:
            continue
        a = max(cand, key=lambda q: q[1] - q[0])
        span_in = (x - xc) / tx
        le_pts.append((span_in, (y_nose - (a[1] - 1)) / ty))
        te_pts.append((span_in, (y_nose - a[0]) / ty))
    le_pts, te_pts = np.array(le_pts), np.array(te_pts)
    # Straight LE/TE fit outboard of the root extension (60 in to 200 in from the centreline).
    sel = (le_pts[:, 0] > 60) & (le_pts[:, 0] < 200)
    le_fit = np.polyfit(le_pts[sel, 0], le_pts[sel, 1], 1)
    te_fit = np.polyfit(te_pts[sel, 0], te_pts[sel, 1], 1)
    le_root_in = np.polyval(le_fit, 0.0)  # inches aft of the spinner tip, LE extrapolated to the centreline
    semi_in = DIM["span"] / 2
    root_chord_in = np.polyval(te_fit, 0.0) - le_root_in
    tip_chord_in = np.polyval(te_fit, semi_in) - np.polyval(le_fit, semi_in)
    le_tip_in = np.polyval(le_fit, semi_in) - le_root_in
    log["wing"] = {"le_root_from_spinner_tip_in": le_root_in, "root_chord_in": root_chord_in, "tip_chord_in": tip_chord_in, "le_sweep_at_tip_in": le_tip_in,
                   "le_slope_in_per_in": le_fit[0], "te_slope_in_per_in": te_fit[0], "fit_residual_le_in": float(np.std(np.polyval(le_fit, le_pts[sel, 0]) - le_pts[sel, 1]))}
    # Root leading-edge extension (the D's "kink"): LE inboard of 60 in vs the straight line.
    inboard = le_pts[le_pts[:, 0] < 60]
    log["wing"]["root_extension_in"] = [[float(s), float(np.polyval(le_fit, s) - z)] for s, z in inboard]
    # Ailerons/flaps are not separable in the silhouette.

    # --- Stab from the plan view ---------------------------------------------------------------------------------
    stab_le_pts, stab_te_pts = [], []
    for x in range(int(xc) + int(6 * tx), tcols.max(), int(2 * tx)):
        r = runs(T[:, x])
        cand = [a for a in r if (y_nose - (a[1] - 1)) / ty > 300 and (a[1] - a[0]) / ty > 10]
        if not cand:
            continue
        a = max(cand, key=lambda q: q[1] - q[0])
        span_in = (x - xc) / tx
        stab_le_pts.append((span_in, (y_nose - (a[1] - 1)) / ty))
        stab_te_pts.append((span_in, (y_nose - a[0]) / ty))
    stab_le_pts, stab_te_pts = np.array(stab_le_pts), np.array(stab_te_pts)
    # Tip: the outermost sampled column whose chord is still >= 30 % of the inboard chord (+1 in to the rounded end);
    # thinner runs further out are tip remnants or dimension lines and depend on the 2 in sampling grid.
    chords = stab_te_pts[:, 1] - stab_le_pts[:, 1]
    ref_chord = float(np.median(chords[stab_le_pts[:, 0] < 30]))
    keep = chords >= 0.3 * ref_chord
    stab_le_pts, stab_te_pts = stab_le_pts[keep], stab_te_pts[keep]
    stab_half_in = stab_le_pts[:, 0].max() + 1.0
    ssel = (stab_le_pts[:, 0] > 12) & (stab_le_pts[:, 0] < stab_half_in - 6)
    sle = np.polyfit(stab_le_pts[ssel, 0], stab_le_pts[ssel, 1], 1)
    ste = np.polyfit(stab_te_pts[ssel, 0], stab_te_pts[ssel, 1], 1)
    log["stab"] = {"half_span_in": stab_half_in, "measured_span_vs_printed": 2 * stab_half_in / DIM["stab_span"],
                   "root_le_from_spinner_tip_in": float(np.polyval(sle, 0)), "root_chord_in": float(np.polyval(ste, 0) - np.polyval(sle, 0)),
                   "tip_le_from_spinner_tip_in": float(np.polyval(sle, stab_half_in)), "tip_chord_in": float(np.polyval(ste, stab_half_in) - np.polyval(sle, stab_half_in))}

    # --- Assemble metrology in the model frame (metres; z aft from the centreline LE, y above the FRL) ------------
    z0 = le_root_in  # inches from the spinner tip
    zm = lambda z_in: (z_in - z0) * IN
    # Fuselage top/bottom at 2 in steps along the side view, canopy included (tagged separately below).
    stations = []
    for z_in in np.arange(0.0, DIM["length"], 2.0):
        i = int(np.argmin(np.abs(top[:, 0] - z_in)))
        j = int(np.argmin(np.abs(bottom[:, 0] - z_in)))
        k = int(np.argmin(np.abs(plan[:, 0] - z_in))) if len(plan) else None
        stations.append({"z": round(zm(z_in), 4), "top": round(top[i, 1] * IN, 4), "bottom": round(bottom[j, 1] * IN, 4),
                         "half_width": round(float(plan[k, 1] * IN), 4) if k is not None and abs(plan[k, 0] - z_in) < 1.5 else None})
    sp_r_px = log["side"]["spinner_radius_at_prop_plane_in"] * log["front"]["px_per_in_x"]
    frl_row_front = log["front"]["top_row"] + sp_r_px + spinner_axis_in * log["front"]["px_per_in_x"]
    chord_plane_root_in = (frl_row_front - log["front"]["chord_plane_row_at_centreline"]) / log["front"]["px_per_in_x"]
    log["front"]["chord_plane_root_above_frl_in"] = float(chord_plane_root_in)
    # --- V01: tail outlines (side) and stab planform (plan), full-size metres in the model frame -------------------
    tail_z_m = zm(DIM["length"])
    upper, lower = [], []
    for z_in in np.arange(4.7 / IN + z0, DIM["length"] - 0.01, 1.5):  # from aft of the antenna mast
        i = int(np.argmin(np.abs(top[:, 0] - z_in)))
        upper.append([round(zm(z_in), 4), round(top[i, 1] * IN, 4)])
    for z_in in np.arange(6.1 / IN + z0, DIM["length"] - 0.01, 1.5):
        j = int(np.argmin(np.abs(bottom[:, 0] - z_in)))
        lower.append([round(zm(z_in), 4), round(bottom[j, 1] * IN, 4)])
    stab_le = [[round(sp * IN, 4), round(zm(zz), 4)] for sp, zz in stab_le_pts if sp > 4.0]
    stab_te = [[round(sp * IN, 4), round(zm(zz), 4)] for sp, zz in stab_te_pts if sp > 4.0]
    metrology = {
        "format": "openrc-metrology v1",
        "drawing": picks["drawing"], "drawing_sha256": sha(drawing), "picks_sha256": sha(HERE / "picks.json"),
        "frame": "full-size metres; z aft from the wing leading edge extrapolated to the centreline (straight outboard LE), y up from the fuselage reference line (FRL), x right",
        "calibration": log,
        "reserved_checks": {},
        "spinner": {"tip_z": round(zm(0.0), 4), "axis_y": round(spinner_axis_in * IN, 4)},
        "length_m": round(DIM["length"] * IN, 4),
        "profile_2in": stations,
        "wing": {"le_z_root": 0.0, "le_z_tip": round(le_tip_in * IN, 4), "root_chord": round(root_chord_in * IN, 4), "tip_chord": round(tip_chord_in * IN, 4),
                 "semi_span": round(semi_in * IN, 4), "root_extension": [[round(s * IN, 4), round(d * IN, 4)] for s, d in log["wing"]["root_extension_in"]]},
        "stab": {"half_span": round(stab_half_in * IN, 4), "root_le_z": round(zm(log["stab"]["root_le_from_spinner_tip_in"]), 4), "root_chord": round(log["stab"]["root_chord_in"] * IN, 4),
                 "tip_le_z": round(zm(log["stab"]["tip_le_from_spinner_tip_in"]), 4), "tip_chord": round(log["stab"]["tip_chord_in"] * IN, 4)},
        "fin": {"top_y": round(DIM["fin_top_above_frl"] * IN, 4)},
        "tail_outlines": {"upper": upper, "lower": lower, "stab_le": stab_le, "stab_te": stab_te,
                          "note": "upper: top contour of the side silhouette from the dorsal start to the rudder TE (dorsal fillet, fin LE, cap, rudder TE); lower: tail-cone/rudder bottom aft of the tail wheel; stab_le/te: plan-view planform [x from centreline, z], 2 in steps; the vertical axis of the side view is ~3 % short (not corrected)"},
        "front": {"dihedral_deg_fit": round(log["front"]["dihedral_fit_deg"], 2), "chord_plane_y_root": round(chord_plane_root_in * IN, 4)},
    }
    metrology["reserved_checks"]["dihedral"] = {"measured_deg": log["front"]["dihedral_fit_deg"], "printed_deg": DIM["dihedral_deg"]}
    metrology["reserved_checks"]["wing_ref_line"] = {"chord_plane_root_below_frl_in": -chord_plane_root_in, "printed_wing_ref_below_frl_in": DIM["wing_ref_below_frl"], "note": "the wing reference line is a datum of the airfoil, not necessarily the chord-plane mid-height"}
    # Reserved checks against printed dimensions not used for calibration.
    metrology["reserved_checks"]["stab_span"] = {"measured_in": 2 * stab_half_in, "printed_in": DIM["stab_span"], "error_pct": 100 * (2 * stab_half_in / DIM["stab_span"] - 1)}
    wing_area_in2 = DIM["span"] * (root_chord_in + tip_chord_in) / 2
    metrology["reserved_checks"]["trapezoid_area"] = {"measured_ft2": wing_area_in2 / 144, "published_ft2": 235.0, "error_pct": 100 * (wing_area_in2 / 144 / 235.0 - 1)}
    mac_in = 2 / 3 * root_chord_in * (1 + (tip_chord_in / root_chord_in) + (tip_chord_in / root_chord_in) ** 2) / (1 + tip_chord_in / root_chord_in)
    metrology["reserved_checks"]["mac"] = {"measured_in": mac_in, "printed_in": DIM["mac"], "error_pct": 100 * (mac_in / DIM["mac"] - 1)}
    text = json.dumps(metrology, indent=2) + "\n"
    target = HERE / "metrology.json"
    if args.check:
        if not target.exists() or target.read_text() != text:
            sys.exit("stale metrology.json: run measure.py")
        print("metrology.json is up to date")
        return
    target.write_text(text)
    print(json.dumps(log, indent=1, default=float))
    print(json.dumps(metrology["reserved_checks"], indent=1))
    if args.output:
        args.output.mkdir(parents=True, exist_ok=True)
        for name, (M, bx_, by_, *_rest) in diag.items():
            crop = im[by_:by_ + M.shape[0], bx_:bx_ + M.shape[1]]
            rgb = np.stack([crop] * 3, -1).copy()
            rgb[M] = (rgb[M] * 0.5 + np.array([255, 80, 80]) * 0.5).astype(np.uint8)
            Image.fromarray(rgb).save(args.output / f"silhouette_{name}.png")
        print("diagnostics in", args.output)


if __name__ == "__main__":
    main()
