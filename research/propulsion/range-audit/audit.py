"""G1b1: audit recorded propeller operating points; no force reconstruction."""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'app/tests'))
from check_trimmed_flight import COLUMNS, AUX_LAYOUT, STATE_LAYOUT, check_input_identity

TABLES = ('ct_table', 'cp_table')
LOAD_TIMING = ('Fx..Mz: body-axis loads excluding gravity; tick 0 evaluates reset state/aux; '
               'tick k>0 evaluates state k-1 with aux k (after pre_step)')
STATE_TIMING = ('state and aux at tick k; aux advances before RK4 and is held through its stages; '
                'cmd_* drives that step (reset commands at tick 0)')
FRAMES = 'world NED (north, east, down); body FRD (forward, right, down); quaternion body->NED [w,x,y,z]'
FLAGS = ('stopped', 'reverse_flow_clamped', 'below_table', 'above_table',
         'documented_j_gap', 'outside_source_rpm', 'rpm_coverage_unknown',
         'j_gap_coverage_unknown', 'source_j_uncovered', 'reverse_flow_source_coverage_unknown')


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def number(value, label: str) -> float:
    if type(value) not in (float, int) or not math.isfinite(value):
        raise ValueError(f'{label}: expected finite number')
    return float(value)


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f'duplicate JSON key: {key}')
        result[key] = value
    return result


def decode(data: bytes) -> dict:
    result = json.loads(data, object_pairs_hook=unique_object,
                        parse_constant=lambda s: (_ for _ in ()).throw(ValueError(s)))
    if not isinstance(result, dict):
        raise ValueError('expected JSON object')
    return result


def interval(value, label, *, strict=False, positive=False):
    if not isinstance(value, list) or len(value) != 2:
        raise ValueError(f'{label}: expected two endpoints')
    a, b = [number(x, label) for x in value]
    if a > b or (strict and a == b) or (positive and a <= 0):
        raise ValueError(f'{label}: invalid interval')
    return [a, b]


def quantity(node, unit):
    if not isinstance(node, dict) or node.get('unit') != unit:
        raise ValueError(f'expected quantity in {unit}')
    if node.get('kind') not in ('manual', 'measured', 'borrowed', 'estimated', 'derived'):
        raise ValueError('quantity: invalid evidence kind')
    if not isinstance(node.get('source'), str) or not node['source'].strip():
        raise ValueError('quantity: missing source')
    return node['value']


def propeller(data):
    if data.get('format') != 'openrc-aircraft v1':
        raise ValueError('expected openrc-aircraft v1')
    propulsion = data['propulsion']
    if not isinstance(propulsion, dict):
        raise ValueError('propulsion must be an object')
    if propulsion.get('kind', 'glow_prop') != 'glow_prop':
        raise ValueError('propeller audit cannot interpret turbine spool RPM')
    prop = propulsion['propeller']
    if not isinstance(prop, dict):
        raise ValueError('propeller must be an object')
    diameter = number(quantity(prop['diameter'], 'm'), 'diameter')
    if diameter <= 0:
        raise ValueError('diameter must be positive')
    axis = [1.0, 0.0, 0.0]
    if 'thrust_angles' in prop:
        angles = quantity(prop['thrust_angles'], 'deg')
        if not isinstance(angles, list) or len(angles) != 2:
            raise ValueError('thrust_angles: expected down/right pair')
        angles = [number(x, 'thrust angle') for x in angles]
        if any(abs(x) > 10 for x in angles):
            raise ValueError('thrust angles outside loader range +/-10 degrees')
        down, right = [math.radians(x) for x in angles]
        axis = [math.cos(down)*math.cos(right), math.cos(down)*math.sin(right), math.sin(down)]
    tables = {}
    for key in TABLES:
        rows = quantity(prop[key], '1')
        if not isinstance(rows, list) or len(rows) < 2:
            raise ValueError(f'{key}: at least two rows required')
        parsed = []
        for row in rows:
            if not isinstance(row, list) or len(row) != 2:
                raise ValueError(f'{key}: invalid row')
            parsed.append([number(x, key) for x in row])
        if parsed[0][0] != 0 or any(a[0] >= b[0] for a, b in zip(parsed, parsed[1:])):
            raise ValueError(f'{key}: J must start at zero and strictly increase')
        tables[key] = {'j_range': [parsed[0][0], parsed[-1][0]],
                       'kind': prop[key]['kind'], 'source': prop[key]['source']}
    return diameter, axis, tables


def coverage_contract(data, aircraft_hash, tables):
    if data is None:
        return {}
    if not isinstance(data, dict):
        raise ValueError('coverage must be an object')
    if data.get('format') != 'openrc-propeller-coverage v1' or data.get('aircraft_input_sha256') != aircraft_hash:
        raise ValueError('coverage format or aircraft input hash mismatch')
    if data.get('relationship') not in ('matched-propeller', 'borrowed-propeller', 'synthetic'):
        raise ValueError('coverage needs an explicit propeller relationship')
    entries = data.get('tables')
    if not isinstance(entries, dict) or not entries or entries.keys() - tables.keys():
        raise ValueError('coverage names absent tables')
    out = {}
    for key, entry in entries.items():
        if not isinstance(entry, dict) or not isinstance(entry.get('source'), str) or not entry['source'].strip():
            raise ValueError('coverage needs source for each table')
        regions = entry.get('source_regions')
        if regions is not None:
            if not isinstance(regions, list) or not regions:
                raise ValueError('source_regions must be nonempty or null')
            parsed = []
            for region in regions:
                if not isinstance(region, dict):
                    raise ValueError('source region must be an object')
                j = interval(region['j_range'], 'source J')
                rpm = region.get('rpm_range')
                if rpm is not None:
                    rpm = interval(rpm, 'source RPM', positive=True)
                if not isinstance(region.get('source'), str) or not region['source'].strip():
                    raise ValueError('source region needs provenance')
                parsed.append({'j_range': j, 'rpm_range': rpm, 'source': region['source']})
            regions = parsed
        gaps = entry.get('j_gaps')
        if gaps is not None:
            if not isinstance(gaps, list):
                raise ValueError('j_gaps must be a list or null')
            gaps = [interval(g, 'j_gap', strict=True) for g in gaps]
            lo, hi = tables[key]['j_range']
            if any(a < lo or b > hi for a, b in gaps):
                raise ValueError('gap outside table domain')
            if any(a[1] > b[0] for a, b in zip(gaps, gaps[1:])):
                raise ValueError('gaps must be ordered and nonoverlapping')
            if regions is not None and any(a < r['j_range'][1] and r['j_range'][0] < b
                                           for a, b in gaps for r in regions):
                raise ValueError('declared J gap overlaps a source region; split the source region')
        out[key] = {'source_regions': regions, 'j_gaps': gaps, 'source': entry['source']}
    return out


def read_trace(blob, aircraft_hash, ticks, hz):
    if type(ticks) is not int or ticks < 1 or type(hz) is not int or hz <= 0:
        raise ValueError('positive requested ticks and hz required')
    lines = blob.decode('utf-8').splitlines()
    meta = {}
    for line in lines:
        if line.startswith('#'):
            if not line.startswith('# ') or ': ' not in line:
                raise ValueError('malformed trace metadata')
            key, value = line[2:].split(': ', 1)
            if key in meta:
                raise ValueError('duplicate trace metadata')
            meta[key] = value
    check_input_identity(meta, False, None)
    if meta['aircraft_input_sha256'] != aircraft_hash:
        raise ValueError('trace aircraft input bytes do not match')
    if meta.get('format') != 'openrc-trace v3' or meta.get('engine_rpm_semantics') != 'propeller shaft rpm':
        raise ValueError('expected propeller trace v3')
    if meta.get('propulsion_model') not in ('propeller-rpm-lag-v1', 'propeller-shaft-balance-v1'):
        raise ValueError('unsupported propulsion model')
    if meta.get('loads') != LOAD_TIMING:
        raise ValueError('unsupported load/state timing')
    if meta.get('state_timing') != STATE_TIMING or meta.get('frames') != FRAMES:
        raise ValueError('unsupported state timing or coordinate frames')
    dt = float(meta['dt_s'])
    if not math.isfinite(dt) or not math.isclose(dt, 1/hz, rel_tol=1e-6, abs_tol=0):
        raise ValueError('trace timestep disagrees with requested hz')
    if json.loads(meta['state_layout']) != STATE_LAYOUT or json.loads(meta['aux_layout']) != AUX_LAYOUT:
        raise ValueError('trace state/aux layout mismatch')
    rows = list(csv.reader(line for line in lines if not line.startswith('#')))
    if not rows or rows[0] != COLUMNS or len(rows) != ticks + 2:
        raise ValueError('trace columns or requested sample count mismatch')
    samples = []
    for row in rows[1:]:
        if len(row) != len(COLUMNS):
            raise ValueError('trace row width mismatch')
        values = [float(x) for x in row]
        if not all(math.isfinite(x) for x in values):
            raise ValueError('nonfinite trace sample')
        sample = dict(zip(COLUMNS, values))
        tick = sample['tick']
        if tick < 0 or tick >= 2**53 or tick != int(tick):
            raise ValueError('invalid trace tick')
        if samples and tick != samples[-1]['tick'] + 1:
            raise ValueError('discontinuous trace ticks')
        if abs(sample['t_s'] - tick/hz) > 1e-9 or sample['engine_rpm'] < 0:
            raise ValueError('invalid trace time or negative RPM')
        samples.append(sample)
    first = samples[0]
    if meta['recording_start_tick'] != str(int(first['tick'])):
        raise ValueError('recording-start tick mismatch')
    aux = json.loads(meta['recording_start_aux'])
    if not isinstance(aux, list) or len(aux) != len(AUX_LAYOUT):
        raise ValueError('invalid initial auxiliary state')
    if any(abs(number(x, 'initial aux') - first[k]) > 1e-9 for k, x in zip(AUX_LAYOUT, aux)):
        raise ValueError('recording-start auxiliary state mismatch')
    return meta, samples


def classify(sample, diameter, axis, tables, coverage):
    rpm = sample['engine_rpm']
    axial = sum(sample[k]*a for k, a in zip(('u_mps', 'v_mps', 'w_mps'), axis))
    stopped = rpm < 1.0  # Propulsion.STOPPED_RPM, checked against the engine by the fixture.
    advance = None if stopped else max(axial, 0.0) / ((rpm/60.0)*diameter)
    if not math.isfinite(axial) or (advance is not None and not math.isfinite(advance)):
        raise ValueError('operating-point overflow')
    flags = {}
    for key, table in tables.items():
        status = []
        if stopped:
            status.append('stopped')
        else:
            if axial < 0:
                status.append('reverse_flow_clamped')
                status.append('reverse_flow_source_coverage_unknown')
            lo, hi = table['j_range']
            if advance < lo:
                status.append('below_table')
            if advance > hi:
                status.append('above_table')
            support = coverage.get(key, {})
            gaps = support.get('j_gaps')
            if gaps is None:
                status.append('j_gap_coverage_unknown')
            elif any(a < advance < b for a, b in gaps):
                status.append('documented_j_gap')
            regions = support.get('source_regions')
            # A clamped runtime J=0 is not a static source condition when axial flow is negative.
            eligible = [] if regions is None or axial < 0 else [r for r in regions if r['j_range'][0] <= advance <= r['j_range'][1]]
            if regions is not None and not eligible:
                status.append('source_j_uncovered')
            if not eligible or any(r['rpm_range'] is None for r in eligible):
                status.append('rpm_coverage_unknown')
            elif not any(r['rpm_range'][0] <= rpm <= r['rpm_range'][1] for r in eligible):
                status.append('outside_source_rpm')
        flags[key] = status
    return {'tick': int(sample['tick']), 't_s': sample['t_s'], 'rpm': rpm,
            'axial_mps': axial, 'advance_ratio': advance, 'tables': flags}


def audit(trace: bytes, aircraft: bytes, *, ticks: int, hz=240, still_air=False, coverage=None):
    if still_air is not True:
        raise ValueError('trace v3 lacks wind: explicit still-air assumption required')
    data = decode(aircraft)
    diameter, axis, tables = propeller(data)
    aircraft_hash = digest(aircraft)
    support = coverage_contract(coverage, aircraft_hash, tables)
    meta, samples = read_trace(trace, aircraft_hash, ticks, hz)
    points = [classify(samples[0], diameter, axis, tables, support)]
    for previous, current in zip(samples, samples[1:]):
        query = dict(current)
        for key in ('u_mps', 'v_mps', 'w_mps'):
            query[key] = previous[key]
        points.append(classify(query, diameter, axis, tables, support))
    counts = {key: {flag: 0 for flag in FLAGS} for key in tables}
    first = {key: {} for key in tables}
    for point in points[1:]:  # Initial sample is reported separately, not counted as a flown tick.
        for key, flags in point['tables'].items():
            for flag in flags:
                counts[key][flag] += 1
                first[key].setdefault(flag, {'tick': point['tick'], 't_s': point['t_s']})
    active = [p['advance_ratio'] for p in points[1:] if p['advance_ratio'] is not None]
    return {'format': 'openrc-propeller-range-audit v1',
            'trace_sha256': digest(trace), 'aircraft_input_sha256': aircraft_hash,
            'aircraft': meta.get('aircraft'), 'assumption': 'still air: body velocity equals air-relative velocity',
            'sample_semantics': 'rounded previous state with current auxiliary RPM: recorded force query; internal RK stages are not counted',
            'load_query_samples': ticks, 'hz': hz, 'elapsed_s': ticks/hz,
            'diameter_m': diameter, 'shaft_axis_body_frd': axis,
            'table_domains': tables, 'coverage': coverage, 'initial_state_point': points[0],
            'initial_is_recorded_load_query': samples[0]['tick'] == 0,
            'counts': counts, 'first_occurrence': first,
            'active_j_range': [min(active), max(active)] if active else None,
            'limits': ['Counts use nominal nine-decimal trace values; boundary decisions can be rounding-sensitive.',
                       'Assumes diameter, axis and coefficient tables were not overridden after loading the identified input.',
                       'Source regions are documented exclusions, not a measured polar or an uncertainty band.',
                       'No flag does not establish physical validity or coverage of internal integration stages.']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('trace', type=Path)
    parser.add_argument('--aircraft', required=True, type=Path)
    parser.add_argument('--ticks', required=True, type=int)
    parser.add_argument('--hz', default=240, type=int)
    parser.add_argument('--assume-still-air', action='store_true')
    parser.add_argument('--coverage', type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    try:
        sources = [args.trace, args.aircraft] + ([args.coverage] if args.coverage else [])
        if args.output.resolve() in [p.resolve() for p in sources]:
            raise ValueError('output must not overwrite an input')
        trace, aircraft = args.trace.read_bytes(), args.aircraft.read_bytes()
        coverage = args.coverage.read_bytes() if args.coverage else None
        report = audit(trace, aircraft, ticks=args.ticks, hz=args.hz, still_air=args.assume_still_air,
                       coverage=decode(coverage) if coverage else None)
        report['coverage_sha256'] = digest(coverage) if coverage else None
        report['tool_sha256'] = digest(Path(__file__).read_bytes())
        report['identity_reader_sha256'] = digest((ROOT/'app/tests/check_trimmed_flight.py').read_bytes())
        args.output.write_text(json.dumps(report, indent=2, allow_nan=False)+'\n')
    except (OSError, UnicodeError, ValueError, KeyError, TypeError, OverflowError, csv.Error) as error:
        print(f'FAIL: {error}', file=sys.stderr)
        return 1
    print(f'{report["load_query_samples"]} recorded load queries audited: {args.output}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
