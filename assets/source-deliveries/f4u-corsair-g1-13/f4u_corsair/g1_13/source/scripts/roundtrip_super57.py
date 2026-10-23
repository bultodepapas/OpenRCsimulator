from pathlib import Path
source=Path(__file__).with_name('roundtrip.py').read_text()
source=source.replace('export/aircraft.glb','export/aircraft_super57.glb').replace('previews/roundtrip.json','previews/super57-roundtrip.json')
exec(compile(source,str(Path(__file__).with_name('roundtrip.py')),'exec'))
