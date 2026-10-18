#!/usr/bin/env python3
"""L11a: local 25–35 m transition checks and masked FLIP on verified grass A/B captures."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import math
import importlib.metadata
import numpy as np
import flip_evaluator
from check_grass import load_run, image_rgb, expected_cameras, verify_scenery, validate_camera_metadata


def ground_radius(case: dict, pilot_north: float | None = None, pilot_east: float | None = None) -> np.ndarray:
    """Intersect camera rays with the flat pilot-area ground, in render coordinates."""
    az, el = math.radians(case['azimuth_deg']), math.radians(case['elevation_deg'])
    forward = np.array([math.sin(az)*math.cos(el), math.sin(el), -math.cos(az)*math.cos(el)])
    right = np.array([math.cos(az), 0., math.sin(az)])
    up = np.cross(right, forward)
    yy, xx = np.indices((720, 1280), dtype=np.float64)
    scale = math.tan(math.radians(case['camera_fov_deg'])/2.) / 360.
    rays = forward + ((xx+0.5-640.)*scale)[..., None]*right + ((360.-yy-0.5)*scale)[..., None]*up
    valid = rays[..., 1] < -1e-9
    t = np.divide(-case['camera_height_m'], rays[..., 1], out=np.zeros_like(xx), where=valid)
    n = case['camera_north_m'] - t*rays[..., 2]
    e = case['camera_east_m'] + t*rays[..., 0]
    # Placement remains anchored to the pilot even when the camera moves away.
    center_n = case['camera_north_m'] if pilot_north is None else pilot_north
    center_e = case['camera_east_m'] if pilot_east is None else pilot_east
    radius = np.hypot(n-center_n, e-center_e)
    return np.where(valid, radius, np.inf)


def measure(off: np.ndarray, on: np.ndarray, radius: np.ndarray) -> dict:
    delta = np.abs(on.astype(np.float64)-off.astype(np.float64))
    flip = np.asarray(flip_evaluator.evaluate(off.astype(np.float32)/255., on.astype(np.float32)/255.,
                                            'LDR', applyMagma=False)[0]).squeeze()
    if flip.shape != radius.shape or not np.isfinite(flip).all():
        raise ValueError('invalid FLIP result')
    cells = []
    for low in range(25, 35):
        for sector in range(8):
            mask = (radius >= low) & (radius < low+1)
            mask[:, :sector*160] = False
            mask[:, (sector+1)*160:] = False
            count = int(mask.sum())
            if count < 32:
                continue
            percent = 100.*delta[mask].mean(axis=0)/np.maximum(off[mask].mean(axis=0), 1.)
            p99 = float(np.percentile(flip[mask], 99))
            cells.append({'radial_m': [low, low+1], 'screen_x': [sector*160, (sector+1)*160],
                          'pixels': count, 'max_channel_mean_abs_percent': float(percent.max()), 'flip_p99': p99})
    covered = {cell['radial_m'][0] for cell in cells}
    if covered != set(range(25, 35)):
        raise ValueError('every 1 m radial band must have usable projected pixels')
    failed = [c for c in cells if c['max_channel_mean_abs_percent'] > 3. or c['flip_p99'] > .1]
    band = (radius >= 25.) & (radius < 35.)
    return {'passed': not failed, 'cells': cells, 'failed_cells': failed,
            'max_local_channel_mean_abs_percent': max(c['max_channel_mean_abs_percent'] for c in cells),
            'max_local_flip_p99': max(c['flip_p99'] for c in cells),
            'masked_flip_mean': float(flip[band].mean()), 'masked_flip_p99': float(np.percentile(flip[band], 99)),
            'band_pixels': int(band.sum())}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--captures', type=Path, required=True, help='verified v3 capture directory')
    parser.add_argument('--mode', choices=('fallback', 'imported'), default='fallback')
    parser.add_argument('--app', type=Path, default=Path(__file__).resolve().parents[2]/'app')
    parser.add_argument('--out', type=Path, required=True, help='summary JSON path')
    parser.add_argument('--self-test', action='store_true', help='also reject a narrow artificial dark seam on a copy')
    args = parser.parse_args()
    if args.out.resolve() in {(args.captures/'capture-manifest.json').resolve()} or args.out.suffix != '.json':
        parser.error('--out must be a separate .json summary')
    if args.out.exists():
        parser.error('--out must be a new file; existing evidence is never overwritten')
    manifest, cases = load_run(args.captures, 'scenery' if args.mode == 'imported' else 'candidate')
    pilot_north, pilot_east, cameras = expected_cameras(args.app)
    scenario = 'scenery-runway-edge' if args.mode == 'imported' else 'band-25-35m'
    off_case, on_case = cases[scenario+'-grass-off'], cases[scenario+'-grass-on']
    if args.mode == 'imported':
        verify_scenery(args.captures, manifest, cases, pilot_north, pilot_east, cameras)
    else:
        validate_camera_metadata(off_case, scenario, 'off', cameras[scenario])
        validate_camera_metadata(on_case, scenario, 'on', cameras[scenario])
    for key in ['camera_north_m','camera_east_m','camera_height_m','azimuth_deg','elevation_deg','camera_fov_deg']:
        if off_case[key] != on_case[key]:
            raise ValueError('seam pair camera mismatch: '+key)
    for case in (off_case, on_case):
        if case.get('shader_clock') != 0.0 or case.get('wind_vec') != [0.0, 0.0, 0.0]:
            raise ValueError('seam comparison requires matched zero-clock, zero-wind captures')
    off, on = image_rgb(args.captures/off_case['image']), image_rgb(args.captures/on_case['image'])
    radius = ground_radius(off_case, pilot_north, pilot_east)
    report = measure(off, on, radius)
    mutation = None
    if args.self_test:
        # A 25 cm wide dark ring segment is diluted by a whole-annulus average. Do not edit the captures.
        # Use the identical reference as the control so a failing candidate cannot
        # make the negative control pass vacuously.
        control = measure(off, off, radius)
        if not control['passed']:
            raise ValueError('identical-image control failed')
        defect = off.copy()
        mask = (radius >= 29.) & (radius < 29.25)
        mask[:, :480] = False
        mask[:, 800:] = False
        if int(mask.sum()) < 32:
            raise ValueError('mutation patch too small')
        defect[mask] = np.rint(defect[mask].astype(np.float32)*.65).astype(np.uint8)
        checked = measure(off, defect, radius)
        if checked['passed']:
            raise ValueError('local seam mutation was not rejected')
        mutation = {'rejected': True, 'identical_reference_passed': control['passed'],
                    'reference': 'grass-off', 'pixels': int(mask.sum()),
                    'max_local_channel_mean_abs_percent': checked['max_local_channel_mean_abs_percent'],
                    'max_local_flip_p99': checked['max_local_flip_p99']}
    report.update({'format':'openrc-l11a-seam v2','complete':True,'gates_kind':'engineering estimates',
                   'mode':args.mode,'material_mode':manifest['grass']['material_mode'],
                   'scenario':scenario,'pilot_north_m':pilot_north,'pilot_east_m':pilot_east,
                   'field_sha256':hashlib.sha256((args.app/'data/fields/default.json').read_bytes()).hexdigest(),
                   'capture_manifest_sha256':hashlib.sha256((args.captures/'capture-manifest.json').read_bytes()).hexdigest(),
                   'dependencies':{name:importlib.metadata.version(name) for name in ('numpy','Pillow','flip-evaluator')},
                   'gates':{'local_channel_mean_abs_percent':3.,'local_flip_p99':.1},
                   'source_captures':{c['image']:hashlib.sha256((args.captures/c['image']).read_bytes()).hexdigest()
                                      for c in (off_case,on_case)},
                   'checker_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                   'mutation':mutation,'limitations':'Flat pilot-area ground projection, one recorded camera. Static hidden/visible metrics do not establish moving boundary continuity, all-around coverage, or human Gate L.'})
    args.out.parent.mkdir(parents=True,exist_ok=True)
    args.out.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({k:report[k] for k in ['passed','max_local_channel_mean_abs_percent','max_local_flip_p99','mutation']}))
    return 0 if report['passed'] else 1

if __name__ == '__main__':
    raise SystemExit(main())
