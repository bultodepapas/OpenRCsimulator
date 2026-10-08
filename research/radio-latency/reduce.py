#!/usr/bin/env python3
"""F6b: reduce filmed input-to-patch frame annotations (Python stdlib only)."""
import argparse
import csv
import hashlib
import io
import json
import math
from pathlib import Path
import re
import sys

COLUMNS = ('condition', 'trial', 'clip', 'stick_frame', 'patch_frame',
           'stick_pick_radius', 'patch_pick_radius', 'exclusion_reason')
LIMITATIONS = [
    'Only physical-reference crossing to visible patch transition is observed; no servo or aircraft response.',
    'Frame intervals are conditional bounds, not confidence intervals or population percentile uncertainty.',
    'Exposure, rolling shutter, scanline mismatch and physical-reference error are not quantified here.',
    'Constant original acquisition cadence is required; playback FPS and variable/dropped-frame clips are unsupported.',
    'Twenty usable trials are a minimum screen, not a stable estimate of tail latency.',
    'Clip hashes and acquisition metadata are declarations; video files are not opened or authenticated.',
    'No hardware acceptance or input-threading decision is inferred from this report.',
]


def fields(obj, expected, where):
    if not isinstance(obj, dict) or set(obj) != set(expected):
        raise ValueError(f'{where}: expected exactly {sorted(expected)}')


def text(value, where):
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f'{where}: expected nonempty text')
    return value


def number(value, where, positive=True):
    if type(value) not in (int, float) or not math.isfinite(value):
        raise ValueError(f'{where}: expected finite number')
    if value < 0 or (positive and value == 0):
        raise ValueError(f'{where}: invalid sign/zero')
    return value


def integer(value, where):
    if type(value) is not int or not 0 <= value <= 2**53-1:
        raise ValueError(f'{where}: expected nonnegative exact frame integer')
    return value


def finite(value):
    if not math.isfinite(value):
        raise ValueError('derived result outside finite range')
    return value


def load(raw):
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise ValueError(f'duplicate JSON key: {key}')
            result[key] = value
        return result

    def bad_constant(value):
        raise ValueError(f'nonfinite JSON constant: {value}')

    return json.loads(raw, object_pairs_hook=pairs, parse_constant=bad_constant)


def read_trials(raw):
    reader = csv.DictReader(io.StringIO(raw), strict=True)
    if reader.fieldnames != list(COLUMNS):
        raise ValueError(f'CSV header must be {",".join(COLUMNS)}')
    rows = list(reader)
    for row in rows:
        fields(row, COLUMNS, 'CSV row')
        if any(value is None for value in row.values()):
            raise ValueError('incomplete CSV row')
    return rows


def manifest_records(document):
    fields(document, ('format', 'evidence', 'notes', 'conditions', 'clips'), 'manifest')
    if document['format'] != 'openrc-latency-video v1':
        raise ValueError('unsupported manifest format')
    if document['evidence'] not in ('synthetic', 'measured'):
        raise ValueError('evidence must be synthetic or measured')
    text(document['notes'], 'notes')
    for key in ('conditions', 'clips'):
        if not isinstance(document[key], list) or not document[key]:
            raise ValueError(f'{key}: expected nonempty list')
    conditions, clips, hashes = {}, {}, set()
    for c in document['conditions']:
        fields(c, ('id', 'build', 'system', 'radio', 'display_refresh_hz', 'vsync',
                   'frame_cap_fps', 'achieved_fps', 'marker', 'notes'), 'condition')
        for key in ('id', 'build', 'system', 'radio', 'marker', 'notes'):
            text(c[key], f'condition.{key}')
        if c['id'] in conditions:
            raise ValueError('duplicate condition ID')
        if c['vsync'] not in ('on', 'off', 'adaptive', 'mailbox'):
            raise ValueError('vsync must name the observed mode')
        for key in ('display_refresh_hz', 'achieved_fps', 'frame_cap_fps'):
            number(c[key], key, positive=(key != 'frame_cap_fps'))
        conditions[c['id']] = c
    for clip in document['clips']:
        fields(clip, ('id', 'condition', 'source', 'sha256', 'frame_count', 'timebase',
                      'acquisition_fps', 'timing_notes'), 'clip')
        for key in ('id', 'condition', 'source', 'timing_notes'):
            text(clip[key], f'clip.{key}')
        if clip['condition'] not in conditions:
            raise ValueError('clip references unknown condition')
        if clip['id'] in clips:
            raise ValueError('duplicate clip ID')
        digest = clip['sha256']
        if not isinstance(digest, str) or not re.fullmatch('[0-9a-f]{64}', digest):
            raise ValueError('clip sha256 must be 64 lowercase hexadecimal digits')
        if digest in hashes:
            raise ValueError('same clip hash declared more than once')
        hashes.add(digest)
        if integer(clip['frame_count'], 'frame_count') < 2:
            raise ValueError('clip needs at least two frames')
        if clip['timebase'] != 'constant-acquisition-cadence':
            raise ValueError('only constant original acquisition cadence is supported')
        fps = clip['acquisition_fps']
        fields(fps, ('value', 'min', 'max', 'kind', 'source'), 'acquisition_fps')
        for key in ('value', 'min', 'max'):
            number(fps[key], f'acquisition_fps.{key}')
        if not fps['min'] <= fps['value'] <= fps['max']:
            raise ValueError('acquisition FPS bounds must contain value')
        if fps['kind'] not in ('synthetic', 'measured', 'derived'):
            raise ValueError('acquisition FPS kind must be synthetic, measured or derived')
        if document['evidence'] == 'measured' and fps['kind'] == 'synthetic':
            raise ValueError('synthetic cadence in measured campaign')
        text(fps['source'], 'acquisition_fps.source')
        clips[clip['id']] = clip
    return conditions, clips


def median(values):
    s = sorted(values)
    n = len(s)
    return s[n//2] if n % 2 else finite(s[n//2-1]/2+s[n//2]/2)


def p95(values):
    s = sorted(values)
    return s[(95*len(s)+99)//100-1]


def reduce(document, rows):
    conditions, clips = manifest_records(document)
    if not isinstance(rows, list) or not rows:
        raise ValueError('need at least one annotated or excluded trial')
    trials, seen, stick_events, patch_events = [], set(), set(), set()
    for row in rows:
        fields(row, COLUMNS, 'trial')
        if any(not isinstance(v, str) for v in row.values()):
            raise ValueError('CSV trial fields must be text')
        for key in ('condition', 'trial', 'clip'):
            text(row[key], key)
        condition, clip_id = row['condition'], row['clip']
        if condition not in conditions or clip_id not in clips:
            raise ValueError('trial references unknown condition/clip')
        clip = clips[clip_id]
        if clip['condition'] != condition:
            raise ValueError('trial condition disagrees with clip')
        identity = (condition, row['trial'])
        if identity in seen:
            raise ValueError('duplicate trial ID within condition')
        seen.add(identity)
        frame_keys = COLUMNS[3:7]
        excluded = bool(row['exclusion_reason'].strip())
        if row['exclusion_reason'] and not excluded:
            raise ValueError('exclusion reason cannot be whitespace')
        if excluded and all(row[k] == '' for k in frame_keys):
            trials.append({'annotation': row, 'excluded': True})
            continue
        parsed = {}
        for key in frame_keys:
            if not re.fullmatch('[0-9]+', row[key]):
                raise ValueError(f'{key}: expected nonnegative integer text')
            parsed[key] = integer(int(row[key]), key)
        s, p, rs, rp = (parsed[k] for k in frame_keys)
        for frame, radius in ((s, rs), (p, rp)):
            if frame-1-radius < 0 or frame+radius >= clip['frame_count']:
                raise ValueError('event interval extends outside original clip')
        stick_event, patch_event = (clip_id, s), (clip_id, p)
        if stick_event in stick_events or patch_event in patch_events:
            raise ValueError('stick or patch crossing reused in multiple trials')
        stick_events.add(stick_event)
        patch_events.add(patch_event)
        if excluded:
            trials.append({'annotation': row, 'excluded': True})
            continue
        fps = clip['acquisition_fps']
        delta = p-s
        radius = 1+rs+rp
        corners = [finite(1000.*d/f) for d in (delta-radius, delta+radius)
                   for f in (fps['min'], fps['max'])]
        trials.append({'annotation': row, 'excluded': False,
                       'latency_ms': finite(1000.*delta/fps['value']),
                       'frame_and_cadence_bounds_ms': [min(corners), max(corners)]})
    summaries = []
    for condition in conditions:
        group = [r for r in trials if r['annotation']['condition'] == condition]
        usable = [r for r in group if not r['excluded']]
        n = len(usable)
        summary = {'condition': condition, 'trial_count': len(group), 'usable_count': n,
                   'excluded_count': len(group)-n, 'minimum_20_trials_met': n >= 20,
                   'statistics': None, 'warnings': []}
        if n < 20:
            summary['warnings'].append('Fewer than 20 usable trials; collect more for the F6 screen.')
        if n:
            stats = {}
            for name, reducer in (('median', median), ('p95_nearest_rank', p95)):
                stats[name+'_ms'] = reducer([r['latency_ms'] for r in usable])
                stats[name+'_bounds_ms'] = [reducer([r['frame_and_cadence_bounds_ms'][i] for r in usable])
                                            for i in (0, 1)]
            stats['min_ms'] = min(r['latency_ms'] for r in usable)
            stats['max_ms'] = max(r['latency_ms'] for r in usable)
            summary['statistics'] = stats
            if any(r['latency_ms'] < 0 for r in usable):
                summary['warnings'].append('Negative nominal latency: inspect reference marks and frame pairing; values retained.')
            if any(r['frame_and_cadence_bounds_ms'][0] < 0 for r in usable):
                summary['warnings'].append('At least one event interval permits negative latency; no zero clamping applied.')
        summaries.append(summary)
    return {'format': 'openrc-latency-video-result v1', 'kind': 'derived', 'input': document,
            'trials': trials, 'conditions': summaries, 'video_hashes_verified': False,
            'proposed_60hz_reference_budget_ms': {'median': 50, 'p95': 70,
                'status': 'reference only; no automatic acceptance'}, 'limitations': LIMITATIONS}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('manifest', type=Path)
    parser.add_argument('trials', type=Path)
    args = parser.parse_args()
    try:
        manifest_raw, trials_raw = args.manifest.read_bytes(), args.trials.read_bytes()
        result = reduce(load(manifest_raw), read_trials(trials_raw.decode('utf-8')))
        result['sha256'] = {'manifest': hashlib.sha256(manifest_raw).hexdigest(),
                            'trials_csv': hashlib.sha256(trials_raw).hexdigest(),
                            'reducer': hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
        rendered = json.dumps(result, indent=2, allow_nan=False)+'\n'
    except (OSError, ValueError, TypeError, OverflowError, ZeroDivisionError, RecursionError, csv.Error) as exc:
        print(f'Latency reduction failed: {exc}', file=sys.stderr)
        return 1
    sys.stdout.write(rendered)
    return 0


if __name__ == '__main__':
    sys.exit(main())
