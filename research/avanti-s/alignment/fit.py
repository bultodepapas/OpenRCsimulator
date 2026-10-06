#!/usr/bin/env python3
"""Fit a fixed-FOV camera, never aircraft geometry, to manually selected landmarks."""
import hashlib
import argparse
import json
from pathlib import Path
import numpy as np
from scipy.optimize import least_squares
from scipy.spatial.transform import Rotation
import scipy

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def initial_pose(position):
    position = np.array(position, dtype=float)
    forward = (np.array([0., 0., .05]) - position)
    forward /= np.linalg.norm(forward)
    right = np.cross(forward, [0., 1., 0.])
    right /= np.linalg.norm(right)
    down = np.cross(forward, right)
    rotation = np.array([right, down, forward])
    return np.r_[Rotation.from_matrix(rotation).as_rotvec(), -rotation @ position]


def project(pose, points, focal, center):
    rotation = Rotation.from_rotvec(pose[:3]).as_matrix()
    camera = points @ rotation.T + pose[3:]
    uv = focal * camera[:, :2] / np.maximum(camera[:, 2:], .1) + center
    return uv, camera[:, 2]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--picks', type=Path, default=HERE / 'picks.json')
    parser.add_argument('--output', type=Path, default=HERE / 'camera-fit.json')
    args = parser.parse_args()
    data = json.loads(args.picks.read_text())
    assert sha(ROOT / 'research/avanti-s/av02/geometry.json') == data['model_geometry_sha256']
    output = []
    for view in data['views']:
        assert sha(ROOT / view['photo']) == view['photo_sha256']
        keys = list(view['fit'])
        xyz = np.array([data['landmarks_m'][key] for key in keys])
        uv = np.array(list(view['fit'].values()))
        width, height = view['size_px']
        center = np.array([width / 2, height / 2])
        focal = height / (2 * np.tan(np.deg2rad(view['assumed_vertical_fov_deg']) / 2))

        def residual(pose):
            projected, depth = project(pose, xyz, focal, center)
            return np.r_[(projected - uv).ravel(), np.minimum(depth - .2, 0) * 1000]

        initial = initial_pose(view['initial_camera'])
        roll = Rotation.from_euler('z', view.get('initial_camera_roll_deg', 0), degrees=True)
        initial[:3] = (roll * Rotation.from_rotvec(initial[:3])).as_rotvec()
        initial[3:] = roll.apply(initial[3:])
        rng = np.random.default_rng(42)
        fits = []
        for attempt in range(12):
            guess = initial.copy()
            if attempt:
                guess[:3] += rng.normal(0, .18, 3)
                guess[3:] += rng.normal(0, .2, 3)
            fit = least_squares(residual, guess, max_nfev=1000, ftol=1e-12, xtol=1e-12, gtol=1e-12)
            _, depth = project(fit.x, xyz, focal, center)
            camera_position = -Rotation.from_rotvec(fit.x[:3]).as_matrix().T @ fit.x[3:]
            hemisphere_ok = view.get('camera_hemisphere') != 'below' or camera_position[1] < 0
            if fit.success and np.min(depth) > .2 and hemisphere_ok:
                fits.append(fit)
        assert fits, view['id']
        fit = min(fits, key=lambda x: np.sum(x.fun ** 2))
        rotation = Rotation.from_rotvec(fit.x[:3]).as_matrix()
        position = -rotation.T @ fit.x[3:]
        # CV camera axes: right, down, forward. Godot: right, up, backward.
        basis = rotation.T @ np.diag([1., -1., -1.])
        errors = []
        for role in ['fit', 'check']:
            for key, picked in view[role].items():
                projected, _ = project(fit.x, np.array([data['landmarks_m'][key]]), focal, center)
                delta = projected[0] - picked
                errors.append(dict(key=key, role=role, picked_px=picked,
                                   projected_px=projected[0].tolist(), error_px=float(np.linalg.norm(delta))))
        record = dict(view, camera_position_m=position.tolist(), camera_basis_columns=basis.T.tolist(),
                      fit_rms_px=float(np.sqrt(np.mean([e['error_px'] ** 2 for e in errors if e['role'] == 'fit']))),
                      check_rms_px=float(np.sqrt(np.mean([e['error_px'] ** 2 for e in errors if e['role'] == 'check']))),
                      landmarks=errors)
        output.append(record)
        print(f"{view['id']}: fit RMS {record['fit_rms_px']:.1f}px; withheld {record['check_rms_px']:.1f}px")
    result = dict(schema='openrc-avanti-camera-fit-v1', date='2026-10-06',
                  method='Perspective rigid camera; fixed vertical FOV45, centered principal point, no lens distortion',
                  versions=dict(numpy=np.__version__, scipy=scipy.__version__), picks_sha256=sha(args.picks),
                  model_geometry_sha256=data['model_geometry_sha256'], limits=data['limitations'], views=output)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')


if __name__ == '__main__':
    main()
