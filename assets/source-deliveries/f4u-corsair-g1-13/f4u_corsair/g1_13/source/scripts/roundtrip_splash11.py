"""Reimport the delivered GLB and audit all transforms and section tags."""
from pathlib import Path
P=Path(__file__).resolve().parents[2]
source=(P/'source/scripts/roundtrip.py').read_text().replace("P/'export/aircraft.glb'","P/'export/aircraft_splash.glb'").replace("P/'previews/roundtrip.json'","P/'previews/splash-roundtrip.json'")
exec(compile(source,str(P/'source/scripts/roundtrip.py'),'exec'))
