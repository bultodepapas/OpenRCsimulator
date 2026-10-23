"""Run the established structural and export audit against the fourth variant."""
from pathlib import Path
P=Path(__file__).resolve().parents[2]
source=(P/'source/scripts/verify.py').read_text()
source=source.replace("meta['glb_sha256']","meta['additional_spectrum_delivery']['glb_sha256']").replace("P/'export/aircraft.glb'","P/'export/aircraft_spectrum.glb'").replace("P/'verification.json'","P/'previews/spectrum-structural-verification.json'")
exec(compile(source,str(P/'source/scripts/verify.py'),'exec'))
