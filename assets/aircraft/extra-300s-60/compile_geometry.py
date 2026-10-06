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
    assert g['main_axle'][1] < g['leg']['tip'][2] and g['track'] > 2 * g['leg_root_half_spacing']
    pant = g['pant_profile']
    assert all(a[0] < b[0] for a, b in zip(pant, pant[1:])) and all(row[1] >= row[2] for row in pant)
    assert pant[0][0] < g['main_axle'][0] < pant[-1][0] and 0 < g['leg']['thickness'] < 0.01
    assert g['leg']['root'][0] < g['leg']['root'][1] and g['leg']['tip'][0] < g['leg']['tip'][1] and g['leg']['tip'][2] < g['leg']['root'][2]
    pr = d['propeller']
    assert 0.2 < pr['diameter'] < 0.4 and 0.05 < pr['pitch'] < 0.4 and pr['blades'] == 2 and 0 < pr['hub_radius'] < pr['diameter'] / 4
    for key in ('chord_fraction_of_radius', 'thickness_fraction_of_chord'):
        rows = pr['blade'][key]
        assert all(a[0] < b[0] for a, b in zip(rows, rows[1:])) and rows[-1][0] == 1.0 and all(0 < r[1] < 0.5 for r in rows), key
    pl = d['pilot']
    assert pl['chin'][1] < pl['nose_front'][1] < pl['cap_brim_front'][1] < pl['cap_top'][1] and pl['nose_front'][0] < pl['head_back'][0]
    assert pl['shoulder_front'][0] < pl['shoulder_back'][0] and 0 < pl['head_half_width'] < pl['shoulder_half_width'] < 0.06
    groups = {key.split('.')[0] for key in d['evidence']}
    for required in ['wing', 'fuselage_stations', 'canopy', 'tail', 'gear', 'propeller', 'pilot']:
        assert required in groups, f'missing evidence for {required}'
    for key, record in d['evidence'].items():
        assert record['kind'] in {'manual', 'measured', 'borrowed', 'estimated', 'derived'}, key


def check_against_metrology(d):
    """Measured fields must equal research/extra-300/ex01/metrology.json up to the 0.1 mm rounding."""
    m = json.loads((ROOT / 'research/extra-300/ex01/metrology.json').read_text())
    assert not [c['name'] for c in m['checks'] if not c['ok']], 'metrology has failing reserved checks'
    a = m['adopted_model_values']
    w, mw, t, g = d['wing'], a['wing'], d['tail'], d['gear']
    pairs = [
        (w['span'], mw['span']), (w['root_chord'], mw['root_chord_centreline']), (w['tip_chord'], mw['tip_chord']),
        (w['le_z_root'], mw['le_z_centreline']), (w['le_z_tip'], mw['le_z_tip']), (w['chord_plane_y'], mw['chord_plane_y']),
        (w['aileron_inner'], mw['aileron_inner']), (w['aileron_outer'], mw['aileron_outer']), (w['aileron_chord'], mw['aileron_chord']),
        (w['reference']['s_over_b'], mw['reference_chord_S_over_b']), (w['reference']['mac'], mw['mac']),
        (d['spinner']['tip_z'], a['spinner']['tip_z']), (d['spinner']['back_z'], a['spinner']['back_z']), (d['spinner']['radius'], a['spinner']['radius']),
        (d['firewall_z'], a['firewall_z']), (d['cowl_rear_z'], a['cowl_rear_z']),
        (t['stab_half_span'], a['stab']['half_span']), (t['stab_root_le_z'], a['stab']['root_le_z']), (t['elevator_hinge_z'], a['stab']['hinge_z']),
        (t['elevator_tip_te_z'], a['stab']['elevator_tip_te_z']), (t['rudder_hinge_z'], a['fin']['hinge_z']), (t['fin_top_y'], a['fin']['top_y']),
        (g['main_axle'][0], a['main_axle'][0]), (g['main_axle'][1], a['main_axle'][1]), (g['tail_axle'][0], a['tailwheel_axle'][0]), (g['tail_axle'][1], a['tailwheel_axle'][1]),
    ]
    pairs += [(x, y) for row, ref in zip(d['fuselage_stations'], a['fuselage_stations']) for x, y in zip(row[:4], ref)]
    pairs += [(x, y) for row, ref in zip(d['canopy']['top'], a['canopy_top']) for x, y in zip(row, ref)]
    pairs += [(x, y) for row, ref in zip(g['pant_profile'], a['wheel_pant_profile']) for x, y in zip(row, ref)]
    pairs += [(x, y) for key in ('root', 'tip') for x, y in zip(g['leg'][key], a['main_leg'][key])]
    pairs += [(x, y) for key in a['pilot'] for x, y in zip(d['pilot'][key], a['pilot'][key])]
    assert len(g['pant_profile']) == len(a['wheel_pant_profile'])
    assert len(d['fuselage_stations']) == len(a['fuselage_stations']) and len(d['canopy']['top']) == len(a['canopy_top'])
    worst = max(abs(x - y) for x, y in pairs)
    assert worst <= 0.00006, f'geometry.json differs from metrology.json by {worst} m'
    return len(pairs), worst


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    data = json.loads((HERE / 'geometry.json').read_text())
    validate(data)
    count, worst = check_against_metrology(data)
    print(f'{count} measured values match metrology.json (max difference {worst * 1000:.3f} mm)')
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
