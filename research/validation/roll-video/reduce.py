#!/usr/bin/env python3
"""VAL-8b: reduce annotated complete-roll timing, not projected attitude or body p."""
import argparse
import csv
import hashlib
import io
import json
import math
import os
from pathlib import Path
import re
import sys
import tempfile

COLUMNS = ['id', 'frame', 'frame_u', 'turn_index']
MAX_EXACT_INT = 2**53 - 1
LIMITATIONS = [
    'Completed-turn timing is a cycle average, not instantaneous body p, Euler bank rate, roll damping or Clp.',
    'No image-based attitude reconstruction: the operator must resolve full turns, sign and repeated physical phase without perspective or 180-degree aliasing.',
    'Positive turn index means right wing down about the forward body axis; screen-clockwise motion does not define this sign.',
    'Original constant-cadence capture frames only, without dropped, duplicated or interpolated frames; playback FPS is not capture FPS.',
    'Video identity and declarations do not verify image content, capture timing, observer accuracy or flight conditions.',
    'First-order standard uncertainties (k=1), conditional on exact integer turn counts and independent event-pick residuals; no coverage interval or acceptance band.',
    'Event timing uncertainties must cover finite exposure, phase selection and other relevant residual timing errors; unknown uncertainty is not zero.',
    'Named event and clock contributions retain covariance across intervals; other correlated annotation errors are unsupported.',
    'A comparison needs matched commands, airspeed, aircraft configuration and maneuver definition; no simulator coefficient is inferred or updated.',
    'Synthetic observations verify tooling only; real flights and physical validation remain VAL-8.',
]


def require(condition, message):
    if not condition:
        raise ValueError(message)


def fields(value, names, label):
    require(isinstance(value, dict) and set(value) == set(names.split()), f'{label}: missing/unknown fields')


def text(value):
    return isinstance(value, str) and bool(value.strip())


def number(value, label):
    require(type(value) in (int, float) and math.isfinite(value), f'{label}: finite number required')
    return float(value)


def identifier(value):
    return isinstance(value, str) and re.fullmatch(r'[a-z][a-z0-9_-]*', value) is not None


def load_json(raw):
    def pairs(items):
        result = {}
        for key, value in items:
            require(key not in result, f'duplicate JSON key: {key}')
            result[key] = value
        return result
    def invalid(value):
        raise ValueError(f'nonfinite JSON constant: {value}')
    return json.loads(raw, object_pairs_hook=pairs, parse_constant=invalid)


def validate(campaign):
    fields(campaign, 'format evidence aircraft configuration conditions video annotation intervals', 'campaign')
    require(campaign['format'] == 'openrc-roll-video v1', 'unsupported format')
    require(campaign['evidence'] in ('synthetic', 'measured'), 'invalid evidence')
    for key in ('aircraft', 'configuration', 'conditions'):
        require(text(campaign[key]), f'missing {key}')
    video = campaign['video']
    fields(video, 'source sha256 frame_count capture_fps_num capture_fps_den fps_relative_u original_cfr_verified timing_source', 'video')
    require(text(video['source']) and text(video['timing_source']), 'video source and timing source required')
    for key in ('frame_count', 'capture_fps_num', 'capture_fps_den'):
        require(type(video[key]) is int and 0 < video[key] <= MAX_EXACT_INT, f'invalid video.{key}')
    require(number(video['fps_relative_u'], 'fps_relative_u') >= 0, 'negative clock uncertainty')
    require(video['original_cfr_verified'] is True, 'original constant capture cadence must be verified')
    digest = video['sha256']
    require((campaign['evidence'] == 'synthetic' and digest is None)
            or (isinstance(digest, str) and re.fullmatch(r'[0-9a-f]{64}', digest)), 'video SHA-256 required for measured evidence')
    annotation = campaign['annotation']
    fields(annotation, 'source phase_definition sign_verified complete_turns_verified same_phase_verified independent_event_errors', 'annotation')
    require(text(annotation['source']) and text(annotation['phase_definition']), 'annotation source and physical phase definition required')
    for key in ('sign_verified', 'complete_turns_verified', 'same_phase_verified', 'independent_event_errors'):
        require(annotation[key] is True, f'annotation.{key} must be verified')
    require(isinstance(campaign['intervals'], list) and campaign['intervals'], 'intervals required')
    seen = set()
    for interval in campaign['intervals']:
        fields(interval, 'id start end notes', 'interval')
        require(all(identifier(interval[k]) for k in ('id', 'start', 'end')), 'invalid interval/event ID')
        require(interval['id'] not in seen, 'duplicate interval ID')
        require(text(interval['notes']), 'interval notes required')
        seen.add(interval['id'])


def read_events(raw, frame_count):
    reader = csv.DictReader(io.StringIO(raw.decode('utf-8'), newline=''), strict=True)
    require(reader.fieldnames == COLUMNS, 'CSV header must be ' + ','.join(COLUMNS))
    events = {}
    previous = -1
    for row in reader:
        require(set(row) == set(COLUMNS) and all(v is not None and v.strip() for v in row.values()), 'malformed/empty CSV row')
        name = row['id']
        require(identifier(name) and name not in events, 'invalid/duplicate event ID')
        require(re.fullmatch(r'0|[1-9][0-9]*', row['frame']), 'frame must be a nonnegative integer')
        require(re.fullmatch(r'0|-?[1-9][0-9]*', row['turn_index']), 'turn index must be a signed integer')
        frame, turns = int(row['frame']), int(row['turn_index'])
        require(previous < frame < frame_count, 'frames must increase within the original clip')
        require(abs(turns) <= MAX_EXACT_INT, 'turn index outside exact integer range')
        u = number(float(row['frame_u']), 'frame_u')
        require(u >= 0, 'negative event uncertainty')
        events[name] = {'frame': frame, 'frame_u': u, 'turn_index': turns}
        previous = frame
    require(len(events) >= 2, 'at least two events required')
    return events


def quantity(value, unit, terms):
    number(value, 'derived value')
    for term in terms.values():
        number(term, 'derived contribution')
    u = number(math.hypot(*terms.values()), 'derived uncertainty')
    return {'value': value, 'unit': unit, 'u': u, 'kind': 'derived', 'standard_uncertainty_contributions': terms}


def reduce_interval(interval, events, campaign):
    start_id, end_id = interval['start'], interval['end']
    require(start_id in events and end_id in events, 'missing interval event')
    start, end = events[start_id], events[end_id]
    n = end['frame'] - start['frame']
    turns = end['turn_index'] - start['turn_index']
    require(n > 0, 'interval end must follow start')
    require(turns != 0, 'nonzero complete turns required')
    segment = [e['turn_index'] for e in events.values() if start['frame'] <= e['frame'] <= end['frame']]
    require(all((b-a)*turns > 0 for a, b in zip(segment, segment[1:])), 'reversal or repeated turn index inside interval')
    fps = campaign['video']['capture_fps_num'] / campaign['video']['capture_fps_den']
    duration = n / fps
    period = duration / abs(turns)
    frequency = turns / duration
    rate = 360.0 * frequency
    require(all(math.isfinite(v) and v != 0 for v in (duration, period, frequency, rate)), 'derived result overflowed/underflowed')
    clock_u = campaign['video']['fps_relative_u']
    def timed(value, reciprocal):
        # Sign retains negative-turn rates; the same event/clock names carry cross-interval covariance.
        factor = 1.0 if reciprocal else -1.0
        return {f'event:{start_id}': factor*value/n*start['frame_u'],
                f'event:{end_id}': -factor*value/n*end['frame_u'],
                'capture_clock': factor*value*clock_u}
    q = {'duration': quantity(duration, 's', timed(duration, False)),
         'mean_period': quantity(period, 's/turn', timed(period, False)),
         'signed_turn_frequency': quantity(frequency, 'turn/s', timed(frequency, True)),
         'mean_completed_roll_rate': quantity(rate, 'deg/s', timed(rate, True))}
    warnings = []
    if q['duration']['u'] / duration > 0.1:
        warnings.append('Large timing uncertainty: first-order reciprocal propagation may be inadequate.')
    return {**interval, 'delta_frames': n, 'signed_complete_turns': turns,
            'frames_per_turn': n/abs(turns), **q, 'warnings': warnings}


def reduce(campaign, events_raw):
    """Pure calculation for tests; only the CLI verifies clip bytes and binds report hashes."""
    validate(campaign)
    events = read_events(events_raw, campaign['video']['frame_count'])
    return {'format': 'openrc-roll-video-result v1', 'evidence': campaign['evidence'],
            'campaign': campaign, 'events': events, 'limitations': LIMITATIONS,
            'intervals': [reduce_interval(i, events, campaign) for i in campaign['intervals']]}


def file_hash(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024*1024), b''):
            digest.update(block)
    return digest.hexdigest()


def refuse_alias(output, inputs):
    for path in inputs:
        require(output.resolve() != path.resolve() and not (output.exists() and path.exists() and output.samefile(path)),
                'output aliases an input or reducer')


def atomic_write(path, contents):
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', newline='\n', dir=path.parent, delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(contents)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('campaign', type=Path)
    parser.add_argument('events', type=Path)
    parser.add_argument('--video', type=Path, help='original clip; required exactly when a video hash is declared')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    try:
        inputs = [args.campaign, args.events, Path(__file__)] + ([args.video] if args.video else [])
        if args.output:
            refuse_alias(args.output, inputs)
        campaign_raw, events_raw = args.campaign.read_bytes(), args.events.read_bytes()
        campaign = load_json(campaign_raw)
        report = reduce(campaign, events_raw)
        expected = campaign['video']['sha256']
        require((args.video is not None) == (expected is not None), '--video must match the declared video SHA-256')
        video_hash = file_hash(args.video) if args.video else None
        require(video_hash == expected, 'video SHA-256 mismatch')
        report['input_sha256'] = {'campaign': hashlib.sha256(campaign_raw).hexdigest(),
                                  'events_csv': hashlib.sha256(events_raw).hexdigest(),
                                  'video': video_hash, 'reducer': file_hash(Path(__file__))}
        output = json.dumps(report, indent=2, sort_keys=True, allow_nan=False) + '\n'
        if args.output:
            refuse_alias(args.output, inputs)
            atomic_write(args.output, output)
        else:
            sys.stdout.write(output)
        return 0
    except (OSError, ValueError, TypeError, OverflowError, csv.Error) as error:
        print(f'VAL-8b: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
