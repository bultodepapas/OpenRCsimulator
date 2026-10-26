"""Restore the recorded solver bytes over a disposable checkout of the recorded commit."""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--repo', type=Path, required=True, help='repository containing the recorded Git commit')
parser.add_argument('--destination', type=Path, required=True, help='disposable checkout or source-only verification directory')
parser.add_argument('--candidate', action='store_true')
args = parser.parse_args()
home = Path(__file__).resolve().parent
repo, destination = args.repo.resolve(), args.destination.resolve()
if destination == repo:
    parser.error('use a disposable destination, not the source repository')
baseline = json.loads((home / 'baseline-manifest.json').read_text(encoding='utf-8'))
manifest = json.loads((home / ('candidate-manifest.json' if args.candidate else 'baseline-manifest.json')).read_text(encoding='utf-8'))
hasher = hashlib.sha256()
for name in sorted(manifest['sources']):
    relative = Path(name)
    if relative.is_absolute() or '..' in relative.parts or relative.parts[:2] not in [('app', 'physics'), ('app', 'sim'), ('app', 'failures')]:
        raise ValueError('invalid source path: ' + name)
    overlay = home / 'baseline-source' / name
    if overlay.is_file():
        raw = overlay.read_bytes()
    else:
        raw = subprocess.check_output(['git', '-C', str(repo), 'show', baseline['head'] + ':' + name])
        raw = raw.replace(b'\r\n', b'\n')
        if baseline['line_endings'][name] == 'crlf':
            raw = raw.replace(b'\n', b'\r\n')
    if args.candidate and (home / 'candidate-source' / name).is_file():
        raw = (home / 'candidate-source' / name).read_bytes()
    assert hashlib.sha256(raw).hexdigest() == manifest['sources'][name], name
    target = destination / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(raw)
    hasher.update(('res://' + name.removeprefix('app/')).encode())
    hasher.update(raw)
assert hasher.hexdigest() == manifest['solver_sha256']
if args.candidate:
    for source in (home / 'verification-source').rglob('*.gd'):
        target = destination / source.relative_to(home / 'verification-source')
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(source.read_bytes())
print(json.dumps({'candidate': args.candidate, 'sources': len(manifest['sources']), 'solver_sha256': hasher.hexdigest(), 'verified': True}))
