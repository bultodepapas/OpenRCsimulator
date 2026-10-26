from pathlib import Path
import hashlib
import json
import shutil
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
OUT = ROOT / 'docs/research/ground-physics/GP-12/evidence/fixed-brake-input'
assert not (OUT / 'manifest.json').exists(), 'Never overwrite a sealed cohort'
OUT.mkdir(parents=True, exist_ok=True)
def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
def copy(source, relative):
    target = OUT / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, target)
promotion = json.loads((HERE / 'root-promotion.json').read_text())
test_path = 'app/tests/test_fixed_gear_brake_input.gd'
assert sha(HERE / 'before-retention-test.gd') == promotion['files'][test_path]
retention = {'format': 'openrc-fixed-brake-test-retention v1', 'path': test_path,
    'before_sha256': promotion['files'][test_path], 'after_sha256': sha(ROOT / test_path),
    'change': 'Optional --retain-evidence skips deletion of generated test outputs; default cleanup unchanged',
    'reason': 'Initial packaging found the default test had deleted both already-verified ORFLs; rerun retains actual artifacts',
    'runtime_changed': False}
(HERE / 'root-retention-followup.json').write_text(json.dumps(retention, indent=2) + '\n', encoding='utf-8')
for path, expected in promotion['files'].items():
    source = ROOT / path
    if path == test_path:
        expected = retention['after_sha256']
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
recordings = sorted(HERE.glob('candidate-*.orfl'))
assert len(recordings) == 2, 'Retain exactly the two installed fixture recordings'
for source in recordings:
    copy(source, 'recordings/' + source.name)
for source in HERE.glob('trace-*.csv'):
    copy(source, 'production-checks/' + source.name)
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
