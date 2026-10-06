#!/usr/bin/env python3
import hashlib,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
HERE=Path(__file__).resolve().parent
OUT=ROOT/'references/avanti-s/user-profile'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
fit=json.loads((HERE/'camera-fit.json').read_text())
manifest=json.loads((OUT/'renders-profile/render-manifest.json').read_text())
assert manifest['fit_sha256']==sha(HERE/'camera-fit.json')
assert sha(ROOT/fit['views'][0]['photo'])==fit['views'][0]['photo_sha256']
assert sha(OUT/'renders-profile/profile.png')==manifest['captures'][0]['sha256']
(OUT/'index.html').write_text((HERE/'viewer.html').read_text())
print(OUT/'index.html')
