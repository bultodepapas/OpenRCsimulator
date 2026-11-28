"""Compute the exact minima of Cp - J Ct for the authored decimal table entries."""

import argparse
import json
import re
from fractions import Fraction
from pathlib import Path


def affine_pieces(table):
    for (x0, y0), (x1, y1) in zip(table, table[1:]):
        slope = Fraction(y1 - y0, x1 - x0)
        yield x0, x1, slope, y0 - slope * x0


def minimum(ct, cp):
    candidates = []
    for t0, t1, t_slope, t_intercept in affine_pieces(ct):
        for p0, p1, p_slope, p_intercept in affine_pieces(cp):
            lo, hi = max(t0, p0, 0), min(t1, p1)
            if hi < lo:
                continue
            # (a_t*J + b_t)*(-J) + a_p*J + b_p
            quadratic, linear = -t_slope, p_slope - t_intercept
            points = [lo, hi]
            if quadratic > 0:
                vertex = -linear / (2 * quadratic)
                if lo < vertex < hi:
                    points.append(vertex)
            candidates.extend((((quadratic*j + linear)*j + p_intercept, j) for j in points))
    return min(candidates)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("repo", type=Path)
    root = parser.parse_args().repo
    catalog = (root / 'app/app_state/aircraft_catalog.gd').read_text()
    base_paths = set(re.findall(r'^\s*data = "res://data/aircraft/([^"/]+\.json)"', catalog, re.M))
    files = sorted((root / 'app/data/aircraft').glob('*.json'))
    table_rows, wake_lengths, unique_tables = {}, {}, set()
    for path in files:
        record = json.loads(path.read_text(), parse_float=Fraction)
        tail = record.get('aero', {}).get('surfaces', {}).get('horizontal', {})
        if 'downwash_gradient' in tail:
            ref = record['reference']
            assert [ref['wing_area']['unit'], ref['wing_span']['unit'], tail['position']['unit']] == ['m2', 'm', 'm']
            wake_lengths[path.stem] = tail['position']['value'][0] - ref['wing_area']['value'] / (4 * ref['wing_span']['value'])
        model = record.get('propulsion', {})
        prop = model.get('propeller', {})
        if 'ct_table' not in prop or 'glow_installation' in model.get('engine', {}):
            continue
        ct, cp = prop['ct_table']['value'], prop['cp_table']['value']
        unique_tables.add(tuple(tuple(map(tuple, table)) for table in [ct, cp]))
        margin, advance = minimum(ct, cp)
        table_rows[path.name] = {'catalog_base': path.name in base_paths,
                                 'minimum': str(margin), 'at': str(advance)}
    worst = min(table_rows, key=lambda name: Fraction(table_rows[name]['minimum']))
    assert all(Fraction(row['minimum']) > 0 for row in table_rows.values())
    assert all(value > 0 for value in wake_lengths.values())
    result = {'direct_files_screened': len(table_rows),
              'catalog_base_files': sum(row['catalog_base'] for row in table_rows.values()),
              'distinct_table_pairs': len(unique_tables), 'worst_file': worst,
              'smallest_margin': float(Fraction(table_rows[worst]['minimum'])),
              'advance_at_smallest': float(Fraction(table_rows[worst]['at'])),
              'wake_files': len(wake_lengths), 'min_length_m': float(min(wake_lengths.values())),
              'max_length_m': float(max(wake_lengths.values())), 'table_rows': table_rows}
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == '__main__':
    main()
