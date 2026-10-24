"""Reauthor existing interior atlas with naval identity; keep racer source untouched."""
from pathlib import Path
import shutil
P=Path(__file__).resolve().parents[2];D=P/'textures/liveries/midnight/interiors';D.mkdir(parents=True,exist_ok=True)
shutil.copy2(P/'textures/interiors/layout.json',D/'layout.json')
source=Path(__file__).with_name('build_interior_atlas19.py').read_text()
source=source.replace("D=P/'textures/interiors'","D=P/'textures/liveries/midnight/interiors'").replace('label=f"57 /','label=f"308 /').replace('Corsair 57 inner doors g1.9','Naval Corsair 308 inner doors g1.10')
exec(compile(source,str(Path(__file__).with_name('build_interior_atlas19.py')),'exec'))
