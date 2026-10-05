"""Compile the editable visual record into a dependency-free Godot constant.

No physics data is generated. Run --check to detect a stale runtime copy.
"""
import argparse
import json
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
