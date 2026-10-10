#!/usr/bin/env python3
"""Verify weather traces v4/v5 using independent scalar wind, OU, and quaternion equations."""
import argparse
import csv
import json
import math
from pathlib import Path
import re

from check_trimmed_flight import COLUMNS

WEATHER_COLUMNS = ['wind_north_mps', 'wind_east_mps', 'wind_down_mps', 'tas_mps',
                   'ground_horizontal_mps', 'loads_t_s', 'loads_wind_north_mps',
                   'loads_wind_east_mps', 'loads_wind_down_mps', 'loads_tas_mps']
TURBULENCE_COLUMNS = ['turbulence_north_mps', 'turbulence_east_mps', 'turbulence_down_mps',
                      'loads_turbulence_north_mps', 'loads_turbulence_east_mps', 'loads_turbulence_down_mps']
TURBULENCE_MODEL = 'uniform-ned-cosine-plus-temporal-ou-pcg32-normal53-v1'
PCG_MULTIPLIER = 6364136223846793005
PCG_DEFAULT_SEQUENCE = 1442695040888963407
MASK32 = (1 << 32) - 1
MASK64 = (1 << 64) - 1
PCG_STREAM_INCREMENT = ((PCG_DEFAULT_SEQUENCE << 1) | 1) & MASK64
MAX_OPEN_UNIFORM = 0.9999999999999999


def matrix(q):
    w, x, y, z = q
    return ((1-2*(y*y+z*z), 2*(x*y-w*z), 2*(x*z+w*y)),
            (2*(x*y+w*z), 1-2*(x*x+z*z), 2*(y*z-w*x)),
            (2*(x*z-w*y), 2*(y*z+w*x), 1-2*(x*x+y*y)))


def wind(config, t):
    angle = math.radians(config['from_deg'])
    unit = (-math.cos(angle), -math.sin(angle), 0.0)
    phase = (t-config['gust_delay_s']) % config['gust_period_s']
    gain = 0.0
    if t >= config['gust_delay_s'] and 0 < phase < config['gust_duration_s']:
        gain = (1-math.cos(2*math.pi*phase/config['gust_duration_s']))/2
    return (unit[0]*(config['speed_mps']+gain*config['gust_mps']),
            unit[1]*(config['speed_mps']+gain*config['gust_mps']), -gain*config['gust_up_mps'])


def airspeed(velocity, rotation, air):
    relative = [velocity[j]-sum(rotation[i][j]*air[i] for i in range(3)) for j in range(3)]
    return math.sqrt(sum(v*v for v in relative))


def _number(value, label, lower, upper):
    if type(value) not in (int, float):
        raise ValueError('invalid weather value ' + label)
    try:
        number = float(value)
    except OverflowError as error:
        raise ValueError('invalid weather value ' + label) from error
    if not math.isfinite(number) or not lower <= number <= upper:
        raise ValueError('invalid weather value ' + label)
    return number


def _finite_number(value):
    if type(value) not in (int, float):
        return False
    try:
        return math.isfinite(float(value))
    except OverflowError:
        return False


def _weather_config(raw, trace_version):
    try:
        config = json.loads(raw)
    except (TypeError, json.JSONDecodeError) as error:
        raise ValueError('invalid weather_config JSON') from error
    if type(config) is not dict:
        raise ValueError('weather_config must be an object')
    base = {'format', 'speed_mps', 'from_deg', 'gust_mps', 'gust_up_mps',
            'gust_duration_s', 'gust_period_s', 'gust_delay_s'}
    version = config.get('format')
    turbulent = version == 'openrc-weather v2'
    expected_keys = base | ({'turbulence_rms_mps', 'turbulence_tau_s', 'turbulence_seed'} if turbulent else set())
    if version not in ('openrc-weather v1', 'openrc-weather v2') or set(config) != expected_keys:
        raise ValueError('unsupported weather configuration')
    if trace_version == 5 and not turbulent:
        raise ValueError('weather trace v5 requires weather config v2')

    bounds = {'speed_mps': (0, 15), 'from_deg': (0, 360), 'gust_mps': (0, 8),
              'gust_up_mps': (-8, 8), 'gust_duration_s': (.5, 20),
              'gust_period_s': (.5, 120), 'gust_delay_s': (0, 3600)}
    for key, (low, high) in bounds.items():
        _number(config[key], key, low, high)
    if config['gust_period_s'] < config['gust_duration_s']:
        raise ValueError('overlapping pulse configuration')

    if turbulent:
        sigma = config['turbulence_rms_mps']
        if type(sigma) is not list or len(sigma) != 3:
            raise ValueError('turbulence_rms_mps must have three NED components')
        config['turbulence_rms_mps'] = tuple(
            _number(value, f'turbulence_rms_mps[{axis}]', 0, 3) for axis, value in enumerate(sigma))
        config['turbulence_tau_s'] = _number(config['turbulence_tau_s'], 'turbulence_tau_s', .2, 30)
        seed = config['turbulence_seed']
        if type(seed) is not int or not 0 <= seed <= MASK32:
            raise ValueError('invalid turbulence_seed')
    else:
        config['turbulence_rms_mps'] = (0.0, 0.0, 0.0)
        config['turbulence_tau_s'] = 2.0
        config['turbulence_seed'] = 20261009

    has_turbulence = any(value > 0.0 for value in config['turbulence_rms_mps'])
    if trace_version == 5 and not has_turbulence:
        raise ValueError('v5 trace requires at least one nonzero turbulence RMS component')
    if trace_version == 4 and has_turbulence:
        raise ValueError('weather v2 with nonzero turbulence requires trace v5')
    return config


def _signed_integer(raw, label, lower, upper):
    if type(raw) is not str or not re.fullmatch(r'-?(0|[1-9][0-9]*)', raw):
        raise ValueError('invalid ' + label)
    value = int(raw)
    if not lower <= value <= upper or str(value) != raw:
        raise ValueError('out-of-range ' + label)
    return value


def _pcg32(state):
    """Return one Godot 4.7.2 raw PCG32 word and its next unsigned 64-bit state."""
    old_state = state & MASK64
    next_state = (old_state * PCG_MULTIPLIER + PCG_STREAM_INCREMENT) & MASK64
    xorshifted = (((old_state >> 18) ^ old_state) >> 27) & MASK32
    rotation = old_state >> 59
    output = ((xorshifted >> rotation) | (xorshifted << ((-rotation) & 31))) & MASK32
    return output, next_state


def _uniform53(state):
    high_word, state = _pcg32(state)
    low_word, state = _pcg32(state)
    mantissa = (high_word >> 5) * (1 << 26) + (low_word >> 6)
    value = (float(mantissa) + 0.5) / (1 << 53)
    if value >= 1.0:
        value = MAX_OPEN_UNIFORM
    if value <= 0.0 or not math.isfinite(value):
        raise ValueError('PCG uniform outside open unit interval')
    return value, state


def _normal_pair(state):
    u1, state = _uniform53(state)
    u2, state = _uniform53(state)
    radius = math.sqrt(-2.0 * math.log(u1))
    angle = 2.0 * math.pi * u2
    return (radius * math.cos(angle), radius * math.sin(angle)), state


def _seeded_pcg_state(seed):
    """Reproduce RandomNumberGenerator.seed initialization before any distribution draws."""
    state = 0
    _, state = _pcg32(state)
    state = (state + seed) & MASK64
    _, state = _pcg32(state)
    return state


def _active_normals(sigma, state):
    normals = [0.0, 0.0, 0.0]
    pair = (0.0, 0.0)
    pair_index = 2
    for axis in range(3):
        if sigma[axis] == 0.0:
            continue
        if pair_index >= 2:
            pair, state = _normal_pair(state)
            pair_index = 0
        normals[axis] = pair[pair_index]
        pair_index += 1
    return normals, state


def _ou_step(previous, sigma, tau, dt, rng_state):
    normals, rng_state = _active_normals(sigma, rng_state)
    decay = math.exp(-dt / tau)
    innovation_gain = math.sqrt(max(0.0, 1.0 - decay * decay))
    values = [decay * previous[axis] + sigma[axis] * innovation_gain * normals[axis] for axis in range(3)]
    if not all(math.isfinite(value) for value in values):
        raise ValueError('OU recurrence produced a nonfinite sample')
    return values, rng_state


def _interpolate_window(window, time_s, dt):
    interval_start = window[6]
    fraction = min(1.0, max(0.0, (time_s - interval_start) / dt))
    return tuple(window[axis] + fraction * (window[axis + 3] - window[axis]) for axis in range(3))


def _start_turbulence(metadata, config, dt, first_tick):
    if metadata.get('turbulence_interval') != 'linear interpolation between exact OU tick samples; wall time tau; independent NED axes':
        raise ValueError('unsupported turbulence interval contract')
    index = _signed_integer(metadata.get('turbulence_aux_index'), 'turbulence_aux_index', 4, 1_000_000)
    rng_state = _signed_integer(metadata.get('recording_start_rng_state'), 'recording_start_rng_state', -(1 << 63), (1 << 63) - 1)
    try:
        window = json.loads(metadata['recording_start_turbulence'])
    except (KeyError, json.JSONDecodeError) as error:
        raise ValueError('invalid recording_start_turbulence') from error
    if type(window) is not list or len(window) != 7 or any(not _finite_number(value) for value in window):
        raise ValueError('recording_start_turbulence must be seven finite numbers')
    window = tuple(float(value) for value in window)
    expected_start = max(0, first_tick - 1) * dt
    cadence_tolerance = max(1e-9, abs(expected_start) * 2e-12)
    if abs(window[6] - expected_start) > cadence_tolerance:
        raise ValueError('recording-start turbulence interval is off cadence')
    for axis, sigma in enumerate(config['turbulence_rms_mps']):
        if sigma == 0.0 and (window[axis] != 0.0 or window[axis + 3] != 0.0):
            raise ValueError('zero-RMS turbulence axis is nonzero at recording start')
    if first_tick == 0:
        if window[6] != 0.0 or window[:3] != window[3:6]:
            raise ValueError('tick-zero turbulence must be a stationary initial sample')
        normals, expected_state = _active_normals(
            config['turbulence_rms_mps'], _seeded_pcg_state(config['turbulence_seed']))
        expected_initial = [sigma * normal for sigma, normal in zip(config['turbulence_rms_mps'], normals)]
        signed_expected_state = expected_state if expected_state < (1 << 63) else expected_state - (1 << 64)
        if rng_state != signed_expected_state:
            raise ValueError('tick-zero raw RNG state does not follow the seeded initial draw')
        if any(abs(window[axis] - expected_initial[axis]) > 1e-12 for axis in range(3)):
            raise ValueError('tick-zero turbulence does not match the stationary seeded initial draw')
    return index, window, rng_state


def check(path, duration=None):
    metadata = {}
    lines = Path(path).read_text().splitlines()
    for line in lines:
        if line.startswith('# '):
            key, separator, value = line[2:].partition(': ')
            if not separator or key in metadata:
                raise ValueError('malformed or duplicate metadata')
            metadata[key] = value
    trace_format = metadata.get('format')
    if trace_format == 'openrc-trace v4':
        trace_version = 4
        expected_schema = 'openrc-flight-meta v3'
        expected_model = 'uniform-ned-repeating-cosine-v1'
    elif trace_format == 'openrc-trace v5':
        trace_version = 5
        expected_schema = 'openrc-flight-meta v4'
        expected_model = TURBULENCE_MODEL
    else:
        raise ValueError('expected weather trace v4 or v5')
    if metadata.get('metadata_schema') != expected_schema or metadata.get('weather_model') != expected_model:
        raise ValueError('weather trace metadata schema/model mismatch')
    if 'weather_config' not in metadata:
        raise ValueError('missing weather_config')
    config = _weather_config(metadata['weather_config'], trace_version)
    try:
        dt = float(metadata['dt_s'])
        first_tick = _signed_integer(metadata['recording_start_tick'], 'recording_start_tick', 0, (1 << 63) - 1)
    except (KeyError, TypeError, ValueError) as error:
        raise ValueError('missing/invalid trace clock metadata') from error
    if not math.isfinite(dt) or not 0 < dt <= 1:
        raise ValueError('invalid trace clock')
    if metadata.get('weather_timing') != 'wind/TAS at row state time; loads_* wind and loads_t_s describe k1 (tick-1, current aux); reset uses t=0':
        raise ValueError('unsupported weather timing contract')
    if metadata.get('weather_evidence') != 'user-selected/authored practice conditions; not measured meteorology':
        raise ValueError('unsupported weather evidence contract')

    expected_columns = COLUMNS + WEATHER_COLUMNS + (TURBULENCE_COLUMNS if trace_version == 5 else [])
    reader = csv.DictReader(line for line in lines if line and not line.startswith('#'))
    if reader.fieldnames != expected_columns:
        raise ValueError('weather trace columns mismatch')
    raw_rows = list(reader)
    if len(raw_rows) < 2:
        raise ValueError('incomplete trace: need at least two samples')
    try:
        previous = json.loads(metadata['recording_start_previous_state'])
    except (KeyError, json.JSONDecodeError) as error:
        raise ValueError('invalid recording-start previous state JSON') from error
    if type(previous) is not list or len(previous) != 13 or any(not _finite_number(v) for v in previous):
        raise ValueError('invalid recording-start previous state')
    if abs(sum(v*v for v in previous[6:10])-1) > 1e-8:
        raise ValueError('invalid previous quaternion')

    turbulence_index = -1
    turbulence_window = None
    rng_state = None
    if trace_version == 5:
        turbulence_index, turbulence_window, rng_state = _start_turbulence(metadata, config, dt, first_tick)

    previous_tick = None
    maximum_wind_error = maximum_speed_error = maximum_turbulence_error = 0.0
    turbulence_end = turbulence_window[3:6] if turbulence_window is not None else None
    sigma = config['turbulence_rms_mps']
    for raw in raw_rows:
        if set(raw) != set(reader.fieldnames) or any(value is None for value in raw.values()):
            raise ValueError('malformed row width')
        try:
            row = {key: float(value) for key, value in raw.items()}
        except (TypeError, ValueError) as error:
            raise ValueError('non-numeric trace sample') from error
        if not all(math.isfinite(v) for v in row.values()):
            raise ValueError('nonfinite trace sample')
        tick = row['tick']
        if tick < 0 or tick > (1 << 53) - 1 or tick != int(tick) or (previous_tick is not None and tick != previous_tick+1):
            raise ValueError('noncontinuous ticks')
        if previous_tick is None and tick != first_tick:
            raise ValueError('recording origin mismatch')
        load_time = max(0, int(tick)-1) * dt
        if abs(row['t_s']-tick*dt) > 1e-8 or abs(row['loads_t_s']-load_time) > 1e-8:
            raise ValueError('state/load clock mismatch')
        q = [row[key] for key in ('qw', 'qx', 'qy', 'qz')]
        if abs(sum(v*v for v in q)-1) > 1e-8:
            raise ValueError('invalid quaternion')
        rotation = matrix(q)
        velocity = [row[key] for key in ('u_mps', 'v_mps', 'w_mps')]

        if trace_version == 5:
            if previous_tick is None:
                current_turbulence = _interpolate_window(turbulence_window, tick * dt, dt)
                load_turbulence = _interpolate_window(turbulence_window, load_time, dt)
            else:
                current_turbulence, rng_state = _ou_step(turbulence_end, sigma,
                    config['turbulence_tau_s'], dt, rng_state)
                load_turbulence = turbulence_end
            turbulence_end = current_turbulence
            for axis, value in enumerate(current_turbulence):
                error = abs(value-row[TURBULENCE_COLUMNS[axis]])
                maximum_turbulence_error = max(maximum_turbulence_error, error)
                if error > 2e-8:
                    raise ValueError('current OU sample/state mismatch')
            for axis, value in enumerate(load_turbulence):
                error = abs(value-row[TURBULENCE_COLUMNS[axis + 3]])
                maximum_turbulence_error = max(maximum_turbulence_error, error)
                if error > 2e-8:
                    raise ValueError('force-time OU sample/cadence mismatch')
            for axis, component_sigma in enumerate(sigma):
                if component_sigma == 0.0 and (
                    row[TURBULENCE_COLUMNS[axis]] != 0.0
                    or row[TURBULENCE_COLUMNS[axis + 3]] != 0.0
                ):
                    raise ValueError('zero-RMS turbulence component must remain exactly zero')
            if previous_tick is None and first_tick == 0:
                initial_state = [row[key] for key in (
                    'north_m', 'east_m', 'down_m', 'u_mps', 'v_mps', 'w_mps',
                    'qw', 'qx', 'qy', 'qz', 'p_radps', 'q_radps', 'r_radps')]
                if any(abs(actual - expected) > 1e-8 for actual, expected in zip(previous, initial_state)):
                    raise ValueError('tick-zero recording-start previous state disagrees with the initial row')
        else:
            current_turbulence = (0.0, 0.0, 0.0)
            load_turbulence = (0.0, 0.0, 0.0)

        current_base = wind(config, tick*dt)
        force_base = wind(config, load_time)
        current_wind = tuple(current_base[axis] + current_turbulence[axis] for axis in range(3))
        force_wind = tuple(force_base[axis] + load_turbulence[axis] for axis in range(3))
        for expected, prefix in ((current_wind, ''), (force_wind, 'loads_')):
            for axis, value in zip(('north', 'east', 'down'), expected):
                error = abs(value-row[prefix+'wind_'+axis+'_mps'])
                maximum_wind_error = max(maximum_wind_error, error)
                if error > 2e-8:
                    raise ValueError('wind/time mismatch')

        world = [sum(rotation[i][j]*velocity[j] for j in range(3)) for i in range(3)]
        expectations = {'tas_mps': airspeed(velocity, rotation, current_wind),
                        'ground_horizontal_mps': math.hypot(world[0], world[1]),
                        'speed_mps': math.sqrt(sum(v*v for v in velocity)),
                        'loads_tas_mps': airspeed(previous[3:6], matrix(previous[6:10]), force_wind)}
        for key, value in expectations.items():
            error = abs(value-row[key])
            maximum_speed_error = max(maximum_speed_error, error)
            if error > 1e-6:
                raise ValueError('velocity definition mismatch: '+key)
        previous = [row[key] for key in ('north_m', 'east_m', 'down_m', 'u_mps', 'v_mps', 'w_mps', 'qw', 'qx', 'qy', 'qz', 'p_radps', 'q_radps', 'r_radps')]
        previous_tick = int(tick)
    if duration is not None:
        if not math.isfinite(duration) or duration <= 0:
            raise ValueError('invalid requested duration')
        if abs(float(raw_rows[-1]['t_s'])-float(raw_rows[0]['t_s'])-duration) > 1e-8:
            raise ValueError('requested duration not completed')
    result = {'rows': len(raw_rows), 'first_tick': int(raw_rows[0]['tick']), 'last_tick': previous_tick,
              'max_wind_error_mps': maximum_wind_error, 'max_speed_error_mps': maximum_speed_error}
    if trace_version == 5:
        result['max_turbulence_error_mps'] = maximum_turbulence_error
        result['turbulence_aux_index'] = turbulence_index
        result['recording_start_rng_state'] = _signed_integer(metadata['recording_start_rng_state'], 'recording_start_rng_state', -(1 << 63), (1 << 63) - 1)
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('trace', type=Path)
    parser.add_argument('--duration', type=float)
    args = parser.parse_args()
    print(json.dumps(check(args.trace, args.duration), indent=2))
