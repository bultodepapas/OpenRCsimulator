#!/usr/bin/env python3
"""G1a1: normalize one identified UIUC table; no interpolation or aircraft writes."""
import argparse
from decimal import Decimal, InvalidOperation
import hashlib
import json
import math
from pathlib import Path
import re
import sys

HEADERS = {'static': ['RPM', 'CT', 'CP'], 'tunnel': ['J', 'CT', 'CP', 'eta']}
NUMBER = re.compile(r'[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[Ee][+-]?[0-9]+)?\Z')
LIMITATIONS = [
    'Source identity and declarations do not independently verify measurement quality or propeller applicability.',
    'Run RPM labels are not per-row RPM measurements or measured RPM coverage.',
    'Unknown coefficient-reference diameter stays unknown; nominal size is never substituted.',
    'Sorted knots and coordinate extents are not continuous validated coverage; no interpolation, extrapolation or uncertainty is supplied.',
    'Identical published rows are collapsed with all source line numbers retained; conflicting repeats are refused, never averaged.',
    'Signed Ct, Cp and eta are retained. Negative power/thrust or eta outside [0,1] is not silently clamped.',
    'Import does not validate a different propeller, engine installation or operating range; no aircraft parameters are installed.',
]


def require(condition, message):
    if not condition:
        raise ValueError(message)


def fields(value, names, label):
    require(isinstance(value, dict) and set(value) == set(names.split()), f'{label}: missing/unknown fields')


def nonempty(value):
    return isinstance(value, str) and bool(value.strip())


def finite(value, label):
    require(type(value) in (int, float) and math.isfinite(value), f'{label}: finite number required')
    return float(value)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def decode(raw):
    def pairs(items):
        result = {}
        for k, v in items:
            require(k not in result, f'duplicate JSON key: {k}')
            result[k] = v
        return result
    def invalid(value):
        raise ValueError(f'nonfinite JSON constant: {value}')
    return json.loads(raw, object_pairs_hook=pairs, parse_constant=invalid)


def validate(manifest):
    fields(manifest, 'format id evidence table_kind source_url source_sha256 propeller coefficient_reference_diameter run_rpm_label notes', 'manifest')
    require(manifest['format'] == 'openrc-uiuc-source v1', 'unsupported manifest format')
    require(nonempty(manifest['id']), 'source id required')
    require(manifest['evidence'] in ('measured-source', 'synthetic'), 'invalid evidence')
    require(manifest['table_kind'] in HEADERS, 'unsupported table kind')
    require(isinstance(manifest['source_url'], str) and manifest['source_url'].startswith('https://'), 'HTTPS source URL required')
    require(isinstance(manifest['source_sha256'], str) and re.fullmatch(r'[0-9a-f]{64}', manifest['source_sha256']), 'source SHA-256 required')
    require(nonempty(manifest['notes']), 'source notes required')
    prop = manifest['propeller']
    fields(prop, 'manufacturer family nominal_size source', 'propeller')
    require(all(nonempty(v) for v in prop.values()), 'propeller identity/provenance required')
    diameter = manifest['coefficient_reference_diameter']
    if diameter is not None:
        fields(diameter, 'value unit kind source', 'coefficient_reference_diameter')
        require(finite(diameter['value'], 'diameter') > 0 and diameter['unit'] == 'm', 'positive diameter in m required')
        require(diameter['kind'] in ('measured', 'manual', 'derived', 'synthetic') and nonempty(diameter['source']), 'diameter provenance required')
        require(manifest['evidence'] == 'synthetic' or diameter['kind'] != 'synthetic', 'synthetic diameter in measured source')
    rpm = manifest['run_rpm_label']
    if manifest['table_kind'] == 'static':
        require(rpm is None, 'static sweep must not carry a fixed run RPM label')
    elif rpm is not None:
        fields(rpm, 'value unit source', 'run_rpm_label')
        require(finite(rpm['value'], 'run RPM label') > 0 and rpm['unit'] == 'rpm' and nonempty(rpm['source']), 'invalid run RPM label')


def parse_table(raw, kind):
    """Return float64 knots, preserving Decimal equality and physical line provenance."""
    require(kind in HEADERS, 'unsupported table kind')
    lines = [(n, line.split()) for n, line in enumerate(raw.decode('ascii').splitlines(), 1) if line.strip()]
    require(lines and lines[0][1] == HEADERS[kind], 'unexpected table header')
    unique = {}
    float_axis = {}
    order = []
    input_rows = 0
    for line_number, cells in lines[1:]:
        require(len(cells) == len(HEADERS[kind]), f'line {line_number}: wrong column count')
        require(all(NUMBER.fullmatch(cell) for cell in cells), f'line {line_number}: invalid numeric token')
        exact = tuple(Decimal(cell) for cell in cells)
        numbers = tuple(float(value) for value in exact)
        require(all(math.isfinite(v) and (v != 0 or d == 0) for v, d in zip(numbers, exact)),
                f'line {line_number}: float64 overflow/underflow')
        axis = exact[0]
        require(axis > 0 if kind == 'static' else axis >= 0, f'line {line_number}: invalid RPM/J domain')
        input_rows += 1
        if axis in unique:
            require(exact == unique[axis]['exact'], f'line {line_number}: conflicting duplicate coordinate')
            unique[axis]['source_lines'].append(line_number)
            continue
        require(numbers[0] not in float_axis, f'line {line_number}: distinct coordinates collapse in float64')
        float_axis[numbers[0]] = axis
        order.append(axis)
        unique[axis] = {'exact': exact, 'values': numbers, 'source_lines': [line_number]}
    require(len(unique) >= 2, 'at least two distinct coordinates required')
    knots = []
    for axis in sorted(unique):
        row = unique[axis]
        x, ct, cp = row['values'][:3]
        knots.append({'rpm': x if kind == 'static' else None, 'j': 0.0 if kind == 'static' else x,
                      'ct': ct, 'cp': cp, 'eta': None if kind == 'static' else row['values'][3],
                      'source_lines': row['source_lines']})
    return {'knots': knots, 'input_rows': input_rows, 'unique_rows': len(knots),
            'duplicate_rows_collapsed': input_rows-len(knots), 'reordered': order != sorted(order)}


def import_table(manifest_raw, table_raw):
    manifest = decode(manifest_raw)
    validate(manifest)
    require(sha(table_raw) == manifest['source_sha256'], 'source SHA-256 mismatch')
    kind = manifest['table_kind']
    parsed = parse_table(table_raw, kind)
    knots = parsed['knots']
    axis = 'rpm' if kind == 'static' else 'j'
    return {'format': 'openrc-propeller-knots v1', 'source': manifest,
            'input_sha256': {'manifest': sha(manifest_raw), 'table': sha(table_raw)},
            'normalization': {k: v for k, v in parsed.items() if k != 'knots'},
            'coordinate_axis': axis, 'coordinate_unit': 'rpm' if kind == 'static' else '1',
            'coordinate_extent': [knots[0][axis], knots[-1][axis]],
            'rpm_semantics': 'source column at each static point' if kind == 'static' else 'per-row RPM unavailable; run label only',
            'per_row_rpm_extent': [knots[0]['rpm'], knots[-1]['rpm']] if kind == 'static' else None,
            'knots': knots, 'limitations': LIMITATIONS}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('manifest', type=Path)
    parser.add_argument('table', type=Path)
    args = parser.parse_args()
    try:
        report = import_table(args.manifest.read_bytes(), args.table.read_bytes())
        report['importer_sha256'] = sha(Path(__file__).read_bytes())
        print(json.dumps(report, indent=2, sort_keys=True, allow_nan=False))
        return 0
    except (OSError, ValueError, TypeError, OverflowError, InvalidOperation) as error:
        print(f'G1a1: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
