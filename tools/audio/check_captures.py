"""AUD-04: check real mixer captures; never substitutes meters for listening."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import string
import wave
from pathlib import Path

import numpy as np


def finite_positive(value: object) -> bool:
    try:
        number = float(value)
    except (TypeError, ValueError, OverflowError):
        return False
    return math.isfinite(number) and number > 0.0


def is_sha256(value: object) -> bool:
    return isinstance(value, str) and len(value) == 64 and all(char in string.hexdigits for char in value)


def check_bookkeeping(report: dict, recorded_frames: int, failures: list[str]) -> dict | None:
    bookkeeping = report.get('capture_bookkeeping')
    if not isinstance(bookkeeping, dict):
        failures.append('capture frame bookkeeping is missing')
        return None
    names = ('pushed_frames', 'recorded_frames', 'flushed_frames', 'truncated_frames',
             'overflow_discarded_frames', 'unaccounted_pushed_frames')
    if any(not isinstance(bookkeeping.get(name), int) or bookkeeping[name] < 0 for name in names):
        failures.append('capture frame bookkeeping contains invalid counts')
        return bookkeeping
    if not isinstance(bookkeeping.get('buffer_length_frames'), int) or bookkeeping['buffer_length_frames'] <= 0:
        failures.append('capture ring-buffer length is missing or invalid')
    if bookkeeping['recorded_frames'] != recorded_frames:
        failures.append('capture bookkeeping recorded-frame count differs from WAV')
    if bookkeeping['overflow_discarded_frames'] != report.get('discarded_frames'):
        failures.append('capture bookkeeping overflow count differs from report')
    if bookkeeping['truncated_frames'] != 0:
        failures.append('capture exceeded the staged PCM memory bound')
    final = bookkeeping.get('final')
    if not isinstance(final, dict) or not isinstance(final.get('available_frames_after_flush'), int):
        failures.append('capture final buffer count is missing')
        return bookkeeping
    pending = final['available_frames_after_flush']
    if pending < 0 or pending != 0:
        failures.append('capture buffer was not empty after final drain')
    if (not isinstance(final.get('available_frames_before_flush'), int)
            or not isinstance(final.get('flushed_frames'), int)
            or final['available_frames_before_flush'] != final['flushed_frames']
            or final['flushed_frames'] != bookkeeping['flushed_frames']):
        failures.append('capture final flush count differs from remaining buffer count')
    expected_unaccounted = (bookkeeping['pushed_frames'] - bookkeeping['recorded_frames']
                            - bookkeeping['flushed_frames'] - bookkeeping['truncated_frames'] - pending)
    if bookkeeping['unaccounted_pushed_frames'] != expected_unaccounted or expected_unaccounted != 0:
        failures.append('capture pushed/recorded/flushed frame counts do not balance')
    initial = bookkeeping.get('initial')
    if not isinstance(initial, dict):
        failures.append('capture initial counters are missing')
        return bookkeeping
    if (not isinstance(initial.get('pushed_frames'), int)
            or not isinstance(final.get('pushed_frames'), int)
            or final['pushed_frames'] - initial['pushed_frames'] != bookkeeping['pushed_frames']):
        failures.append('capture pushed-frame endpoints do not match their delta')
    if (not isinstance(initial.get('discarded_frames'), int)
            or not isinstance(final.get('discarded_frames'), int)
            or final['discarded_frames'] - initial['discarded_frames']
            != bookkeeping['overflow_discarded_frames']):
        failures.append('capture overflow endpoints do not match their delta')
    if not report.get('capture_effect_removed', False):
        failures.append('capture effect was not removed after recording')
    return bookkeeping


def analyze(prefix: Path) -> dict:
    report = json.loads(prefix.with_suffix('.json').read_text())
    path = prefix.with_suffix('.wav')
    with wave.open(str(path), 'rb') as wav:
        assert wav.getnchannels() == 2 and wav.getsampwidth() == 2
        rate = wav.getframerate()
        pcm = np.frombuffer(wav.readframes(wav.getnframes()), dtype='<i2').reshape(-1, 2)
    audio = pcm.astype(np.float64) / 32768.0
    failures = []
    if report['discarded_frames'] != 0:
        failures.append('mixer capture dropped frames')
    wall = report.get('capture_wall_seconds')
    if not finite_positive(wall):
        failures.append('capture wall time is missing, non-finite, or non-positive')
        wall_error = None
    else:
        wall_error = abs(len(pcm) / rate - float(wall))
    if wall_error is not None and wall_error > .12:
        failures.append('native PCM duration differs from capture wall time by over 120 ms')
    check_bookkeeping(report, len(pcm), failures)
    if not is_sha256(report.get('probe_sha256')):
        failures.append('capture probe source hash is missing or invalid')
    if report.get('finite_samples') is not True:
        failures.append('capture contains non-finite samples')
    timing_sample_count = report.get('soundscape_timing_sample_count')
    if not isinstance(timing_sample_count, int) or timing_sample_count <= 0:
        failures.append('soundscape timing sample set is empty')
    if report['peak_dbfs'] > -0.9:
        failures.append('capture crossed the -1 dBFS ceiling tolerance')
    if np.any(np.abs(pcm.astype(np.int32)) >= 32767):
        failures.append('PCM reached a full-scale rail')
    events = {int(e['stage']): e for e in report['events']}
    wildlife_review = bool(report.get('arguments', {}).get('wildlife-review', False))
    if not wildlife_review and set(events) != set(range(7)):
        failures.append('transition tape did not complete')
    pause = (audio[int((events[3]['wall_s'] + .35) * rate):int((events[4]['wall_s'] - .15) * rate)]
             if 3 in events and 4 in events else audio[:0])
    pause_peak = float(np.max(np.abs(pause))) if pause.size else 1.0
    if not wildlife_review and pause_peak > 1.0 / 32768.0:
        failures.append('pause did not reach silence')
    if not wildlife_review and report['distance_min_m'] > 4.0:
        failures.append('camera change did not reach close aircraft view')
    if not wildlife_review and not (all(i in events for i in (1, 2, 3)) and
            events[2]['rpm'] > events[1]['rpm'] and events[2]['rpm'] > events[3]['rpm']):
        failures.append('real RPM did not rise and fall across throttle tape')
    if wildlife_review:
        if report.get('final_paused', True) or report.get('final_tick', 0) < report['captured_seconds'] * 240 * .85:
            failures.append('wildlife review did not sustain the actual flight')
        previous = {}
        for event in report.get('wildlife_events', []):
            species = event['species']
            if previous.get(species) == event['variant']:
                failures.append('adjacent wildlife variant repeated')
            previous[species] = event['variant']
        if not previous:
            failures.append('wildlife review captured no animal calls')
    if report['soundscape_update_p95_us'] > 500:
        failures.append('adapter update p95 exceeded 0.5 ms budget')
    result = {
        'capture': prefix.name, 'sha256_wav': hashlib.sha256(path.read_bytes()).hexdigest(),
        'checker_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        'driver': report['driver'], 'display': report['display'], 'fps': report['requested_fps'],
        'aircraft': report['aircraft'], 'seconds': len(pcm) / rate,
        'capture_wall_seconds': float(wall) if finite_positive(wall) else None,
        'capture_wall_error_seconds': wall_error,
        'probe_sha256': report.get('probe_sha256'),
        'capture_bookkeeping': report.get('capture_bookkeeping'),
        'timing_sample_count': timing_sample_count,
        'peak_dbfs': report['peak_dbfs'], 'rms_dbfs': report['rms_dbfs'],
        'pause_peak_linear': None if wildlife_review else pause_peak, 'dropped_frames': report['discarded_frames'],
        'review_kind': 'wildlife' if wildlife_review else 'transitions',
        'wildlife_event_count': len(report.get('wildlife_events', [])),
        'adapter_p95_us': report['soundscape_update_p95_us'],
        'adapter_max_us': report['soundscape_update_max_us'],
        'stereo_difference_rms': float(np.sqrt(np.mean((audio[:, 0] - audio[:, 1]) ** 2))),
        'max_adjacent_sample_step': float(np.max(np.abs(np.diff(audio, axis=0)))),
        'passed': not failures, 'failures': failures,
    }
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('prefix', nargs='+', type=Path)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    results = [analyze(p) for p in args.prefix]
    output = {'format': 'openrc-audio-capture-checks-v1', 'captures': results,
              'limits': 'Mixer and transition verification only. Sample steps are reported, not a perceptual click detector. Shared-host wall timings are not target-hardware qualification.'}
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(output, indent=2) + '\n')
    print(json.dumps(output, indent=2))
    return 0 if all(r['passed'] for r in results) else 1


if __name__ == '__main__':
    raise SystemExit(main())
