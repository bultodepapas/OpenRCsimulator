"""Check the bounded camera follow-up, without treating paused runs as flight."""
from pathlib import Path
import json
import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
candidate = json.loads((HERE / 'candidate/edges.json').read_text())
assert candidate['complete']
cases = {case['name']: case for case in candidate['cases']}
for name, expected in [('raised-eye', True), ('lowered-eye', False), ('sky-only', False), ('restored', True)]:
    case = cases[name]
    assert case['active'] == expected, name
    assert case['probe_mask'] == (0 if expected else 2), name
    assert case['update_mode'] == (4 if expected else 0), name
for name in ('raised-eye', 'offscreen-jet', 'restored'):
    case = cases[name]
    assert np.max(np.abs(np.array(case['mirror_uv']) - case['reflected_uv'])) < 0.001, name
assert cases['offscreen-jet']['source_uv'][0] > 1.0
assert all(0.0 < value < 1.0 for value in cases['offscreen-jet']['reflected_uv'])
# Isolate the reflected jet below the separate sun-shadow region.
shown = np.asarray(Image.open(HERE / 'candidate/offscreen-jet.png')).astype(int)
hidden = np.asarray(Image.open(HERE / 'candidate/offscreen-hidden.png')).astype(int)
delta = np.abs(shown[520:660, 1100:1280] - hidden[520:660, 1100:1280])
changed = int(np.any(delta > 2, axis=2).sum())
assert changed > 200, 'reflected-aircraft ROI is absent'
print('Offscreen-aircraft reflection ROI changed pixels >2/255:', changed)
motion = json.loads((HERE / 'candidate/motion.json').read_text())
frames = [row for row in motion['samples'] if 'frame' in row]
assert motion['complete'] and len(frames) == 121 and all(row['active'] for row in frames)
parity = json.loads((HERE / 'motion-parity.json').read_text())
assert len(parity) == 121 and all(row['changed_pixels'] == 0 for row in parity)
print('All 121 orbit/roll/FOV frames remain pixel identical after the gate repair.')
for mode in ('control', 'planar'):
    report = json.loads((HERE / 'native-ineligible' / (mode + '-summary.json')).read_text())
    assert report['collection_valid'] and not report['performance_pass']
    assert report['active_flight_qualifier_count'] == 0
    print(mode, 'native run ineligible:', report['runs'][0]['active_flight_reasons'])
