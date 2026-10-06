"""Compile the P-51D finish parameters (appearance.json) into a dependency-free Godot constant.

The shader that draws them lives in app/aircraft/p51d_finish.gd. Run --check to detect a stale copy.
"""
import argparse
import json
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
TARGET = ROOT / 'app/aircraft/p51d_appearance.gd'


def validate(d):
    assert d['kind'] == 'estimated' and d['source'] and d['purpose']
    assert all(re.fullmatch(r'#[0-9a-f]{6}', c) for c in d['colors'].values())
    m = d['metal']
    lo, hi = m['roughness_range']
    assert 0.7 <= m['metallic'] <= 1.0 and 0.1 <= lo < hi <= 0.6 and 0 <= m['tone_variation'] <= 0.15 and 0.05 < m['panel_hash_scale_m'] < 1
    p = d['panel_lines']
    assert 0 < p['width_m'] <= 0.004 and 0 < p['darkening'] <= 0.6 and 0 < p['rivet_radius_m'] < p['rivet_pitch_m'] / 4 and 0 <= p['rivet_darkening'] <= 0.5
    f = d['fuselage']
    assert f['major_z_m'] == sorted(f['major_z_m']) and 0.05 < f['pitch_m'] < 0.5 and len(f['longeron_y_m']) <= 4
    w = d['wing']
    assert 0.03 < w['rib_pitch_m'] < 0.3 and all(0 < c < 0.79 for c in w['spar_chord_fractions']), 'spars stay ahead of the aileron hinge (0.79 chord)'
    assert 0.03 < d['tail']['pitch_m'] < 0.3 and 0 < d['tail']['spar_fraction'] < 0.65


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    data = json.loads((HERE / 'appearance.json').read_text())
    validate(data)
    output = '# Generated from assets/aircraft/p51d-mustang-120/appearance.json; edit that source.\n'
    output += '# Finish parameters only (artistic estimate); drawn by p51d_finish.gd.\nextends RefCounted\n\nconst DATA := '
    output += json.dumps(data, ensure_ascii=False, indent='\t') + '\n'
    if args.check:
        assert TARGET.read_text() == output, 'Stale appearance data: run compile_appearance.py'
        print('P-51 appearance source/runtime: identical')
    else:
        TARGET.write_text(output)
        print(TARGET.relative_to(ROOT))


if __name__ == '__main__':
    main()
