"""Verify a complete, finite, trimmed app flight against an externally requested duration.

Defaults match the three-second, 240 Hz smoke flight. Capture/export callers pass
--duration explicitly. The initial tick is a sample, not evidence of a flown tick.
"""
from flap_trace_contract import project as project_flaps
from mass_trace_contract import project as project_mass_trace
import argparse
import csv
import hashlib
import json
import math
from pathlib import Path
import re
import sys

COLUMNS = (
    "tick t_s north_m east_m down_m alt_m u_mps v_mps w_mps speed_mps "
    "qw qx qy qz yaw_deg pitch_deg roll_deg p_radps q_radps r_radps "
    "Fx_N Fy_N Fz_N Mx_Nm My_Nm Mz_Nm cmd_roll cmd_pitch cmd_yaw cmd_throttle "
    "engine_rpm srv_roll srv_pitch srv_yaw"
).split()
ELECTRIC_COLUMNS = ('drive_enabled drive_duty bus_voltage_v motor_current_a drive_bus_current_a '
                    'source_torque_nm shaft_power_w copper_loss_w rotational_loss_w').split()
GEAR_COLUMNS = 'gear_extension gear_target_down cmd_gear_down cmd_wheel_brake'.split()
# BAT-10: finite pack_ecm battery (trace v13), docs/research/battery/BAT-04/specification.md.
PACK_LAW = 'electric-pack-ecm-coupled-events-v1'
PACK_MODEL = 'average-plus-weakest-cell-thevenin-lumped-thermal-no-regeneration-v1'
PACK_LAYOUT = ('axial wash increment m/s, slipstream.pieces order, then propeller shaft rpm, weak-cell remaining charge C, '
               'terminal energy J, pack loss J, average-cell RC V, weak-cell RC V, pack temperature K, ESC sensed V, '
               'ESC limit, ESC phase, ESC timer s, ESC detected cells; RK4 coupled; ESC slots sampled at accepted endpoints')
PACK_COLUMNS = ('battery_soc battery_soc_weak remaining_charge_c consumed_charge_c pack_current_a auxiliary_current_a '
                'ocv_v polarization_v cell_voltage_avg_v cell_voltage_min_v pack_temperature_k ambient_temperature_k '
                'pack_terminal_power_w pack_loss_w terminal_energy_j pack_heat_j esc_sensed_voltage_v esc_limit '
                'esc_effective_duty esc_detected_cells esc_phase pack_exhausted').split()
# Trace v3 prints time to nine decimal places. Allow rounding, not a missing tick.
TIME_TOLERANCE = 1e-9
STATE_LAYOUT = 'north_m east_m down_m u_mps v_mps w_mps qw qx qy qz p_radps q_radps r_radps'.split()
AUX_LAYOUT = 'engine_rpm srv_roll srv_pitch srv_yaw'.split()
SEMANTIC_HASH_CONVENTION = ('sha256 of Godot JSON.stringify(parsed_input, indent=empty, '
                            'sort_keys=true, full_precision=false); not file bytes')
INPUT_HASH_CONVENTION = 'sha256 of exact aircraft input file bytes'
WHEEL_STATE_MODEL = 'relative-wheel-rim-speed-rk4-v1'
WHEEL_LAYOUT_SUFFIX = 'wheel rim speeds in m/s, landing-gear contact order, appended continuous tail'
WHEEL_PROFILE_HASH_CONVENTION = (
    'profile_sha256 is canonical JSON for the selected aircraft profile; '
    'input_sha256 is SHA-256 of exact wheel_profiles.json bytes')
SHAFT_LAYOUT = 'axial wash increment m/s, slipstream.pieces order, then propeller shaft rpm; RK4 coupled'
BATTERY_LAYOUT = ('axial wash increment m/s, slipstream.pieces order, then propeller shaft rpm, '
                  'remaining charge C, terminal energy J, pack heat J; RK4 coupled')
WASH_ONLY_LAYOUT = 'axial wash increment m/s, slipstream.pieces order; RK4 coupled; checkpoint only'
TURBINE_LAYOUT = 'turbine shaft rpm; RK4 coupled; prescribed fuel mass'
LIQUID_MODEL = 'single-store-finite-liquid-fixed-datum-v1'
LIQUID_SCHEMA = 'openrc-liquid-fuel v1'
LIQUID_LAYOUT = 'base propulsion/wheels; usable fuel kg; source latch 0/1'
LIQUID_LAWS = {'gasoline_bsfc_v1', 'turbine_map_v1'}
GEAR_LAW = 'retractable-point-gear-v1'
GEAR_TRACE_SCHEMA = 'openrc-gear-trace v1'
GEAR_INPUT_LAYOUT = ['roll', 'pitch', 'yaw', 'throttle', 'gear_down', 'wheel_brake']


def _finite_number(value: object) -> bool:
    if type(value) not in (int, float):
        return False
    try:
        return math.isfinite(float(value))
    except OverflowError:
        return False


def check_fixed_bus_sample(metadata: dict, sample: dict) -> None:
    """TT-08: independently reconstruct accepted-endpoint DC-equivalent telemetry."""
    if metadata.get('propulsion_model') != 'electric-fixed-bus-coupled-stop-v1':
        raise ValueError('calm electric v7 smoke requires the fixed-bus law')
    if metadata.get('electric_sample_timing') != 'accepted endpoint; current tick input and source-enabled mode':
        raise ValueError('missing or invalid electric sample timing')
    try:
        configuration = json.loads(metadata['electric_configuration'])
        motor, battery, esc = (configuration[key] for key in ('motor', 'battery', 'esc'))
        kv, resistance, idle_current = (motor[key] for key in (
            'kv_rpm_per_volt', 'resistance_ohm', 'no_load_current_a'))
        voltage = battery['voltage_v']
    except (KeyError, TypeError, ValueError) as error:
        raise ValueError('missing or invalid electric configuration') from error
    if (not all(_finite_number(x) for x in (kv, resistance, idle_current, voltage))
            or kv <= 0 or resistance <= 0 or idle_current < 0 or voltage <= 0
            or battery.get('kind') != 'fixed_voltage'
            or esc != {'kind': 'ideal_motoring', 'command_mapping': 'identity'}):
        raise ValueError('invalid fixed-bus electric configuration')
    enabled, duty, rpm = (sample[key] for key in ('drive_enabled', 'drive_duty', 'engine_rpm'))
    if enabled not in (0, 1) or not 0 <= duty <= 1 or rpm < 0 or (enabled == 0 and duty != 0):
        raise ValueError('invalid electric endpoint mode')
    if enabled != 1 or abs(duty - sample['cmd_throttle']) > 2e-9:
        raise ValueError('trimmed electric drive disagrees with the sampled command')
    current = max(0, (duty * voltage - rpm / kv) / resistance) if duty > 0 else 0
    kt, omega = 60 / (2 * math.pi * kv), rpm * 2 * math.pi / 60
    loss = kt * idle_current
    if rpm == 0:
        loss = min(loss, kt * current)
    torque = kt * current - loss
    expected = dict(bus_voltage_v=voltage, motor_current_a=current,
                    drive_bus_current_a=duty * current, source_torque_nm=torque,
                    shaft_power_w=torque * omega, copper_loss_w=current * current * resistance,
                    rotational_loss_w=loss * omega)
    for key, value in expected.items():
        # Printed commands/RPM have nine decimal places; propagate their rounding to power.
        if not math.isclose(sample[key], value, rel_tol=2e-7, abs_tol=2e-6):
            raise ValueError('electric endpoint equation disagrees: ' + key)
def pack_slots(metadata: dict) -> int:
    """Battery slots after the shaft RPM for a pack_ecm trace: 9 + 2 x RC branches."""
    try:
        branches = json.loads(metadata['battery_pack'])['branches']
    except (KeyError, TypeError, ValueError) as error:
        raise ValueError('missing or invalid pack metadata') from error
    if metadata.get('battery_model') != PACK_MODEL or type(branches) is not int or branches not in (0, 1, 2):
        raise ValueError('missing or unsupported pack model')
    return 9 + 2 * branches


def check_pack_sample(sample: dict, budget_c: float) -> None:
    """BAT-10: a trimmed pack flight stays connected, ESC-normal and inside its charge budget."""
    if sample['drive_enabled'] != 1 or abs(sample['drive_duty'] - sample['cmd_throttle']) > 2e-9:
        raise ValueError('trimmed pack drive disagrees with the sampled command')
    if abs(sample['esc_effective_duty'] - min(sample['drive_duty'], sample['esc_limit'])) > 2e-9:
        raise ValueError('ESC effective duty is not min(command, limit)')
    if sample['esc_phase'] != 0 or sample['esc_limit'] != 1 or sample['pack_exhausted'] != 0:
        raise ValueError('trimmed pack flight left the normal ESC state')
    if (not 0 < sample['battery_soc'] <= 1 or not 0 < sample['battery_soc_weak'] <= 1
            or sample['pack_temperature_k'] <= 0 or sample['esc_detected_cells'] < 1
            or sample['cell_voltage_min_v'] > sample['cell_voltage_avg_v'] + 2e-9
            or not sample['bus_voltage_v'] < sample['ocv_v']):
        raise ValueError('pack state out of its connected motoring domain')
    if abs(sample['remaining_charge_c'] + sample['consumed_charge_c'] - budget_c) > 2e-6:
        raise ValueError('pack charge budget does not close')
    if not math.isclose(sample['pack_terminal_power_w'], sample['bus_voltage_v'] * sample['pack_current_a'],
                        rel_tol=2e-7, abs_tol=2e-6):
        raise ValueError('pack terminal power is not V x I')


def check_input_identity(metadata: dict, allow_legacy: bool, aircraft_input: Path | None) -> str:
    """Never reinterpret the old rounded semantic digest as an exact file hash."""
    schema = metadata.get('metadata_schema')
    if schema == 'openrc-flight-meta v1':
        if any(key.startswith(('aircraft_input_', 'aircraft_semantic_')) for key in metadata):
            raise ValueError('legacy metadata v1 cannot contain v2 input/semantic fields')
        if not allow_legacy:
            raise ValueError('legacy metadata v1 has no exact input identity; use --allow-legacy-metadata for archival checks')
        if aircraft_input is not None:
            raise ValueError('legacy metadata cannot verify --aircraft-input')
        digest_key, convention_key = 'aircraft_data_sha256', 'aircraft_data_hash_convention'
        identity = 'legacy semantic-only metadata; exact input identity unavailable'
    elif schema in {f'openrc-flight-meta v{version}' for version in range(2, 10)}:
        if any(key in metadata for key in ('aircraft_data_sha256', 'aircraft_data_hash_convention')):
            raise ValueError('metadata v2 must use explicit input/semantic hash names')
        if metadata.get('aircraft_input_format') not in ('openrc-aircraft v1', 'openrc-aircraft v2'):
            raise ValueError('missing or unsupported aircraft input format')
        if metadata.get('aircraft_input_hash_convention') != INPUT_HASH_CONVENTION:
            raise ValueError('missing or unsupported aircraft input hash convention')
        raw_hash = metadata.get('aircraft_input_sha256', '')
        if not re.fullmatch(r'[0-9a-f]{64}', raw_hash):
            raise ValueError('missing or invalid exact aircraft input SHA-256')
        if aircraft_input is not None and hashlib.sha256(aircraft_input.read_bytes()).hexdigest() != raw_hash:
            raise ValueError('aircraft input bytes do not match recorded SHA-256')
        digest_key, convention_key = 'aircraft_semantic_sha256', 'aircraft_semantic_hash_convention'
        identity = ('exact aircraft input bytes verified' if aircraft_input is not None
                    else 'exact aircraft input SHA-256 recorded (source bytes not checked)')
    elif schema is None:
        raise ValueError('unversioned legacy metadata is unsupported; C7-R2 v1 or DATA-3 v2 required')
    else:
        raise ValueError('missing or unsupported flight metadata schema')
    if not re.fullmatch(r'[0-9a-f]{64}', metadata.get(digest_key, '')):
        raise ValueError('missing or invalid aircraft semantic SHA-256')
    if metadata.get(convention_key) != SEMANTIC_HASH_CONVENTION:
        raise ValueError('missing or unsupported aircraft semantic hash convention')
    return identity


def check_metadata(metadata: dict, first: dict) -> None:
    """C7-R2 state/feature requirements shared by metadata v1 and v2."""
    for key in ('aircraft', 'configuration', 'loads', 'state_timing'):
        if not metadata.get(key):
            raise ValueError(f'missing flight metadata: {key}')
    for key, allowed in {
        'aero_model': ('global-derivatives-v1', 'local-surfaces-v1 with bounded attached oracle',
                       'section-plane-source-weighted-wake-velocity-v2 with bounded attached oracle'),
        'propulsion_model': ('propeller-rpm-lag-v1', 'propeller-shaft-balance-v1', 'turbine-ecu-spool-v1',
                             'turbine-rpm-governor-rk4-v1',
                             'propeller-shaft-coupled-rk4-v1', 'electric-fixed-bus-coupled-stop-v1',
                             'electric-ocv-resistance-coupled-events-v1', PACK_LAW),
        'propwash_model': ('none', 'tail-slipstream-increment-v1', 'tail-slipstream-axial-transport-v1'),
    }.items():
        if metadata.get(key) not in allowed:
            raise ValueError(f'missing or unsupported {key}')
    turbine = metadata['propulsion_model'] in ('turbine-ecu-spool-v1', 'turbine-rpm-governor-rk4-v1')
    if metadata.get('engine_rpm_semantics') != ('turbine spool rpm' if turbine else 'propeller shaft rpm'):
        raise ValueError('engine_rpm_semantics disagrees with propulsion_model')
    try:
        state_layout = json.loads(metadata['state_layout'])
        aux_layout = json.loads(metadata['aux_layout'])
        aux = json.loads(metadata['recording_start_aux'])
        features = json.loads(metadata['propulsion_features'])
    except (KeyError, ValueError) as error:
        raise ValueError('missing or invalid structured flight metadata') from error
    if state_layout != STATE_LAYOUT or aux_layout != AUX_LAYOUT:
        raise ValueError('state/aux layout disagrees with trace v3')
    if not isinstance(aux, list) or len(aux) != len(AUX_LAYOUT) or any(not _finite_number(value) for value in aux):
        raise ValueError('invalid recording_start_aux')
    if any(abs(value - first[column]) > 1e-9 for column, value in zip(AUX_LAYOUT, aux)):
        raise ValueError('recording_start_aux disagrees with first sample')
    if metadata.get('recording_start_tick') != str(int(first['tick'])):
        raise ValueError('recording_start_tick disagrees with first sample')
    if metadata.get('recording_start_engine_running') != 'true':
        raise ValueError('trimmed powered flight must start with engine running')
    feature_names = {'propeller_normal_force', 'propeller_pfactor', 'rotor_gyroscopic_coupling',
                     'turbine_ram_flow', 'turbine_ram_jet'}
    if not isinstance(features, dict) or features.keys() != feature_names or any(
        type(value) is not bool for value in features.values()
    ):
        raise ValueError('invalid propulsion_features')
    if turbine and (metadata['propwash_model'] != 'none' or features['propeller_normal_force']
                    or features['propeller_pfactor']):
        raise ValueError('turbine metadata declares propeller features')
    if not turbine and (features['turbine_ram_flow'] or features['turbine_ram_jet']):
        raise ValueError('propeller metadata declares turbine features')
    check_coupled_metadata(metadata)


def _has_gear_metadata(metadata: dict) -> bool:
    keys = ('gear_law', 'gear_aux_index', 'gear_trace_schema', 'recording_start_gear')
    if any(key in metadata for key in keys):
        return True
    if 'input_layout' in metadata:
        try:
            layout = json.loads(metadata['input_layout'])
        except (TypeError, ValueError):
            return 'gear_down' in str(metadata['input_layout']) or 'wheel_brake' in str(metadata['input_layout'])
        return (isinstance(layout, list)
                and (len(layout) == 6 or 'gear_down' in layout or 'wheel_brake' in layout))
    return False


def check_gear_metadata(metadata: dict, first: dict | None = None) -> dict:
    """Validate the opt-in six-input gear contract and, when supplied, its first CSV row."""
    flaps = metadata.get('metadata_schema') == 'openrc-flight-meta v9'
    if flaps and (metadata.get('flap_law') != 'controls.flaps.hinged_trailing_edge.v1'
                  or metadata.get('flap_trace_schema') != 'openrc-flap-trace v1'
                  or metadata.get('flap_input_index') != '6'):
        raise ValueError('invalid flap extension of gear metadata')
    if (metadata.get('metadata_schema') not in ('openrc-flight-meta v8', 'openrc-flight-meta v9')
            or metadata.get('gear_law') != GEAR_LAW
            or metadata.get('gear_trace_schema') != GEAR_TRACE_SCHEMA):
        raise ValueError('missing or unsupported retractable gear trace contract')
    try:
        index_text = metadata['gear_aux_index']
        layout = json.loads(metadata['input_layout'])
        start = json.loads(metadata['recording_start_gear'])
    except (KeyError, TypeError, ValueError) as error:
        raise ValueError('missing or invalid retractable gear metadata') from error
    if (not isinstance(index_text, str) or not re.fullmatch(r'(?:0|[1-9][0-9]*)', index_text)
            or int(index_text) < 4):
        raise ValueError('invalid gear_aux_index')
    if layout != GEAR_INPUT_LAYOUT + (['flaps'] if flaps else []):
        raise ValueError('input_layout disagrees with the six-input gear contract')
    if (not isinstance(start, list) or len(start) != 2
            or any(not _finite_number(value) for value in start)
            or not 0.0 <= float(start[0]) <= 1.0 or float(start[1]) not in (0.0, 1.0)):
        raise ValueError('invalid recording_start_gear')
    if 'turbulence_aux_index' in metadata:
        turbulence_text = metadata['turbulence_aux_index']
        if (not isinstance(turbulence_text, str) or not re.fullmatch(r'(?:0|[1-9][0-9]*)', turbulence_text)
                or int(turbulence_text) != int(index_text) + 2 + int(flaps)):
            raise ValueError('gear AUX pair is not immediately before turbulence state')
    if first is not None:
        if any(key not in first for key in GEAR_COLUMNS):
            raise ValueError('gear trace is missing its four gear columns')
        check_gear_sample(first)
        if (abs(first['gear_extension'] - float(start[0])) > 1e-9
                or first['gear_target_down'] != float(start[1])):
            raise ValueError('recording_start_gear disagrees with first sample')
    return {'aux_index': int(index_text), 'recording_start': [float(start[0]), float(start[1])]}


def check_gear_sample(sample: dict) -> None:
    """Enforce bounded state and command values without assuming a gear motion rate."""
    extension, target, command, brake = (sample[key] for key in GEAR_COLUMNS)
    if (not all(_finite_number(value) for value in (extension, target, command, brake))
            or not 0.0 <= extension <= 1.0 or target not in (0.0, 1.0)
            or command not in (0.0, 1.0) or not 0.0 <= brake <= 1.0):
        raise ValueError('invalid retractable gear state or command')


def _check_liquid_metadata(metadata: dict) -> dict | None:
    keys = ('liquid_fuel_model', 'liquid_fuel_schema', 'fuel_consumption_law', 'fuel_store_id',
            'fuel_capacity_kg', 'fuel_unusable_kg', 'fuel_state_index')
    if not any(key in metadata for key in keys):
        return None
    if (metadata.get('liquid_fuel_model') != LIQUID_MODEL
            or metadata.get('liquid_fuel_schema') != LIQUID_SCHEMA
            or metadata.get('fuel_consumption_law') not in LIQUID_LAWS
            or not metadata.get('fuel_store_id')):
        raise ValueError('missing or unsupported finite-liquid store identity')
    try:
        capacity = float(metadata['fuel_capacity_kg'])
        unusable = float(metadata['fuel_unusable_kg'])
        state_index = int(metadata['fuel_state_index'])
        fill = float(metadata['fuel_start_fill'])
        continuous = json.loads(metadata['recording_start_continuous'])
        start_tick = int(metadata['recording_start_tick'])
    except (KeyError, TypeError, ValueError, OverflowError) as error:
        raise ValueError('invalid finite-liquid start metadata') from error
    if (not math.isfinite(capacity) or capacity <= 0.0 or not math.isfinite(unusable)
            or unusable < 0.0 or unusable >= capacity or state_index < 0
            or str(state_index) != metadata['fuel_state_index']
            or str(start_tick) != metadata.get('recording_start_tick')
            or not math.isfinite(fill) or fill < 0.0 or fill > 1.0
            or metadata.get('fuel_start_fill_known') not in ('true', 'false')):
        raise ValueError('finite-liquid store range or continuous index is invalid')
    if metadata.get('propulsion_model') not in ('propeller-shaft-coupled-rk4-v1', 'turbine-rpm-governor-rk4-v1'):
        raise ValueError('finite-liquid trace has an unsupported propulsion model')
    if not isinstance(metadata.get('continuous_layout'), str) \
            or not metadata['continuous_layout'].endswith('; ' + LIQUID_LAYOUT):
        raise ValueError('finite-liquid trace layout suffix is missing')
    if (type(continuous) is not list or len(continuous) != state_index + 2
            or state_index != len(continuous) - 2
            or any(type(value) not in (int, float) or not math.isfinite(float(value)) for value in continuous)):
        raise ValueError('finite-liquid continuous tail does not match its declared index')
    usable, source_latch = continuous[state_index:state_index + 2]
    if (usable < 0.0 or usable > capacity - unusable or source_latch not in (0.0, 1.0)
            or (usable == 0.0 and source_latch != 0.0)):
        raise ValueError('finite-liquid start tail is outside its declared domain')
    if metadata['fuel_start_fill_known'] == 'true' \
            and abs(usable + unusable - fill * capacity) > max(1e-10, capacity * 1e-10):
        raise ValueError('finite-liquid start fill disagrees with its continuous state')
    return {'capacity': capacity, 'unusable': unusable, 'state_index': state_index,
            'usable_start': usable, 'source_start': source_latch}


def check_coupled_metadata(metadata: dict) -> None:
    """Optional model extension shared by calm, wind and atmosphere readers."""
    liquid = _check_liquid_metadata(metadata)
    gear = check_gear_metadata(metadata) if _has_gear_metadata(metadata) else None
    turbine = metadata.get('propulsion_model') == 'turbine-rpm-governor-rk4-v1'
    if turbine or 'turbine_integrator' in metadata:
        wheel_keys = {
            'wheel_state_model', 'wheel_state_layout', 'wheel_profile_status', 'wheel_profile_sha256',
            'wheel_profile_input_sha256', 'wheel_profile_hash_convention', 'wheel_brakes',
            'launch_continuous',
        }
        has_wheel_metadata = any(key in metadata for key in wheel_keys)
        if (not turbine or metadata.get('turbine_integrator') != 'rk4'
                or (metadata.get('metadata_schema') == 'openrc-flight-meta v6' and not has_wheel_metadata)
                or (has_wheel_metadata and gear is None)
                or (gear is not None and not has_wheel_metadata)
                or metadata.get('continuous_layout') != TURBINE_LAYOUT + (
                    '; ' + WHEEL_LAYOUT_SUFFIX if has_wheel_metadata else '') + (
                    '; ' + LIQUID_LAYOUT if liquid is not None else '')
                or any(key in metadata for key in ('shaft_integrator', 'rotor_coupling',
                                                  'electric_configuration'))):
            raise ValueError('missing or unsupported continuous turbine semantics')
        try:
            continuous = json.loads(metadata['recording_start_continuous'])
            aux = json.loads(metadata['recording_start_aux'])
        except (KeyError, ValueError) as error:
            raise ValueError('missing continuous turbine recording state') from error
        wheel = _check_wheel_metadata(metadata, gear=gear is not None, liquid=liquid) if has_wheel_metadata else None
        if (not isinstance(continuous, list) or len(continuous) != (1 + (len(wheel['entries']) if has_wheel_metadata else 0)
                                                                       + (2 if liquid is not None else 0))
                or not _finite_number(continuous[0]) or continuous[0] < 0
                or not isinstance(aux, list) or len(aux) != 4
                or any(not _finite_number(value) for value in aux) or continuous[0] != aux[0]):
            raise ValueError('continuous turbine RPM does not match its endpoint mirror')
        if has_wheel_metadata:
            _check_wheel_continuous(metadata, wheel, shaft=False, turbine=True, liquid=liquid)
        return
    wheel_keys = {
        'wheel_state_model', 'wheel_state_layout', 'wheel_profile_status', 'wheel_profile_sha256',
        'wheel_profile_input_sha256', 'wheel_profile_hash_convention', 'wheel_brakes',
        'launch_continuous',
    }
    has_wheel_metadata = any(key in metadata for key in wheel_keys)
    if has_wheel_metadata:
        wheel = _check_wheel_metadata(metadata, gear=gear is not None, liquid=liquid)
    else:
        if metadata.get('metadata_schema') == 'openrc-flight-meta v6':
            raise ValueError('metadata v6 is missing wheel-state metadata')
        wheel = None

    propulsion_model = metadata.get('propulsion_model')
    shaft_models = {
        'propeller-shaft-coupled-rk4-v1', 'electric-fixed-bus-coupled-stop-v1',
        'electric-ocv-resistance-coupled-events-v1', PACK_LAW,
    }
    has_shaft_fields = any(key in metadata for key in ('shaft_integrator', 'rotor_coupling'))
    shaft = propulsion_model in shaft_models
    if not shaft and not has_shaft_fields:
        if 'recording_start_continuous' in metadata and wheel is None:
            raise ValueError('coupled shaft metadata has the wrong propulsion model')
        if wheel is not None:
            _check_wheel_continuous(metadata, wheel, shaft=False)
        return
    if not shaft or (metadata.get('shaft_integrator') != 'coupled-rk4'
                     or metadata.get('rotor_coupling') != 'relative-spin-locked-inertia-reaction-v1'):
        raise ValueError('missing or unsupported coupled shaft semantics')

    try:
        continuous = json.loads(metadata['recording_start_continuous'])
        aux = json.loads(metadata['recording_start_aux'])
    except (KeyError, ValueError) as error:
        raise ValueError('missing coupled shaft recording state') from error
    layout = metadata.get('continuous_layout')
    battery = layout == BATTERY_LAYOUT or (
        isinstance(layout, str) and layout.startswith(BATTERY_LAYOUT + '; ' + WHEEL_LAYOUT_SUFFIX))
    pack = propulsion_model == PACK_LAW
    slots = pack_slots(metadata) if pack else (3 if battery else 0)
    expected_base = PACK_LAYOUT if pack else BATTERY_LAYOUT if battery else SHAFT_LAYOUT
    expected_tail = ('; ' + WHEEL_LAYOUT_SUFFIX if wheel is not None else '') + (
        '; ' + LIQUID_LAYOUT if liquid is not None else '')
    if wheel is not None:
        expected_layout = expected_base + expected_tail
    else:
        expected_layout = expected_base + ('; ' + LIQUID_LAYOUT if liquid is not None else '')
    if layout != expected_layout:
        raise ValueError('missing or unsupported coupled shaft semantics')
    if (not isinstance(continuous, list) or not continuous or any(not _finite_number(value) for value in continuous)
            or not isinstance(aux, list) or len(aux) != 4
            or not _finite_number(aux[0])):
        raise ValueError('invalid coupled shaft recording state')

    if wheel is None:
        # Legacy shaft traces placed RPM at the end, immediately after any wash states.
        shaft_index = len(continuous) - 1 - slots - (2 if liquid is not None else 0)
    else:
        # The wheel tail is last; shaft RPM precedes optional battery states.
        shaft_index = wheel['first_index'] - slots - 1
    if shaft_index < 0 or continuous[shaft_index] < 0 or abs(continuous[shaft_index] - aux[0]) > 1e-9:
        raise ValueError('continuous shaft RPM disagrees with boundary mirror')
    wash_count = shaft_index
    if (metadata.get('propwash_model') == 'tail-slipstream-axial-transport-v1') != (wash_count > 0):
        raise ValueError('continuous layout disagrees with transported-wash model')
    if wheel is not None:
        _check_wheel_continuous(metadata, wheel, shaft=True, battery=battery, wash_count=wash_count,
                                pack_slots=slots if pack else 0, liquid=liquid)


def _check_wheel_metadata(metadata: dict, *, gear: bool = False, liquid: dict | None = None) -> dict:
    """Validate v6 wheel provenance, contact ordering, and the declared continuous tail."""
    required = {
        'wheel_state_model', 'wheel_state_layout', 'wheel_profile_status', 'wheel_profile_sha256',
        'wheel_profile_input_sha256', 'wheel_profile_hash_convention', 'wheel_brakes',
        'recording_start_continuous', 'launch_continuous',
    }
    supported_schema = metadata.get('metadata_schema') == 'openrc-flight-meta v6' or (
        gear and metadata.get('metadata_schema') in ('openrc-flight-meta v8', 'openrc-flight-meta v9'))
    if not supported_schema or not required.issubset(metadata):
        raise ValueError('incomplete or unsupported wheel-state metadata')
    if metadata.get('wheel_state_model') != WHEEL_STATE_MODEL:
        raise ValueError('unsupported wheel-state model')
    if metadata.get('wheel_profile_status') != 'applied':
        raise ValueError('wheel profile is not applied')
    for key in ('wheel_profile_sha256', 'wheel_profile_input_sha256'):
        if not re.fullmatch(r'[0-9a-f]{64}', metadata.get(key, '')):
            raise ValueError('missing or invalid wheel profile SHA-256')
    if metadata.get('wheel_profile_hash_convention') != WHEEL_PROFILE_HASH_CONVENTION:
        raise ValueError('missing or unsupported wheel profile hash convention')
    try:
        entries = json.loads(metadata['wheel_state_layout'])
        brakes = json.loads(metadata['wheel_brakes'])
    except (TypeError, ValueError) as error:
        raise ValueError('invalid wheel-state metadata JSON') from error
    if type(entries) is not list or not entries:
        raise ValueError('wheel_state_layout must be a nonempty array')
    contacts = []
    indices = []
    for entry in entries:
        if (type(entry) is not dict or set(entry) != {'index', 'contact', 'unit'}
                or type(entry['index']) is not int or entry['index'] < 0
                or type(entry['contact']) is not str or not entry['contact']
                or entry['unit'] != 'm/s rim speed'):
            raise ValueError('invalid wheel_state_layout entry')
        indices.append(entry['index'])
        contacts.append(entry['contact'])
    if indices != list(range(indices[0], indices[0] + len(indices))) or len(set(contacts)) != len(contacts):
        raise ValueError('wheel state indices or contacts are not contiguous and unique')
    if type(brakes) is not list or len(brakes) != len(entries):
        raise ValueError('wheel_brakes does not match wheel contacts')
    for contact, brake in zip(contacts, brakes):
        if (type(brake) is not dict or set(brake) != {'contact', 'availability', 'max_torque_nm'}
                or brake['contact'] != contact or type(brake['availability']) is not str
                or brake['availability'] not in ('available', 'none', 'unspecified')
                or not _finite_number(brake['max_torque_nm']) or brake['max_torque_nm'] < 0
                or (brake['max_torque_nm'] > 0 and brake['availability'] != 'available')):
            raise ValueError('invalid wheel brake metadata')
    layout = metadata.get('continuous_layout')
    expected_suffix = '; ' + WHEEL_LAYOUT_SUFFIX + ('; ' + LIQUID_LAYOUT if liquid is not None else '')
    if (not isinstance(layout, str)
            or (layout != WHEEL_LAYOUT_SUFFIX and not layout.endswith(expected_suffix))):
        raise ValueError('continuous layout is missing the wheel-state tail')
    return {'entries': entries, 'first_index': indices[0], 'contacts': contacts}


def _check_wheel_continuous(metadata: dict, wheel: dict, *, shaft: bool,
                            battery: bool = False, wash_count: int | None = None,
                            turbine: bool = False, pack_slots: int = 0,
                            liquid: dict | None = None) -> None:
    """Check wheel state arrays and ensure all declared wheel slots are the final slots."""
    try:
        continuous = json.loads(metadata['recording_start_continuous'])
        launch = json.loads(metadata['launch_continuous'])
    except (KeyError, ValueError) as error:
        raise ValueError('missing or invalid wheel continuous state') from error
    # Physics checkpoints deliberately discard original launch provenance. The
    # current recording state is still mandatory; do not invent launch rim speeds.
    unknown_launch = (metadata.get('launch_kind') == 'checkpoint_restore'
                      and metadata.get('launch_choice') == 'unknown' and launch == [])
    if (type(continuous) is not list or not continuous or type(launch) is not list
            or (len(launch) != len(continuous) and not unknown_launch)
            or any(not _finite_number(value) for value in continuous + launch)):
        raise ValueError('invalid wheel continuous state')
    entries = wheel['entries']
    first_index = wheel['first_index']
    liquid_slots = 2 if liquid is not None else 0
    if first_index + len(entries) != len(continuous) - liquid_slots:
        raise ValueError('wheel states are not a contiguous continuous-state tail')
    if turbine:
        try:
            aux = json.loads(metadata['recording_start_aux'])
        except (KeyError, ValueError) as error:
            raise ValueError('missing continuous turbine AUX state') from error
        if (metadata.get('continuous_layout') != TURBINE_LAYOUT + '; ' + WHEEL_LAYOUT_SUFFIX + (
                    '; ' + LIQUID_LAYOUT if liquid is not None else '')
                or first_index != 1 or continuous[0] < 0
                or type(aux) is not list or len(aux) != 4
                or any(not _finite_number(value) for value in aux)
                or abs(continuous[0] - aux[0]) > 1e-9):
            raise ValueError('turbine RPM/wheel state tail disagrees with its declared layout')
    elif shaft:
        prefix = PACK_LAYOUT if pack_slots else BATTERY_LAYOUT if battery else SHAFT_LAYOUT
        if metadata.get('continuous_layout') != prefix + '; ' + WHEEL_LAYOUT_SUFFIX + (
                '; ' + LIQUID_LAYOUT if liquid is not None else ''):
            raise ValueError('unsupported wheel continuous-state prefix')
        if wash_count is None or first_index != wash_count + 1 + (pack_slots or (3 if battery else 0)):
            raise ValueError('wheel state tail disagrees with shaft prefix')
    else:
        layout = metadata.get('continuous_layout')
        base_layout = ('none' if layout == WHEEL_LAYOUT_SUFFIX
                       else layout.removesuffix('; ' + WHEEL_LAYOUT_SUFFIX))
        if base_layout not in ('none', WASH_ONLY_LAYOUT):
            raise ValueError('unsupported nonshaft wheel continuous-state prefix')
        expected_wash = first_index
        if base_layout == 'none' and expected_wash != 0:
            raise ValueError('wheel state tail disagrees with empty continuous prefix')
        if base_layout == WASH_ONLY_LAYOUT and expected_wash == 0:
            raise ValueError('wheel state tail disagrees with wash-only prefix')
        if (metadata.get('propwash_model') == 'tail-slipstream-axial-transport-v1') != (expected_wash > 0):
            raise ValueError('continuous layout disagrees with transported-wash model')


def check(path: Path, duration: float, hz: int, *, allow_legacy: bool = False,
          aircraft_input: Path | None = None) -> str:
    if not math.isfinite(duration) or duration <= 0 or hz <= 0:
        raise ValueError("duration and tick rate must be finite and positive")
    handled, projected = project_mass_trace(path, check, duration, hz, allow_legacy=allow_legacy, aircraft_input=aircraft_input)
    if handled:
        return projected
    handled, projected = project_flaps(path, check, duration, hz, allow_legacy=allow_legacy, aircraft_input=aircraft_input)
    if handled:
        return projected
    tick_count = duration * hz
    if not math.isfinite(tick_count) or tick_count >= 2**63:
        raise ValueError("duration exceeds the tick counter")
    expected_ticks = math.floor(tick_count)
    if tick_count - expected_ticks >= 0.5:  # nearest tick; positive half-ties round up
        expected_ticks += 1
    if expected_ticks < 1:
        raise ValueError("duration must round to at least one physics tick")
    lines = path.read_text(encoding="utf-8").splitlines()
    metadata = {}
    for line in lines:
        if line.startswith("# ") and ": " in line:
            key, value = line[2:].split(": ", 1)
            if key in metadata:
                raise ValueError(f"duplicate metadata: {key}")
            metadata[key] = value
    trace_format = metadata.get('format')
    gear = trace_format == 'openrc-trace v10'
    claims_gear = _has_gear_metadata(metadata)
    pack = trace_format == 'openrc-trace v13'
    if trace_format not in ('openrc-trace v3', 'openrc-trace v7', 'openrc-trace v10', 'openrc-trace v13'):
        raise ValueError("expected openrc-trace v3, calm fixed-bus v7, retractable-gear v10 or pack v13")
    if pack != (metadata.get('propulsion_model') == PACK_LAW):
        raise ValueError('trace format disagrees with the pack_ecm electric law')
    if gear != claims_gear:
        raise ValueError('trace format disagrees with retractable gear metadata')
    if gear:
        check_gear_metadata(metadata)
    electric = (trace_format in ('openrc-trace v7', 'openrc-trace v10')
                and metadata.get('propulsion_model') == 'electric-fixed-bus-coupled-stop-v1')
    if ((trace_format == 'openrc-trace v7'
         and metadata.get('propulsion_model') != 'electric-fixed-bus-coupled-stop-v1')
            or (trace_format == 'openrc-trace v3'
                and metadata.get('propulsion_model') == 'electric-fixed-bus-coupled-stop-v1')):
        raise ValueError('trace format disagrees with the fixed-bus electric law')
    columns = COLUMNS + (ELECTRIC_COLUMNS if electric or pack else []) + (PACK_COLUMNS if pack else []) \
        + (GEAR_COLUMNS if gear else [])
    try:
        dt = float(metadata["dt_s"])
    except (KeyError, ValueError) as error:
        raise ValueError("missing or invalid dt_s") from error
    if not math.isfinite(dt) or not math.isclose(dt, 1 / hz, rel_tol=1e-6, abs_tol=0):
        raise ValueError("dt_s does not match the requested tick rate")
    rows = list(csv.reader(line for line in lines if not line.startswith("#")))
    if not rows or rows[0] != columns:
        raise ValueError("missing or unexpected trace columns")
    if len(rows) - 1 != expected_ticks + 1:
        raise ValueError(f"expected {expected_ticks + 1} samples, got {len(rows) - 1}")
    data = []
    for index, row in enumerate(rows[1:]):
        if len(row) != len(columns):
            raise ValueError(f"sample {index}: wrong column count")
        try:
            values = [float(cell) for cell in row]
        except ValueError as error:
            raise ValueError(f"sample {index}: nonnumeric value") from error
        if not all(math.isfinite(value) for value in values):
            raise ValueError(f"sample {index}: non-finite value")
        sample = dict(zip(columns, values))
        if sample["tick"] != index:
            raise ValueError(f"sample {index}: discontinuous tick")
        if abs(sample["t_s"] - index / hz) > TIME_TOLERANCE:
            raise ValueError(f"sample {index}: wrong elapsed time")
        if electric:
            check_fixed_bus_sample(metadata, sample)
        if pack:
            budget = data[0]['remaining_charge_c'] + data[0]['consumed_charge_c'] if data else \
                sample['remaining_charge_c'] + sample['consumed_charge_c']
            check_pack_sample(sample, budget)
        if gear:
            check_gear_sample(sample)
        data.append(sample)
    first, last = data[0], data[-1]
    identity = check_input_identity(metadata, allow_legacy, aircraft_input)
    check_metadata(metadata, first)
    if gear:
        check_gear_metadata(metadata, first)
    rpm_tolerance = 1.0
    if pack:
        # A finite pack sags while its polarization builds from rest: the shaft follows d·V, so allow the RPM
        # change the recorded bus-voltage change explains (Kv · duty · ΔV) on top of the trimmed-flight 1 rpm.
        kv = json.loads(metadata['electric_configuration'])['motor']['kv_rpm_per_volt']
        rpm_tolerance += kv * first['esc_effective_duty'] * abs(last['bus_voltage_v'] - first['bus_voltage_v'])
    for key, tolerance in (("speed_mps", .01), ("pitch_deg", .05), ("alt_m", .05), ("engine_rpm", rpm_tolerance)):
        if abs(last[key] - first[key]) > tolerance:
            raise ValueError(f"{key} drifts {first[key]:.6f} -> {last[key]:.6f}")
    if not .05 < first["cmd_throttle"] < .95 or first["engine_rpm"] < 3000:
        raise ValueError("engine not at a trimmed setting")
    if abs(first["cmd_pitch"]) < 1e-6:
        raise ValueError("no elevator trim applied")
    ground = metadata.get("ground", "")
    if not ground:
        raise ValueError("no ground metadata")
    if "spring-damper" in ground and "field '" not in ground:
        raise ValueError("gear without the field's surfaces")
    return (f"trimmed level flight: {expected_ticks} ticks, {last['t_s']:.9f} s, all samples finite; "
            f"alt {first['alt_m']:.3f} -> {last['alt_m']:.3f} m, speed {last['speed_mps']:.4f} m/s; {identity}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("trace", type=Path)
    parser.add_argument("--duration", type=float, default=3.0, help="requested flight seconds (default: 3)")
    parser.add_argument("--hz", type=int, default=240, help="requested physics ticks/s (default: 240)")
    parser.add_argument("--aircraft-input", type=Path, help="verify the recorded SHA-256 against this exact input file")
    parser.add_argument("--allow-legacy-metadata", action="store_true",
                        help="allow C7-R2 metadata v1 for archival checks; cannot verify exact input bytes")
    args = parser.parse_args()
    try:
        print(check(args.trace, args.duration, args.hz, allow_legacy=args.allow_legacy_metadata,
                    aircraft_input=args.aircraft_input))
    except (OSError, UnicodeError, ValueError, csv.Error) as error:
        print(f"FAIL {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
