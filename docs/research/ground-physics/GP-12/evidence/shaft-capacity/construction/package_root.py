from pathlib import Path
import hashlib
import json
import shutil
import subprocess
import tempfile

ROOT = Path.cwd()
HERE = Path(__file__).resolve().parent
OUT = ROOT / 'docs/research/ground-physics/GP-12/evidence/shaft-capacity'
assert not OUT.exists()
OUT.mkdir(parents=True)
def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
def copy(source, name):
    target = OUT / name
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, target)
promotion = json.loads((HERE / 'root-promotion.json').read_text())
for path, expected in promotion['files'].items():
    assert sha(ROOT / path) == expected, path
    copy(ROOT / path, 'source/' + path)
for source in (HERE / 'root-before').rglob('*'):
    if source.is_file(): copy(source, 'before/' + source.relative_to(HERE / 'root-before').as_posix())
for source in HERE.iterdir():
    if source.is_file() and source.suffix in ['.py', '.gd', '.txt', '.json', '.patch', '.md'] and source.name != 'evidence-readme.md':
        copy(source, 'construction/' + source.name)
for name in ['mechanism.bin', 'results-main-oracle-final.bin']:
    copy(HERE / name, 'buffers/' + name)
for group in ['checks', 'production-checks']:
    for source in (HERE / group).rglob('*'):
        if source.is_file() and source.name in ['report.json', 'engine.log']:
            copy(source, group + '/' + source.relative_to(HERE / group).as_posix())
copy(HERE / 'evidence-readme.md', 'README.md')
(OUT / '.gitattributes').write_text('** -text whitespace=cr-at-eol\n**/*.log -whitespace\n', encoding='utf-8')
files = []
for source in sorted(OUT.rglob('*')):
    if source.is_file():
        files.append({'path': source.relative_to(OUT).as_posix(), 'bytes': source.stat().st_size, 'sha256': sha(source)})
(OUT / 'manifest.json').write_text(json.dumps({'format': 'openrc-stable-shaft-capacity-evidence v1', 'files': files, 'scope': 'Selected source, immutable original outputs and conditional checks; not a complete repository closure'}, indent=2) + '\n', encoding='utf-8')
transport = Path(tempfile.mkdtemp(prefix='gp12-shaft-transport-', dir=ROOT / 'tmp'))
origin, clone = transport / 'origin', transport / 'clone'
shutil.copytree(OUT, origin / 'evidence')
def git(*args, cwd):
    return subprocess.run(['git', *args], cwd=cwd, check=True, capture_output=True, text=True).stdout
git('init', '-q', cwd=origin)
git('config', 'core.autocrlf', 'true', cwd=origin)
git('add', 'evidence', cwd=origin)
git('-c', 'user.name=Evidence transport', '-c', 'user.email=evidence@localhost', 'commit', '-qm', 'Stable shaft evidence transport', cwd=origin)
git('-c', 'core.autocrlf=true', 'clone', '-q', str(origin), str(clone), cwd=transport)
for source in OUT.rglob('*'):
    if source.is_file():
        assert source.read_bytes() == (clone / 'evidence' / source.relative_to(OUT)).read_bytes(), str(source)
receipt = {'files_verified': len(files) + 1, 'manifest_sha256': sha(OUT / 'manifest.json'), 'transport': str(transport), 'shared_tree_staged': False}
(HERE / 'root-package-receipt.json').write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')
print(json.dumps(receipt, indent=2))
