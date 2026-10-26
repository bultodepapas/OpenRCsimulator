from pathlib import Path
path = Path('docs/advanced-ground-flight-physics-masterplan.md')
raw = path.read_bytes()
needle = b'| GP-12 recorded input roles (2026-10-26) |'
assert raw.count(needle) == 1
row = ('| GP-12 fixed-gear brake input (2026-10-26) | '
       '[256 focused and 3,247 existing production assertions plus 13 Python tests]'
       '(research/ground-physics/GP-12/evidence/fixed-brake-input/README.md): '
       'Session/Main admit a shared brake channel only for explicit profile hardware; '
       'checkpoint, replay, reset and release preserve role identity. Legacy Trace v17 '
       'declares its extra command while older physical validators refuse it. '
       'Historical fixed/retractable outputs and six candidate replay tapes remain '
       'compatible. Stock authoring, differential/airborne mechanics, Workshop UI '
       'and physical calibration remain open. |\n').encode()
assert b'| GP-12 fixed-gear brake input (2026-10-26) |' not in raw
path.write_bytes(raw.replace(needle, row + needle, 1))
