#!/usr/bin/env python3
"""Build the local new-angle gallery and fixed-camera overlays without altering photos."""
import hashlib
import json
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
OUT = ROOT / 'references/avanti-s/new-angles'
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()

def main():
    records = json.loads((ROOT/'docs/research/avanti-s-new-angle-resources.json').read_text())['items']
    fit_path = HERE/'camera-fit.json'
    fit = json.loads(fit_path.read_text())
    rendered = json.loads((OUT/'renders-final/render-manifest.json').read_text())
    assert rendered['fit_sha256'] == sha(fit_path)
    assert fit['picks_sha256'] == sha(HERE/'picks.json')
    for r in records:
        path = ROOT/r['path']
        assert sha(path) == r['sha256'], path
    for view in fit['views']:
        assert sha(ROOT/view['photo']) == view['photo_sha256']
        capture = next(c for c in rendered['captures'] if c['id']==view['id'])
        assert sha(OUT/'renders-final'/capture['file']) == capture['sha256']
        assert capture['scipy_projection_max_delta_px'] < .05
        if view.get('camera_hemisphere')=='below': assert view['camera_position_m'][1]<0
    html = (HERE/'viewer.html').read_text().replace('__DATA__',json.dumps(dict(fit=fit,items=records),ensure_ascii=False))
    (OUT/'index.html').write_text(html)
    print(OUT/'index.html')

if __name__=='__main__': main()
