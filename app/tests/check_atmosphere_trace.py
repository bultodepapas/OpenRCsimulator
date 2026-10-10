#!/usr/bin/env python3
"""Independently validate atmospheric fields in custom-atmosphere trace v6."""
import argparse
import csv
import io
import json
import math
from pathlib import Path
import tempfile

from check_trimmed_flight import COLUMNS
from check_wind_trace import TURBULENCE_COLUMNS, TURBULENCE_MODEL, WEATHER_COLUMNS, check as check_wind
from check_trimmed_flight import check_coupled_metadata

FORMAT = 'openrc-trace v6'
METADATA_SCHEMA = 'openrc-flight-meta v5'
ATMOSPHERE_MODEL = 'uniform-field-qnh-isa-buck-liquid-v1'
COSINE_MODEL = 'uniform-ned-repeating-cosine-v1'
ATMOSPHERIC_COLUMNS = [
    'rho_kgm3', 'density_ratio', 'equivalent_airspeed_mps', 'density_altitude_m',
    'pressure_pa', 'temperature_k', 'engine_charge_ratio',
]
BASE_WEATHER_KEYS = {
    'format', 'speed_mps', 'from_deg', 'gust_mps', 'gust_up_mps',
    'gust_duration_s', 'gust_period_s', 'gust_delay_s',
}
TURBULENCE_KEYS = {'turbulence_rms_mps', 'turbulence_tau_s', 'turbulence_seed'}
ATMOSPHERE_KEYS = {
    'atmosphere_mode', 'field_elevation_m', 'temperature_c', 'qnh_hpa', 'relative_humidity_pct',
}
WEATHER_V3_KEYS = BASE_WEATHER_KEYS | TURBULENCE_KEYS | ATMOSPHERE_KEYS
WEATHER_TIMING = 'wind/TAS at row state time; loads_* wind and loads_t_s describe k1 (tick-1, current aux); reset uses t=0'
WEATHER_EVIDENCE = 'user-selected/authored practice conditions; not measured meteorology'
ATMOSPHERE_SCOPE = 'uniform field density per flight; geometric field elevation; liquid-water RH; fixed gravity; not a vertical sounding'
ENGINE_ATMOSPHERE = 'shaft: dry-air indicated torque, fixed friction; rpm-lag: prescribed rpm; turbine: existing density-scaled map (experimental)'

# The constants and equations mirror the documented model, not the GDScript implementation.
SEA_LEVEL_PRESSURE_PA = 101325.0
SEA_LEVEL_TEMPERATURE_K = 288.15
SEA_LEVEL_DENSITY_KGM3 = 1.225
STANDARD_GRAVITY_MPS2 = 9.80665
TROPOSPHERE_LAPSE_KPM = 0.0065
DRY_AIR_GAS_CONSTANT_J_KG_K = 287.05287
WATER_VAPOR_GAS_CONSTANT_J_KG_K = 461.523329
EARTH_EFFECTIVE_RADIUS_M = 6356766.0
MIN_CONFIG = {
    'speed_mps': 0.0, 'from_deg': 0.0, 'gust_mps': 0.0, 'gust_up_mps': -8.0,
    'gust_duration_s': 0.5, 'gust_period_s': 0.5, 'gust_delay_s': 0.0,
    'field_elevation_m': -500.0, 'temperature_c': -20.0,
    'qnh_hpa': 870.0, 'relative_humidity_pct': 0.0,
}
MAX_CONFIG = {
    'speed_mps': 15.0, 'from_deg': 360.0, 'gust_mps': 8.0, 'gust_up_mps': 8.0,
    'gust_duration_s': 20.0, 'gust_period_s': 120.0, 'gust_delay_s': 3600.0,
    'field_elevation_m': 4000.0, 'temperature_c': 45.0,
    'qnh_hpa': 1085.0, 'relative_humidity_pct': 100.0,
}
STATE_KEYS = {
    'ok', 'errors', 'pressure_pa', 'temperature_k', 'vapor_pressure_pa', 'rho_kgm3',
    'dry_air_density_kgm3', 'sigma', 'engine_charge_ratio', 'density_altitude_m',
}
def _finite_number(value):
    if type(value) not in (int, float):
        return False
    try:
        return math.isfinite(float(value))
    except OverflowError:
        return False


def _number(value, label, minimum, maximum):
    if not _finite_number(value):
        raise ValueError('invalid weather value ' + label)
    number = float(value)
    if not minimum <= number <= maximum:
        raise ValueError('weather value outside range: ' + label)
    return number


def _unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('duplicate JSON key: ' + key)
        result[key] = value
    return result


def _reject_json_constant(value):
    raise ValueError('nonfinite JSON constant: ' + value)


def _load_json(raw):
    return json.loads(raw, object_pairs_hook=_unique_object, parse_constant=_reject_json_constant)


def _validate_weather_config(raw):
    try:
        config = _load_json(raw)
    except (TypeError, json.JSONDecodeError) as error:
        raise ValueError('invalid weather_config JSON') from error
    if type(config) is not dict or set(config) != WEATHER_V3_KEYS:
        raise ValueError('weather_config v3 must have the exact sixteen-key schema')
    if config.get('format') != 'openrc-weather v3':
        raise ValueError('trace v6 requires openrc-weather v3')
    for key in BASE_WEATHER_KEYS - {'format'}:
        _number(config[key], key, MIN_CONFIG[key], MAX_CONFIG[key])
    if config['from_deg'] == 360.0:
        raise ValueError('weather_config heading is not in canonical range')
    if config['gust_period_s'] < config['gust_duration_s']:
        raise ValueError('weather gust pulse overlaps the next period')
    rms = config['turbulence_rms_mps']
    if type(rms) is not list or len(rms) != 3:
        raise ValueError('turbulence_rms_mps must contain three NED components')
    for axis, value in enumerate(rms):
        _number(value, f'turbulence_rms_mps[{axis}]', 0.0, 3.0)
    _number(config['turbulence_tau_s'], 'turbulence_tau_s', 0.2, 30.0)
    seed = config['turbulence_seed']
    if type(seed) is not int or not 0 <= seed <= 0xFFFFFFFF:
        raise ValueError('invalid turbulence_seed')
    if config['atmosphere_mode'] != 'custom':
        raise ValueError('trace v6 cannot use reference atmosphere mode')
    for key in ('field_elevation_m', 'temperature_c', 'qnh_hpa', 'relative_humidity_pct'):
        _number(config[key], key, MIN_CONFIG[key], MAX_CONFIG[key])
    return config


def atmosphere_state(config):
    """Evaluate the custom field density using independent scalar ISA/Buck equations."""
    elevation = float(config['field_elevation_m'])
    temp_c = float(config['temperature_c'])
    qnh_hpa = float(config['qnh_hpa'])
    rh = float(config['relative_humidity_pct'])
    geopotential_m = EARTH_EFFECTIVE_RADIUS_M * elevation / (EARTH_EFFECTIVE_RADIUS_M + elevation)
    pressure_base = 1.0 - TROPOSPHERE_LAPSE_KPM * geopotential_m / SEA_LEVEL_TEMPERATURE_K
    if not math.isfinite(pressure_base) or pressure_base <= 0.0:
        raise ValueError('field elevation has invalid ISA pressure base')
    pressure_exponent = STANDARD_GRAVITY_MPS2 / (DRY_AIR_GAS_CONSTANT_J_KG_K * TROPOSPHERE_LAPSE_KPM)
    pressure_pa = qnh_hpa * 100.0 * pressure_base ** pressure_exponent
    temperature_k = temp_c + 273.15
    vapor_exponent = (18.678 - temp_c / 234.5) * temp_c / (257.14 + temp_c)
    saturation_vapor_pressure_pa = 611.21 * math.exp(vapor_exponent)
    vapor_pressure_pa = rh / 100.0 * saturation_vapor_pressure_pa
    if not math.isfinite(pressure_pa) or not math.isfinite(temperature_k) or pressure_pa <= vapor_pressure_pa:
        raise ValueError('derived pressure, temperature, or vapor pressure is invalid')
    dry_density = (pressure_pa - vapor_pressure_pa) / (DRY_AIR_GAS_CONSTANT_J_KG_K * temperature_k)
    vapor_density = vapor_pressure_pa / (WATER_VAPOR_GAS_CONSTANT_J_KG_K * temperature_k)
    density = dry_density + vapor_density
    sigma = density / SEA_LEVEL_DENSITY_KGM3
    charge_ratio = dry_density / SEA_LEVEL_DENSITY_KGM3
    sea_level_dry_density = SEA_LEVEL_PRESSURE_PA / (DRY_AIR_GAS_CONSTANT_J_KG_K * SEA_LEVEL_TEMPERATURE_K)
    density_exponent = STANDARD_GRAVITY_MPS2 / (DRY_AIR_GAS_CONSTANT_J_KG_K * TROPOSPHERE_LAPSE_KPM) - 1.0
    density_ratio = density / sea_level_dry_density
    if density_ratio <= 0.0 or density_exponent <= 0.0:
        raise ValueError('invalid density-altitude inversion input')
    da_geopotential_m = SEA_LEVEL_TEMPERATURE_K / TROPOSPHERE_LAPSE_KPM * (
        1.0 - density_ratio ** (1.0 / density_exponent))
    denominator = EARTH_EFFECTIVE_RADIUS_M - da_geopotential_m
    if denominator == 0.0:
        raise ValueError('invalid density-altitude geometric conversion')
    density_altitude_m = EARTH_EFFECTIVE_RADIUS_M * da_geopotential_m / denominator
    result = {
        'ok': True,
        'errors': [],
        'pressure_pa': pressure_pa,
        'temperature_k': temperature_k,
        'vapor_pressure_pa': vapor_pressure_pa,
        'rho_kgm3': density,
        'dry_air_density_kgm3': dry_density,
        'sigma': sigma,
        'engine_charge_ratio': charge_ratio,
        'density_altitude_m': density_altitude_m,
    }
    if any(not _finite_number(value) for key, value in result.items() if key not in ('ok', 'errors')):
        raise ValueError('atmosphere equation produced a nonfinite result')
    if density <= 0.0 or dry_density <= 0.0 or sigma <= 0.0 or charge_ratio <= 0.0:
        raise ValueError('atmosphere equation produced a nonpositive density')
    return result


def _close(actual, expected, absolute=1e-10, relative=1e-9):
    return _finite_number(actual) and abs(float(actual) - expected) <= absolute + relative * abs(expected)


def _json_metadata_value(metadata, key):
    raw = metadata.get(key)
    if not isinstance(raw, str):
        raise ValueError('missing ' + key)
    try:
        return _load_json(raw)
    except json.JSONDecodeError as error:
        raise ValueError('invalid ' + key + ' JSON') from error


def check(path, duration=None):
    lines = Path(path).read_text(encoding='utf-8').splitlines()
    metadata = {}
    data_lines = []
    for line in lines:
        if line.startswith('# '):
            key, separator, value = line[2:].partition(': ')
            if not separator or not key or key in metadata:
                raise ValueError('malformed or duplicate metadata')
            metadata[key] = value
        elif line.startswith('#'):
            raise ValueError('malformed trace comment')
        elif line:
            data_lines.append(line)
    if metadata.get('format') != FORMAT:
        raise ValueError('expected custom-atmosphere trace v6')
    if metadata.get('metadata_schema') != METADATA_SCHEMA:
        raise ValueError('trace v6 requires flight metadata v5')
    if metadata.get('atmosphere_model') != ATMOSPHERE_MODEL:
        raise ValueError('unsupported atmosphere_model')
    if metadata.get('atmosphere_scope') != ATMOSPHERE_SCOPE:
        raise ValueError('unsupported atmosphere scope')
    if metadata.get('engine_atmosphere') != ENGINE_ATMOSPHERE:
        raise ValueError('unsupported engine atmosphere contract')
    config = _validate_weather_config(metadata.get('weather_config'))
    expected_weather_model = TURBULENCE_MODEL if any(float(value) > 0.0 for value in config['turbulence_rms_mps']) else COSINE_MODEL
    if metadata.get('weather_model') != expected_weather_model:
        raise ValueError('weather_model disagrees with configured turbulence')
    expected_state = atmosphere_state(config)
    recorded_state = _json_metadata_value(metadata, 'atmosphere_state')
    if type(recorded_state) is not dict or set(recorded_state) != STATE_KEYS:
        raise ValueError('atmosphere_state is not the full kernel-state object')
    if recorded_state.get('ok') is not True or recorded_state.get('errors') != []:
        raise ValueError('atmosphere_state reports failure')
    max_state_error = 0.0
    for key in STATE_KEYS - {'ok', 'errors'}:
        actual = recorded_state.get(key)
        if not _finite_number(actual):
            raise ValueError('atmosphere_state has invalid ' + key)
        error = abs(float(actual) - expected_state[key])
        max_state_error = max(max_state_error, error)
        if not _close(actual, expected_state[key]):
            raise ValueError('atmosphere_state disagrees with independent equation: ' + key)

    try:
        dt = float(metadata['dt_s'])
        first_tick_text = metadata['recording_start_tick']
        first_tick = int(first_tick_text)
    except (KeyError, TypeError, ValueError) as error:
        raise ValueError('missing or invalid trace timing metadata') from error
    if not math.isfinite(dt) or not 0.0 < dt <= 1.0 or str(first_tick) != first_tick_text or first_tick < 0:
        raise ValueError('invalid trace clock or recording origin')
    check_coupled_metadata(metadata)
    expected_timing = ('wind/TAS at row state time; loads_* wind and loads_t_s describe k1 (tick-1 body/shaft, current sampled servos); reset uses t=0'
                       if metadata.get('shaft_integrator') == 'coupled-rk4' else WEATHER_TIMING)
    if metadata.get('weather_timing') != expected_timing or metadata.get('weather_evidence') != WEATHER_EVIDENCE:
        raise ValueError('unsupported weather timing/evidence metadata')
    if not data_lines:
        raise ValueError('trace has no CSV header or samples')
    reader = csv.DictReader(data_lines)
    fieldnames = reader.fieldnames
    has_turbulence = expected_weather_model == TURBULENCE_MODEL
    expected_columns = COLUMNS + WEATHER_COLUMNS + (TURBULENCE_COLUMNS if has_turbulence else []) + ATMOSPHERIC_COLUMNS
    if fieldnames != expected_columns or len(set(fieldnames or [])) != len(expected_columns):
        raise ValueError('trace v6 columns/order mismatch')
    rows = list(reader)
    if len(rows) < 2:
        raise ValueError('incomplete trace: need an initial sample and a flight tick')

    static_keys = [key for key in ATMOSPHERIC_COLUMNS if key != 'equivalent_airspeed_mps']
    max_rho_rounding_error = 0.0
    max_eas_error = 0.0
    previous_tick = None
    for raw in rows:
        if set(raw) != set(expected_columns) or any(value is None for value in raw.values()):
            raise ValueError('malformed CSV row width')
        try:
            row = {key: float(value) for key, value in raw.items()}
        except (TypeError, ValueError) as error:
            raise ValueError('nonnumeric trace sample') from error
        if not all(math.isfinite(value) for value in row.values()):
            raise ValueError('nonfinite trace sample')
        tick = row['tick']
        if tick < 0 or tick > (1 << 53) - 1 or tick != int(tick):
            raise ValueError('invalid trace tick')
        if previous_tick is None and int(tick) != first_tick:
            raise ValueError('recording origin mismatch')
        if previous_tick is not None and tick != previous_tick + 1:
            raise ValueError('noncontinuous ticks')
        if abs(row['t_s'] - tick * dt) > 1e-8:
            raise ValueError('state clock mismatch')
        for key in static_keys:
            expected = expected_state[{
                'rho_kgm3': 'rho_kgm3', 'density_ratio': 'sigma', 'density_altitude_m': 'density_altitude_m',
                'pressure_pa': 'pressure_pa', 'temperature_k': 'temperature_k',
                'engine_charge_ratio': 'engine_charge_ratio',
            }[key]]
            error = abs(row[key] - expected)
            max_rho_rounding_error = max(max_rho_rounding_error, error)
            if error > 2e-9:
                raise ValueError('row atmosphere field disagrees with header/config: ' + key)
        expected_eas = row['tas_mps'] * math.sqrt(expected_state['sigma'])
        eas_error = abs(row['equivalent_airspeed_mps'] - expected_eas)
        max_eas_error = max(max_eas_error, eas_error)
        if eas_error > 1e-6:
            raise ValueError('equivalent_airspeed_mps disagrees with TAS and density ratio')
        previous_tick = int(tick)

    if int(float(rows[0]['tick'])) != first_tick:
        raise ValueError('recording origin mismatch')
    if 'recording_start_previous_state' not in metadata:
        raise ValueError('missing previous body state needed for wind validation')
    projection = _project_weather_trace(metadata, config, expected_columns, rows, has_turbulence)
    with tempfile.TemporaryDirectory(prefix='openrc-atmos-v6-wind-') as directory:
        projected_path = Path(directory) / 'wind-projection.csv'
        projected_path.write_text(projection, encoding='utf-8')
        wind_result = check_wind(projected_path, duration)

    result = {
        'format': FORMAT,
        'metadata_schema': METADATA_SCHEMA,
        'rows': len(rows),
        'first_tick': int(float(rows[0]['tick'])),
        'last_tick': int(float(rows[-1]['tick'])),
        'rho_kgm3': expected_state['rho_kgm3'],
        'density_ratio': expected_state['sigma'],
        'engine_charge_ratio': expected_state['engine_charge_ratio'],
        'density_altitude_m': expected_state['density_altitude_m'],
        'max_atmosphere_state_error': max_state_error,
        'max_atmosphere_row_error': max_rho_rounding_error,
        'max_eas_error_mps': max_eas_error,
        'max_wind_error_mps': wind_result['max_wind_error_mps'],
        'max_speed_error_mps': wind_result['max_speed_error_mps'],
    }
    if has_turbulence:
        result['max_turbulence_error_mps'] = wind_result['max_turbulence_error_mps']
    if duration is not None:
        if not math.isfinite(duration) or duration <= 0.0:
            raise ValueError('invalid requested duration')
        elapsed = float(rows[-1]['t_s']) - float(rows[0]['t_s'])
        if abs(elapsed - duration) > 1e-8:
            raise ValueError('requested duration not completed')
    return result


def _project_weather_trace(metadata, config, expected_columns, rows, has_turbulence):
    """Project only already-validated v6 data into the existing v4/v5 wind verifier."""
    projected_metadata = dict(metadata)
    trace_version = 5 if has_turbulence else 4
    projected_metadata['format'] = f'openrc-trace v{trace_version}'
    projected_metadata['metadata_schema'] = 'openrc-flight-meta v4' if has_turbulence else 'openrc-flight-meta v3'
    projected_metadata['weather_model'] = TURBULENCE_MODEL if has_turbulence else COSINE_MODEL
    projected_config = {key: value for key, value in config.items() if key not in ATMOSPHERE_KEYS}
    projected_config['format'] = 'openrc-weather v2'
    projected_metadata['weather_config'] = json.dumps(projected_config, separators=(',', ':'), allow_nan=False)
    projected_metadata.pop('atmosphere_model', None)
    projected_metadata.pop('atmosphere_state', None)
    projected_metadata.pop('atmosphere_scope', None)
    projected_metadata.pop('engine_atmosphere', None)
    columns = [key for key in expected_columns if key not in ATMOSPHERIC_COLUMNS]
    output = io.StringIO()
    output.write(f'# format: openrc-trace v{trace_version}\n')
    for key, value in projected_metadata.items():
        if key == 'format':
            continue
        output.write(f'# {key}: {value}\n')
    writer = csv.writer(output, lineterminator='\n')
    writer.writerow(columns)
    for row in rows:
        writer.writerow([row[key] for key in columns])
    return output.getvalue()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('trace', type=Path)
    parser.add_argument('--duration', type=float)
    args = parser.parse_args()
    try:
        print(json.dumps(check(args.trace, args.duration), sort_keys=True))
    except (OSError, ValueError) as error:
        parser.error(str(error))


if __name__ == '__main__':
    main()
