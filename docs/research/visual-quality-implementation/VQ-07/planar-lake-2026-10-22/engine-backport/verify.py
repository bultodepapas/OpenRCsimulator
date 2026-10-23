"""Compare retained native custom-engine controls and images; no Godot launch."""
from pathlib import Path
import hashlib
import json
import re
import sys
from PIL import Image, ImageChops, ImageStat

root = Path(sys.argv[1])
rows = []
reference = None
for phase in ('baseline', 'patched'):
    directory = root / 'runs' / phase
    before = json.loads((directory / 'app-before.json').read_text())
    assert before == json.loads((directory / 'app-after.json').read_text())
    reference = before if reference is None else reference
    assert reference == before, 'Tracked app bytes differ between engine builds'
    for label, baseline_count in [('no-probe', 0), ('one-probe', 7), ('four-worlds', 28),
                                  ('high-probe', 7), ('high-planar', 7), ('standard-planar', 0)]:
        paths = list((directory / 'checks').glob(label + '-*/report.json'))
        assert len(paths) == 1, (phase, label, paths)
        receipt = json.loads(paths[0].read_text())
        assert receipt['ok'] and receipt['counts']['error'] == 0, (phase, label, receipt)
        log_bytes = paths[0].with_name('engine.log').read_bytes()
        assert hashlib.sha256(log_bytes).hexdigest() == receipt['log_sha256']
        log = log_bytes.decode('utf-8')
        count = sum(map(int, re.findall(r'(\d+) RIDs of type "Texture" were leaked', log)))
        assert count == (baseline_count if phase == 'baseline' else 0), (phase, label, count)
        rows.append({'phase': phase, 'case': label, 'leaked_texture_rids': count,
                     'warnings': receipt['counts']['warning']})
def image_difference(before_path, after_path):
    with Image.open(before_path) as a, Image.open(after_path) as b:
        assert a.size == b.size == (1920, 1080)
        diff = ImageChops.difference(a.convert('RGB'), b.convert('RGB'))
        red, green, blue = diff.split()
        maximum = ImageChops.lighter(ImageChops.lighter(red, green), blue)
        return {
            'rgb_pixel_identical': diff.getbbox() is None,
            'changed_pixels': a.width * a.height - maximum.histogram()[0],
            'max_channel_delta_255': maximum.getextrema()[1],
            'mean_absolute_channel_delta_255': sum(ImageStat.Stat(diff).mean) / 3,
            'bbox': diff.getbbox(),
        }


images = []
for case in ('high-probe', 'high-planar', 'standard-planar'):
    for phase in ('baseline', 'patched'):
        report = json.loads((root / 'runs' / phase / case / 'report.json').read_text())
        assert report['complete'] and report['viewport'] == [1920, 1080]
        assert all(row['active'] == (case == 'high-planar') for row in report['cases'])
        assert report['profile']['active'] == ('standard' if case.startswith('standard') else 'high_experimental')
    for view in ('low', 'roll60', 'high'):
        before_path = root / 'runs/baseline' / case / (view + '.png')
        after_path = root / 'runs/patched' / case / (view + '.png')
        difference = image_difference(before_path, after_path)
        images.append({'case': case, 'view': view, **difference})
        if case.startswith('high'):
            assert difference['rgb_pixel_identical'], (case, view, 'High pixel mismatch')
repeats = []
for phase in ('baseline', 'patched'):
    paths = list((root / 'checks').glob(phase + '-standard-repeat-*/report.json'))
    assert len(paths) == 1
    receipt = json.loads(paths[0].read_text())
    assert receipt['ok'] and receipt['counts']['error'] == receipt['counts']['warning'] == 0
    assert hashlib.sha256(paths[0].with_name('engine.log').read_bytes()).hexdigest() == receipt['log_sha256']
    for view in ('low', 'roll60', 'high'):
        repeats.append({'phase': phase, 'view': view, **image_difference(
            root / 'runs' / phase / 'standard-planar' / (view + '.png'),
            root / ('repeat-' + phase) / (view + '.png'))})
result = {'lifecycle': rows, 'images': images, 'native_cases': len(rows),
          'matched_images': sum(row['rgb_pixel_identical'] for row in images),
          'standard_within_build_repeats': repeats,
          'high_pixel_parity': True,
          'standard_pixel_parity': all(row['rgb_pixel_identical'] for row in images if row['case'].startswith('standard')),
          'standard_disposition': 'Exact parity failed. Within-build repeats also vary; these controls do not uniquely attribute the cross-build differences to the patch. No tolerance-based acceptance or root cause is inferred.',
          'performance_qualification': False,
          'scope': 'Native Windows custom editor builds; not official binary, release template or cross-platform qualification'}
(root / 'comparison.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result, indent=2))
