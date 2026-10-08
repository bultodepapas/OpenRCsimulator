"""Select exact recorded circuit ticks for rendering, without replaying dynamics."""
import csv
import gzip
import hashlib
import json
import math
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'research/landing/e3c2a'))
from check_trace import check

EVIDENCE = ROOT / 'docs/research/ground-contact/E3c2a'
STATE = 'north_m east_m down_m u_mps v_mps w_mps qw qx qy qz p_radps q_radps r_radps'.split()
PHASES = ['idle', 'takeoff_roll', 'initial_climb', 'crosswind_turn', 'crosswind',
          'downwind_turn', 'downwind', 'base_turn', 'base', 'final_turn', 'final_join',
          'approach', 'flare', 'rollout']


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def select_frames(rows, result):
    hz = result['hz']
    if [event['phase'] for event in result['phases']] != PHASES:
        raise ValueError('missing or reordered circuit phases')
    times = {event['phase']: event['time_s'] for event in result['phases']}
    if any(not math.isfinite(t) for t in times.values()) or list(times.values()) != sorted(set(times.values())):
        raise ValueError('invalid phase times')
    # The phase report was sampled at tick boundaries; cross-check its reported pose.
    for event in result['phases']:
        tick = round(event['time_s'] * hz)
        if not 0 <= tick < len(rows):
            raise ValueError('phase outside recording')
        row = rows[tick]
        for key in ('north_m', 'east_m', 'speed_mps'):
            if abs(row[key] - event[key]) > 1e-7:
                raise ValueError('phase report disagrees with trace')
        if abs(row['alt_m'] - event['altitude_m']) > 1e-7:
            raise ValueError('phase altitude disagrees with trace')
    # Labels denote verified controller phases, not a new reconstruction of impact time.
    requests = [('parked', 0.0), ('takeoff_roll', (times['takeoff_roll'] + times['initial_climb']) / 2),
                ('climb', (times['initial_climb'] + times['crosswind_turn']) / 2),
                ('crosswind', times['crosswind']), ('downwind', (times['downwind'] + times['base_turn']) / 2),
                ('base', times['base']), ('final_join', times['final_join']),
                ('approach', times['approach']), ('flare', times['flare']),
                ('rollout_entry', times['rollout']),
                ('rollout', (times['rollout'] + result['duration_s']) / 2),
                ('stopped', result['duration_s'])]
    ticks = [round(t * hz) for _, t in requests]
    if ticks != sorted(set(ticks)) or ticks[-1] != len(rows)-1:
        raise ValueError('capture events not distinct and ordered')
    phases, angle = {}, 0.0
    for i, row in enumerate(rows):
        if i:
            # RPM is recorded, shaft phase is not. Trapezoidal integration is visual-only.
            angle = (angle + math.tau / 60 * (rows[i-1]['engine_rpm'] + row['engine_rpm']) / (2*hz)) % math.tau
        if i in ticks:
            phases[i] = angle
    frames = []
    for (name, _), tick in zip(requests, ticks):
        row = rows[tick]
        state = [row[k] for k in STATE]
        if abs(sum(v*v for v in state[6:10]) - 1) > 1e-7:
            raise ValueError('non-unit recorded attitude')
        surfaces = {axis: row['srv_'+axis] for axis in ('roll', 'pitch', 'yaw')}
        surfaces['throttle'] = row['cmd_throttle']
        if any(abs(v) > 1 for v in surfaces.values()) or surfaces['throttle'] < 0:
            raise ValueError('recorded surfaces outside normalized range')
        frames.append(dict(id=name, tick=tick, time_s=row['t_s'], state=state,
                           surfaces=surfaces, prop_angle_rad=phases[tick]))
    return frames


def prepare(trace=EVIDENCE / 'circuit.csv.gz', report_path=EVIDENCE / 'report.json'):
    trace, report_path = Path(trace), Path(report_path)
    payload = trace.read_bytes()
    raw = gzip.decompress(payload) if trace.suffix == '.gz' else payload
    report = json.loads(report_path.read_text())
    if report.get('coverage') != 'full' or report.get('failures') != 0:
        raise ValueError('a passing full circuit report is required')
    if [(r['hz'], r['eastbound']) for r in report['results']] != [(240, True), (240, False), (480, True)]:
        raise ValueError('incomplete verification coverage')
    result = report['results'][0]
    summary = check(raw.decode(), result)
    rows = [{k: float(v) for k, v in row.items()} for row in csv.DictReader(
        line for line in raw.decode().splitlines() if not line.startswith('#'))]
    return dict(format='openrc-circuit-captures v1', aircraft='jensen-das-ugly-stik-60',
                purpose='Recorded-state rendering only; no dynamics replay or physical/readability acceptance',
                trace_sha256=hashlib.sha256(payload).hexdigest(), trace_bytes_sha256=hashlib.sha256(raw).hexdigest(),
                report_sha256=sha256(report_path), verified_trace=summary,
                propeller_phase='visual-only trapezoidal integral of recorded RPM; initial angle zero',
                frames=select_frames(rows, result))
