"""Reconstruct the R5 baseline, then apply and verify the R6 one-field candidate."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--repo', type=Path, required=True)
parser.add_argument('--destination', type=Path, required=True)
args = parser.parse_args()
home = Path(__file__).resolve().parent
subprocess.run([sys.executable, str(home.parent/'M5-W05d-R5/restore_sources.py'),
    '--repo', str(args.repo), '--destination', str(args.destination)], check=True)
for source in (home/'candidate-source').rglob('*.gd'):
    target = args.destination/source.relative_to(home/'candidate-source')
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)
manifest = json.loads((home/'comparison-manifest.json').read_text())['candidate']
solver = hashlib.sha256()
for name, expected in sorted(manifest['sources'].items()):
    raw = (args.destination/name).read_bytes()
    assert hashlib.sha256(raw).hexdigest() == expected, name
    solver.update(('res://'+name.removeprefix('app/')).encode())
    solver.update(raw)
assert solver.hexdigest() == manifest['solver_sha256']
print(json.dumps({'verified': True, 'sources': len(manifest['sources']), 'solver_sha256': solver.hexdigest()}))
