"""Reduce EX-06 configuration and EX-08 probe comparisons; no fitted physical targets."""
import argparse
import hashlib
import json
import math
from pathlib import Path


def configuration(app):
    data = json.loads((app / 'data/aircraft/gp_extra_300s_60.json').read_text(encoding='utf-8'))
    items = data['inventory']
    mass = sum(c['mass']['value'] for c in items)
    cg = [sum(c['mass']['value'] * c['position']['value'][i] for c in items) / mass for i in range(3)]
    dry_items = [c for c in items if c['name'] != 'fuel (half tank)']
    dry_mass = sum(c['mass']['value'] for c in dry_items)
    dry_cg = [sum(c['mass']['value'] * c['position']['value'][i] for c in dry_items) / dry_mass for i in range(3)]
    diagonal = [0., 0., 0.]
    for c in items:
        m = c['mass']['value']
        offset = [c['position']['value'][i] - cg[i] for i in range(3)]
        size = c.get('size', {'value': [0., 0., 0.]})['value']
        for axis in range(3):
            others = [i for i in range(3) if i != axis]
            diagonal[axis] += m * sum(offset[i] ** 2 + size[i] ** 2 / 12 for i in others)
    prop = data['propulsion']['propeller']
    return {
        'mass_kg': mass, 'cg_le_m': cg, 'dry_mass_kg': dry_mass, 'dry_cg_le_m': dry_cg,
        'inertia_diagonal_kgm2': diagonal,
        'virtual_ballast_kg': next(c['mass']['value'] for c in items if c['name'].startswith('virtual reference')),
        'estimated_1g_stall_mps': math.sqrt(2 * mass * 9.80665 / (1.225 * data['reference']['wing_area']['value'] * data['aero']['envelope']['CL_max']['value'])),
        'thrust_angles_down_right_deg': prop.get('thrust_angles', {'value': [0., 0.]})['value'],
        'thrust_offset_le_from_cg_m': prop['thrust_line_offset']['value'],
    }


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--baseline-app', required=True, type=Path)
    p.add_argument('--after-app', required=True, type=Path)
    p.add_argument('--evidence', required=True, type=Path)
    a = p.parse_args()
    report = {'baseline': configuration(a.baseline_app), 'after': configuration(a.after_app), 'unchanged_aircraft_files': {}}
    for source in sorted((a.baseline_app / 'data/aircraft').glob('*.json')):
        if source.name == 'gp_extra_300s_60.json':
            continue
        other = a.after_app / 'data/aircraft' / source.name
        report['unchanged_aircraft_files'][source.name] = {
            'equal_bytes': source.read_bytes() == other.read_bytes(),
            'sha256': hashlib.sha256(other.read_bytes()).hexdigest(),
        }
    refinement = {}
    for probe in ['envelope', 'ground']:
        low = json.loads((a.evidence / f'{probe}-after-240.json').read_text())
        high = json.loads((a.evidence / f'{probe}-after-480.json').read_text())
        key = 'id' if probe == 'envelope' else 'name'
        high_cases = {c[key]: c for c in high['cases']}
        rows = {}
        for case in low['cases']:
            other = high_cases[case[key]]
            if probe == 'envelope':
                rows[case[key]] = {metric: abs(case['flight']['metrics'][metric]['end'] - other['flight']['metrics'][metric]['end'])
                                  for metric in ['alt_m', 'speed_mps', 'p_radps', 'q_radps', 'r_radps']}
            else:
                rows[case[key]] = {metric: abs(case['metrics'][metric] - other['metrics'][metric])
                                  for metric in ['elapsed_s', 'ground_distance_m', 'liftoff_time_s', 'liftoff_speed_mps', 'touchdown_time_s', 'touchdown_sink_mps']}
                rows[case[key]]['crash_agrees'] = case['metrics']['crash'] == other['metrics']['crash']
        refinement[probe] = rows
    (a.evidence / 'configuration-comparison.json').write_text(json.dumps(report, indent=2) + '\n')
    (a.evidence / 'refinement.json').write_text(json.dumps(refinement, indent=2) + '\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
