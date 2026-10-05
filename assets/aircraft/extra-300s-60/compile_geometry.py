"""Compile the Extra 300S .60 visual record into a dependency-free Godot constant.

No physics data is generated. Run --check to detect a stale runtime copy.
"""
import argparse
import json
import math
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
TARGET = ROOT / 'app/aircraft/extra_300s_geometry.gd'


def finite(*values):
    return all(isinstance(v, (int, float)) and math.isfinite(v) for v in values)


def validate(d):
    assert d['units'] == 'm' and d['axes'] == {'nose': '-Z', 'right': '+X', 'up': '+Y'}
    w = d['wing']
    assert abs(w['span'] - 64 * 0.0254) < 0.01, 'span drifted from the 64 in kit'
    assert 0 < w['tip_chord'] < w['root_chord']
    assert 0 < w['aileron_inner'] < w['aileron_outer'] <= w['span'] / 2
    assert 0 < w['aileron_chord'] < w['tip_chord'] / 2
    assert 0 < w['hinge_gap'] < 0.01
    section = w['section']
    assert section[0] == [0.0, 0.0] and section[-1][0] == 1.0
    assert all(a[0] < b[0] for a, b in zip(section, section[1:])), 'section x must increase'
    assert all(finite(*p) and p[1] >= 0 for p in section)
    stations = d['fuselage_stations']
    assert all(a[0] < b[0] for a, b in zip(stations, stations[1:])), 'stations must run nose to tail'
    for z, half_width, top, bottom, top_round, bottom_round in stations:
        assert finite(z, half_width, top, bottom) and half_width > 0 and top > bottom
        assert 0 <= top_round <= 1 and 0 <= bottom_round <= 1
    s = d['spinner']
    assert s['tip_z'] < s['back_z'] <= stations[0][0] and s['radius'] > 0
    assert stations[0][0] < d['firewall_z'] < d['cowl_rear_z']
    canopy = d['canopy']['top']
    assert all(a[0] < b[0] for a, b in zip(canopy, canopy[1:])) and 0 < d['canopy']['halfwidth_fraction'] < 1
    t = d['tail']
    assert t['stab_root_le_z'] < t['elevator_hinge_z'] < t['elevator_tip_te_z']
    assert t['stab_root_le_z'] < t['stab_tip_le_z'] < t['elevator_hinge_z']
    assert 0 < t['elevator_inner_hinge'][0] < t['elevator_root_corner'][0] < t['stab_half_span']
    assert t['fin_root_le'][0] < t['balance_front_z'] < t['fin_le_top_z'] < t['rudder_hinge_z'] < t['rudder_top_te_z']
    assert t['rudder_bottom_hinge'][1] < t['fin_root_le'][1] < t['balance_bottom_y'] < t['fin_top_y']
    g = d['gear']
    assert g['main_axle'][1] < g['main_leg_root'][1] and g['track'] > 2 * g['leg_root_half_spacing']
    assert g['pant_z'][0] < g['main_axle'][0] < g['pant_z'][1]
    groups = {key.split('.')[0] for key in d['evidence']}
    for required in ['wing', 'fuselage_stations', 'canopy', 'tail', 'gear', 'propeller']:
        assert required in groups, f'missing evidence for {required}'
    for key, record in d['evidence'].items():
        assert record['kind'] in {'manual', 'measured', 'borrowed', 'estimated', 'derived'}, key


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    data = json.loads((HERE / 'geometry.json').read_text())
    validate(data)
    output = '# Generated from assets/aircraft/extra-300s-60/geometry.json; edit that source.\n'
    output += '# Visual geometry only. Every group has provenance in DATA.evidence.\nextends RefCounted\n\nconst DATA := '
    output += json.dumps(data, ensure_ascii=False, indent='\t') + '\n'
    if args.check:
        assert TARGET.read_text() == output, 'Stale model data: run compile_geometry.py'
        print('Extra visual geometry source/runtime: identical')
    else:
        TARGET.write_text(output)
        print(TARGET.relative_to(ROOT))


if __name__ == '__main__':
    main()
