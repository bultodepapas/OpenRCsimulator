#!/usr/bin/env python3
"""L11a: local 25–35 m transition checks and masked FLIP on verified grass A/B captures."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import math
import numpy as np
import flip_evaluator
from check_grass import load_run, image_rgb


def ground_radius(case: dict) -> np.ndarray:
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
    # The guarded producer's band camera is at the default field's pilot station.
    radius = np.hypot(n-case['camera_north_m'], e-case['camera_east_m'])
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
    parser.add_argument('--captures', type=Path, required=True, help='candidate-repeat-1 output directory')
    parser.add_argument('--out', type=Path, required=True, help='summary JSON path')
    parser.add_argument('--self-test', action='store_true', help='also reject a narrow artificial dark seam on a copy')
    args = parser.parse_args()
    if args.out.resolve() in {(args.captures/'capture-manifest.json').resolve()} or args.out.suffix != '.json':
        parser.error('--out must be a separate .json summary')
    args.out.unlink(missing_ok=True)
    manifest, cases = load_run(args.captures, 'candidate')
    off_case, on_case = cases['band-25-35m-grass-off'], cases['band-25-35m-grass-on']
    for key in ['camera_north_m','camera_east_m','camera_height_m','azimuth_deg','elevation_deg','camera_fov_deg']:
        if off_case[key] != on_case[key]:
            raise ValueError('seam pair camera mismatch: '+key)
    off, on = image_rgb(args.captures/off_case['image']), image_rgb(args.captures/on_case['image'])
    radius = ground_radius(off_case)
    report = measure(off, on, radius)
    if not report['passed']:
        raise ValueError('local seam exceeds 3% channel mean or FLIP p99 0.1: '+str(report['failed_cells']))
    mutation = None
    if args.self_test:
        # A 25 cm wide dark ring segment is diluted by a whole-annulus average. Do not edit the captures.
        defect = on.copy()
        mask = (radius >= 29.) & (radius < 29.25)
        mask[:, :480] = False
        mask[:, 800:] = False
        if int(mask.sum()) < 32:
            raise ValueError('mutation patch too small')
        defect[mask] = np.rint(defect[mask].astype(np.float32)*.65).astype(np.uint8)
        checked = measure(off, defect, radius)
        if checked['passed']:
            raise ValueError('local seam mutation was not rejected')
        mutation = {'rejected': True, 'pixels': int(mask.sum()),
                    'max_local_channel_mean_abs_percent': checked['max_local_channel_mean_abs_percent'],
                    'max_local_flip_p99': checked['max_local_flip_p99']}
    report.update({'format':'openrc-l11a-seam v1','complete':True,'gates_kind':'engineering estimates',
                   'gates':{'local_channel_mean_abs_percent':3.,'local_flip_p99':.1},
                   'source_captures':{c['image']:hashlib.sha256((args.captures/c['image']).read_bytes()).hexdigest()
                                      for c in (off_case,on_case)},
                   'checker_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                   'mutation':mutation,'limitations':'Flat pilot-area ground projection; software-rendered image metrics do not close human Gate L.'})
    args.out.parent.mkdir(parents=True,exist_ok=True)
    args.out.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({k:report[k] for k in ['passed','max_local_channel_mean_abs_percent','max_local_flip_p99','mutation']}))
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
