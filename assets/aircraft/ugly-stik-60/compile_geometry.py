"""Compile the editable visual record into a dependency-free Godot constant.

No physics data is generated. Run --check to detect a stale runtime copy.
"""
import argparse
import json
import math
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
TARGET = ROOT / 'app/aircraft/ugly_stik_geometry.gd'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    data = json.loads((HERE / 'geometry.json').read_text())
    assert data['units'] == 'm'
    assert abs(data['wing']['span'] - 1.524) < 1e-9
    assert all(row[1] > 0 and row[2] > row[3] for row in data['fuselage_stations'])
    assert all(a[0] < b[0] for a, b in zip(data['fuselage_stations'], data['fuselage_stations'][1:]))
    w = data['wing']
    assert 0 < w['aileron_inner'] < w['aileron_outer'] <= w['span'] / 2
    assert 0 < w['tip_start'] < w['tip_le_span'] <= w['span'] / 2
    assert 0 < w['hinge_gap'] < 0.01
    assert 0 < w['hinge_fraction'] < 1
    assert sum(abs(p[0] - w['hinge_fraction']) < 1e-8 for p in w['section']) == 2
    assert all(len(p) == 2 and all(math.isfinite(v) for v in p) for p in w['section'])
    assert all(0 <= p[0] <= 1 for p in w['section'])
    tail = data['tail']
    assert 0 < tail['hinge_gap'] < 0.01
    assert 0 < tail['elevator_cutout_half_width'] < tail['span'] / 2
    for key in ['stab_outline', 'elevator_outline', 'fin_outline', 'rudder_outline']:
        points = tail[key]
        assert len(points) >= 3 and all(len(p) == 2 and all(math.isfinite(v) for v in p) for p in points), key
        area2 = sum(a[0] * b[1] - b[0] * a[1] for a, b in zip(points, points[1:] + points[:1]))
        assert abs(area2) > 1e-8, key
    assert abs(data['fuselage_stations'][0][0] - data['equipment']['firewall_z']) < 1e-6
    output = '# Generated from assets/aircraft/ugly-stik-60/geometry.json; edit that source.\n'
    output += '# Visual geometry only. Every group has provenance in DATA.evidence.\nextends RefCounted\n\nconst DATA := '
    output += json.dumps(data, ensure_ascii=False, indent='\t') + '\n'
    if args.check:
        assert TARGET.read_text() == output, 'Stale model data: run compile_geometry.py'
        print('Visual geometry source/runtime: identical')
    else:
        TARGET.parent.mkdir(parents=True, exist_ok=True)
        TARGET.write_text(output)
        print(TARGET.relative_to(ROOT))


if __name__ == '__main__':
    main()
