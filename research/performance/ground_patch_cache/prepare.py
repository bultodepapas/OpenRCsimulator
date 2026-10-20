"""Prepare a disposable paired field comparison; production sources stay untouched."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--work', type=Path, required=True, help='New directory outside app/')
parser.add_argument('--reference', type=Path, required=True, help='Original ground_features.gd')
parser.add_argument('--candidate', type=Path)
args = parser.parse_args()
repo = Path(__file__).resolve().parents[3]
work = args.work.resolve()
if work.is_relative_to(repo / 'app'):
    parser.error('Keep disposable scripts outside app/')
reference = args.reference.read_bytes()
candidate = (args.candidate or repo / 'app/scenery/ground_features.gd').read_bytes()
work.mkdir(parents=True, exist_ok=False)
for variant, source in [('reference', reference), ('candidate', candidate)]:
    (work / f'ground_{variant}.gd').write_bytes(source)
    scenery = (repo / 'app/scenery/scenery.gd').read_text()
    old = 'res://scenery/ground_features.gd'
    assert scenery.count(old) == 1
    scenery = scenery.replace(old, (work / f'ground_{variant}.gd').as_posix())
    (work / f'scenery_{variant}.gd').write_text(scenery, newline='\n')
    field = (repo / 'app/render/field.gd').read_text()
    old = 'res://scenery/scenery.gd'
    assert field.count(old) == 1
    field = field.replace(old, (work / f'scenery_{variant}.gd').as_posix())
    (work / f'field_{variant}.gd').write_text(field, newline='\n')
shutil.copy2(Path(__file__).with_name('field_compare.gd'), work / 'field_compare.gd')
identities = {p.relative_to(repo).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
              for p in (repo / 'app').rglob('*')
              if p.is_file() and '.godot' not in p.parts and p.suffix in ('.gd', '.json', '.godot')}
(work / 'source-hashes.json').write_text(json.dumps(identities, indent=2))
print(work / 'field_compare.gd')
