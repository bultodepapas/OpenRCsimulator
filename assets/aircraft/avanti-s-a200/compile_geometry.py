"""Compile the Avanti S visual study (AV-02 geometry) into a dependency-free Godot constant.

Visual data only, no physics. Run --check to detect a stale runtime copy.
"""
import argparse
import json
import math
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
TARGET = ROOT / 'app/aircraft/avanti_s_geometry.gd'


def as_godot_json(value):
    """Godot's JSON parser (used by the AV-02 study) reads every number as float; keep that here."""
    if isinstance(value, bool) or value is None or isinstance(value, str):
        return value
    if isinstance(value, (int, float)):
        assert math.isfinite(value), value
        return float(value)
    if isinstance(value, list):
        return [as_godot_json(v) for v in value]
    return {k: as_godot_json(v) for k, v in value.items()}


def validate(d):
    assert d['schema'] == 'openrc-avanti-visual-study-v1' and d['units'] == 'm'
    assert d['axes'] == {'nose': '-Z', 'right': '+X', 'up': '+Y'}
    assert d['nominal']['span_m'] == 2.0 and d['nominal']['length_m'] == 2.22
    for key in ('fuselage_stations', 'canopy_stations'):
        rows = d[key]
        assert all(a[0] < b[0] for a, b in zip(rows, rows[1:])), key + ' must run nose to tail'
        assert all(r[1] > 0 and r[2] > r[3] for r in rows), key
    assert d['controls_deg']['flap_cruise'] <= d['controls_deg']['flap_landing']
    for key, record in d['evidence'].items():
        assert record.get('kind'), 'evidence without kind: ' + key


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    data = json.loads((HERE / 'geometry.json').read_text())
    validate(data)
    output = '# Generated, do not edit. Source: assets/aircraft/avanti-s-a200/geometry.json (revision %s).\n' % data['revision']
    output += '# Regenerate with: python3 assets/aircraft/avanti-s-a200/compile_geometry.py\n'
    output += '# Visual preview geometry only (AV-02 estimates, see DATA.evidence); not flyable.\n'
    output += 'extends RefCounted\n\nconst DATA := '
    output += json.dumps(as_godot_json(data), ensure_ascii=False, indent='\t') + '\n'
    if args.check:
        assert TARGET.exists() and TARGET.read_text() == output, 'Stale model data: run compile_geometry.py'
        print('Avanti S visual geometry source/runtime: identical')
    else:
        TARGET.write_text(output)
        print(TARGET.relative_to(ROOT))


if __name__ == '__main__':
    main()
