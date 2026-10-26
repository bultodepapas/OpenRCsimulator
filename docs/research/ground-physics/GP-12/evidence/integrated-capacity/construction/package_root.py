from pathlib import Path
import gzip
import hashlib
import json
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
OUT = ROOT / 'docs/research/ground-physics/GP-12/evidence/integrated-capacity'

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def copy(source, relative):
    target = OUT / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, target)

assert not OUT.exists(), 'Never overwrite a sealed cohort'
review_path = HERE / 'review-v1/manifest.json'
assert digest(review_path) == 'adfd3a03de06335c38c42c89c362b3f11d294e00e9265c8a658347fabfff0780'
review = json.loads(review_path.read_text())
final_path = HERE / 'review-v1/final-integration.json'
assert digest(final_path) == '34c671ed4804b265df8b3d63296968ba59e68994f74c86699c3666f2b459cc56'
final = json.loads(final_path.read_text())
OUT.mkdir(parents=True)
for item in review['frozen_scripts']:
    source = ROOT / item['frozen']['path']
    assert digest(source) == item['frozen']['sha256'], str(source)
    copy(source, 'frozen/' + source.relative_to(HERE / 'review-v1/frozen').as_posix())
for item in review['assets']:
    source = ROOT / item['path']
    assert digest(source) == item['sha256'], str(source)
    copy(source, 'assets/' + item['path'])
for item in final['payload']:
    for role in ['production', 'validated']:
        source = ROOT / item[role]['path']
        assert digest(source) == item[role]['sha256'], str(source)
        copy(source, role + '/' + item['target'])
for name in ['manifest.json', 'final-integration.json']:
    copy(HERE / 'review-v1' / name, 'construction/' + name)
for name in ['root-promotion.json', 'promote_root.py', 'seal_trajectory.py', 'freeze_review.py', 'source-integration-followup.md', 'package_root.py']:
    copy(HERE / name, 'construction/' + name)
for source in (HERE / 'root-before').rglob('*'):
    if source.is_file():
        copy(source, 'before/' + source.relative_to(HERE / 'root-before').as_posix())
for group in ['checks', 'production-checks']:
    for source in (HERE / group).rglob('*'):
        if source.is_file() and source.name in ['report.json', 'engine.log']:
            copy(source, group + '/' + source.relative_to(HERE / group).as_posix())
compressed = []
for tape in final['tapes']:
    source = ROOT / tape['binary']['path']
    assert digest(source) == tape['binary']['sha256'], str(source)
    relative = 'trajectories/' + source.name + '.gz'
    target = OUT / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(gzip.compress(source.read_bytes(), mtime=0))
    assert gzip.decompress(target.read_bytes()) == source.read_bytes()
    compressed.append({'path': relative, 'uncompressed': tape['binary']})
(OUT / 'trajectories/encoding.json').write_text(json.dumps(compressed, indent=2) + '\n', encoding='utf-8')

# Oracle followup is assembled only after independent generation and installed checks.
oracle = HERE / 'test-oracle-followup'
promotion = json.loads((oracle / 'root-promotion.json').read_text())
for path, sha in promotion['files'].items():
    source = ROOT / path
    assert digest(source) == sha, path
    copy(source, 'installed/' + path)
for source in oracle.rglob('*'):
    if source.is_file() and source.suffix not in ['.uid', '.pyc']:
        copy(source, 'oracle-followup/' + source.relative_to(oracle).as_posix())
copy(HERE / 'evidence-readme.md', 'README.md')
(OUT / '.gitattributes').write_text('** -text whitespace=cr-at-eol\n**/*.log -whitespace\n', encoding='utf-8')
files = []
for source in sorted(OUT.rglob('*')):
    if source.is_file():
        files.append({'path': source.relative_to(OUT).as_posix(), 'bytes': source.stat().st_size, 'sha256': digest(source)})
(OUT / 'manifest.json').write_text(json.dumps({'format': 'openrc-integrated-capacity-evidence v1', 'files': files}, indent=2) + '\n', encoding='utf-8')

transport = Path(tempfile.mkdtemp(prefix='gp12-capacity-transport-', dir=ROOT / 'tmp'))
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
receipt = {'files_verified': len(files) + 1, 'manifest_sha256': digest(OUT / 'manifest.json'), 'transport': str(transport), 'shared_tree_staged': False}
(HERE / 'root-package-receipt.json').write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')
print(json.dumps(receipt, indent=2))
