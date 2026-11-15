#!/usr/bin/env python3
"""Independent SciPy audit of Godot-captured flight-mode Jacobians.

Usage: python audit_followup_modes_analysis.py captured_probe.json summary.json
Uses only saved production-probe data; does not run or modify the simulator.
"""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
import scipy
from scipy.linalg import eig
from scipy.optimize import linear_sum_assignment

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('source', type=Path, help='Structured JSON produced by modes_probe.gd')
parser.add_argument('destination', type=Path, help='Path to write independent-analysis JSON')
args = parser.parse_args()
source, dest = args.source, args.destination
with source.open() as f:
    d = json.load(f)


def spectrum(a):
    a = np.asarray(a, dtype=float)
    vals, left, right = eig(a, left=True, right=True)
    out = []
    for j, lam in enumerate(vals):
        v, w = right[:, j], left[:, j]
        scale = np.linalg.norm(a, 2) * np.linalg.norm(v, 2)
        resid = np.linalg.norm(a @ v - lam * v, 2) / scale if scale else 0.0
        overlap = np.vdot(w, v)
        cond = float(np.linalg.norm(w) * np.linalg.norm(v) / abs(overlap)) if abs(overlap) else None
        part = np.conjugate(w) * v / overlap if abs(overlap) else np.zeros_like(v)
        out.append({'real': float(lam.real), 'imag': float(lam.imag),
                    'normalized_eigenpair_residual': float(resid), 'eigenvalue_condition_2norm': cond,
                    'state_participation_real': [float(x.real) for x in part]})
    return sorted(out, key=lambda z: (z['real'], -z['imag']))


def value(z):
    return complex(z['real'], z['imag'])


def root_match(a, b):
    a, b = list(a), list(b)
    r, c = linear_sum_assignment(np.abs(np.subtract.outer(a, b)))
    return float(max(abs(a[i] - b[j]) for i, j in zip(r, c))) if r.size else 0.0


def nearest_slow_real(roots):
    reals = [z for z in roots if abs(z['imag']) < 1e-7]
    return max(reals, key=lambda z: z['real']) if reals else None

out = {'format': 'openrc-fs64v-modes-independent-analysis-v1',
       'source': source.name, 'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
       'numpy': np.__version__, 'scipy': scipy.__version__,
       'scope': 'Eigensolutions of saved, unit-bearing production Jacobians; condition/participation depend on coordinates. Not a nonlinear simulation.',
       'state_order': d['state_order'], 'cases': []}
for m in d['modes']:
    if not m['ok']:
        continue
    a = np.asarray(m['full_jacobian'], dtype=float)
    lon = np.asarray(m['longitudinal_jacobian'], dtype=float)
    lat = np.asarray(m['lateral_jacobian'], dtype=float)
    full, lons, lats = spectrum(a), spectrum(lon), spectrum(lat)
    rt = [complex(*x) for x in m['longitudinal_roots_runtime']]
    rep = m['finite_difference_replicated']
    hroots = {str(z['h']): spectrum(z['longitudinal_jacobian']) for z in rep}
    record = {'aircraft': m['aircraft'], 'speed_mps': m['speed_mps'],
              'diagnostic_instantaneous_downwash': m['diagnostic_instantaneous_downwash'],
              'trim_residual_norm': m['trim']['residual'],
              'longitudinal_roots_scipy': lons, 'lateral_roots_scipy': lats,
              'full_roots_scipy': full,
              'maximum_runtime_longitudinal_eigenvalue_difference': root_match(rt, [value(x) for x in lons]),
              'replicated_longitudinal_default_matrix_max_difference': float(np.max(np.abs(lon - np.asarray(next(z['longitudinal_jacobian'] for z in rep if z['h'] == 1e-6))))),
              'longitudinal_root_difference_h_1e7_vs_1e6': root_match([value(x) for x in hroots['1e-07']], [value(x) for x in hroots['1e-06']]),
              'longitudinal_root_difference_h_1e5_vs_1e6': root_match([value(x) for x in hroots['1e-05']], [value(x) for x in hroots['1e-06']]),
              'full_slowest_real': nearest_slow_real(full), 'lateral_slowest_real': nearest_slow_real(lats)}
    if all('full_jacobian' in z for z in rep):
        full_hroots = {str(z['h']): spectrum(z['full_jacobian']) for z in rep}
        production_h = next(z['full_jacobian'] for z in rep if z['h'] == 1e-6)
        record['full_jacobian_step_sweep'] = {
            'default_matrix_max_difference': float(np.max(np.abs(a - np.asarray(production_h)))),
            'root_difference_h_1e7_vs_1e6': root_match([value(x) for x in full_hroots['1e-07']], [value(x) for x in full_hroots['1e-06']]),
            'root_difference_h_1e5_vs_1e6': root_match([value(x) for x in full_hroots['1e-05']], [value(x) for x in full_hroots['1e-06']]),
            'slowest_real_by_h': {h: nearest_slow_real(roots) for h, roots in full_hroots.items()},
            'scope': 'Replicated RHS finite-difference sensitivity of full matrix; not physical validation.'}
    if m['aircraft'] == 'fs64v' and m['speed_mps'] == 20.0 and not m['diagnostic_instantaneous_downwash']:
        # One transparent nondimensional scaling, NOT a model or matrix change.
        # Speeds/lag scale by V, angular rates by 2V/span or 2V/chord,
        # and Euler angles by one radian. Different scaling changes conditioning.
        v, span, chord = 20.0, 1.524, 0.3048
        scales = np.array([v, v, v, 2*v/span, 2*v/chord, 2*v/span, 1., 1., v])
        scaled = (a * scales[np.newaxis, :]) / scales[:, np.newaxis]
        scaled_roots = spectrum(scaled)
        record['similarity_scaling'] = {
            'state_scales': [float(x) for x in scales],
            'maximum_eigenvalue_difference': root_match([value(x) for x in full], [value(x) for x in scaled_roots]),
            'scaled_slowest_real': nearest_slow_real(scaled_roots),
            'note': 'Dimensionless similarity D^-1 A D; eigenvalues invariant, eigenvalue condition changes with D.'}
    out['cases'].append(record)

with dest.open('w') as f:
    json.dump(out, f, indent=2, allow_nan=False)
    f.write('\n')
print('SciPy independent eigensystem analysis:', dest)
print('NumPy', np.__version__, 'SciPy', scipy.__version__)
for c in out['cases']:
    if c['diagnostic_instantaneous_downwash'] and c['speed_mps'] != 20.0:
        continue
    f, l = c['full_slowest_real'], c['lateral_slowest_real']
    print(f"{c['aircraft']:14s} V={c['speed_mps']:8.4f} no_lag={str(c['diagnostic_instantaneous_downwash']):5s} "
          f"full={f['real']:+.9f} lat={l['real']:+.9f} residual={f['normalized_eigenpair_residual']:.2g} "
          f"cond={f['eigenvalue_condition_2norm']:.3g} d_rt={c['maximum_runtime_longitudinal_eigenvalue_difference']:.2g} "
          f"d_h={max(c['longitudinal_root_difference_h_1e7_vs_1e6'],c['longitudinal_root_difference_h_1e5_vs_1e6']):.2g}")
