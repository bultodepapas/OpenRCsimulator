"""AUD-04: check real mixer captures; never substitutes meters for listening."""
from __future__ import annotations

import argparse
import hashlib
import json
import wave
from pathlib import Path

import numpy as np


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
        'driver': report['driver'], 'display': report['display'], 'fps': report['requested_fps'],
        'aircraft': report['aircraft'], 'seconds': len(pcm) / rate,
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
