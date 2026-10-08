#!/usr/bin/env python3
"""Verify a whole-circuit v3 trace against the independently requested flight report."""
import argparse
import csv
import gzip
import json
import math
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'app/tests'))
from check_trimmed_flight import COLUMNS, check_input_identity, check_metadata


def check(blob: str, result: dict) -> dict:
    if not result.get('completed') or result.get('error') or result.get('crash') or result.get('fault'):
        raise ValueError('report does not describe a completed flight')
    ticks, hz = result['tick_count'], result['hz']
    if type(ticks) is not int or ticks < 1000 or type(hz) is not int or hz not in (240, 480):
        raise ValueError('invalid requested flight ticks/rate')
    lines = blob.splitlines()
    meta = {}
    for line in lines:
        if line.startswith('# ') and ': ' in line:
            key, value = line[2:].split(': ', 1)
            if key in meta:
                raise ValueError('duplicate metadata')
            meta[key] = value
    if meta.get('format') != 'openrc-trace v3' or not meta.get('scenario', '').startswith('E3c2a continuous'):
        raise ValueError('wrong trace format/scenario')
    dt = float(meta.get('dt_s', 'nan'))
    if not math.isfinite(dt) or not math.isclose(dt, 1 / hz, rel_tol=1e-6):
        raise ValueError('wrong trace timestep')
    rows = list(csv.reader(line for line in lines if not line.startswith('#')))
    if not rows or rows.pop(0) != COLUMNS or len(rows) != ticks + 1:
        raise ValueError('wrong trace columns or incomplete row count')
    previous = None
    turn = area = max_cross = 0.0
    first = last = None
    for index, raw in enumerate(rows):
        if len(raw) != len(COLUMNS):
            raise ValueError('wrong row width')
        values = [float(x) for x in raw]
        if not all(math.isfinite(x) for x in values):
            raise ValueError('nonfinite sample')
        row = dict(zip(COLUMNS, values))
        if row['tick'] != index or abs(row['t_s'] - index / hz) > 1e-9:
            raise ValueError('tick/time discontinuity')
        if first is None:
            first = row
        if previous is not None:
            turn += (row['yaw_deg'] - previous['yaw_deg'] + 180) % 360 - 180
            area += .5 * ((previous['east_m'] - first['east_m']) * (row['north_m'] - first['north_m'])
                          - (row['east_m'] - first['east_m']) * (previous['north_m'] - first['north_m']))
        max_cross = max(max_cross, abs(row['north_m'] - first['north_m']))
        previous = last = row
    check_input_identity(meta, False, ROOT / 'app/data/aircraft/jensen_ugly_stik_60.json')
    check_metadata(meta, first)
    if not 5.8 <= abs(math.radians(turn)) <= 6.8 or abs(area) < 15000 or max_cross < 80:
        raise ValueError('recorded motion does not complete the required circuit')
    if first['speed_mps'] >= .02 or last['speed_mps'] >= .02 or last['cmd_throttle'] != 0:
        raise ValueError('flight does not start and finish parked at idle')
    if abs(last['t_s'] - result['duration_s']) > 1e-9:
        raise ValueError('trace/report duration mismatch')
    return dict(rows=len(rows), hz=hz, duration_s=last['t_s'], turn_deg=turn,
                signed_area_m2=area, max_cross_track_m=max_cross,
                exact_aircraft_bytes_verified=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('trace', type=Path)
    parser.add_argument('report', type=Path)
    parser.add_argument('--self-test', action='store_true', help='reject three corruptions of this valid trace')
    args = parser.parse_args()
    try:
        blob = gzip.decompress(args.trace.read_bytes()).decode() if args.trace.suffix == '.gz' else args.trace.read_text()
        report = json.loads(args.report.read_text())
        if report.get('coverage') != 'full' or report.get('failures') != 0:
            raise ValueError('maneuver verification failed')
        cases = [(r.get('hz'), r.get('eastbound')) for r in report['results']]
        if cases != [(240, True), (240, False), (480, True)]:
            raise ValueError('missing required heading/rate coverage')
        result = report['results'][0]
        summary = check(blob, result)
        if args.self_test:
            lines = blob.splitlines()
            data_start = next(i for i, line in enumerate(lines) if not line.startswith('#')) + 1
            mutations = [lines[:-1], lines[:data_start+1]]
            nonfinite = lines.copy()
            cells = nonfinite[data_start+10].split(',')
            cells[2] = 'nan'
            nonfinite[data_start+10] = ','.join(cells)
            mutations.append(nonfinite)
            for changed in mutations:
                try:
                    check('\n'.join(changed), result)
                except ValueError:
                    continue
                raise ValueError('trace checker accepted a deliberate corruption')
            summary['trace_mutations_rejected'] = len(mutations)
        print(json.dumps(summary, indent=2))
    except (ValueError, KeyError, IndexError, OSError) as error:
        print(f'FAIL: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
