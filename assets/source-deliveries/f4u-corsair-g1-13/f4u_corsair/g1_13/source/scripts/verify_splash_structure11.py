"""Run the established structural and export audit against the third variant."""
from pathlib import Path
P=Path(__file__).resolve().parents[2]
source=(P/'source/scripts/verify.py').read_text()
source=source.replace("meta['glb_sha256']","meta['additional_splash_delivery']['glb_sha256']").replace("P/'export/aircraft.glb'","P/'export/aircraft_splash.glb'").replace("P/'verification.json'","P/'previews/splash-structural-verification.json'")
exec(compile(source,str(P/'source/scripts/verify.py'),'exec'))
