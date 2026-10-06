#!/usr/bin/env python3
"""Read rendered alpha for exploratory contour distances; emit native SVG comparison.
Does not alter source photos or rendered PNGs. Requires alignment/requirements.txt + Pillow.
"""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from PIL import Image
from scipy.ndimage import binary_erosion, distance_transform_edt

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--candidate', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    baseline = ROOT / 'references/avanti-s/alignment/renders-v1'
    candidate = args.candidate.resolve()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    picks = json.loads((HERE / 'contour-picks.json').read_text())
    fit_path = ROOT / 'research/avanti-s/alignment/camera-fit.json'
    fit = json.loads(fit_path.read_text())
    manifest = json.loads((candidate / 'render-manifest.json').read_text())
    original_manifest = json.loads((baseline / 'render-manifest.json').read_text())
    assert manifest['fit_sha256'] == original_manifest['fit_sha256'] == sha(fit_path), 'Camera changed'
    rows, views = [], []
    for view in fit['views']:
        key = view['id']
        assert sha(ROOT / view['photo']) == view['photo_sha256'], 'Original photo changed'
        groups = picks['views'][key]
        fields = []
        for folder, record in ((baseline, original_manifest), (candidate, manifest)):
            path = folder / (key + '.png')
            capture = next(c for c in record['captures'] if c['id'] == key)
            assert sha(path) == capture['sha256'], 'Capture changed'
            rgba = np.asarray(Image.open(path).convert('RGBA'))
            assert rgba.shape == (488, 650, 4)
            alpha = rgba[:, :, 3] >= 128
            edge = alpha & ~binary_erosion(alpha)
            fields.append(distance_transform_edt(~edge))
        for group, points in groups.items():
            before, after = [[float(field[y, x]) for x, y in points] for field in fields]
            rows.append(dict(view=key, group=group, samples=len(points),
                             before_mean_px=float(np.mean(before)), after_mean_px=float(np.mean(after)),
                             before_max_px=max(before), after_max_px=max(after)))
        import os
        relative = lambda path: os.path.relpath(path, output)
        views.append(dict(id=key, title=view['title'], photo=relative(ROOT / view['photo']),
                          before=relative(baseline / (key + '.png')), after=relative(candidate / (key + '.png')),
                          groups=groups))
    result = dict(schema='openrc-contour-review-v1', method=picks['method'],
                  metric='Unsigned distance to nearest alpha>=128 silhouette pixel, 8-neighbour erosion. Samples are not independent and nearest edge may belong to another component. Not a full-mask IoU or aerodynamic/metric accuracy.',
                  geometry_sha256=manifest['geometry_sha256'], model_sha256=manifest['model_sha256'],
                  camera_fit_sha256=sha(fit_path), contour_picks_sha256=sha(HERE/'contour-picks.json'), groups=rows)
    (output / 'metrics.json').write_text(json.dumps(result, indent=2)+'\n')
    data = dict(views=views, metrics=result)
    html = (HERE/'review.html').read_text().replace('__REVIEW_DATA__', json.dumps(data, ensure_ascii=False))
    (output/'index.html').write_text(html)
    for row in rows:
        print(f"{row['view']:12} {row['group']:5} {row['before_mean_px']:5.1f} → {row['after_mean_px']:5.1f} px")
    print(output/'index.html')

if __name__ == '__main__':
    main()
