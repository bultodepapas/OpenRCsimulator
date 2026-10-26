from pathlib import Path
import hashlib
import json
import shutil
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
OUT = ROOT / 'docs/research/ground-physics/GP-12/evidence/fixed-brake-input'
assert not OUT.exists(), 'Never overwrite a sealed cohort'
OUT.mkdir(parents=True)
def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
def copy(source, relative):
    target = OUT / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, target)
promotion = json.loads((HERE / 'root-promotion.json').read_text())
for path, expected in promotion['files'].items():
    source = ROOT / path
    assert sha(source) == expected, path
    copy(source, 'source/' + path)
copy(ROOT / 'app/test.sh', 'source/app/test.sh')
for source in (HERE / 'root-before').rglob('*'):
    if source.is_file():
        copy(source, 'before/' + source.relative_to(HERE / 'root-before').as_posix())
for source in HERE.iterdir():
    if source.is_file() and source.suffix in ['.py', '.gd', '.json', '.md', '.patch'] and source.name != 'evidence-readme.md':
        copy(source, 'construction/' + source.name)
for group in ['checks', 'production-checks']:
    for source in (HERE / group).rglob('*'):
        if source.is_file() and source.name in ['engine.log', 'report.json']:
            copy(source, group + '/' + source.relative_to(HERE / group).as_posix())
for name in ['candidate-7461546.orfl', 'candidate-7679400.orfl']:
    copy(HERE / name, 'recordings/' + name)
copy(ROOT / 'tmp/flight-log-2558929/verification.json', 'production-checks/existing-flight-log-verification.json')
copy(HERE / 'evidence-readme.md', 'README.md')
(OUT / '.gitattributes').write_text('** -text whitespace=cr-at-eol\n**/*.log -whitespace\n', encoding='utf-8')
files = []
for source in sorted(OUT.rglob('*')):
    if source.is_file():
        files.append({'path': source.relative_to(OUT).as_posix(), 'bytes': source.stat().st_size, 'sha256': sha(source)})
(OUT / 'manifest.json').write_text(json.dumps({'format': 'openrc-fixed-brake-input-evidence v1', 'files': files, 'scope': 'Selected source/test/recording evidence, not a full repository closure'}, indent=2) + '\n', encoding='utf-8')

transport = Path(tempfile.mkdtemp(prefix='gp12-fixed-brake-transport-', dir=ROOT / 'tmp'))
origin, clone = transport / 'origin', transport / 'clone'
shutil.copytree(OUT, origin / 'evidence')
def git(*args, cwd):
    return subprocess.run(['git', *args], cwd=cwd, check=True, capture_output=True, text=True).stdout
git('init', '-q', cwd=origin)
git('config', 'core.autocrlf', 'true', cwd=origin)
git('add', 'evidence', cwd=origin)
git('-c', 'user.name=Evidence transport', '-c', 'user.email=evidence@localhost', 'commit', '-qm', 'Evidence transport verification', cwd=origin)
git('-c', 'core.autocrlf=true', 'clone', '-q', str(origin), str(clone), cwd=transport)
for source in OUT.rglob('*'):
    if source.is_file():
        assert source.read_bytes() == (clone / 'evidence' / source.relative_to(OUT)).read_bytes(), str(source)
receipt = {'files_verified': len(files) + 1, 'manifest_sha256': sha(OUT / 'manifest.json'), 'transport': str(transport), 'shared_tree_staged': False}
(HERE / 'root-package-receipt.json').write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')
print(json.dumps(receipt, indent=2))
