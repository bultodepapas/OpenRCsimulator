#!/usr/bin/env python3
"""Fit a perspective camera (pose and vertical FOV, never the geometry) to landmarks picked on the user's P-51D photo.

As research/avanti-s/alignment/fit.py, with the FOV as a seventh unknown because the photo is a telephoto shot (a fixed
45 deg would force a wrong distance). Landmark model coordinates come from geometry.json so a regenerated geometry
refits automatically. Writes camera-fit.json for ../render.gd (--fit=).

    python3 research/p51/p51-02/silhouette/photo/fit.py
"""
import hashlib
import json
from pathlib import Path

import numpy as np
import scipy
from scipy.optimize import least_squares
from scipy.spatial.transform import Rotation

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
GEOMETRY = ROOT / "assets/aircraft/p51d-mustang-120/geometry.json"
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()


def landmarks(g):
    w, t, gear, sp = g["wing"], g["tail"], g["gear"], g["spinner"]
    semi = w["span"] / 2
    tip_y = w["chord_plane_y"] + semi * np.tan(np.radians(w["dihedral_deg"]))
    tip_z = w["le_z_tip"] + w["tip_chord"] / 2
    crown = max(g["canopy"]["top"], key=lambda p: p[1])
    return {
        "spinner_tip": [0.0, 0.0, sp["tip_z"]],
        "wing_tip_left": [-semi, tip_y, tip_z],
        "wing_tip_right": [semi, tip_y, tip_z],
        "fin_top": [0.0, t["fin_top_y"], t["fin_top_le_z"] + 0.02],  # the cap's highest point sits at its leading corner
        "wheel_bottom_left": [-gear["track"] / 2, gear["main_axle"][1] - gear["main_wheel_diameter"] / 2, gear["main_axle"][0]],
        "wheel_bottom_right": [gear["track"] / 2, gear["main_axle"][1] - gear["main_wheel_diameter"] / 2, gear["main_axle"][0]],
        "canopy_crown": [0.0, crown[1], crown[0]],
        "scoop_lip_bottom": [0.0, g["scoop_stations"][0][2], g["scoop_stations"][0][0]],
    }


def project(pose, points, focal, center):
    rotation = Rotation.from_rotvec(pose[:3]).as_matrix()
    camera = points @ rotation.T + pose[3:6]
    uv = focal * camera[:, :2] / np.maximum(camera[:, 2:], 0.1) + center
    return uv, camera[:, 2]


def initial_pose(position, target):
    position = np.array(position, float)
    forward = np.array(target) - position
    forward /= np.linalg.norm(forward)
    right = np.cross(forward, [0.0, 1.0, 0.0]); right /= np.linalg.norm(right)
    down = np.cross(forward, right)
    rotation = np.array([right, down, forward])  # CV axes: right, down, forward
    return np.r_[Rotation.from_matrix(rotation).as_rotvec(), -rotation @ position]


def main():
    picks = json.loads((HERE / "picks.json").read_text())
    g = json.loads(GEOMETRY.read_text())
    assert sha(ROOT / picks["photo"]) == picks["photo_sha256"], "photo changed"
    lm = landmarks(g)
    width, height = picks["size_px"]
    center = np.array([width / 2, height / 2])
    keys = picks["fit"]
    xyz = np.array([lm[k] for k in keys])
    uv = np.array([picks["picked_px"][k] for k in keys], float)

    def residual(x):
        focal = height / (2 * np.tan(np.radians(x[6]) / 2))
        projected, depth = project(x[:6], xyz, focal, center)
        return np.r_[(projected - uv).ravel(), np.minimum(depth - 0.5, 0) * 1000]

    rng = np.random.default_rng(42)
    base = initial_pose(picks["initial_camera_m"], [0.0, 0.0, 0.4])
    fits = []
    for attempt in range(40):
        guess = np.r_[base, 20.0]
        if attempt:
            guess[:3] += rng.normal(0, 0.25, 3)
            guess[3:6] += rng.normal(0, 1.0, 3)
            guess[6] = rng.uniform(6, 50)
        fit = least_squares(residual, guess, bounds=([-np.inf] * 6 + [4.0], [np.inf] * 6 + [70.0]), max_nfev=4000, ftol=1e-12, xtol=1e-12)
        _, depth = project(fit.x[:6], xyz, height / (2 * np.tan(np.radians(fit.x[6]) / 2)), center)
        if fit.success and depth.min() > 0.5:
            fits.append(fit)
    assert fits
    fit = min(fits, key=lambda f: np.sum(f.fun ** 2))
    fov = float(fit.x[6])
    focal = height / (2 * np.tan(np.radians(fov) / 2))
    rotation = Rotation.from_rotvec(fit.x[:3]).as_matrix()
    position = -rotation.T @ fit.x[3:6]
    basis = rotation.T @ np.diag([1.0, -1.0, -1.0])  # CV (right, down, forward) -> Godot (right, up, back)
    errors = []
    for role in ("fit", "check"):
        for key in picks[role]:
            projected, _ = project(fit.x[:6], np.array([lm[key]]), focal, center)
            delta = projected[0] - np.array(picks["picked_px"][key])
            errors.append(dict(key=key, role=role, model_m=lm[key], picked_px=picks["picked_px"][key], projected_px=projected[0].tolist(), error_px=float(np.linalg.norm(delta))))
    rms = lambda role: float(np.sqrt(np.mean([e["error_px"] ** 2 for e in errors if e["role"] == role])))
    # Sensitivity: refit with the FOV frozen at +-20 % to show how weakly a telephoto shot constrains it.
    view = dict(id="photo_oblique", title="Foto del usuario · oblicua baja frontal-izquierda", photo=picks["photo"], photo_sha256=picks["photo_sha256"],
                size_px=[width, height], projection="perspective", assumed_vertical_fov_deg=fov, fitted_fov=True,
                camera_position_m=position.tolist(), camera_basis_columns=basis.T.tolist(), distance_to_origin_m=float(np.linalg.norm(position)),
                fit_rms_px=rms("fit"), check_rms_px=rms("check"), landmarks=errors,
                anchors={e["key"]: dict(model_m=e["model_m"], picked_px=e["picked_px"]) for e in errors if e["role"] == "fit"}, checks={})
    out = dict(schema="openrc-photo-camera-fit-v1", date="2026-10-06", method="Perspective rigid camera with fitted vertical FOV (7 unknowns, 6 landmarks, 40 random restarts), centred principal point, no lens distortion; geometry never adjusted",
               versions=dict(numpy=np.__version__, scipy=scipy.__version__), picks_sha256=sha(HERE / "picks.json"), model_geometry_sha256=sha(GEOMETRY),
               drawing_sha256=picks["photo_sha256"], limits=["Six hand-picked landmarks with ~6 px tolerance; wheel contact points depend on tyre compression and the model's gear height from the drawing",
               "FOV and distance are strongly correlated for a telephoto shot: trust the overlay, not the distance", "Motion-blurred propeller excluded from the comparison"], views=[view])
    (HERE / "camera-fit.json").write_text(json.dumps(out, indent=2) + "\n")
    print(f"fit RMS {view['fit_rms_px']:.1f} px, withheld {view['check_rms_px']:.1f} px, FOV {fov:.1f} deg, camera {np.round(position, 2)} ({view['distance_to_origin_m']:.1f} m)")
    for e in errors:
        print(f"  {e['role']:5} {e['key']:18} picked {e['picked_px']} -> {np.round(e['projected_px'], 1)}  {e['error_px']:.1f} px")


if __name__ == "__main__":
    main()
