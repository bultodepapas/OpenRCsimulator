"""Compile the Extra 300S .60 finish parameters into a dependency-free Godot constant.

The shader that draws them lives in app/aircraft/extra_300s_finish.gd. Run --check to detect a stale copy.
"""
import argparse
import json
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
TARGET = ROOT / 'app/aircraft/extra_300s_appearance.gd'


def validate(d):
    assert d['kind'] == 'estimated' and d['source']
    assert all(re.fullmatch(r'#[0-9a-f]{6}', c) for c in d['colors'].values())
    a, b = d['wing_top']['band_chord_fraction']
    assert 0 < a < b < 0.7, 'the wing band must stay ahead of the aileron hinge (~0.74 chord at the tip)'
    assert len(d['wing_top']['star_span_m']) == 3 and all(0.3 < s < 0.8 for s in d['wing_top']['star_span_m'])
    a, b = d['stab_top']['band_from_hinge_m']
    assert -0.076 < a < b < 0, 'the stab band must sit on the fixed stab (tip LE is 76 mm ahead of the hinge)'
    f = d['fuselage']
    assert len(f['side_band_center_y_m']) == 2 and 0 < f['side_band_half_height_m'] < 0.03
    a, b = f['cowl_panel_y_m']
    assert a < f['cowl_star_y_m'] < b and abs(b - (f['side_band_center_y_m'][0][1] + f['side_band_half_height_m'])) < 0.002, \
        'the cowl panel top must continue the side band top'
    assert d['wing_bottom']['stripe_period_m'] > 0 and d['stab_bottom']['stripe_period_m'] > 0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    data = json.loads((HERE / 'appearance.json').read_text())
    validate(data)
    output = '# Generated from assets/aircraft/extra-300s-60/appearance.json; edit that source.\n'
    output += '# Finish parameters only (artistic estimate); drawn by extra_300s_finish.gd.\nextends RefCounted\n\nconst DATA := '
    output += json.dumps(data, ensure_ascii=False, indent='\t') + '\n'
    if args.check:
        assert TARGET.read_text() == output, 'Stale appearance data: run compile_appearance.py'
        print('Extra appearance source/runtime: identical')
    else:
        TARGET.write_text(output)
        print(TARGET.relative_to(ROOT))


if __name__ == '__main__':
    main()
