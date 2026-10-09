#!/usr/bin/env python3
"""Verify weather trace v4 using independent scalar wind and quaternion equations."""
import argparse
import csv
import json
import math
from pathlib import Path

from check_trimmed_flight import COLUMNS

WEATHER_COLUMNS = ['wind_north_mps', 'wind_east_mps', 'wind_down_mps', 'tas_mps',
                   'ground_horizontal_mps', 'loads_t_s', 'loads_wind_north_mps',
                   'loads_wind_east_mps', 'loads_wind_down_mps', 'loads_tas_mps']


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


def check(path, duration=None):
    metadata = {}
    lines = Path(path).read_text().splitlines()
    for line in lines:
        if line.startswith('# '):
            key, separator, value = line[2:].partition(': ')
            if not separator or key in metadata:
                raise ValueError('malformed or duplicate metadata')
            metadata[key] = value
    if metadata.get('format') != 'openrc-trace v4' or metadata.get('metadata_schema') != 'openrc-flight-meta v3':
        raise ValueError('expected weather trace v4 / metadata v3')
    if metadata.get('weather_model') != 'uniform-ned-repeating-cosine-v1':
        raise ValueError('unsupported weather model')
    config = json.loads(metadata['weather_config'])
    keys = {'format', 'speed_mps', 'from_deg', 'gust_mps', 'gust_up_mps', 'gust_duration_s', 'gust_period_s', 'gust_delay_s'}
    if set(config) != keys or config['format'] != 'openrc-weather v1':
        raise ValueError('unsupported weather configuration')
    bounds = {'speed_mps': (0, 15), 'from_deg': (0, 360), 'gust_mps': (0, 8),
              'gust_up_mps': (-8, 8), 'gust_duration_s': (.5, 20), 'gust_period_s': (.5, 120), 'gust_delay_s': (0, 3600)}
    for key, (low, high) in bounds.items():
        value = config[key]
        if type(value) not in (int, float) or not math.isfinite(value) or not low <= value <= high:
            raise ValueError('invalid weather value ' + key)
    if config['gust_period_s'] < config['gust_duration_s']:
        raise ValueError('overlapping pulse configuration')
    dt = float(metadata['dt_s'])
    if not math.isfinite(dt) or dt <= 0:
        raise ValueError('invalid timestep')
    reader = csv.DictReader(line for line in lines if line and not line.startswith('#'))
    if reader.fieldnames != COLUMNS + WEATHER_COLUMNS:
        raise ValueError('weather trace columns mismatch')
    raw_rows = list(reader)
    if len(raw_rows) < 2:
        raise ValueError('incomplete trace: need at least two samples')
    previous = json.loads(metadata['recording_start_previous_state'])
    if not isinstance(previous, list) or len(previous) != 13 or any(type(v) not in (int, float) or not math.isfinite(v) for v in previous):
        raise ValueError('invalid recording-start previous state')
    if abs(sum(v*v for v in previous[6:10])-1) > 1e-8:
        raise ValueError('invalid previous quaternion')
    previous_tick = None
    maximum_wind_error = maximum_speed_error = 0.0
    for raw in raw_rows:
        if set(raw) != set(reader.fieldnames) or any(value is None for value in raw.values()):
            raise ValueError('malformed row width')
        row = {key: float(value) for key, value in raw.items()}
        if not all(math.isfinite(v) for v in row.values()):
            raise ValueError('nonfinite trace sample')
        tick = row['tick']
        if tick < 0 or tick != int(tick) or (previous_tick is not None and tick != previous_tick+1):
            raise ValueError('noncontinuous ticks')
        if previous_tick is None and tick != int(metadata['recording_start_tick']):
            raise ValueError('recording origin mismatch')
        if abs(row['t_s']-tick*dt) > 1e-8 or abs(row['loads_t_s']-max(0, tick-1)*dt) > 1e-8:
            raise ValueError('state/load clock mismatch')
        q = [row[key] for key in ('qw', 'qx', 'qy', 'qz')]
        if abs(sum(v*v for v in q)-1) > 1e-8:
            raise ValueError('invalid quaternion')
        rotation = matrix(q)
        velocity = [row[key] for key in ('u_mps', 'v_mps', 'w_mps')]
        current_wind = wind(config, tick*dt)
        force_wind = wind(config, max(0, tick-1)*dt)
        for expected, prefix in ((current_wind, ''), (force_wind, 'loads_')):
            for axis, value in zip(('north', 'east', 'down'), expected):
                error = abs(value-row[prefix+'wind_'+axis+'_mps'])
                maximum_wind_error = max(maximum_wind_error, error)
                if error > 1e-8:
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
    return {'rows': len(raw_rows), 'first_tick': int(raw_rows[0]['tick']), 'last_tick': previous_tick,
            'max_wind_error_mps': maximum_wind_error, 'max_speed_error_mps': maximum_speed_error}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('trace', type=Path)
    parser.add_argument('--duration', type=float)
    args = parser.parse_args()
    print(json.dumps(check(args.trace, args.duration), indent=2))
