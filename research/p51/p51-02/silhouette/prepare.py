#!/usr/bin/env python3
"""Orthographic cameras that lay the P-51D model over the three views of the public-domain AN 01-60-3 drawing.

As in research/avanti-s/user-profile/prepare.py: two anchors per view fix a uniform scale and position (no rotation,
no anisotropic stretch, no image edit). Side: spinner tip and rudder trailing edge (printed length 387 5/16 in);
plan and front: the two wing tips (printed span 37 ft 5/16 in). Writes camera-fit.json for render.gd.
The anchor pixels come from the filled silhouettes of measure.py (outer extents), so they are reproducible.

    python3 research/p51/p51-02/silhouette/prepare.py
"""
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
import sys
sys.path.insert(0, str(HERE))
from measure import silhouette, picks  # noqa: E402

GEOMETRY = ROOT / "assets/aircraft/p51d-mustang-120/geometry.json"
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()


def main():
    g = json.loads(GEOMETRY.read_text())
    drawing = ROOT / picks["drawing"]
    im = np.asarray(Image.open(drawing)).astype(np.uint8)
    dark = im < 140
    span = g["wing"]["span"]
    tip_z = g["spinner"]["tip_z"]
    te_z = g["tail"]["rudder_te_bottom"][0]
    fin_top = g["tail"]["fin_top_y"]
    views = []
    for key, v in picks["views"].items():
        S = silhouette(dark, v["box"], v["exclude"])
        ys, xs = np.where(S)
        x0, y0 = v["box"][0], v["box"][1]
        w, h = v["box"][2] - x0, v["box"][3] - y0
        if key == "side":
            # nose = leftmost silhouette pixel (spinner tip), tail = rightmost (rudder TE); FRL = model y 0 at the row of the FRL.
            frl = picks["views"]["side"]["frl_row_hint"] - y0
            band = dark[y0 + frl - 8:y0 + frl + 9, x0:x0 + w].sum(axis=1)
            frl = frl - 8 + int(np.argmax(band))
            nose_px, tail_px = [int(xs.min()), frl], [int(xs.max()), frl]
            scale = (tail_px[0] - nose_px[0]) / (te_z - tip_z)  # px per model metre
            # Camera at -X looking +X: image right = +Z (aft), image up = +Y. Image centre maps to model (z_c, y_c).
            z_c = tip_z + (w / 2 - nose_px[0]) / scale
            y_c = (frl - h / 2) / scale  # rows grow downward
            views.append(dict(id="side", title="Perfil · AN 01-60-3", crop_box=v["box"], size_px=[w, h], projection="orthographic",
                              orthographic_size_m=h / scale, display_scale_px_per_model_m=scale,
                              camera_position_m=[-20.0, y_c, z_c], camera_basis_columns=[[0, 0, 1], [0, 1, 0], [-1, 0, 0]],
                              anchors=dict(spinner_tip=dict(model_m=[0, 0, tip_z], picked_px=nose_px), rudder_te=dict(model_m=[0, 0, te_z], picked_px=tail_px)),
                              checks=dict(fin_top=dict(model_m=[0, fin_top, g["tail"]["fin_top_le_z"] + g["tail"]["fin_top_chord"]], picked_px=[int(xs[ys == ys.min()].mean()), int(ys.min())]))))
        elif key == "top":
            left, right = int(xs.min()), int(xs.max())
            xc = (left + right) / 2
            scale = (right - left) / span
            nose_row = int(ys.max())  # nose at the bottom of the plan view
            # Camera above looking down: image right = -X (right wing on the viewer's left), image up = +Z (aft).
            x_c = -((w / 2 - xc) / scale)
            z_c = tip_z + (nose_row - h / 2) / scale
            views.append(dict(id="top", title="Planta · AN 01-60-3", crop_box=v["box"], size_px=[w, h], projection="orthographic",
                              orthographic_size_m=h / scale, display_scale_px_per_model_m=scale,
                              camera_position_m=[x_c, 20.0, z_c], camera_basis_columns=[[-1, 0, 0], [0, 0, 1], [0, 1, 0]],
                              anchors=dict(right_tip=dict(model_m=[span / 2, 0, 0], picked_px=[left, None]), left_tip=dict(model_m=[-span / 2, 0, 0], picked_px=[right, None])),
                              checks=dict(spinner_tip=dict(model_m=[0, 0, tip_z], picked_px=[int(xc), nose_row]))))
        elif key == "front":
            left = int(xs.min())
            xc = picks_top_centre(dark) - x0
            scale = (xc - left) / (span / 2)
            # Camera ahead looking aft: image right = -X, image up = +Y. Vertical anchor: the spinner axis row = the
            # silhouette's spinner top row + its radius (from the plan/side scale) is not robust; use the fuselage
            # reference line of the side view transferred through the stab height later. Here: wing tip chord-plane
            # height as the vertical anchor (model y of the tip chord plane).
            tip_rows = ys[xs <= left + 4]
            tip_row = float(tip_rows.mean())
            tip_y = g["wing"]["chord_plane_y"] + (span / 2) * np.tan(np.radians(g["wing"]["dihedral_deg"]))
            x_c = -((w / 2 - xc) / scale)
            y_c = tip_y + (tip_row - h / 2) / scale
            views.append(dict(id="front", title="Frontal · AN 01-60-3 (mitad izquierda)", crop_box=v["box"], size_px=[w, h], projection="orthographic",
                              orthographic_size_m=h / scale, display_scale_px_per_model_m=scale,
                              camera_position_m=[x_c, y_c, -20.0], camera_basis_columns=[[-1, 0, 0], [0, 1, 0], [0, 0, -1]],
                              anchors=dict(right_tip=dict(model_m=[span / 2, tip_y, 0], picked_px=[left, int(tip_row)]), centre=dict(model_m=[0, 0, 0], picked_px=[int(xc), None])),
                              checks={}))
    fit = dict(schema="openrc-profile-diagnostic-camera-v1", date="2026-10-06", drawing=picks["drawing"], drawing_sha256=sha(drawing),
               model_geometry_sha256=sha(GEOMETRY), picks_sha256=sha(HERE / "picks.json"),
               method="Orthographic cameras from two anchors per view (uniform scale, no rotation, no image deformation), as research/avanti-s/user-profile. Side: spinner tip and rudder TE on the fuselage reference line; plan and front: wing tips. The front view's vertical anchor is the wing-tip chord plane (dihedral 5 deg from the drawing).",
               limits=["The 1945 reproduction is about 3 % anisotropic in the side view (fin height vs length); only the horizontal anchors are used, so vertical positions in the side view carry that error.",
                       "The drawing's outline is the ink centre; the filled silhouettes used for the anchors are eroded 2 px to it.",
                       "Propeller blades, drop tanks, dimension lines and the main wheels are not compared."],
               views=views)
    (HERE / "camera-fit.json").write_text(json.dumps(fit, indent=2) + "\n")
    for v in views:
        print(v["id"], "scale px/m", round(v["display_scale_px_per_model_m"], 2), "ortho size m", round(v["orthographic_size_m"], 4))


def picks_top_centre(dark):
    """Symmetry column of the plan view (original image coordinates): median of the fuselage outline midpoints."""
    from measure import runs
    v = picks["views"]["top"]
    T = silhouette(dark, v["box"], v["exclude"])
    centres = []
    for y in range(T.shape[0]):
        r = runs(T[y])
        if r:
            centres.append((r[0][0] + r[-1][1] - 1) / 2)
    return float(np.median(centres)) + v["box"][0]


if __name__ == "__main__":
    main()
