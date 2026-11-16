#!/usr/bin/env python3
"""Revalidate CPU-backend evidence, stage a candidate, then publish after Home proof.

A package-flight summary alone is not a promotion decision. This artifact
consistency workflow makes no GPU, scanout, physical-radio or graphics claim.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timedelta
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import re
import statistics
import subprocess
import sys
import tempfile
import time
from typing import Any


class AdmissionError(ValueError):
    pass


MAX_REGRESSION = 0.05
REPOSITORY = 'bultodepapas/OpenRCsimulator'
CI_GATES = ('CI required', 'NK-3 native kernel qualification (macOS ARM64) / Experimental fixed-wing source correctness')
ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AdmissionError(message)


def canonical_sha(value: Any) -> str:
    data = json.dumps(value, sort_keys=True, separators=(',', ':'), allow_nan=False).encode('utf-8')
    return hashlib.sha256(data).hexdigest()


def verify_ci_records(before: Any, jobs: Any, after: Any, commit: str, run_id: int) -> dict[str, str]:
    """Bind a stable GitHub API run and its actual aggregate and Mac jobs."""
    require(isinstance(commit, str) and re.fullmatch(r'[0-9a-f]{40}', commit) is not None
            and type(run_id) is int and run_id > 0 and isinstance(before, dict) and isinstance(after, dict)
            and isinstance(jobs, list), 'CI evidence is malformed')
    require(isinstance(before.get('repository'), dict) and isinstance(after.get('repository'), dict),
            'CI repository identity is malformed')
    fields = ('id', 'run_attempt', 'head_sha', 'status', 'conclusion', 'path', 'event')
    require(all(before.get(key) == after.get(key) for key in fields)
            and before.get('id') == run_id and before.get('head_sha') == commit
            and type(before.get('run_attempt')) is int and before['run_attempt'] > 0
            and before.get('status') == 'completed' and before.get('conclusion') == 'success'
            and before.get('path') == '.github/workflows/ci.yml'
            and before.get('event') in ('push', 'workflow_dispatch')
            and before.get('repository', {}).get('full_name') == REPOSITORY
            and after.get('repository', {}).get('full_name') == REPOSITORY, 'CI run identity or result differs')
    selected = {}
    for name in CI_GATES:
        matches = [job for job in jobs if isinstance(job, dict) and job.get('name') == name]
        require(len(matches) == 1 and matches[0].get('run_id') == run_id
                and type(matches[0].get('id')) is int and matches[0]['id'] > 0
                and matches[0].get('status') == 'completed' and matches[0].get('conclusion') == 'success',
                'required CI job missing, duplicated, skipped or failed: ' + name)
        selected[name] = matches[0]['id']
    require(selected[CI_GATES[0]] != selected[CI_GATES[1]], 'CI job identifiers collide')
    return {'head_sha': commit, 'repository': REPOSITORY, 'run_id': str(run_id),
            'attempt': str(before['run_attempt']), 'required_job_id': str(selected[CI_GATES[0]]),
            'macos_job_id': str(selected[CI_GATES[1]])}


def _arguments(scenario: dict[str, Any], role: str) -> list[str]:
    args = scenario.get('arguments')
    require(isinstance(args, list) and all(isinstance(arg, str) for arg in args), 'missing scenario arguments')
    require(role in ('gdscript_reference', 'native')
            and [arg for arg in args if arg.startswith('--physics-backend=')] == ['--physics-backend=' + role]
            and [arg for arg in args if arg.startswith('--experimental-native-macos=')] ==
            ['--experimental-native-macos=' + ('true' if role == 'native' else 'false')],
            'flight backend or explicit experimental admission differs')
    omitted = ('--frametimes=', '--package-flight-receipt=', '--physics-backend=', '--experimental-native-macos=')
    return [arg for arg in args if not arg.startswith(omitted)]


def _interval(checked: dict[str, Any]) -> tuple[datetime, datetime]:
    started, elapsed = checked.get('started_utc'), checked.get('elapsed_seconds')
    require(isinstance(started, str) and type(elapsed) in (int, float)
            and math.isfinite(elapsed) and 0 < elapsed <= 7500, 'invalid checked-process time interval')
    try:
        first = datetime.fromisoformat(started.replace('Z', '+00:00'))
    except (ValueError, OverflowError) as error:
        raise AdmissionError('invalid checked-process start') from error
    require(first.utcoffset() is not None, 'checked-process start lacks a UTC offset')
    return first, first + timedelta(seconds=elapsed)


def _utc(value: Any) -> datetime:
    require(isinstance(value, str) and 1 <= len(value) <= 64, 'host witness UTC timestamp is missing')
    try:
        result = datetime.fromisoformat(value.replace('Z', '+00:00'))
    except (ValueError, OverflowError) as error:
        raise AdmissionError('host witness UTC timestamp is invalid') from error
    require(result.utcoffset() == timedelta(0), 'host witness timestamp is not UTC')
    return result


def verify_host_witness(witness: Any, frame: dict[str, Any], checked: dict[str, Any], checked_sha: str,
                        expected_host: dict[str, Any]) -> dict[str, Any]:
    """Bind one reported host/boot and outer clock bracket to a checked capture."""
    require(isinstance(witness, dict) and set(witness) == {'format', 'before', 'checked', 'after'}
            and witness.get('format') == 'openrc-package-flight-host-witness v1', 'host witness is malformed')
    before, middle, after = witness.get('before'), witness.get('checked'), witness.get('after')
    boundary = {'utc_start', 'utc_end', 'monotonic_start_ns', 'monotonic_end_ns', 'host'}
    middle_fields = {'utc_start', 'utc_end', 'monotonic_start_ns', 'monotonic_end_ns',
                     'capture_id', 'pid', 'report_sha256', 'log_sha256'}
    require(isinstance(before, dict) and isinstance(after, dict) and isinstance(middle, dict)
            and set(before) == boundary and set(after) == boundary and set(middle) == middle_fields,
            'host witness boundaries are malformed')
    host = before.get('host')
    host_fields = {'model', 'cpu_brand', 'memory_bytes', 'boot_session_uuid', 'os_product_version', 'os_build_version'}
    require(isinstance(host, dict) and set(host) == host_fields and after.get('host') == host
            and all(host.get(key) == expected_host.get(key) and type(host.get(key)) is type(expected_host.get(key))
                    for key in host_fields - {'boot_session_uuid'})
            and type(host.get('memory_bytes')) is int and host['memory_bytes'] > 0
            and isinstance(host.get('boot_session_uuid'), str)
            and re.fullmatch(r'[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}', host['boot_session_uuid']) is not None
            and host['boot_session_uuid'] != '00000000-0000-0000-0000-000000000000',
            'host witness does not match the selected M1 hardware, OS or boot identity')
    require(middle.get('capture_id') == frame.get('capture_id') == checked.get('capture_id')
            and type(middle.get('pid')) is int and middle['pid'] > 0 and middle['pid'] == frame.get('pid')
            and middle.get('report_sha256') == checked_sha and middle.get('log_sha256') == checked.get('log_sha256'),
            'host witness belongs to a different checked process or evidence')
    times = [piece.get(key) for piece in (before, middle, after)
             for key in ('monotonic_start_ns', 'monotonic_end_ns')]
    require(all(type(value) is int and value > 0 for value in times)
            and all(a <= b for a, b in zip(times, times[1:])) and times[2] < times[3],
            'host witness monotonic brackets overlap or regress')
    utc = [_utc(piece.get(key)) for piece in (before, middle, after) for key in ('utc_start', 'utc_end')]
    require(all(a <= b for a, b in zip(utc, utc[1:])) and utc[2] < utc[3],
            'host witness UTC brackets overlap or regress')
    start, end = _interval(checked)
    require(utc[2] - timedelta(milliseconds=2) <= start <= end <= utc[3] + timedelta(milliseconds=2),
            'host witness does not bracket the checked invocation')
    return {'capture_id': middle['capture_id'], 'pid': middle['pid'],
            'boot_session_uuid': host['boot_session_uuid'].lower()}


def verify_campaign_hosts(hosts: Any) -> None:
    require(isinstance(hosts, list) and len(hosts) == 16 and all(isinstance(item, dict) for item in hosts)
            and len({item.get('boot_session_uuid') for item in hosts}) == 1
            and all(isinstance(item.get('boot_session_uuid'), str) and item['boot_session_uuid'] for item in hosts),
            'package campaign must use one witnessed boot across all sixteen captures')


def _resource_comparison(reference: Any, native: Any, label: str) -> float:
    require(isinstance(reference, dict) and isinstance(native, dict), 'resource window is missing: ' + label)
    ref_cpu = reference.get('cpu', {}).get('per_matched_simulated_second_estimate')
    nat_cpu = native.get('cpu', {}).get('per_matched_simulated_second_estimate')
    ref_rss = reference.get('process_memory', {}).get('rss_bytes', {})
    nat_rss = native.get('process_memory', {}).get('rss_bytes', {})
    require(all(type(value) in (int, float) and math.isfinite(value) and value > 0
                for value in (ref_cpu, nat_cpu)) and nat_cpu <= ref_cpu * (1 + MAX_REGRESSION),
            'package CPU regression exceeds 5% or is unknown: ' + label)
    require(isinstance(ref_rss, dict) and isinstance(nat_rss, dict)
            and ref_rss.get('status') == 'ok' and nat_rss.get('status') == 'ok'
            and all(type(value) in (int, float) and math.isfinite(value) and value > 0
                    for value in (ref_rss.get('sampled_peak'), nat_rss.get('sampled_peak')))
            and nat_rss['sampled_peak'] <= ref_rss['sampled_peak'] * (1 + MAX_REGRESSION),
            'sampled package RSS regression exceeds 5% or is unknown: ' + label)
    return nat_cpu / ref_cpu


def _host_acceptable(value: Any) -> bool:
    if not isinstance(value, dict) or value.get('status') != 'complete':
        return False
    for name, expected in (('thermal', ['nominal']), ('low_power', [False]), ('power_source', ['ac'])):
        field = value.get(name)
        if not isinstance(field, dict) or field.get('status') != 'ok' or field.get('values') != expected \
                or any(type(actual) is not type(wanted) for actual, wanted in zip(field['values'], expected)):
            return False
    pressure = value.get('memory_pressure')
    if not isinstance(pressure, dict):
        return False
    for key in ('events', 'boundary_uncertain_events'):
        events = pressure.get(key)
        if not isinstance(events, list) or any(not isinstance(item, dict) or type(item.get('flags')) is not int
                                               or not 1 <= item['flags'] <= 7 or item['flags'] & 6 for item in events):
            return False
    # The existing helper cannot report the initial pressure level or OS event
    # coalescing. Absence of observed warnings is not proof of zero pressure.
    return True


def screened_selection(scenario: Any) -> dict[str, Any]:
    """Read the stock-domain result, preserving the actual start and branch facts."""
    require(isinstance(scenario, dict) and isinstance(scenario.get('screened_domain'), dict),
            'screened package-flight domain is missing')
    domain = scenario['screened_domain']
    require(set(domain) == {'selection', 'branches'} and isinstance(domain['selection'], dict)
            and isinstance(domain['branches'], dict), 'screened domain is malformed')
    selected, branches = domain['selection'], domain['branches']
    require(set(selected) == {'ok', 'reason', 'profile', 'aircraft', 'battery', 'start', 'weather', 'start_sha256'}
            and selected.get('ok') is True and selected.get('reason') == '' and selected.get('profile') == 'production'
            and selected.get('aircraft') == 'jensen-das-ugly-stik-60' and selected.get('battery') == 'ideal'
            and selected.get('start') == 'airborne' and selected.get('weather') == 'calm'
            and isinstance(selected.get('start_sha256'), str)
            and re.fullmatch(r'[0-9a-f]{64}', selected['start_sha256']) is not None,
            'flight is outside the fixed screened stock selection')
    boolean_fields = {'soft_hull', 'gear_retractable', 'wheel_brake', 'flaps', 'battery_dynamic', 'battery_pack',
                      'turbine_continuous', 'glow', 'liquid', 'weather_calm', 'weather_atmosphere',
                      'weather_spatial', 'weather_vertical'}
    string_fields = {'flap_mix_owner', 'shaft_integrator', 'wheel_layout', 'electric_law'}
    require(set(branches) == boolean_fields | string_fields | {'wheel_count'}
            and all(type(branches.get(key)) is bool for key in boolean_fields)
            and all(type(branches.get(key)) is str for key in string_fields)
            and type(branches.get('wheel_count')) is int and 0 <= branches['wheel_count'] <= 64
            and branches['soft_hull'] is True and branches['flap_mix_owner'] == 'simulator',
            'screened flight configuration branches are malformed or unsupported')
    return {'aircraft': selected['aircraft'], 'battery': selected['battery'], 'start': selected['start'],
            'weather': selected['weather'], 'soft_hull': branches['soft_hull'], 'trim_profile': selected['profile'],
            'start_sha256': selected['start_sha256']}


def verify_campaign_selection(items: list[dict[str, Any]], selection: dict[str, Any]) -> None:
    require(items and all(screened_selection(item.get('health', {}).get('scenario')) == selection for item in items),
            'package-flight screened start does not match the qualified fleet row')


def flight_evidence(item: dict[str, Any]) -> dict[str, str]:
    """Bind each revalidated raw flight attachment, not only the frame report."""
    summary = item.get('summary')
    fields = ('frame_report_sha256', 'frame_stream_sha256', 'health_sha256', 'checked_sha256', 'resource_sha256')
    require(isinstance(summary, dict) and isinstance(summary.get('capture_id'), str)
            and 0 < len(summary['capture_id']) <= 128
            and all(isinstance(summary.get(key), str) and re.fullmatch(r'[0-9a-f]{64}', summary[key]) is not None
                    for key in fields), 'package-flight evidence digest is missing or malformed')
    return {'capture_id': summary['capture_id'], **{key: summary[key] for key in fields}}


def compare_pair(reference: dict[str, Any], native: dict[str, Any], seen: set[str]) -> dict[str, Any]:
    """Join already revalidated raw summaries, health, frame and checked reports."""
    for role, item in (('gdscript_reference', reference), ('native', native)):
        summary, health, frame, checked = (item.get(key) for key in ('summary', 'health', 'frame', 'checked'))
        require(all(isinstance(value, dict) for value in (summary, health, frame, checked)), 'package run is incomplete')
        require(summary.get('collection_valid') is True and summary.get('promotion_eligible') is False
                and summary.get('route') == 'app-root-direct-flight-fixed-circuit'
                and summary.get('duration', {}).get('eligible') is True
                and summary.get('rendering', {}).get('eligible') is True
                and summary.get('pacing', {}).get('pass') is True
                and summary.get('drawable', {}).get('actual_1080p') is True
                and _host_acceptable(summary.get('resources', {}).get('host_state')),
                'package run lacks 1080p, complete host or software pacing evidence')
        require(health.get('backend_identity', {}).get('backend') == role
                and summary.get('scenario') == health.get('scenario')
                and summary.get('render_scope') == health.get('render_scope'), 'package role or scope differs')
        capture = summary.get('capture_id')
        require(isinstance(capture, str) and 0 < len(capture) <= 128 and capture not in seen
                and health.get('capture_id') == capture and frame.get('capture_id') == capture
                and checked.get('capture_id') == capture, 'capture is missing, substituted or reused')
        seen.add(capture)
        scenario = health.get('scenario', {})
        screened_selection(scenario)
        require(scenario.get('trim', {}).get('throttle') == 0.5
                and scenario.get('frame_generation_requested') is False
                and scenario.get('display_link_requested') is False
                and scenario.get('metalfx_trial_requested') is False, 'unexpected trim or graphics experiment')
        require(checked.get('complete') is True and checked.get('ok') is True
                and checked.get('reason') == 'passed' and checked.get('process_exit') == 0,
                'checked package invocation did not complete')
        _interval(checked)
        actual, warm = frame.get('actual_sample_s'), frame.get('actual_warmup_s')
        require(type(actual) in (int, float) and type(warm) in (int, float)
                and math.isfinite(actual) and math.isfinite(warm) and actual > 0 and warm >= 30
                and checked['elapsed_seconds'] + 0.001 >= actual + warm,
                'checked process cannot contain the reported warm-up and sample')

    ref_h, nat_h = reference['health'], native['health']
    require(reference['frame'].get('pid') != native['frame'].get('pid'), 'paired processes are not independent')
    ref_s, nat_s = ref_h['scenario'], nat_h['scenario']
    require(all(isinstance(value, str) and re.fullmatch(r'[0-9a-f]{64}', value) is not None for value in
                (ref_s.get('configuration'), nat_s.get('configuration'),
                 ref_s.get('screened_configuration_sha256'), nat_s.get('screened_configuration_sha256'),
                 ref_h.get('initial_checkpoint_sha256'), nat_h.get('initial_checkpoint_sha256'),
                 ref_h.get('initial_screened_checkpoint_sha256'),
                 nat_h.get('initial_screened_checkpoint_sha256'))),
            'actual or screened checkpoint identity is malformed')
    require({k: v for k, v in ref_s.items() if k not in ('arguments', 'configuration')} ==
            {k: v for k, v in nat_s.items() if k not in ('arguments', 'configuration')}
            and _arguments(ref_s, 'gdscript_reference') == _arguments(nat_s, 'native')
            and ref_h.get('initial_screened_checkpoint_sha256') ==
            nat_h.get('initial_screened_checkpoint_sha256')
            and ref_h.get('render_scope') == nat_h.get('render_scope'), 'reference/native flight scope differs')
    ref_ticks, nat_ticks = reference['frame'].get('measured_simulation'), native['frame'].get('measured_simulation')
    require(isinstance(ref_ticks, dict) and isinstance(nat_ticks, dict), 'measured simulation range is missing')
    bounds = [ref_ticks.get('start_tick'), ref_ticks.get('end_tick'), nat_ticks.get('start_tick'), nat_ticks.get('end_tick')]
    require(all(type(value) is int and value >= 0 for value in bounds), 'measured simulation range is malformed')
    lower, upper = max(bounds[0], bounds[2]), min(bounds[1], bounds[3])
    require(lower < upper, 'package measurements do not overlap')
    ref_points, nat_points = ref_h.get('checkpoints'), nat_h.get('checkpoints')
    require(isinstance(ref_points, list) and isinstance(nat_points, list), 'checkpoint windows are missing')
    native_windows = {(point['start_tick'], point['end_tick']): point for point in nat_points
                      if isinstance(point, dict) and point.get('partial') is False}
    matched = []
    for point in ref_points:
        if not isinstance(point, dict) or point.get('partial') is not False:
            continue
        first, last = point.get('start_tick'), point.get('end_tick')
        require(type(first) is int and type(last) is int and last - first + 1 == 6000,
                'reference checkpoint window is malformed')
        if first < lower or last > upper:
            continue
        other = native_windows.get((first, last))
        require(isinstance(other, dict) and isinstance(point.get('sha256'), str)
                and re.fullmatch(r'[0-9a-f]{64}', point['sha256']) is not None
                and other.get('sha256') == point['sha256'], 'measured state/input window differs or is missing')
        matched.append({'start_tick': first, 'end_tick': last, 'sha256': point['sha256']})
    require(bool(matched), 'no complete 6000-tick window is shared by both measurements')
    # Activation is sampled at each simulated second. Compare only common
    # measured ticks, preserving the actual values rather than inventing an
    # equivalent workload from endpoint configuration alone.
    def activations(health: dict[str, Any]) -> dict[int, Any]:
        rows = health.get('activation_samples')
        require(isinstance(rows, list), 'package activation samples are missing')
        selected = {}
        for row in rows:
            require(isinstance(row, dict) and type(row.get('tick')) is int
                    and isinstance(row.get('value'), dict), 'package activation sample is malformed')
            tick = row['tick']
            if lower <= tick <= upper:
                require(tick not in selected, 'package activation sample is duplicated')
                selected[tick] = row['value']
        return selected
    ref_activation, nat_activation = activations(ref_h), activations(nat_h)
    require(bool(ref_activation) and ref_activation == nat_activation,
            'matched package-flight activation histories differ or are missing')
    for key in ('p95', 'p99'):
        ref_value = reference['summary'].get('metrics', {}).get('frame_ms', {}).get(key)
        nat_value = native['summary'].get('metrics', {}).get('frame_ms', {}).get(key)
        require(all(type(value) in (int, float) and math.isfinite(value) and value > 0
                    for value in (ref_value, nat_value)) and nat_value <= ref_value * (1 + MAX_REGRESSION),
                'package frame-tail regression exceeds 5% or is unknown: ' + key)
    cpu_ratio = _resource_comparison(reference['summary'].get('resources'), native['summary'].get('resources'), 'full')
    ref_edges, nat_edges = reference['summary'].get('edge_windows'), native['summary'].get('edge_windows')
    if reference['summary'].get('duration', {}).get('minimum_sample_s') == 1800:
        require(isinstance(ref_edges, dict) and isinstance(nat_edges, dict)
                and ref_edges.get('status') == 'available' and nat_edges.get('status') == 'available',
                'long-run early/final resource windows are missing')
        for edge in ('early', 'final'):
            _resource_comparison(ref_edges.get(edge), nat_edges.get(edge), edge)
    ref_time, nat_time = _interval(reference['checked']), _interval(native['checked'])
    require(ref_time[1] <= nat_time[0] or nat_time[1] <= ref_time[0], 'paired processes overlap')
    frames = [reference['frame'].get('frames'), native['frame'].get('frames')]
    seconds = [reference['frame'].get('actual_sample_s'), native['frame'].get('actual_sample_s')]
    require(all(type(value) is int and value > 0 for value in frames)
            and all(type(value) in (int, float) and math.isfinite(value) and value > 0 for value in seconds),
            'callback-loop frame count or interval is unavailable')
    callback_ratio = (frames[1] / seconds[1]) / (frames[0] / seconds[0])
    return {'reference_capture': reference['summary']['capture_id'],
            'native_capture': native['summary']['capture_id'], 'windows': matched,
            'windows_sha256': canonical_sha(matched),
            'cpu_ratio': cpu_ratio, 'callback_fps_ratio': callback_ratio,
            'first_role': 'reference' if ref_time[0] < nat_time[0] else 'native',
            'first_start': min(ref_time[0], nat_time[0]), 'last_end': max(ref_time[1], nat_time[1])}


def compare_campaign(short_pairs: list[tuple[dict, dict]], long_pairs: list[tuple[dict, dict]]) -> dict[str, Any]:
    """Require the fixed independent alternating package-flight schedule."""
    require(len(short_pairs) == 5 and len(long_pairs) == 3, 'exactly five short and three long pairs are required')
    seen: set[str] = set()
    pids: set[int] = set()
    output: dict[str, Any] = {'short_pairs': [], 'long_pairs': [], 'benefit': {}}
    previous_end = None
    common_scope = None
    for name, pairs, minimum in (('short_pairs', short_pairs, 120), ('long_pairs', long_pairs, 1800)):
        previous_role = None
        ratios, frame_ratios = [], []
        for reference, native in pairs:
            for item in (reference, native):
                duration = item.get('summary', {}).get('duration', {})
                actual = item.get('frame', {}).get('actual_sample_s')
                require(type(duration.get('minimum_sample_s')) in (int, float)
                        and duration['minimum_sample_s'] >= minimum
                        and type(actual) in (int, float) and math.isfinite(actual) and actual >= minimum,
                        'package run does not meet its required actual duration')
                pid = item.get('frame', {}).get('pid')
                require(type(pid) is int and pid > 0 and pid not in pids, 'package process ID is missing or reused')
                pids.add(pid)
            result = compare_pair(reference, native, seen)
            ratios.append(result['cpu_ratio'])
            frame_ratios.append(result['callback_fps_ratio'])
            scenario = reference['health']['scenario']
            scope = {'scenario': {key: value for key, value in scenario.items() if key != 'arguments'},
                     'arguments': [arg for arg in _arguments(scenario, 'gdscript_reference') if not arg.startswith('--t=')],
                     'render_scope': reference['health']['render_scope'],
                     'initial_screened_checkpoint_sha256': reference['health']['initial_screened_checkpoint_sha256'],
                     'reference_checkpoint_sha256': reference['health']['initial_checkpoint_sha256'],
                     'native_checkpoint_sha256': native['health']['initial_checkpoint_sha256'],
                     'native_configuration': native['health']['scenario']['configuration'],
                     'reference_package': reference['health'].get('package_before'),
                     'native_package': native['health'].get('package_before')}
            require(common_scope is None or scope == common_scope, 'package campaign workload or package changed')
            common_scope = scope
            require(previous_role is None or result['first_role'] != previous_role,
                    'package pair order does not alternate')
            require(previous_end is None or result['first_start'] >= previous_end,
                    'independent package pairs overlap or are out of order')
            previous_role, previous_end = result['first_role'], result['last_end']
            reference_digest = reference['summary'].get('frame_report_sha256')
            native_digest = native['summary'].get('frame_report_sha256')
            require(all(isinstance(value, str) and re.fullmatch(r'[0-9a-f]{64}', value) for value in
                        (reference_digest, native_digest)), 'package frame-report hash is missing')
            output[name].append({'reference_sha256': reference_digest, 'native_sha256': native_digest,
                                 'reference_capture': result['reference_capture'],
                                 'native_capture': result['native_capture'], 'windows_sha256': result['windows_sha256']})
        cpu_median, frame_median = statistics.median(ratios), statistics.median(frame_ratios)
        passing = []
        if cpu_median <= 0.95:
            passing.append('whole_process_cpu_per_accepted_simulated_second')
        if frame_median >= 1.05:
            passing.append('callback_loop_fps')
        require(bool(passing), 'package campaign lacks a 5% median CPU or callback-loop benefit: ' + name)
        output['benefit'][name] = {'passing_metrics': passing, 'native_over_reference_cpu': cpu_median,
                                   'native_over_reference_callback_fps': frame_median,
                                   'scope': 'sampled process CPU and process-loop callbacks; not displayed FPS or GPU completion'}
    return output


def load_module(name: str, path: Path) -> Any:
    spec = importlib.util.spec_from_file_location(name, path)
    require(spec is not None and spec.loader is not None, 'cannot load required validator: ' + str(path))
    result = importlib.util.module_from_spec(spec)
    sys.path.insert(0, str(path.parent))
    try:
        spec.loader.exec_module(result)
    finally:
        sys.path.pop(0)
    return result


def verify_checked_case(report: Any, log: bytes, command: list[str], markers: list[str]) -> None:
    require(isinstance(report, dict) and report.get('format') == 'openrc-godot-check v1'
            and report.get('complete') is True and report.get('ok') is True
            and report.get('reason') == 'passed' and report.get('process_exit') == 0
            and report.get('command') == command and report.get('log_sha256') == hashlib.sha256(log).hexdigest()
            and report.get('counts') == {'error': 0, 'warning': 0}, 'packaged functional check failed')
    lines = log.decode('utf-8', errors='strict').splitlines()
    require(all(lines.count(marker) == 1 for marker in markers), 'packaged functional check lacks its exact markers')
    require(not re.search(rb'ObjectDB instances leaked|resources? still in use|Leaked instance', log, re.I),
            'packaged functional check reported retained objects or resources')


def validate_package_checks(config: Any, executable: Path, reference: dict[str, Any], native: dict[str, Any],
                            baseline: Any, probe: Any, checked_tool: Any) -> dict[str, Any]:
    """Read the five real checked package invocations and their session reports."""
    names = ('stage', 'lifecycle', 'replay', 'session_reference', 'session_native')
    require(isinstance(config, dict) and set(config) == set(names), 'five packaged checks are required')
    reports: dict[str, Any] = {}
    evidence: dict[str, Any] = {}
    seen_captures: set[str] = set()
    for name in names:
        entry = config[name]
        is_session = name.startswith('session_')
        expected_fields = {'checked', 'output'} if is_session else {'checked'}
        require(isinstance(entry, dict) and set(entry) == expected_fields, 'packaged check entry is malformed: ' + name)
        paths = {key: Path(value) for key, value in entry.items() if isinstance(value, str)}
        require(set(paths) == expected_fields, 'packaged check paths are malformed: ' + name)
        for path in paths.values():
            probe.no_links(path)
        checked_path = paths['checked']
        require(checked_path.name == 'report.json', 'packaged check must cite its original checked report')
        checked_data = probe.read_regular(checked_path)
        checked = probe.object_from(checked_data)
        log_path = checked_path.with_name('engine.log')
        probe.no_links(log_path)
        log = probe.read_regular(log_path, 16 * 1024 * 1024)
        require(checked.get('report') == str(checked_path) and checked.get('log') == str(log_path),
                'packaged check paths differ from their actual hierarchy')
        mode = 'session' if is_session else name
        command = [str(executable), '--headless', '--audio-driver', 'Dummy', '--', '--quick-flight',
                   '--native-qualification=' + mode]
        markers = ['NATIVE_QUALIFICATION preloaded=false', 'NATIVE_QUALIFICATION mode=' + mode + ' verdict=pass']
        if is_session:
            role = 'gdscript_reference' if name == 'session_reference' else 'native'
            command += ['--output=' + str(paths['output']), '--aircraft=jensen-das-ugly-stik-60', '--case=trim',
                        '--warmup-ticks=24', '--sample-ticks=240', '--observer=on', '--physics-backend=' + role,
                        '--experimental-native-macos=true', '--battery=ideal', '--trim-profile=production']
            output_data = probe.read_regular(paths['output'], 16 * 1024 * 1024)
            payload = probe.object_from(output_data)
            errors = baseline.validate_probe_report(payload, expected={
                'aircraft_id': 'jensen-das-ugly-stik-60', 'case_id': 'trim', 'observer': True,
                'requested': {'warmup_ticks': 24, 'sample_ticks': 240}, 'physics_backend': role,
                'battery': 'ideal', 'trim_profile': 'production'})
            require(not errors and payload.get('complete') is True and payload.get('template_release') is True,
                    'packaged short session is incomplete or out of scope: ' + name)
            reports[role] = payload
        else:
            command += ['--experimental-native-macos=true']
            markers.insert(1, {'stage': 'NK3_NATIVE_STAGE_NATIVE verdict=pass',
                               'lifecycle': 'NK3_NATIVE_SESSION_NATIVE verdict=pass',
                               'replay': 'NK3_NATIVE_REPLAY_NATIVE verdict=pass'}[name])
        verify_checked_case(checked, log, command, markers)
        scanned = checked_tool.inspect_log(log_path, markers)
        require(scanned.get('counts') == {'error': 0, 'warning': 0} and not scanned.get('missing_required_text'),
                'packaged check log has diagnostics')
        capture = checked.get('capture_id')
        require(isinstance(capture, str) and capture and capture not in seen_captures,
                'packaged check invocation is missing or reused')
        seen_captures.add(capture)
        item = {'checked_sha256': hashlib.sha256(checked_data).hexdigest(),
                'log_sha256': hashlib.sha256(log).hexdigest(), 'capture_id': capture}
        if is_session:
            require(probe.read_regular(paths['output'], 16 * 1024 * 1024) == output_data,
                    'packaged session output changed while checking')
            item['output_sha256'] = hashlib.sha256(output_data).hexdigest()
        require(probe.read_regular(checked_path) == checked_data and probe.read_regular(log_path, 16 * 1024 * 1024) == log,
                'packaged functional evidence changed while checking')
        evidence[name] = item
    paired = baseline.reduce_backend_pair(reports.get('gdscript_reference'), reports.get('native'),
                                           mac_reference_identity=reference, mac_native_identity=native)
    require(isinstance(paired, dict) and paired.get('comparable') is True,
            'packaged reference/native session fingerprints or identities differ')
    evidence['session_pair_sha256'] = canonical_sha(paired)
    return evidence


def _read_flight(path: Path, minimum: int, pins: dict[str, Any], summary: Any, probe: Any,
                 executable: Path, reference: dict[str, Any], native: dict[str, Any],
                 expected_host: dict[str, Any], package_identity: dict[str, Any]) -> dict[str, Any]:
    probe.no_links(path)
    reduced = summary.reduce_run(path, pins, minimum_seconds=minimum)
    data = {}
    for key, file_path, bound in (
            ('frame', path, summary.native.MAX_REPORT_BYTES),
            ('health', path.with_name('health-' + path.name), summary.MAX_HEALTH_BYTES),
            ('checked', path.with_name('checked-' + path.name), summary.native.MAX_BENCHMARK_CHECK_BYTES)):
        probe.no_links(file_path)
        raw = probe.read_regular(file_path, bound)
        require(hashlib.sha256(raw).hexdigest() == reduced[key + '_sha256' if key != 'frame' else 'frame_report_sha256'],
                'package-flight ' + key + ' differs from the strict reader')
        data[key] = probe.object_from(raw)
    data['summary'] = reduced
    require(isinstance(data['checked'].get('command'), list) and data['checked']['command']
            and data['checked']['command'][0] == str(executable), 'package flight did not run the selected executable')
    role = data['health'].get('backend_identity', {}).get('backend')
    before = data['health'].get('package_before')
    if role == 'native':
        stage = data['health'].get('backend_identity')
        require(isinstance(stage, dict) and all(stage.get(key) == package_identity.get(key)
                for key in ('binary_sha256', 'source_sha256', 'lock_sha256')),
                'native flight did not use the verified installed stage')
        require(isinstance(before, dict) and before.get('ok') is True and all(before.get(key) == native.get(key) for key in
                ('kind', 'sha256', 'receipt_sha256', 'reference_receipt_sha256', 'manifest_sha256',
                 'library_sha256', 'descriptor_sha256')) and isinstance(before.get('reference_identity'), dict),
                'native flight package identity differs')
        before = before['reference_identity']
    require(isinstance(before, dict) and before.get('ok') is True and all(before.get(key) == reference.get(key) for key in
            ('kind', 'sha256', 'receipt_sha256', 'executable_sha256', 'pack_sha256', 'probe_sha256', 'architecture')),
            'reference flight package identity differs')
    def version(value: Any) -> tuple[int, int, int]:
        require(isinstance(value, str) and re.fullmatch(r'\d+(?:\.\d+){0,2}', value) is not None,
                'flight or preflight OS version is malformed')
        parts = [int(part) for part in value.split('.')]
        return tuple((parts + [0, 0])[:3])
    require(version(data['frame'].get('os_version')) == version(expected_host.get('os_product_version')),
            'package-flight operating system differs from the qualified host')
    witness_path = path.with_name('host-witness.json')
    probe.no_links(witness_path)
    witness_bytes = probe.read_regular(witness_path)
    witness = verify_host_witness(probe.object_from(witness_bytes), data['frame'], data['checked'],
                                  reduced['checked_sha256'], expected_host)
    require(probe.read_regular(witness_path) == witness_bytes, 'package host witness changed during verification')
    witness['sha256'] = hashlib.sha256(witness_bytes).hexdigest()
    data['host_witness'] = witness
    return data


def _current_host(source: Any) -> dict[str, Any]:
    def sw_vers(flag: str) -> str:
        return subprocess.run(['/usr/bin/sw_vers', flag], check=True, capture_output=True, text=True, timeout=10).stdout.strip()
    memory = source._sysctl('hw.memsize')
    require(memory.isascii() and memory.isdigit() and 0 < int(memory) < 2**60, 'current host memory is unavailable')
    return {'model': source._sysctl('hw.model'), 'cpu_brand': source._sysctl('machdep.cpu.brand_string'),
            'memory_bytes': int(memory), 'boot_session_uuid': source._sysctl('kern.bootsessionuuid'),
            'os_product_version': sw_vers('-productVersion'), 'os_build_version': sw_vers('-buildVersion')}


def _ci_snapshot(watch: Any, commit: str, run_id: int) -> dict[str, str]:
    from types import SimpleNamespace
    require(type(run_id) is int and run_id > 0, 'CI run ID must be a positive integer')
    deadline = time.monotonic() + 120
    endpoint = f'repos/{REPOSITORY}/actions/runs/{run_id}'
    try:
        before = watch.request(watch.gh_json, endpoint, deadline, time.monotonic)
        jobs = watch.read_jobs(SimpleNamespace(repository=REPOSITORY, run_id=run_id), watch.gh_json,
                               deadline, time.monotonic)
        after = watch.request(watch.gh_json, endpoint, deadline, time.monotonic)
    except (watch.TransportError, TimeoutError) as error:
        raise AdmissionError('live CI evidence is unavailable') from error
    return verify_ci_records(before, jobs, after, commit, run_id)


def _input_path(value: Any, probe: Any, *, directory: bool = False) -> Path:
    require(isinstance(value, str) and value, 'an absolute input path is required')
    path = Path(value)
    probe.no_links(path)
    require(path.is_dir() if directory else path.is_file(), 'input path has the wrong type: ' + str(path))
    return path


def _source_git(root: Path, *arguments: str) -> bytes:
    # Do not let inherited Git selectors or global ignore rules hide changes.
    env = {key: value for key, value in os.environ.items() if not key.startswith('GIT_')}
    env.update(GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL=os.devnull, GIT_TERMINAL_PROMPT='0')
    return subprocess.run(['git', '--no-optional-locks', '-c', 'core.fsmonitor=false',
                           '-c', 'core.untrackedCache=false', '-C', str(root), *arguments],
                          env=env, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60).stdout


def _source_status(root: Path) -> bytes:
    """Refuse hidden tracked changes and all nonignored untracked files."""
    top = Path(os.fsdecode(_source_git(root, 'rev-parse', '--show-toplevel').strip())).resolve()
    require(root.resolve() == top, 'source path is not the Git worktree root')
    require(not _source_git(root, 'for-each-ref', '--format=%(refname)', 'refs/replace/'),
            'source has Git replacement refs')
    flags = _source_git(root, 'ls-files', '-v', '-z')
    require(all(entry.startswith(b'H ') for entry in flags.split(b'\0') if entry),
            'source uses assume-unchanged, skip-worktree or unresolved index entries')
    status = _source_git(root, 'status', '--porcelain=v1', '-z', '--untracked-files=all')
    require(status in (b'', b' M app/export_presets.cfg\0'),
            'source contains another tracked change, staged file or untracked file')
    return status


def _require_git_environment(environment: Any) -> None:
    require(not any(key.startswith('GIT_') for key in environment),
            'inherited Git overrides would change the source identity')


def verify_source_configuration(root: Path, snapshot: Any, reference: Any, release: Any, probe: Any) -> dict[str, Any]:
    """Allow only the exact paired Mac preset in the actual receipt-bound worktree."""
    require(isinstance(snapshot, dict) and isinstance(snapshot.get('commit'), str)
            and re.fullmatch(r'[0-9a-f]{40}', snapshot['commit'])
            and isinstance(snapshot.get('tree'), str) and re.fullmatch(r'[0-9a-f]{40}', snapshot['tree'])
            and isinstance(snapshot.get('worktree_sha256'), str)
            and re.fullmatch(r'[0-9a-f]{64}', snapshot['worktree_sha256'])
            and type(snapshot.get('dirty')) is bool and isinstance(reference, dict), 'source snapshot is malformed')
    commit, tree = snapshot['commit'], snapshot['tree']
    require(reference.get('source_commit') == commit and reference.get('source_tree') == tree
            and reference.get('source_worktree_sha256') == snapshot['worktree_sha256'],
            'source snapshot differs from the package receipt')
    require(_source_git(root, 'rev-parse', '--verify', 'HEAD').strip().decode('ascii') == commit
            and _source_git(root, 'rev-parse', '--verify', 'HEAD^{tree}').strip().decode('ascii') == tree,
            'source HEAD or tree differs from the captured receipt')
    status = _source_status(root)
    if not status:
        require(snapshot['dirty'] is False, 'clean checkout does not match captured source')
        return {'kind': 'clean'}
    require(snapshot['dirty'] is True, 'changed preset does not match captured source')
    require(isinstance(release, dict) and isinstance(release.get('selection'), dict)
            and isinstance(release['selection'].get('pair'), dict) and isinstance(release.get('package'), dict)
            and isinstance(release['package'].get('engine_pair'), dict), 'verified package pair is unavailable')
    template = _input_path(release['selection']['pair'].get('export_template'), probe)
    expected_template = release['package']['engine_pair'].get('export_template_sha256')
    require(isinstance(expected_template, str) and re.fullmatch(r'[0-9a-f]{64}', expected_template),
            'paired export template digest is invalid')
    template_bytes = probe.read_regular(template, 512 * 1024 * 1024)
    require(hashlib.sha256(template_bytes).hexdigest() == expected_template,
            'selected export template differs from the verified pair')
    original = _source_git(root, 'show', commit + ':app/export_presets.cfg')
    require(0 < len(original) <= 2 * 1024 * 1024 and b'\r' not in original,
            'committed export preset is not bounded LF text')
    text = original.decode('utf-8')
    require(text.count('[preset.2.options]') == 1, 'committed Mac preset is missing or duplicated')
    prefix, options = text.split('[preset.2.options]', 1)
    require('[preset.3]' not in options, 'unexpected later preset in committed source')
    overrides = {'binary_format/architecture': 'arm64', 'custom_template/release': str(template),
                 'application/bundle_identifier': 'org.openrc.research.metalfx.native26production'}
    for key, value in overrides.items():
        pattern = r'(?m)^' + re.escape(key) + '=.*$'
        matches = list(re.finditer(pattern, options))
        require(len(matches) <= 1, 'duplicate committed Mac preset key: ' + key)
        line = key + '=' + json.dumps(value)
        options = re.sub(pattern, lambda _: line, options) if matches else options + '\n' + line + '\n'
    expected = (prefix + '[preset.2.options]' + options).encode('utf-8')
    preset = root / 'app/export_presets.cfg'
    probe.no_links(preset)
    actual = probe.read_regular(preset, 2 * 1024 * 1024)
    require(actual == expected, 'local export preset differs from the three declared Mac overrides')
    require(_source_status(root) == status
            and _source_git(root, 'rev-parse', '--verify', 'HEAD').strip().decode('ascii') == commit
            and _source_git(root, 'rev-parse', '--verify', 'HEAD^{tree}').strip().decode('ascii') == tree
            and probe.read_regular(preset, 2 * 1024 * 1024) == actual
            and hashlib.sha256(probe.read_regular(template, 512 * 1024 * 1024)).hexdigest() == expected_template,
            'source preset or paired export template changed while checking')
    return {'kind': 'paired-mac-local-export-preset', 'preset_sha256': hashlib.sha256(actual).hexdigest(),
            'committed_preset_sha256': hashlib.sha256(original).hexdigest(),
            'export_template': str(template), 'export_template_sha256': expected_template,
            'bundle_identifier': overrides['application/bundle_identifier']}


def _pair_paths(value: Any, count: int, probe: Any) -> list[tuple[Path, Path]]:
    require(isinstance(value, list) and len(value) == count, 'incorrect number of package flight pairs')
    result = []
    for row in value:
        require(isinstance(row, list) and len(row) == 2, 'package pair must identify reference and native reports')
        result.append((_input_path(row[0], probe), _input_path(row[1], probe)))
    return result


def _package_identity(reference: dict[str, Any], native: dict[str, Any], row: dict[str, Any]) -> dict[str, Any]:
    require(isinstance(row.get('mirrored_sources'), dict), 'native receipt has no mirrored-source roster')
    identity = {
        'kind': native.get('kind'), 'native_identity_sha256': native.get('sha256'),
        'native_receipt_sha256': native.get('receipt_sha256'), 'reference_identity_sha256': reference.get('sha256'),
        'reference_receipt_sha256': reference.get('receipt_sha256'), 'executable_sha256': reference.get('executable_sha256'),
        'pack_sha256': reference.get('pack_sha256'), 'manifest_sha256': native.get('manifest_sha256'),
        'descriptor_sha256': native.get('descriptor_sha256'), 'binary_sha256': row.get('binary_sha256'),
        'source_sha256': row.get('source_sha256'), 'lock_sha256': row.get('lock_sha256'),
        'engine_sha256': row.get('engine_sha256'),
        'domain_sha256': row['mirrored_sources'].get('app/sim/native_macos_domain.gd')}
    require(identity['kind'] == 'macos-arm64-native-bundle-v1'
            and all(isinstance(value, str) and re.fullmatch(r'[0-9a-f]{64}', value) is not None
                    for key, value in identity.items() if key != 'kind')
            and native.get('reference_receipt_sha256') == reference.get('receipt_sha256')
            and native.get('library_sha256') == row.get('binary_sha256'), 'package identity is incomplete or inconsistent')
    return identity


def prepare(inputs_path: Path) -> tuple[bytes, dict[str, Any]]:
    """Reread all raw inputs and produce bytes, without writing a marker."""
    require(sys.platform == 'darwin' and not sys.flags.optimize, 'package promotion requires unoptimized macOS Python')
    # Check before importing repository modules so an untracked package cannot
    # be selected as a normal project helper on a dirty checkout.
    _require_git_environment(os.environ)
    _source_status(ROOT)
    if str(ROOT) not in sys.path:
        sys.path.insert(0, str(ROOT))
    from tools.testqueue.common import require_exclusive
    require_exclusive('headless')
    probe = load_module('openrc_package_home_probe', HERE / 'macos_package_default_probe.py')
    source = load_module('openrc_package_source_promotion', HERE / 'macos_promotion.py')
    fleet = source.module('openrc_package_fleet', HERE / 'fleet_campaign.py')
    package = source.module('openrc_package_validator', HERE / 'package.py')
    baseline = source.module('openrc_package_session_baseline', ROOT / 'research/performance/session_baseline.py')
    summary = source.module('openrc_package_flight_summary', ROOT / 'research/performance/package_flight_summary.py')
    checked_tool = source.module('openrc_package_checked_runner', ROOT / 'tools/godot/run_checked.py')
    watch = source.module('openrc_package_ci_watch', ROOT / 'tools/release/watch.py')
    probe.no_links(inputs_path)
    input_data = probe.read_regular(inputs_path)
    config = probe.object_from(input_data)
    fields = {'format', 'project', 'godot', 'tool_root', 'qualification_root', 'native_toolchain_profile',
              'engine_selection', 'release_selection', 'executable', 'preflight', 'fleet_campaign',
              'package_checks', 'short_pairs', 'long_pairs', 'ci_run_id'}
    require(set(config) == fields and config.get('format') == 'openrc-package-default-inputs v1',
            'package promotion inputs are incomplete or unknown')
    project = _input_path(config['project'], probe, directory=True)
    godot = _input_path(config['godot'], probe)
    tool_root = _input_path(config['tool_root'], probe, directory=True)
    qualification_root = _input_path(config['qualification_root'], probe, directory=True)
    selection_path = _input_path(config['engine_selection'], probe)
    release_selection = _input_path(config['release_selection'], probe)
    executable = _input_path(config['executable'], probe)
    preflight_path = _input_path(config['preflight'], probe)
    campaign_path = _input_path(config['fleet_campaign'], probe)
    engine_data = probe.read_regular(selection_path)
    engine = probe.object_from(engine_data)
    profile = config['native_toolchain_profile']
    require(isinstance(profile, str) and profile in source.ENGINE_POLICY.TOOLCHAIN_PROFILES,
            'native toolchain profile is missing or unknown')
    context = {'project': str(project), 'godot': str(godot), 'tool_root': str(tool_root),
               'qualification_root': str(qualification_root), 'trim_profile': 'production', 'research_engine': engine}
    if profile != source.ENGINE_POLICY.DEFAULT_TOOLCHAIN_PROFILE:
        context['toolchain_profile'] = profile
    short_paths, long_paths = _pair_paths(config['short_pairs'], 5, probe), _pair_paths(config['long_pairs'], 3, probe)
    install = package.verified_mac_install(qualification_root, godot, engine, profile)
    guard = fleet.snapshot(context)
    canonical_receipt = ROOT / 'app/native/kernel/build-receipt-macos.json'
    probe.no_links(canonical_receipt)
    require(install.get('platforms', {}).get('macos') == guard.get('receipt')
            and source.sha(canonical_receipt) == guard.get('receipt_sha256'),
            'fleet is not bound to the currently verified native installation')
    preflight, preflight_sha = source.read_json(preflight_path)
    source.validate_preflight(preflight, guard)
    preflight_host = preflight['host']
    expected_host = {'model': preflight_host.get('model_identifier'), 'cpu_brand': preflight_host.get('cpu'),
                     'memory_bytes': preflight_host.get('memory_bytes'), 'os_product_version': preflight_host.get('os_version'),
                     'os_build_version': preflight_host.get('os_build')}
    current_host = _current_host(source)
    require(type(expected_host['memory_bytes']) is int and expected_host['memory_bytes'] > 0
            and all(current_host.get(key) == value and type(current_host.get(key)) is type(value)
                    for key, value in expected_host.items())
            and isinstance(current_host.get('boot_session_uuid'), str)
            and re.fullmatch(r'[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}',
                             current_host['boot_session_uuid']) is not None,
            'current host does not match the M1 preflight')
    selected_rows, fleet_proof = source.validate_fleet(fleet, campaign_path, context, guard)
    row = guard['receipt']
    release = baseline.verify_research_release(executable, engine, release_selection, 30)
    reference, native = release['reference'], release['native']
    package_manifest, manifest_sha = source.read_json(package.MAC_MANIFEST)
    require(manifest_sha == native.get('manifest_sha256') and package_manifest.get('native_receipt') == install
            and package_manifest.get('engine_pair') == release['package'].get('engine_pair'),
            'final signed package does not contain the verified installation and engine pair')
    identity = _package_identity(reference, native, row)
    source_snapshot = baseline.capture_mac_release_source(ROOT)
    require(baseline.mac_release_source_matches(reference, source_snapshot),
            'current source differs from the final release receipt')
    source_configuration = verify_source_configuration(ROOT, source_snapshot, reference, release, probe)
    require(baseline.capture_mac_release_source(ROOT) == source_snapshot,
            'source changed while validating the local build configuration')
    probe._signature(probe._load_receipt_module().bundle_from_executable(executable))
    ci_id = config.get('ci_run_id')
    ci = _ci_snapshot(watch, source_snapshot['commit'], ci_id)
    checks = validate_package_checks(config['package_checks'], executable, reference, native, baseline, probe, checked_tool)
    pins = {'format': 'openrc-package-live-pins v1',
            'reference_receipt_sha256': reference['receipt_sha256'], 'executable_sha256': reference['executable_sha256'],
            'pack_sha256': reference['pack_sha256'], 'native_receipt_sha256': native['receipt_sha256']}

    selection = probe.chosen_selection({'format': 'openrc-macos-native-package-default v2',
                                        'scope': 'package-macos-arm64', 'allowed_selections': selected_rows})

    def read_campaign() -> tuple[dict[str, Any], list[Any], list[Any]]:
        loaded = []
        for minimum, paths in ((120, short_paths), (1800, long_paths)):
            loaded.append([(_read_flight(a, minimum, pins, summary, probe, executable, reference, native, expected_host, identity),
                            _read_flight(b, minimum, pins, summary, probe, executable, reference, native, expected_host, identity)) for a, b in paths])
        items = [item for group in loaded for pair in group for item in pair]
        verify_campaign_selection(items, selection)
        hosts = [item['host_witness'] for item in items]
        verify_campaign_hosts(hosts)
        return compare_campaign(*loaded), hosts, [flight_evidence(item) for item in items]

    pairs, host_witnesses, flight_evidence_rows = read_campaign()
    final_rows, final_fleet = source.validate_fleet(fleet, campaign_path, context, guard)
    final_pairs, final_hosts, final_flights = read_campaign()
    _require_git_environment(os.environ)
    require(final_rows == selected_rows and final_fleet == fleet_proof and final_pairs == pairs
            and final_hosts == host_witnesses and final_flights == flight_evidence_rows and _current_host(source) == current_host
            and fleet.snapshot(context) == guard
            and package.verified_mac_install(qualification_root, godot, engine, profile) == install
            and baseline.verify_research_release(executable, engine, release_selection, 30) == release
            and baseline.capture_mac_release_source(ROOT) == source_snapshot
            and verify_source_configuration(ROOT, source_snapshot, reference, release, probe) == source_configuration
            and source.sha(preflight_path) == preflight_sha and source.sha(canonical_receipt) == guard['receipt_sha256']
            and probe.read_regular(selection_path) == engine_data and probe.read_regular(inputs_path) == input_data
            and validate_package_checks(config['package_checks'], executable, reference, native, baseline, probe, checked_tool) == checks
            and _ci_snapshot(watch, source_snapshot['commit'], ci_id) == ci,
            'package qualification inputs changed during verification')
    source.validate_preflight(preflight, guard)
    probe._signature(probe._load_receipt_module().bundle_from_executable(executable))
    marker = {'format': 'openrc-macos-native-package-default v2', 'scope': 'package-macos-arm64',
              'package_identity': identity, 'engine_pair': package_manifest['engine_pair'],
              'cpu': source.CPU, 'hardware_model': source.MODEL,
              'os_version': row['runtime_os_version'], 'os_build': row['runtime_os_build'],
              'allowed_selections': [selection],
              'evidence': {'format': 'openrc-macos-native-package-evidence v1',
                           'source_fleet_sha256': fleet_proof['campaign_sha256'],
                           'package_release_sha256': canonical_sha(release),
                           'package_session_sha256': canonical_sha({'checks': checks, 'host_witnesses': host_witnesses,
                                                                    'flight_evidence': flight_evidence_rows}), 'ci': ci,
                           'short_pairs': pairs['short_pairs'], 'long_pairs': pairs['long_pairs']}}
    data = (json.dumps(marker, sort_keys=True, indent=2, allow_nan=False) + '\n').encode('utf-8')
    receipt = {'format': 'openrc-package-default-preparation v1', 'status': 'candidate-only',
               'candidate_sha256': hashlib.sha256(data).hexdigest(), 'inputs_sha256': hashlib.sha256(input_data).hexdigest(),
               'source': source_snapshot, 'source_configuration': source_configuration,
               'fleet': fleet_proof, 'package_release_sha256': canonical_sha(release),
               'package_checks': checks, 'host_witnesses': host_witnesses, 'flight_evidence': flight_evidence_rows,
               'validation_host': current_host,
               'ci': ci, 'pairs': pairs, 'selection': selection,
               'scope': 'CPU native backend only; completed GPU pacing, physical radio and presentation are unqualified'}
    return data, receipt


def _private_output(path: Path, probe: Any) -> None:
    require(path.is_absolute() and path == Path(os.path.normpath(path)), 'output path must be absolute and normalized')
    private = ROOT / 'tmp'
    probe.no_links(private)
    require(path.is_relative_to(private) and path != private, 'evidence output must be inside this checkout tmp/')
    probe.no_links(path.parent)
    require(not path.exists() and not path.is_symlink(), 'output already exists or is redirected: ' + str(path))


def _atomic_publish(target: Path, data: bytes, probe: Any) -> None:
    """Publish a completed receipt exclusively; a reader never sees a partial marker."""
    probe.no_links(target.parent)
    require(not target.exists() and not target.is_symlink(), 'canonical marker already exists or is redirected')
    descriptor, staged_name = tempfile.mkstemp(prefix='.' + target.name + '.staged-', dir=target.parent)
    staged = Path(staged_name)
    try:
        with os.fdopen(descriptor, 'wb') as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        require(probe.read_regular(staged) == data, 'staged marker changed before publication')
        os.link(staged, target, follow_symlinks=False)  # exclusive and atomic on the same filesystem
        require(not target.is_symlink() and probe.read_regular(target) == data, 'published marker differs')
    finally:
        staged.unlink(missing_ok=True)  # this exact temporary was created above


def publish_with_receipt(target: Path, data: bytes, receipt_path: Path, result: dict[str, Any], probe: Any) -> None:
    """Keep the reviewed evidence durably before making the marker visible."""
    require(result.get('status') == 'verified_for_publication', 'publication receipt has the wrong state')
    receipt_data = (json.dumps(result, sort_keys=True, indent=2, allow_nan=False) + '\n').encode()
    probe.write_new(receipt_path, receipt_data)
    require(probe.read_regular(receipt_path) == receipt_data, 'publication evidence changed before marker creation')
    _atomic_publish(target, data, probe)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='action', required=True)
    stage = commands.add_parser('prepare', help='validate all non-Home evidence and stage a private candidate')
    stage.add_argument('--inputs', required=True, type=Path)
    stage.add_argument('--candidate', required=True, type=Path)
    stage.add_argument('--receipt', required=True, type=Path)
    final = commands.add_parser('finalize', help='revalidate, check the four raw Home cases, and publish exclusively')
    final.add_argument('--inputs', required=True, type=Path)
    final.add_argument('--candidate', required=True, type=Path)
    final.add_argument('--home-proof', required=True, type=Path)
    final.add_argument('--receipt', required=True, type=Path)
    args = parser.parse_args()
    try:
        probe = load_module('openrc_package_home_output', HERE / 'macos_package_default_probe.py')
        _private_output(args.receipt, probe)
        if args.action == 'prepare':
            _private_output(args.candidate, probe)
        else:
            probe.no_links(args.candidate)
            require(args.candidate.is_relative_to(ROOT / 'tmp'), 'candidate must be a private staged marker')
        data, preparation = prepare(args.inputs)
        if args.action == 'prepare':
            probe.write_new(args.candidate, data)
            probe.write_new(args.receipt, (json.dumps(preparation, sort_keys=True, indent=2, allow_nan=False) + '\n').encode())
            print(json.dumps({'status': 'candidate-only', 'candidate': str(args.candidate),
                              'sha256': hashlib.sha256(data).hexdigest(), 'receipt': str(args.receipt)}))
            return 0
        require(probe.read_regular(args.candidate) == data, 'staged candidate no longer matches all current inputs')
        config = probe.object_from(probe.read_regular(args.inputs))
        executable = _input_path(config.get('executable'), probe)
        home = probe.verify_home_proof(args.home_proof, executable, args.candidate, hashlib.sha256(data).hexdigest())
        # Home verification can take long enough for separately retained fleet,
        # CI or campaign files to change. Re-run the original validators, then
        # reread the raw Home cases immediately before publication.
        final_data, final_preparation = prepare(args.inputs)
        require(final_data == data and final_preparation == preparation,
                'qualification changed while checking the Home cases')
        require(probe.verify_home_proof(args.home_proof, executable, args.candidate,
                                        hashlib.sha256(data).hexdigest()) == home,
                'Home proof changed while rechecking the qualification')
        receipts = probe._load_receipt_module()
        bundle = receipts.bundle_from_executable(executable)
        probe._signature(bundle)
        require(probe.read_regular(args.candidate) == data, 'candidate changed before publication')
        target = bundle.with_name(bundle.name + '.openrc-native-default')
        result = {'format': 'openrc-package-default-publication v1', 'status': 'verified_for_publication',
                  'candidate_sha256': hashlib.sha256(data).hexdigest(), 'marker': str(target),
                  'home_proof': home, 'preparation': preparation,
                  'scope': 'CPU backend artifact consistency only; GPU pacing, physical radio and presentation remain unqualified'}
        publish_with_receipt(target, data, args.receipt, result, probe)
        print(json.dumps({'status': 'published', 'marker': str(target),
                          'sha256': hashlib.sha256(data).hexdigest(), 'receipt': str(args.receipt)}))
        return 0
    except (OSError, ValueError, TypeError, KeyError, OverflowError, RecursionError, subprocess.SubprocessError) as error:
        print('package default promotion refused: ' + str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
