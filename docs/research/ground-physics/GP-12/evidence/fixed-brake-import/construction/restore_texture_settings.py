from pathlib import Path
import hashlib
import json
import subprocess

ROOT = Path.cwd()
HERE = Path(__file__).resolve().parent
paths = {
    'app/assets/landscape/track-signage/flagCheckersSmall_checkers.png.import': 'uid://3jpce0fp0s08',
    'app/assets/landscape/vegetation/models/landscapelab_tree_2026/pine/pine_joined_Image_1.png.import': 'uid://bu6b6e3gv4251',
    'app/assets/landscape/vegetation/models/landscapelab_tree_2026/quercus/quercus_Image_1.png.import': 'uid://c5q22fc0moo5v',
}
def sha(raw):
    return hashlib.sha256(raw).hexdigest()
records = []
for name, generated_uid in paths.items():
    path = ROOT / name
    current = path.read_bytes()
    assert generated_uid.encode() in current and b'mipmaps/generate=false' in current, name
    original = subprocess.run(['git', 'show', 'd0e3829ff:' + name], check=True, capture_output=True).stdout
    head = subprocess.run(['git', 'show', 'HEAD:' + name], check=True, capture_output=True).stdout
    assert head == original, 'Preserve newer committed settings: ' + name
    assert b'mipmaps/generate=true' in original, name
    backup = HERE / 'generated-texture-settings' / path.name
    backup.parent.mkdir(parents=True, exist_ok=True)
    backup.write_bytes(current)
    assert path.read_bytes() == current, 'Preserve concurrent edits: ' + name
    path.write_bytes(original)
    records.append({'path': name, 'automatic_import_sha256': sha(current), 'restored_authored_sha256': sha(original)})
(HERE / 'texture-settings.json').write_text(json.dumps({'reason': 'Normal import regenerated embedded texture defaults; preserve pre-import authored mipmaps/compression/UID settings', 'files': records}, indent=2) + '\n', encoding='utf-8')
print('Preserved three pre-import authored texture configurations')
