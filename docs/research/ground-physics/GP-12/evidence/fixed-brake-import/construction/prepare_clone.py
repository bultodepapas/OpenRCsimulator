from pathlib import Path
import hashlib
import json
import shutil
import subprocess
import tempfile

ROOT = Path.cwd()
HERE = Path(__file__).resolve().parent
transport = Path(tempfile.mkdtemp(prefix='gp12-csv-import-clone-', dir=ROOT / 'tmp'))
origin, clone = transport / 'origin', transport / 'clone'
origin.mkdir()
(origin / '.gitignore').write_text('.godot/\n', encoding='utf-8')
(origin / 'project.godot').write_text('config_version=5\n\n[application]\nconfig/name="Fixed Brake CSV Import Fixture"\nconfig/features=PackedStringArray("4.8")\n\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n', encoding='utf-8')
pins = []
for base in ['fixed_brake_trace_stik.csv', 'fixed_brake_trace_flaps.csv']:
    for suffix in ['', '.import']:
        source = ROOT / 'app/tests/fixtures' / (base + suffix)
        target = origin / 'tests/fixtures' / source.name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        pins.append({'path': target.relative_to(origin).as_posix(), 'sha256': hashlib.sha256(source.read_bytes()).hexdigest()})
(origin / '.gitattributes').write_text('tests/fixtures/** -text\n', encoding='utf-8')
def git(*args, cwd):
    return subprocess.run(['git', *args], cwd=cwd, check=True, capture_output=True, text=True).stdout
git('init', '-q', cwd=origin)
git('add', '.', cwd=origin)
git('-c', 'user.name=Evidence transport', '-c', 'user.email=evidence@localhost', 'commit', '-qm', 'Raw CSV fixture import verification', cwd=origin)
git('-c', 'core.autocrlf=true', 'clone', '-q', str(origin), str(clone), cwd=transport)
receipt = {'format': 'openrc-raw-csv-clone v1', 'origin': str(origin), 'clone': str(clone), 'files': pins, 'shared_tree_staged': False}
(HERE / 'clone.json').write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')
print(str(clone))
