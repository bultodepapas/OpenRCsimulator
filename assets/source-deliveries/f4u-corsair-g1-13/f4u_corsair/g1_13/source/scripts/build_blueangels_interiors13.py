from pathlib import Path
import shutil
P=Path(__file__).resolve().parents[2];D=P/'textures/liveries/blueangels/interiors';D.mkdir(parents=True,exist_ok=True)
shutil.copy2(P/'textures/interiors/layout.json',D/'layout.json')
source=Path(__file__).with_name('build_interior_atlas19.py').read_text()
source=source.replace("D=P/'textures/interiors'","D=P/'textures/liveries/blueangels/interiors'").replace('label=f"57 /','label=f"BA /').replace('Corsair 57 inner doors g1.9','Corsair Blue Angels inner doors g1.13')
exec(compile(source,str(Path(__file__).with_name('build_interior_atlas19.py')),'exec'))
