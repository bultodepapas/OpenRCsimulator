#!/usr/bin/env python3
"""Compare seven frozen cameras. Read alpha; never rewrite reference images."""
import argparse
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path
import numpy as np
from PIL import Image
from scipy.ndimage import label

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
GROUPS = [
    ('original', 'alignment', 'refinement-v3/renders-final'),
    ('additional', 'new-angles', 'new-angles/renders-final'),
    ('profile', 'user-profile', 'user-profile/renders-profile'),
]

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def mask(path):
    return np.asarray(Image.open(path).convert('RGBA'))[:, :, 3] >= 128

def upper_edge(path):
    components, count = label(mask(path))
    assert count
    sizes = np.bincount(components.ravel()); sizes[0] = 0
    body = components == sizes.argmax()
    return np.where(body.any(axis=0), body.argmax(axis=0), np.nan)

def main():
    p = argparse.ArgumentParser(); p.add_argument('--captures', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True); args = p.parse_args()
    out = args.output.resolve(); out.mkdir(parents=True, exist_ok=True)
    views, provenance, profile_metrics = [], [], []
    relative = lambda path: os.path.relpath(path, out)
    for group, camera, before_dir in GROUPS:
        fit_path = ROOT / 'research/avanti-s' / camera / 'camera-fit.json'
        fit = json.loads(fit_path.read_text())
        before = ROOT / 'references/avanti-s' / before_dir
        after = args.captures.resolve() / group
        manifests = [json.loads((folder / 'render-manifest.json').read_text()) for folder in (before, after)]
        assert all(m['fit_sha256'] == sha(fit_path) for m in manifests), 'Camera changed'
        provenance.append(dict(group=group, camera_sha256=sha(fit_path),
                               before_manifest_sha256=sha(before/'render-manifest.json'),
                               after_manifest_sha256=sha(after/'render-manifest.json')))
        for v in fit['views']:
            photo = ROOT / v['photo']; assert sha(photo) == v['photo_sha256']
            files = [folder / (v['id'] + '.png') for folder in (before, after)]
            for path, manifest in zip(files, manifests):
                c = next(c for c in manifest['captures'] if c['id'] == v['id'])
                assert sha(path) == c['sha256']
                assert Image.open(path).size == tuple(v['size_px'])
            views.append(dict(id=v['id'], title=v['title'], size=v['size_px'], photo=relative(photo),
                              before=relative(files[0]), after=relative(files[1])))
            if v['id'] == 'profile':
                edges = [upper_edge(path) for path in [photo] + files]
                for name, start, stop in [('deriva', 280, 500), ('lomo', 500, 800), ('cabina', 800, 1550)]:
                    indices = np.arange(start, stop, 5)
                    valid = np.all(np.isfinite(np.array(edges)[:, indices]), axis=0)
                    indices = indices[valid]
                    profile_metrics.append(dict(region=name, x_range=[start, stop], stride=5, samples=len(indices),
                        before_mean_abs_y_px=float(np.mean(np.abs(edges[1][indices]-edges[0][indices]))),
                        after_mean_abs_y_px=float(np.mean(np.abs(edges[2][indices]-edges[0][indices])))))
    data = dict(inspector=relative(args.captures.resolve()/'inspector'), views=views, provenance=provenance, profile_metrics=profile_metrics,
                profile_method='Upper alpha>=128 boundary of largest 4-connected component, same image x columns every 5 px. Fin range starts at x280 where both upper outlines are visible; omits unmatched tip at x110–280. Native 1818x865 pixels. Approximate frozen side camera, unknown variant/perspective, gear excluded. Not dimensions, full silhouette error or IoU.',
                geometry_sha256=manifests[1]['geometry_sha256'], model_sha256=manifests[1]['model_sha256'])
    (out/'review.json').write_text(json.dumps(data, indent=2, ensure_ascii=False)+'\n')
    (out/'index.html').write_text((HERE/'review.html').read_text().replace('__DATA__', json.dumps(data, ensure_ascii=False)))
    subprocess.run([sys.executable, str(HERE.parent/'refinement/review.py'),
        '--baseline', str(ROOT/'references/avanti-s/refinement-v3/renders-final'),
        '--candidate', str(args.captures.resolve()/'original'), '--output', str(out/'sampled-contours'),
        '--before-label', 'Antes · v3', '--after-label', 'Después · v4',
        '--report', 'avanti-s-refinement-v4.md'], check=True)
    sample_html = out/'sampled-contours/index.html'
    sample_html.write_text(sample_html.read_text().replace('../../../docs/', '../../../../docs/')
        .replace('../alignment/index.html', '../../alignment/index.html')
        .replace('Tren y fences no están representados en esta revisión.',
                 'V4 incorpora placas alares estimadas; el tren sigue sin representarse.'))
    print(json.dumps(profile_metrics, ensure_ascii=False, indent=2))
    print(out/'index.html')

if __name__ == '__main__': main()
