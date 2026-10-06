#!/usr/bin/env python3
"""Publish a local SVG transparency viewer; original images are only referenced."""
import json
from pathlib import Path

here = Path(__file__).resolve().parent
root = here.parents[2]
fit = json.loads((here / 'camera-fit.json').read_text())
out = root / 'references/avanti-s/alignment'
out.mkdir(parents=True, exist_ok=True)
for view in fit['views']:
    assert (root / view['photo']).exists(), view['photo']
    assert (out / 'renders-v1' / (view['id'] + '.png')).exists(), view['id']
html = (here / 'overlay.html').read_text().replace('__ALIGNMENT_DATA__', json.dumps(fit, ensure_ascii=False))
(out / 'index.html').write_text(html)
print(out / 'index.html')
