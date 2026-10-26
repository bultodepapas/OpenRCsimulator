from pathlib import Path
import hashlib
import json
import shutil

ROOT = Path.cwd()
HERE = Path(__file__).resolve().parent
OUT = ROOT / 'docs/research/ground-physics/GP-12/evidence/fixed-brake-import'
assert not OUT.exists()
OUT.mkdir(parents=True)
def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
def copy(source, name):
    destination = OUT / name
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, destination)
clone_record = json.loads((HERE / 'clone.json').read_text())
clone = Path(clone_record['clone'])
for item in clone_record['files']:
    assert sha(clone / item['path']) == item['sha256'], item['path']
assert not list(clone.rglob('*.translation'))
(HERE / 'clone-result.json').write_text(json.dumps({'format': 'openrc-raw-csv-clone-result v1', 'unchanged_files': 4, 'generated_translation_files': 0, 'check': 'fresh-clone-raw-csv strict checked import', 'shared_tree_staged': False}, indent=2) + '\n', encoding='utf-8')
for name in ['fixed_brake_trace_stik.csv', 'fixed_brake_trace_flaps.csv']:
    for suffix in ['', '.import']:
        copy(ROOT / 'app/tests/fixtures' / (name + suffix), 'source/' + name + suffix)
for source in HERE.rglob('*'):
    if source.is_file():
        copy(source, 'construction/' + source.relative_to(HERE).as_posix())
for source in (ROOT / 'tmp/gp12-shaft-capacity/main-import-repair').rglob('*'):
    if source.is_file() and source.name in ['engine.log', 'report.json']:
        copy(source, 'initial-main-import/' + source.parent.name + '/' + source.name)
copy(clone / 'project.godot', 'clone/project.godot')
copy(clone / '.gitattributes', 'clone/.gitattributes')
(OUT / '.gitattributes').write_text('** -text whitespace=cr-at-eol\n**/*.log -whitespace\n', encoding='utf-8')
(OUT / 'README.md').write_text('''# GP-12: numerical CSV import mode

2026-10-26 followup to the fixed-brake input cohort. Normal Godot import first
treated the two numerical CSV fixtures as translations, producing two warnings.
The same cold-cache pass generated a missing Japanese font and encountered ten
asset MD5 diagnostics. The rejected complete report is retained separately.

The two fixture `.csv.import` files now declare `remap/importer="keep"`, the
engine's supported raw-file mode. This follows the [official import guide](https://docs.godotengine.org/en/4.5/tutorials/assets_pipeline/import_process.html)
and the exact pinned [4d10419ca importer implementation](https://github.com/godotengine/godot/blob/4d10419ca/editor/file_system/editor_file_system.cpp#L618).
No CSV bytes, physics, input roles or expected output hashes changed.

The subsequent full-project standard import completed with zero engine errors
and warnings. A separate disposable Git autocrlf clone containing both raw CSVs,
their import settings and a minimal project also imported cleanly from an empty
cache: all four fixture/configuration files stayed byte-identical and no
translation files were generated. This is a cold fixture-import check, not a
whole-application fresh-clone qualification or a full test-suite result.

The normal import regenerated defaults for three embedded landscape textures.
Their pre-import authored UID/compression/mipmap settings were restored with
source/commit guards and retained records; no landscape source was changed.
The next import honored them. Newly generated script UID companions are normal
Godot metadata for the new scripts, not simulation state.

`manifest.json` binds the selected sources, rejected/passing receipts and
construction records. Original fixed-brake evidence remains unchanged.
''', encoding='utf-8')
files = []
for source in sorted(OUT.rglob('*')):
    if source.is_file():
        files.append({'path': source.relative_to(OUT).as_posix(), 'bytes': source.stat().st_size, 'sha256': sha(source)})
(OUT / 'manifest.json').write_text(json.dumps({'format': 'openrc-fixed-brake-import-evidence v1', 'files': files}, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'payloads': len(files), 'manifest_sha256': sha(OUT / 'manifest.json'), 'cold_clone_files_verified': 4, 'translation_files': 0}, indent=2))
