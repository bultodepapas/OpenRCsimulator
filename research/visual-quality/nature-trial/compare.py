#!/usr/bin/env python3
"""Use the repository visual venv (Pillow/NumPy); compare pixels, not PNG compression."""
import json
import sys
from pathlib import Path
import numpy as np
from PIL import Image

root = Path(sys.argv[1])
reports = []
for a, b, limit in [('source', 'optimized', 0), ('source', 'merged-colors', 1),
                    ('multimesh-source', 'multimesh-merged', 1)]:
    x = np.array(Image.open(root / 'repeat-1' / f'{a}.png').convert('RGB')).astype(int)
    y = np.array(Image.open(root / 'repeat-1' / f'{b}.png').convert('RGB')).astype(int)
    diff = np.abs(x - y)
    reports.append({'a': a, 'b': b, 'max_channel_difference_8bit': int(diff.max()),
                    'mean_absolute_channel_difference_8bit': float(diff.mean()),
                    'different_pixels': int(np.any(diff > 0, axis=2).sum()),
                    'limit': limit, 'passed': bool(diff.max() <= limit)})
data = json.loads((root / 'repeat-1/result.json').read_text())
cases = {item['case']: item for item in data['results']}
assert cases['multimesh-source']['primitives'] == cases['multimesh-merged']['primitives'] == 62080
assert cases['multimesh-source']['draw_calls'] == 48
assert cases['multimesh-merged']['draw_calls'] == 24
(root / 'pixel-comparison.json').write_text(json.dumps(reports, indent=2) + '\n')
assert all(item['passed'] for item in reports), 'Pixel comparison failed; inspect JSON'
print(json.dumps(reports, indent=2))
