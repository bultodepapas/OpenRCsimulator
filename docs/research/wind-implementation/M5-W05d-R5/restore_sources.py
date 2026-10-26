"""Restore exact recorded source bytes over a disposable checkout of the recorded commit."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--repo', type=Path, required=True)
parser.add_argument('--destination', type=Path, required=True)
args = parser.parse_args()
home = Path(__file__).resolve().parent
repo, destination = args.repo.resolve(), args.destination.resolve()
if destination == repo or destination in repo.parents:
    parser.error('use a disposable destination, not the source repository or its ancestors')
manifest = json.loads((home / 'reproduction-manifest.json').read_text())
names = sorted(manifest['sources'])
for name in names:
    path = Path(name)
    if path.is_absolute() or '..' in path.parts or path.parts[0] != 'app':
        raise ValueError('invalid source path: ' + name)
batch = subprocess.check_output(['git', '-C', str(repo), 'cat-file', '--batch'],
    input=''.join(manifest['head'] + ':' + name + '\n' for name in names).encode())
offset = 0
solver = hashlib.sha256()
for name in names:
    end = batch.index(b'\n', offset)
    header = batch[offset:end].split()
    offset = end + 1
    original = None
    if header[-1] != b'missing':
        length = int(header[-1])
        original = batch[offset:offset + length]
        offset += length + 1
    overlay = home / 'source-overlays' / name
    if overlay.is_file():
        candidates = [overlay.read_bytes()]
    elif original is not None:
        lf = original.replace(b'\r\n', b'\n')
        candidates = [original, lf, lf.replace(b'\n', b'\r\n')]
    else:
        raise ValueError('missing source: ' + name)
    raw = next((value for value in candidates if hashlib.sha256(value).hexdigest() == manifest['sources'][name]), None)
    if raw is None:
        raise ValueError('source hash mismatch: ' + name)
    target = destination / name
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(raw)
    if any(name.startswith('app/' + directory + '/') for directory in ['physics', 'sim', 'failures']) and name.endswith('.gd'):
        solver.update(('res://' + name.removeprefix('app/')).encode())
        solver.update(raw)
assert solver.hexdigest() == manifest['solver_sha256']
print(json.dumps({'verified': True, 'sources': len(names), 'solver_sha256': solver.hexdigest()}))
