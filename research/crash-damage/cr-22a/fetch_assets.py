"""Fetch the pinned CC0 Kenney source; retain only used, unmodified PNGs."""
import hashlib
import io
import json
from pathlib import Path
import urllib.request
import zipfile

URL = 'https://kenney.nl/media/pages/assets/smoke-particles/23249a0d35-1677695171/kenney_smoke-particles.zip'
SHA256 = '97a1d09c66e4fd6c247c8ea87f84c0cc59caaeceae19414c995afb1616a1e1c9'
ROOT = Path(__file__).resolve().parents[3]

def main():
    raw = urllib.request.urlopen(URL).read()
    if hashlib.sha256(raw).hexdigest() != SHA256:
        raise ValueError('Source archive checksum changed; review before importing')
    z = zipfile.ZipFile(io.BytesIO(raw))
    target = ROOT / 'app/assets/crash'
    target.mkdir(parents=True, exist_ok=True)
    files = {'smoke.png': 'PNG/White puff/whitePuff00.png', 'flame.png': 'PNG/Explosion/explosion00.png'}
    entries = []
    for name, member in files.items():
        data = z.read(member)
        (target / name).write_bytes(data)
        entries.append(dict(path=name, source_member=member, sha256=hashlib.sha256(data).hexdigest()))
    (target / 'LICENSE-Kenney.txt').write_bytes(z.read('license.txt'))
    (target / 'sources.json').write_text(json.dumps(dict(author='Kenney', license='CC0-1.0', page='https://kenney.nl/assets/smoke-particles', download=URL, retrieved='2026-10-11', archive_sha256=hashlib.sha256(raw).hexdigest(), modifications='None', files=entries), indent=2)+'\n')

if __name__ == '__main__':
    main()
