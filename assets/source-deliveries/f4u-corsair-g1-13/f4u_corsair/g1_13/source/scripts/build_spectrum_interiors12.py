from pathlib import Path
import shutil
P=Path(__file__).resolve().parents[2];D=P/'textures/liveries/spectrum/interiors';D.mkdir(parents=True,exist_ok=True)
shutil.copy2(P/'textures/interiors/layout.json',D/'layout.json')
source=Path(__file__).with_name('build_interior_atlas19.py').read_text()
source=source.replace("D=P/'textures/interiors'","D=P/'textures/liveries/spectrum/interiors'").replace('label=f"57 /','label=f"SW /').replace('Corsair 57 inner doors g1.9','Corsair Spectrum inner doors g1.12')
exec(compile(source,str(Path(__file__).with_name('build_interior_atlas19.py')),'exec'))
