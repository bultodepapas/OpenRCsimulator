#!/usr/bin/env python3
"""Validate custom-atmosphere v6/v10 traces or calm standard-column v11 traces."""
import argparse
import csv
import io
import json
import math
from pathlib import Path
import tempfile

from check_trimmed_flight import (
    COLUMNS, ELECTRIC_COLUMNS, GEAR_COLUMNS, check_coupled_metadata, check_gear_metadata,
    check_gear_sample, _has_gear_metadata,
)
from check_wind_trace import (
    TURBULENCE_COLUMNS, TURBULENCE_MODEL, WEATHER_COLUMNS, check as check_wind, matrix as _quaternion_matrix,
)

FORMAT = 'openrc-trace v6'
METADATA_SCHEMA = 'openrc-flight-meta v5'
WHEEL_METADATA_SCHEMA = 'openrc-flight-meta v6'
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
COLUMN_FORMAT = 'openrc-trace v11'
COLUMN_WEATHER_FORMAT = 'openrc-weather v4'
COLUMN_ATMOSPHERE_MODEL = 'standard-column-dry-isa-troposphere-v1'
COLUMN_ATMOSPHERE_SCOPE = 'dry ISA column; geometric altitude = field elevation - NED down; one body datum sample per stage; -500..11000 m; no extrapolation; fixed gravity'
COLUMN_WEATHER_KEYS = WEATHER_V3_KEYS
COLUMN_ATMOSPHERIC_COLUMNS = ['geometric_altitude_m', 'loads_rho_kgm3', 'loads_pressure_pa', 'loads_temperature_k']
BATTERY_COLUMNS = [
    'battery_soc', 'remaining_charge_c', 'consumed_charge_c', 'pack_current_a', 'auxiliary_current_a',
    'ocv_v', 'pack_terminal_power_w', 'pack_loss_w', 'terminal_energy_j', 'pack_heat_j', 'pack_exhausted',
]
GLOW_COLUMNS = [
    'glow_fuel_kg', 'glow_temperature_k', 'glow_running', 'glow_stop_reason_code',
    'glow_phase_revolutions', 'glow_mixture_command_phi', 'glow_fuel_transport_kg_s',
    'glow_opportunity_count', 'glow_fire_count', 'glow_fire_events', 'glow_firing_accumulator',
    'glow_shaft_work_j', 'glow_propeller_work_j', 'glow_thrust_work_j', 'glow_chemical_work_j',
]

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
    trace_format = metadata.get('format')
    gear = trace_format == 'openrc-trace v10'
    if trace_format not in (FORMAT, 'openrc-trace v10'):
        raise ValueError('expected custom-atmosphere trace v6 or retractable-gear trace v10')
    if gear != _has_gear_metadata(metadata):
        raise ValueError('trace format disagrees with retractable gear metadata')
    if gear:
        if metadata.get('metadata_schema') != 'openrc-flight-meta v8':
            raise ValueError('gear atmosphere trace requires flight metadata v8')
        check_gear_metadata(metadata)
    elif metadata.get('metadata_schema') not in (METADATA_SCHEMA, WHEEL_METADATA_SCHEMA):
        raise ValueError('trace v6 requires flight metadata v5 or wheel metadata v6')
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
                       if metadata.get('shaft_integrator') == 'coupled-rk4' else
                       'wind/TAS at row state time; loads_* wind and loads_t_s describe k1 (tick-1 body/turbine, current sampled servos); reset uses t=0'
                       if metadata.get('turbine_integrator') == 'rk4' else WEATHER_TIMING)
    if metadata.get('weather_timing') != expected_timing or metadata.get('weather_evidence') != WEATHER_EVIDENCE:
        raise ValueError('unsupported weather timing/evidence metadata')
    if not data_lines:
        raise ValueError('trace has no CSV header or samples')
    reader = csv.DictReader(data_lines)
    fieldnames = reader.fieldnames
    has_turbulence = expected_weather_model == TURBULENCE_MODEL
    expected_columns = (COLUMNS + WEATHER_COLUMNS
                        + (TURBULENCE_COLUMNS if has_turbulence else [])
                        + ATMOSPHERIC_COLUMNS + (GEAR_COLUMNS if gear else []))
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
        if gear:
            check_gear_sample(row)
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
    if gear:
        check_gear_metadata(metadata, {key: float(value) for key, value in rows[0].items()})
    if 'recording_start_previous_state' not in metadata:
        raise ValueError('missing previous body state needed for wind validation')
    projection = _project_weather_trace(metadata, config, expected_columns, rows, has_turbulence)
    with tempfile.TemporaryDirectory(prefix='openrc-atmos-v6-wind-') as directory:
        projected_path = Path(directory) / 'wind-projection.csv'
        projected_path.write_text(projection, encoding='utf-8')
        wind_result = check_wind(projected_path, duration)

    result = {
        'format': 'openrc-trace v10' if gear else FORMAT,
        'metadata_schema': metadata['metadata_schema'],
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


def standard_column_state(geometric_altitude_m):
    """Independent dry ISA troposphere values at geometric altitude; no app imports."""
    z_m = float(geometric_altitude_m)
    if not math.isfinite(z_m) or not -500.0 <= z_m <= 11000.0:
        raise ValueError('column geometric altitude is outside [-500, 11000] m')
    geopotential_m = EARTH_EFFECTIVE_RADIUS_M * z_m / (EARTH_EFFECTIVE_RADIUS_M + z_m)
    temperature_k = SEA_LEVEL_TEMPERATURE_K - TROPOSPHERE_LAPSE_KPM * geopotential_m
    pressure_pa = SEA_LEVEL_PRESSURE_PA * (temperature_k / SEA_LEVEL_TEMPERATURE_K) ** (
        STANDARD_GRAVITY_MPS2 / (DRY_AIR_GAS_CONSTANT_J_KG_K * TROPOSPHERE_LAPSE_KPM)
    )
    density = pressure_pa / (DRY_AIR_GAS_CONSTANT_J_KG_K * temperature_k)
    sigma = density / SEA_LEVEL_DENSITY_KGM3
    sea_level_dry_density = SEA_LEVEL_PRESSURE_PA / (DRY_AIR_GAS_CONSTANT_J_KG_K * SEA_LEVEL_TEMPERATURE_K)
    density_exponent = STANDARD_GRAVITY_MPS2 / (
        DRY_AIR_GAS_CONSTANT_J_KG_K * TROPOSPHERE_LAPSE_KPM
    ) - 1.0
    da_geopotential_m = SEA_LEVEL_TEMPERATURE_K / TROPOSPHERE_LAPSE_KPM * (
        1.0 - (density / sea_level_dry_density) ** (1.0 / density_exponent)
    )
    density_altitude_m = EARTH_EFFECTIVE_RADIUS_M * da_geopotential_m / (
        EARTH_EFFECTIVE_RADIUS_M - da_geopotential_m
    )
    result = {
        'pressure_pa': pressure_pa,
        'temperature_k': temperature_k,
        'vapor_pressure_pa': 0.0,
        'rho_kgm3': density,
        'dry_air_density_kgm3': density,
        'sigma': sigma,
        'engine_charge_ratio': sigma,
        'density_altitude_m': density_altitude_m,
    }
    if any(not math.isfinite(value) for value in result.values()):
        raise ValueError('independent column equation produced a nonfinite value')
    return result


def _column_weather_config(raw):
    try:
        config = _load_json(raw)
    except (TypeError, json.JSONDecodeError) as error:
        raise ValueError('invalid weather_config JSON') from error
    if type(config) is not dict or set(config) != COLUMN_WEATHER_KEYS:
        raise ValueError('column weather_config must have the exact v4 schema')
    if config.get('format') != COLUMN_WEATHER_FORMAT or config.get('atmosphere_mode') != 'standard_column':
        raise ValueError('v11 requires openrc-weather v4 standard_column mode')
    bounds = {
        'speed_mps': (0.0, 15.0), 'from_deg': (0.0, 360.0), 'gust_mps': (0.0, 8.0),
        'gust_up_mps': (-8.0, 8.0), 'gust_duration_s': (0.5, 20.0),
        'gust_period_s': (0.5, 120.0), 'gust_delay_s': (0.0, 3600.0),
        'turbulence_tau_s': (0.2, 30.0), 'field_elevation_m': (-500.0, 4000.0),
        'temperature_c': (-20.0, 45.0), 'qnh_hpa': (870.0, 1085.0),
        'relative_humidity_pct': (0.0, 100.0),
    }
    for key, (lower, upper) in bounds.items():
        _number(config[key], key, lower, upper)
    if config['from_deg'] == 360.0 or config['gust_period_s'] < config['gust_duration_s']:
        raise ValueError('column weather heading or gust period is not canonical')
    rms = config['turbulence_rms_mps']
    if type(rms) is not list or len(rms) != 3:
        raise ValueError('column turbulence_rms_mps must contain three NED values')
    for axis, value in enumerate(rms):
        _number(value, f'turbulence_rms_mps[{axis}]', 0.0, 3.0)
    seed = config['turbulence_seed']
    if type(seed) is not int or not 0 <= seed <= 0xFFFFFFFF:
        raise ValueError('invalid column turbulence_seed')
    # This reader independently checks the published standard-column preset. It does not
    # claim to verify arbitrary gust or OU settings through this specialized CLI lane.
    if any(float(config[key]) != 0.0 for key in ('speed_mps', 'gust_mps', 'gust_up_mps')) \
            or any(float(value) != 0.0 for value in rms):
        raise ValueError('column CLI checker requires the calm standard-column preset')
    return config


def _column_trace_parts(path):
    metadata = {}
    data_lines = []
    for line in Path(path).read_text(encoding='utf-8').splitlines():
        if line.startswith('# '):
            key, separator, value = line[2:].partition(': ')
            if not separator or not key or key in metadata:
                raise ValueError('malformed or duplicate metadata')
            metadata[key] = value
        elif line.startswith('#'):
            raise ValueError('malformed trace comment')
        elif line:
            data_lines.append(line)
    return metadata, data_lines


def check_column(path, duration=None):
    """Validate calm standard-column v11 traces, including endpoint and k1 samples.

    This specialized lane rejects nonzero wind, gust, or turbulence settings; it does
    not validate arbitrary weather-v4 traces.
    """
    metadata, data_lines = _column_trace_parts(path)
    if metadata.get('format') != COLUMN_FORMAT:
        raise ValueError('expected openrc-trace v11 standard-column output')
    if metadata.get('atmosphere_model') != COLUMN_ATMOSPHERE_MODEL:
        raise ValueError('unsupported or stale standard-column atmosphere_model')
    if metadata.get('atmosphere_scope') != COLUMN_ATMOSPHERE_SCOPE:
        raise ValueError('unsupported standard-column scope')
    config = _column_weather_config(metadata.get('weather_config'))
    if metadata.get('weather_evidence') != WEATHER_EVIDENCE:
        raise ValueError('unsupported weather evidence contract')
    if metadata.get('weather_model') != COSINE_MODEL:
        raise ValueError('calm standard-column preset requires the deterministic cosine weather identity')

    glow = metadata.get('glow_trace_schema') == 'openrc-glow-trace v1'
    gear = _has_gear_metadata(metadata)
    wheel_claim = any(key in metadata for key in (
        'wheel_state_model', 'wheel_state_layout', 'wheel_profile_status', 'wheel_profile_sha256',
        'wheel_profile_input_sha256', 'wheel_brakes', 'launch_continuous',
    ))
    electric = 'electric_configuration' in metadata
    coupled = 'shaft_integrator' in metadata or 'turbine_integrator' in metadata or electric or glow
    expected_schema = (
        'openrc-flight-meta v8' if gear else
        'openrc-flight-meta v7' if glow else
        'openrc-flight-meta v6' if wheel_claim or coupled else
        'openrc-flight-meta v5'
    )
    if metadata.get('metadata_schema') != expected_schema:
        raise ValueError('metadata schema does not match the v11 propulsion/gear family')
    if gear:
        check_gear_metadata(metadata)
    elif expected_schema == 'openrc-flight-meta v8':
        raise ValueError('v8 column trace is missing retractable-gear identity')
    if expected_schema == 'openrc-flight-meta v6':
        check_coupled_metadata(metadata)
    if glow and metadata.get('propulsion_model') != 'glow-mean-cycle-finite-tank-hub-inflow-v2':
        raise ValueError('glow trace schema disagrees with propulsion identity')
    if metadata.get('engine_atmosphere') != (
        'electric motor constants independent of density; propeller loads use stage density'
        if electric else ENGINE_ATMOSPHERE
    ):
        raise ValueError('unsupported engine atmosphere contract')

    try:
        dt = float(metadata['dt_s'])
        first_tick_text = metadata['recording_start_tick']
        first_tick = int(first_tick_text)
    except (KeyError, TypeError, ValueError) as error:
        raise ValueError('missing or invalid trace timing metadata') from error
    if not math.isfinite(dt) or not 0.0 < dt <= 1.0 or str(first_tick) != first_tick_text or first_tick < 0:
        raise ValueError('invalid trace clock or recording origin')
    expected_timing = (
        'wind/TAS at row state time; loads_* wind and loads_t_s describe k1 (tick-1 body/shaft, current sampled servos); reset uses t=0'
        if metadata.get('shaft_integrator') == 'coupled-rk4' else
        'wind/TAS at row state time; loads_* wind and loads_t_s describe k1 (tick-1 body/turbine, current sampled servos); reset uses t=0'
        if metadata.get('turbine_integrator') == 'rk4' else WEATHER_TIMING
    )
    if metadata.get('weather_timing') != expected_timing:
        raise ValueError('unsupported v11 weather timing contract')

    recorded_preview = _json_metadata_value(metadata, 'atmosphere_state')
    if type(recorded_preview) is not dict or set(recorded_preview) != STATE_KEYS:
        raise ValueError('atmosphere_state is not the full field-datum preview object')
    if recorded_preview.get('ok') is not True or recorded_preview.get('errors') != []:
        raise ValueError('field-datum atmosphere preview reports failure')
    expected_preview = standard_column_state(config['field_elevation_m'])
    maximum_preview_error = 0.0
    for key, expected in expected_preview.items():
        actual = recorded_preview.get(key)
        if not _finite_number(actual):
            raise ValueError('field-datum preview has invalid ' + key)
        error = abs(float(actual) - expected)
        maximum_preview_error = max(maximum_preview_error, error)
        if error > max(2e-10, abs(expected) * 2e-12):
            raise ValueError('field-datum preview disagrees with independent ISA equation: ' + key)

    if not data_lines:
        raise ValueError('v11 trace has no CSV header or samples')
    reader = csv.DictReader(data_lines)
    fieldnames = reader.fieldnames or []
    propulsion_model = metadata.get('propulsion_model')
    battery = 'electric_configuration' in metadata and metadata.get('battery_model') == 'balanced-pack-ocv-resistance-no-regeneration-v1'
    electric_columns = list(ELECTRIC_COLUMNS) + (BATTERY_COLUMNS if battery else []) if electric else []
    glow_columns = GLOW_COLUMNS if glow else []
    has_turbulence = any(float(value) > 0.0 for value in config['turbulence_rms_mps'])
    expected_columns = (
        list(COLUMNS) + electric_columns + glow_columns + WEATHER_COLUMNS
        + (TURBULENCE_COLUMNS if has_turbulence else [])
        + ATMOSPHERIC_COLUMNS + COLUMN_ATMOSPHERIC_COLUMNS
        + (GEAR_COLUMNS if gear else [])
    )
    if fieldnames != expected_columns or len(set(fieldnames)) != len(expected_columns):
        raise ValueError('v11 family columns/order mismatch')
    raw_rows = list(reader)
    if len(raw_rows) < 2:
        raise ValueError('incomplete column trace: need an initial sample and a flight tick')

    previous_state_raw = _json_metadata_value(metadata, 'recording_start_previous_state')
    if type(previous_state_raw) is not list or len(previous_state_raw) != 13 or any(not _finite_number(value) for value in previous_state_raw):
        raise ValueError('invalid recording-start previous state needed for k1 load sample')
    max_endpoint_density_error = 0.0
    max_load_density_error = 0.0
    previous_tick = None
    previous_row = None
    parsed_rows = []
    field_elevation = float(config['field_elevation_m'])
    for raw in raw_rows:
        if set(raw) != set(expected_columns) or any(value is None for value in raw.values()):
            raise ValueError('malformed v11 CSV row width')
        try:
            row = {key: float(value) for key, value in raw.items()}
        except (TypeError, ValueError) as error:
            raise ValueError('nonnumeric v11 trace sample') from error
        if not all(math.isfinite(value) for value in row.values()):
            raise ValueError('nonfinite v11 trace sample')
        tick = row['tick']
        if tick < 0 or tick > (1 << 53) - 1 or tick != int(tick):
            raise ValueError('invalid v11 trace tick')
        if previous_tick is None and int(tick) != first_tick:
            raise ValueError('recording origin mismatch')
        if previous_tick is not None and tick != previous_tick + 1:
            raise ValueError('noncontinuous v11 ticks')
        if abs(row['t_s'] - tick * dt) > 1e-8:
            raise ValueError('v11 state clock mismatch')
        load_time = max(0, int(tick) - 1) * dt
        if abs(row['loads_t_s'] - load_time) > 1e-8:
            raise ValueError('v11 k1 load timestamp mismatch')
        if abs(row['alt_m'] + row['down_m']) > 2e-9:
            raise ValueError('row altitude disagrees with NED down')

        endpoint_altitude = field_elevation - row['down_m']
        if abs(row['geometric_altitude_m'] - endpoint_altitude) > 2e-9:
            raise ValueError('geometric_altitude_m is not field datum minus endpoint down')
        endpoint = standard_column_state(endpoint_altitude)
        for column, key in (
            ('rho_kgm3', 'rho_kgm3'), ('density_ratio', 'sigma'), ('density_altitude_m', 'density_altitude_m'),
            ('pressure_pa', 'pressure_pa'), ('temperature_k', 'temperature_k'),
            ('engine_charge_ratio', 'engine_charge_ratio'),
        ):
            error = abs(row[column] - endpoint[key])
            if column == 'rho_kgm3':
                max_endpoint_density_error = max(max_endpoint_density_error, error)
            tolerance = max(1.1e-9, abs(endpoint[key]) * 6e-10)
            if error > tolerance:
                raise ValueError('endpoint atmosphere disagrees with independent ISA equation: ' + column)
        expected_eas = row['tas_mps'] * math.sqrt(endpoint['sigma'])
        if abs(row['equivalent_airspeed_mps'] - expected_eas) > 2e-8:
            raise ValueError('equivalent_airspeed_mps disagrees with local density ratio')

        if int(tick) == 0:
            load_down = row['down_m']
            load_velocity = [row[key] for key in ('u_mps', 'v_mps', 'w_mps')]
            load_quaternion = [row[key] for key in ('qw', 'qx', 'qy', 'qz')]
        elif previous_row is not None:
            load_down = previous_row['down_m']
            load_velocity = [previous_row[key] for key in ('u_mps', 'v_mps', 'w_mps')]
            load_quaternion = [previous_row[key] for key in ('qw', 'qx', 'qy', 'qz')]
        else:
            load_down = float(previous_state_raw[2])
            load_velocity = [float(value) for value in previous_state_raw[3:6]]
            load_quaternion = [float(value) for value in previous_state_raw[6:10]]
        load_altitude = field_elevation - load_down
        expected_load = standard_column_state(load_altitude)
        for column, key in (
            ('loads_rho_kgm3', 'rho_kgm3'), ('loads_pressure_pa', 'pressure_pa'),
            ('loads_temperature_k', 'temperature_k'),
        ):
            error = abs(row[column] - expected_load[key])
            if column == 'loads_rho_kgm3':
                max_load_density_error = max(max_load_density_error, error)
            if error > max(1.1e-9, abs(expected_load[key]) * 6e-10):
                raise ValueError('k1 previous-state atmosphere mismatch: ' + column)
        if int(tick) > 0 and abs(expected_load['rho_kgm3'] - endpoint['rho_kgm3']) < 1e-12:
            # Flat trimmed traces may legitimately stay level; this is diagnostic only.
            pass

        quaternion = [row[key] for key in ('qw', 'qx', 'qy', 'qz')]
        if abs(sum(value * value for value in quaternion) - 1.0) > 1e-8:
            raise ValueError('invalid row quaternion')
        rotation = _quaternion_matrix(quaternion)
        body_velocity = [row[key] for key in ('u_mps', 'v_mps', 'w_mps')]
        expected_tas = math.sqrt(sum(value * value for value in body_velocity))
        if abs(row['tas_mps'] - expected_tas) > 1e-7:
            raise ValueError('calm-preset TAS disagrees with body velocity')
        ned_velocity = [sum(rotation[axis][j] * body_velocity[j] for j in range(3)) for axis in range(3)]
        expected_ground_speed = math.hypot(ned_velocity[0], ned_velocity[1])
        if abs(row['ground_horizontal_mps'] - expected_ground_speed) > 1e-7:
            raise ValueError('ground_horizontal_mps disagrees with rotated body velocity')
        for key in ('wind_north_mps', 'wind_east_mps', 'wind_down_mps',
                    'loads_wind_north_mps', 'loads_wind_east_mps', 'loads_wind_down_mps'):
            if abs(row[key]) > 1e-12:
                raise ValueError('calm standard-column preset emitted nonzero wind: ' + key)
        expected_load_tas = math.sqrt(sum(value * value for value in load_velocity))
        if abs(row['loads_tas_mps'] - expected_load_tas) > 1e-7:
            raise ValueError('loads_tas_mps disagrees with previous k1 body velocity')

        if gear:
            check_gear_sample(row)
        parsed_rows.append(row)
        previous_tick = int(tick)
        previous_row = row

    if gear:
        check_gear_metadata(metadata, parsed_rows[0])
    elapsed = parsed_rows[-1]['t_s'] - parsed_rows[0]['t_s']
    if duration is not None:
        if not math.isfinite(duration) or duration <= 0.0 or abs(elapsed - duration) > 1e-8:
            raise ValueError('requested v11 trace duration not completed')
    return {
        'format': COLUMN_FORMAT,
        'metadata_schema': expected_schema,
        'rows': len(parsed_rows),
        'first_tick': int(parsed_rows[0]['tick']),
        'last_tick': int(parsed_rows[-1]['tick']),
        'elapsed_s': elapsed,
        'field_elevation_m': field_elevation,
        'first_geometric_altitude_m': parsed_rows[0]['geometric_altitude_m'],
        'last_geometric_altitude_m': parsed_rows[-1]['geometric_altitude_m'],
        'first_rho_kgm3': parsed_rows[0]['rho_kgm3'],
        'last_rho_kgm3': parsed_rows[-1]['rho_kgm3'],
        'max_field_datum_preview_error': maximum_preview_error,
        'max_endpoint_density_error_kgm3': max_endpoint_density_error,
        'max_load_density_error_kgm3': max_load_density_error,
        'columns': fieldnames,
    }


def _project_weather_trace(metadata, config, expected_columns, rows, has_turbulence):
    """Project validated weather fields to the wind verifier, retaining gear-v10 identity."""
    projected_metadata = dict(metadata)
    gear = metadata.get('format') == 'openrc-trace v10'
    trace_version = 5 if has_turbulence else 4
    projected_format = 10 if gear else trace_version
    projected_metadata['format'] = f'openrc-trace v{projected_format}'
    if not gear:
        projected_metadata['metadata_schema'] = (
            WHEEL_METADATA_SCHEMA if metadata.get('metadata_schema') == WHEEL_METADATA_SCHEMA else
            'openrc-flight-meta v4' if has_turbulence else 'openrc-flight-meta v3'
        )
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
    output.write(f'# format: openrc-trace v{projected_format}\n')
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
    parser = argparse.ArgumentParser(
        description=__doc__,
        epilog='Use --column only for v11 standard-column traces from the calm preset '
               '(zero wind, gust, and turbulence).',
    )
    parser.add_argument('trace', type=Path)
    parser.add_argument('--duration', type=float)
    parser.add_argument(
        '--column', action='store_true',
        help='validate a v11 standard-column trace from the calm preset only',
    )
    args = parser.parse_args()
    try:
        validator = check_column if args.column else check
        print(json.dumps(validator(args.trace, args.duration), sort_keys=True))
    except (OSError, ValueError) as error:
        parser.error(str(error))


if __name__ == '__main__':
    main()
