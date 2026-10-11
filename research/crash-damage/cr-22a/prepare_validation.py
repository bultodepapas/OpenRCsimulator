"""Snapshot the working repository without altering concurrent developer files."""
from pathlib import Path
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parents[3]
target = root / '.tools' / sys.argv[1]
target.mkdir(parents=True, exist_ok=True)
names = subprocess.check_output(['git','ls-files','-z','--cached','--others','--exclude-standard'], cwd=root).decode().split('\0')
for name in names:
    if not name or name.startswith('.tools/'):
        continue
    source = root / name
    if not source.is_file():
        continue
    dest = target / name
    dest.parent.mkdir(parents=True, exist_ok=True)
    if source.suffix == '.sh':
        dest.write_bytes(source.read_bytes().replace(b'\r\n',b'\n'))
    else:
        shutil.copy2(source, dest)
subprocess.run(['git','init','-q',str(target)],check=True)
tools = target / '.tools'
tools.mkdir(exist_ok=True)
shutil.copy2(root/'.tools/Godot_v4.7.2-stable_linux.x86_64', tools/'Godot_v4.7.2-stable_linux.x86_64')
print(target)
