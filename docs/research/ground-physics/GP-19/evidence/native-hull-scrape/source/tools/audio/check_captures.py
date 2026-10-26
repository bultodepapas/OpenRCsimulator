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
    hull_review = bool(report.get('arguments', {}).get('hull-scrape-review', False))
    hull_result = None
    if hull_review:
        wildlife_review = False
        hull_result = analyze_hull_review(report, audio, rate, failures)
        pause_peak = hull_result.get('pause_peak_linear')
    else:
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
        'review_kind': 'hull_scrape' if hull_review else ('wildlife' if wildlife_review else 'transitions'),
        'wildlife_event_count': len(report.get('wildlife_events', [])),
        'adapter_p95_us': report['soundscape_update_p95_us'],
        'adapter_max_us': report['soundscape_update_max_us'],
        'stereo_difference_rms': float(np.sqrt(np.mean((audio[:, 0] - audio[:, 1]) ** 2))),
        'max_adjacent_sample_step': float(np.max(np.abs(np.diff(audio, axis=0)))),
        'passed': not failures, 'failures': failures,
    }
    if hull_review:
        result['hull_scrape'] = hull_result
    return result


HULL_PHASES = ('airborne', 'opening_overlap', 'brush', 'pause', 'resume', 'reset', 'terminal')
HULL_AIRCRAFT = {
    'jensen-das-ugly-stik-60': 'res://data/aircraft/jensen_ugly_stik_60.json',
    'stik-glow-61fx-2t': 'res://data/aircraft/stik_glow_61fx_2t.json',
}
HULL_SOURCES = {
    'res://main.gd', 'res://sim/flight_session.gd', 'res://sim/simulation.gd',
    'res://physics/hull_contact.gd', 'res://physics/math3d.gd', 'res://physics/rigid_body.gd',
    'res://physics/effective_mass.gd', 'res://physics/mass_inventory.gd',
    'res://render/crash/director.gd', 'res://render/crash/crash_audio.gd',
    'res://render/crash/presentation_context.gd', 'res://assets/audio/crash/sources.json',
    'res://assets/audio/crash/scrape.wav', 'probe',
    'res://data/ground/surface_friction.json',
}


HULL_FIELDS = {'club_field': 'res://data/fields/default.json',
               'green_paradise': 'res://landscapes/green_paradise/field.json'}
HULL_LAKE_SOURCES = {'res://physics/lake_surface.gd', 'res://data/lake_loader.gd',
                     'res://data/fields/lake.json', 'res://render/field.gd',
                     'res://render/lake/lake_world.gd'}


def _number(value: object) -> bool:
    if type(value) not in (int, float):
        return False
    try:
        return math.isfinite(value)
    except OverflowError:
        return False


def _count(value: object, maximum: int = 1_000_000_000) -> bool:
    return type(value) is int and 0 <= value <= maximum


def _bind_phase_trace(phases: list, accepted: list, rendered: list, failures: list[str]) -> bool:
    """Bind every recorded sample to its complete phase slice and source clocks.

    Session.reset currently emits committed tick0 from Simulation before the
    public wrapper advances statistics_generation. Only its one leading old-gen
    accepted_step is allowed, followed immediately by the explicit post-return
    new-gen fixture boundary. This is observed owner ordering, not a generic
    license for mixed generations or reordered records.
    """
    accepted_end = render_end = 0
    for index, phase in enumerate(phases):
        for prefix, size, previous in (('accepted', len(accepted), accepted_end),
                                       ('render', len(rendered), render_end)):
            begin, end = phase.get(f'start_{prefix}_index'), phase.get(f'end_{prefix}_index')
            if not _count(begin, size) or not _count(end, size) or begin != previous or end <= begin:
                failures.append('hull trace phase index partitions are invalid or incomplete')
                return False
            if prefix == 'accepted': accepted_end = end
            else: render_end = end
        if index == 0 and phase['epoch'] != 1:
            failures.append('hull phase epoch/generation descriptors disagree with declared reset tape')
            return False
        if index:
            previous = phases[index-1]
            next_epoch = previous['epoch'] + int(index in (1, 2, 5, 6))
            next_generation = previous['generation'] + int(index == 5)
            if phase['epoch'] != next_epoch or phase['generation'] != next_generation:
                failures.append('hull phase epoch/generation descriptors disagree with declared reset tape')
                return False
    if accepted_end != len(accepted) or render_end != len(rendered):
        failures.append('hull trace phase index partitions are invalid or incomplete')
        return False
    last_wall = last_render_clock = -1.0
    previous_clock = None
    seen = set()
    for index, phase in enumerate(phases):
        begin, end = phase['start_accepted_index'], phase['end_accepted_index']
        samples = accepted[begin:end]
        old_generation_row = samples[0]['generation'] != phase['generation']
        if old_generation_row:
            expected_fixture = 'existing public Session.reset; new physical generation'
            if (index != 5 or phase.get('fixture') != expected_fixture or len(samples) < 2
                    or samples[0]['generation'] != phases[index-1]['generation']
                    or samples[0]['tick'] != 0 or samples[0]['sim_time_s'] != 0.0 or samples[0]['clock_origin'] != 'accepted_step'
                    or samples[1]['generation'] != phase['generation']
                    or samples[1]['tick'] != 0 or samples[1]['sim_time_s'] != 0.0 or samples[1]['clock_origin'] != 'fixture_boundary'):
                failures.append('hull reset publication generation transition is invalid')
                return False
        for offset, row in enumerate(samples):
            expected_generation = phases[index-1]['generation'] if old_generation_row and offset == 0 else phase['generation']
            if row['phase'] != index or row['epoch'] != phase['epoch'] or row['generation'] != expected_generation or row['tick'] < phase['start_tick']:
                failures.append('hull accepted sample is reassigned to another phase/epoch/generation')
                return False
            if (not phase['start_wall_s'] <= row['wall_s'] <= phase['end_wall_s']
                    or row['wall_s'] < last_wall or row['render_index'] < last_render_clock
                    or not phase['start_render_index'] <= row['render_index'] <= phase['end_render_index']):
                failures.append('hull accepted wall/render clocks are reordered or outside their phase')
                return False
            clock = (row['epoch'], row['generation'], row['tick'], row['sim_time_s'])
            identity = (index, row['epoch'], row['generation'], row['tick'], row['paused'])
            if identity in seen:
                failures.append('hull accepted clock was duplicated')
                return False
            if previous_clock is not None and clock[:2] == previous_clock[:2] and (clock[2] < previous_clock[2] or clock[3] < previous_clock[3]):
                failures.append('hull accepted tick/simulation clock ran backward inside its epoch')
                return False
            seen.add(identity)
            previous_clock = clock
            last_wall, last_render_clock = row['wall_s'], row['render_index']
    last_wall = -1.0
    previous_clock = None
    for index, phase in enumerate(phases):
        for position in range(phase['start_render_index'], phase['end_render_index']):
            row = rendered[position]
            if (not all(_count(row.get(key)) for key in ('tick', 'generation', 'render_index'))
                    or row['phase'] != index or row['generation'] != phase['generation']):
                failures.append('hull render sample is reassigned to another phase/generation')
                return False
            if (row['render_index'] != position+1 or row['wall_s'] < last_wall
                    or not phase['start_wall_s'] <= row['wall_s'] <= phase['end_wall_s']):
                failures.append('hull render wall/frame clocks are reordered or outside their phase')
                return False
            clock = (phase['epoch'], row['generation'], row['tick'])
            if previous_clock is not None and clock[:2] == previous_clock[:2] and clock[2] < previous_clock[2]:
                failures.append('hull render tick ran backward inside its epoch')
                return False
            previous_clock = clock
            last_wall = row['wall_s']
    return True


def analyze_hull_review(report: dict, audio: np.ndarray, rate: int, failures: list[str]) -> dict:
    """Separate actual accepted facts from native PCM; counters alone prove no sound."""
    review = report.get('hull_scrape_review')
    result = {'scope': 'CrashFX bus only, no Master/combined mix or acoustic calibration',
              'phase_pcm': {}, 'pause_peak_linear': None}
    if not isinstance(review, dict) or review.get('format') != 'openrc-hull-scrape-native-review-v1':
        failures.append('accepted hull native review envelope is missing or invalid')
        return result
    if (not isinstance(report.get('driver'), str) or not report['driver']
            or report['driver'].upper() == 'DUMMY'):
        failures.append('hull review requires an actual native audio driver')
    landscape = review.get('landscape_id')
    if not isinstance(landscape, str):
        landscape = ''
    if (landscape not in HULL_FIELDS or review.get('field_source') != HULL_FIELDS.get(landscape)
            or report.get('requested_fps') not in (30, 60, 144)):
        failures.append('hull review requires a declared supported field and requested30/60/144FPS')
    if (review.get('capture_bus_role') != 'crash_fx_after_local_limiter'
            or review.get('capture_bus_send') != 'Master' or review.get('master_capture') is not False):
        failures.append('hull PCM must identify the separate CrashFX bus and exclude Master capture')
    if (review.get('power_sampling') != 'accepted_endpoint_instantaneous_power'
            or review.get('cue_age_clock') != 'accepted_simulation_time'
            or not _number(review.get('cue_max_age_s')) or review['cue_max_age_s'] != .25):
        failures.append('hull power sampling or accepted-simulation cue-age contract is invalid')
    if (not isinstance(review.get('law_identity'), str) or not review['law_identity']
            or review.get('failures') != [] or review.get('truncated') is not False):
        failures.append('hull fixture is unsupported, failed, or truncated')
    before, after = review.get('source_before'), review.get('source_after')
    aircraft = report.get('aircraft')
    aircraft_path = HULL_AIRCRAFT.get(aircraft) if isinstance(aircraft, str) else None
    expected = HULL_SOURCES | ({aircraft_path} if aircraft_path else set())
    if landscape in HULL_FIELDS:
        expected |= {HULL_FIELDS[landscape], f'res://landscapes/{landscape}/landscape.gd'}
    if review.get('lake_enabled') is True:
        expected |= HULL_LAKE_SOURCES
    if (type(review.get('lake_enabled')) is not bool
            or not isinstance(review.get('lake_identity'), str)
            or (review['lake_enabled'] and not is_sha256(review['lake_identity']))
            or (not review['lake_enabled'] and review['lake_identity'])):
        failures.append('hull fixture lake binding identity is invalid')
    if (not aircraft_path or review.get('aircraft_source') != aircraft_path
            or not isinstance(before, dict) or not isinstance(after, dict)
            or set(before) != expected or before != after
            or any(not is_sha256(value) for value in before.values())
            or before.get('probe') != report.get('probe_sha256')
            or review.get('source_files_unchanged') is not True):
        failures.append('hull source/asset/aircraft identity is incomplete or changed during capture')
    phases, accepted, rendered = review.get('phases'), review.get('accepted'), review.get('render')
    if (not isinstance(phases, list) or len(phases) != len(HULL_PHASES)
            or not isinstance(accepted, list) or not 1 <= len(accepted) <= 16000
            or not isinstance(rendered, list) or not 1 <= len(rendered) <= 5000):
        failures.append('hull phase or accepted/render sample inventory is invalid')
        return result
    valid = True
    last_wall, last_frame = 0.0, 0
    for index, phase in enumerate(phases):
        if (not isinstance(phase, dict) or phase.get('index') != index
                or type(phase.get('index')) is not int
                or phase.get('name') != HULL_PHASES[index] or phase.get('reset_accepted') is not True
                or not all(_number(phase.get(key)) for key in ('start_wall_s', 'end_wall_s'))
                or not all(_count(phase.get(key), len(audio)) for key in ('start_frame', 'end_frame'))
                or not all(_count(phase.get(key)) for key in ('emitted_before', 'emitted_after', 'epoch', 'start_tick', 'generation'))
                or phase['start_wall_s'] < last_wall or phase['end_wall_s'] <= phase['start_wall_s']
                or phase['start_frame'] < last_frame or phase['end_frame'] <= phase['start_frame']
                or phase['emitted_after'] < phase['emitted_before']):
            valid = False
            break
        last_wall, last_frame = phase['end_wall_s'], phase['end_frame']
        # Byte positions correspond to drained mixer data. Guards avoid existing
        # driver/ring latency at a phase boundary; waveform meters are independent
        # of presentation emission counters and are not a grain fingerprint.
        lead, tail = ((.03, .05) if index in (2, 6) else (.35, .15))
        begin = min(len(audio), phase['start_frame'] + round(lead * rate))
        end = max(begin, min(len(audio), phase['end_frame'] - round(tail * rate)))
        pcm = audio[begin:end]
        if not pcm.size:
            valid = False
            break
        result['phase_pcm'][phase['name']] = {
            'frames': len(pcm), 'peak_linear': float(np.max(np.abs(pcm))),
            'rms_linear': float(np.sqrt(np.mean(pcm ** 2))),
            'begin_frame': begin, 'end_frame': end,
        }
    if not valid:
        failures.append('hull phase boundaries/PCM intervals are incomplete or invalid')
        return result
    for sample in accepted:
        if (not isinstance(sample, dict)
                or not all(_count(sample.get(key)) for key in ('epoch', 'phase', 'tick', 'generation', 'geometric_contacts', 'loaded_contacts', 'queued', 'emitted', 'tagged_voices', 'render_index'))
                or sample['phase'] >= len(HULL_PHASES) or sample['queued'] > 64 or sample['tagged_voices'] > 7
                or not all(type(sample.get(key)) is bool for key in ('paused', 'terminal', 'available', 'cancellation_pending'))
                or not all(_number(sample.get(key)) and sample[key] >= 0 for key in ('wall_s', 'sim_time_s', 'friction_power_w'))
                or not isinstance(sample.get('reason'), str) or not isinstance(sample.get('contact_ids'), list)
                or sample['loaded_contacts'] != len(sample['contact_ids']) or sample['loaded_contacts'] > 256
                or any(not isinstance(value, str) or not value for value in sample['contact_ids'])
                or len(set(sample['contact_ids'])) != len(sample['contact_ids'])
                or sample.get('clock_origin') not in ('accepted_step', 'pause_notification', 'fixture_boundary')
                or sample['available'] is not True or sample['reason']):
            failures.append('hull accepted physical facts are malformed or unavailable')
            return result
        if sample['friction_power_w'] > 0 and not sample['loaded_contacts']:
            failures.append('hull positive friction power has no loaded source contact')
            return result
    for sample in rendered:
        diag = sample.get('diagnostics') if isinstance(sample, dict) else None
        if (not isinstance(sample, dict) or not isinstance(diag, dict)
                or not _count(sample.get('phase'), 6) or not _count(sample.get('max_voices'), 8)
                or sample['max_voices'] != 8 or not _count(sample.get('active_voices'), 8)
                or not _count(sample.get('active_tagged_voices'), 7)
                or not all(type(sample.get(key)) is bool for key in ('paused', 'terminal', 'primary_played'))
                or not _number(sample.get('wall_s')) or sample['wall_s'] < 0
                or sample.get('fault_reason') != ''
                or not all(_count(diag.get(key)) for key in ('queued', 'emitted', 'overflow', 'stale', 'invalid', 'tagged_voices'))
                or diag['queued'] > 64 or diag['tagged_voices'] > 7
                or diag['overflow'] or diag['stale'] or diag['invalid']):
            failures.append('hull render lifecycle/pool facts are malformed or lost events')
            return result
    if not _bind_phase_trace(phases, accepted, rendered, failures):
        return result
    by_phase = [accepted[p['start_accepted_index']:p['end_accepted_index']] for p in phases]
    render_phase = [rendered[p['start_render_index']:p['end_render_index']] for p in phases]
    if any(not rows for rows in by_phase) or any(not rows for rows in render_phase):
        failures.append('hull phase labels lack actual accepted/render observations')
        return result
    if (any(row['loaded_contacts'] or row['friction_power_w'] or row['queued'] for row in by_phase[0])
            or phases[0]['emitted_after'] != phases[0]['emitted_before']):
        failures.append('airborne hull interval produced loaded scraping')
    if any(row['terminal'] for rows in by_phase[:6] for row in rows) or any(row['terminal'] for rows in render_phase[:6] for row in rows):
        failures.append('hull fixture terminated before its declared terminal phase')
    opening = by_phase[1]
    if (not any(row['geometric_contacts'] > 0 and row['loaded_contacts'] == 0 and row['friction_power_w'] == 0 for row in opening)
            or any(row['loaded_contacts'] or row['friction_power_w'] or row['queued'] for row in opening)
            or phases[1]['emitted_after'] != phases[1]['emitted_before']):
        failures.append('opening overlap did not demonstrate zero clamped friction without grains')
    if not any(row['clock_origin'] == 'accepted_step' and row['tick'] > 0 for row in accepted):
        failures.append('hull review has no actual accepted physics advancement')
    brush = by_phase[2]
    if (not any(row['friction_power_w'] > 0 and row['contact_ids'] for row in brush)
            or phases[2]['emitted_after'] <= phases[2]['emitted_before']
            or not any(row['active_tagged_voices'] > 0 for row in render_phase[2])):
        failures.append('brush phase lacks actual loaded source and native tagged playback facts')
    if (not any(row['paused'] for row in by_phase[3])
            or any(row['queued'] for row in by_phase[3])
            or phases[3]['emitted_after'] != phases[3]['emitted_before']):
        failures.append('paused hull interval queued or replayed scraping')
    if not any(not row['paused'] for row in by_phase[4]):
        failures.append('hull resume did not produce an unpaused accepted observation')
    if (phases[5]['generation'] <= phases[4]['generation']
            or any(row['queued'] for row in by_phase[5])):
        failures.append('public hull reset did not advance generation and clear cues')
    terminal = [row for row in render_phase[6] if row['terminal']]
    if (not any(row['terminal'] for row in by_phase[6]) or not terminal
            or not any(row['primary_played'] for row in terminal)
            or any(row['diagnostics']['queued'] or row['diagnostics']['tagged_voices'] or row['active_tagged_voices'] for row in terminal)):
        failures.append('actual terminal handoff did not exclusively cancel living-hull scrape')
    for name in ('airborne', 'opening_overlap', 'pause', 'reset'):
        if result['phase_pcm'][name]['peak_linear'] > 1.0 / 32768.0:
            failures.append(f'{name} CrashFX PCM did not reach silence')
    for name in ('brush', 'terminal'):
        if result['phase_pcm'][name]['peak_linear'] <= 1.0 / 32768.0:
            failures.append(f'{name} has no independent nonzero CrashFX PCM interval')
    result['pause_peak_linear'] = result['phase_pcm']['pause']['peak_linear']
    result['accepted_samples'] = len(accepted)
    result['render_samples'] = len(rendered)
    result['source_files_unchanged'] = review.get('source_files_unchanged')
    result['note'] = ('Loaded source facts, tagged native player state and nonzero bus PCM are separate checks; '
                      'no emission-counter-to-PCM grain, heat, damage, calibrated sound or whole-flight claim.')
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
