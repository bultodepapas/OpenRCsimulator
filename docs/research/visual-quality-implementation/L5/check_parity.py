"""Compare complete L5 capture runs without accepting stale/unlisted screenshots.

Usage: python3 check_parity.py BEFORE/captures AFTER/captures > parity.json
The four legacy pause/hint snapshots use live wall time and are not pixel goldens.
"""
import hashlib
import json
from pathlib import Path
import sys


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inventory(root):
    main = json.loads((root / 'run-manifest.json').read_text())
    matrix_path = root / main['visual_quality_manifest']
    assert main['complete'] is True
    assert sha(matrix_path) == main['visual_quality_manifest_sha256']
    matrix = json.loads(matrix_path.read_text())
    assert matrix['complete'] is True
    assert len(main['captures']) == 46 and len(matrix['captures']) == 66
    entries = {}
    for folder, rows in [(Path('.'), main['captures']), (Path('vq01b'), matrix['captures'])]:
        for row in rows:
            name = str(folder / row['image'])
            assert name not in entries
            png = root / name
            metadata = png.with_suffix('.json')
            native = json.loads(metadata.read_text())
            assert sha(png) == native['sha256']
            # Both producers record their native manifest hash and image hash.
            assert sha(metadata) == (row.get('manifest_sha256') or row['capture_manifest_sha256'])
            assert sha(png) == row['sha256']
            entries[name] = sha(png)
    assert sha(root / 'trace-physics.csv') == main['trace_sha256']
    return entries


def main():
    before, after = map(Path, sys.argv[1:])
    a, b = inventory(before), inventory(after)
    assert a.keys() == b.keys()
    live = {'ui-pause-en.png', 'ui-pause-es.png', 'ui-hint-en.png', 'ui-hint-es.png'}
    fixed = sorted(a.keys() - live)
    different = [name for name in fixed if a[name] != b[name]]
    trace_a, trace_b = [
        '\n'.join(line for line in (root / 'trace-physics.csv').read_text().splitlines()
                  if not line.startswith('#')) for root in (before, after)
    ]
    result = {'format': 'openrc-l5-parity v1', 'before': str(before), 'after': str(after),
              'inventory_count_each': len(a), 'fixed_image_count': len(fixed),
              'identical_images': [name for name in fixed if name not in different],
              'different_images': different, 'excluded_live_snapshots': sorted(live),
              'trace_rows_identical': trace_a == trace_b,
              'trace_data_sha256': hashlib.sha256(trace_a.encode()).hexdigest(),
              'baseline_images_sha256': a, 'result_images_sha256': b}
    print(json.dumps(result, indent=2, sort_keys=True))
    return 1 if different or trace_a != trace_b else 0


if __name__ == '__main__':
    sys.exit(main())
