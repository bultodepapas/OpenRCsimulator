"""Reproduce the reserved-station check and optional local scan overlays.

Core check uses only the standard library. --overlay requires Pillow and the
local source raster from US-02; annotated source images stay under references/.
"""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def interpolate(rows, z, column):
    for a, b in zip(rows, rows[1:]):
        if a[0] <= z <= b[0]:
            return a[column] + (b[column] - a[column]) * (z - a[0]) / (b[0] - a[0])
    raise ValueError('Station outside body')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--overlay', action='store_true')
    args = parser.parse_args()
    source = ROOT / 'assets/aircraft/ugly-stik-60/geometry.json'
    d = json.loads(source.read_text())
    record = json.loads((ROOT / 'research/ugly-stik/model-v3/fuselage-adoption.json').read_text())
    h = record['holdout']
    scale = record['scale_m_per_px']
    proxy = record['y_proxy_px']
    observed = h['observed_source']
    expected = {'roof': -.005 + (proxy - observed['roof_y_px']) * scale,
                'bottom': -.005 + (proxy - observed['bottom_y_px']) * scale,
                'width': observed['width_px'] * scale}
    actual = {'roof': interpolate(d['fuselage_stations'], h['z_m'], 2),
              'bottom': interpolate(d['fuselage_stations'], h['z_m'], 3),
              'width': 2 * interpolate(d['fuselage_stations'], h['z_m'], 1)}
    residuals = {k: actual[k] - expected[k] for k in expected}
    report = {'geometry_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
              'holdout_z_m': h['z_m'], 'expected_m': expected, 'model_m': actual,
              'residual_model_minus_source_m': residuals, 'allowance_m': h['acceptance_m'],
              'ok': all(abs(residuals[k]) <= h['acceptance_m'][k] for k in residuals),
              'limits': ['Compares visual stations against a reserved raster reading; not real-airframe accuracy',
                         'Nominal page scale and estimated vertical proxy are recorded in source evidence']}
    (ROOT / 'research/ugly-stik/model-v3/dimension-check.json').write_text(json.dumps(report, indent=2) + '\n')
    assert report['ok'], report
    print(json.dumps(report, indent=2))
    if not args.overlay:
        return
    from PIL import Image, ImageDraw
    src = ROOT / 'references/ugly-stik/model-v3/us02-jensen-100dpi-1.png'
    im = Image.open(src).convert('RGB')
    for view, box in [('side', (60, 2250, 4460, 2850)), ('top', (60, 1300, 4460, 1810))]:
        tile = im.crop(box)
        draw = ImageDraw.Draw(tile)
        for column in ([2, 3] if view == 'side' else [-1, 1]):
            points = []
            for z, width, roof, bottom in d['fuselage_stations']:
                x = 808 + (z + .115) / scale
                y = proxy - ((roof if column == 2 else bottom) + .005) / scale if view == 'side' else 1565 + column * width / scale
                points.append((x - box[0], y - box[1]))
            draw.line(points, fill=(210, 25, 50), width=4)
            for x, y in points:
                draw.ellipse((x-5, y-5, x+5, y+5), fill=(210,25,50))
        x = 2800 - box[0]
        draw.line((x, 0, x, tile.height), fill=(0, 120, 220), width=3)
        draw.text((x+10, 12), 'RESERVED x=2800', fill=(0, 70, 200))
        draw.text((20, 12), 'Red: model stations; blue: reserved source section. No local rescaling.', fill=(150, 10, 30))
        tile.save(ROOT / f'references/ugly-stik/model-v3/{view}-model-overlay.png')


if __name__ == '__main__':
    main()
