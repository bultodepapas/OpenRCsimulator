"""Verify a complete, finite, trimmed app flight against an externally requested duration.

Defaults match the three-second, 240 Hz smoke flight. Capture/export callers pass
--duration explicitly. The initial tick is a sample, not evidence of a flown tick.
"""
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
# Trace v3 prints time to nine decimal places. Allow rounding, not a missing tick.
TIME_TOLERANCE = 1e-9
STATE_LAYOUT = 'north_m east_m down_m u_mps v_mps w_mps qw qx qy qz p_radps q_radps r_radps'.split()
AUX_LAYOUT = 'engine_rpm srv_roll srv_pitch srv_yaw'.split()
SEMANTIC_HASH_CONVENTION = ('sha256 of Godot JSON.stringify(parsed_input, indent=empty, '
                            'sort_keys=true, full_precision=false); not file bytes')
INPUT_HASH_CONVENTION = 'sha256 of exact aircraft input file bytes'


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
    elif schema == 'openrc-flight-meta v2':
        if any(key in metadata for key in ('aircraft_data_sha256', 'aircraft_data_hash_convention')):
            raise ValueError('metadata v2 must use explicit input/semantic hash names')
        if metadata.get('aircraft_input_format') != 'openrc-aircraft v1':
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
        'aero_model': ('global-derivatives-v1', 'local-surfaces-v1 with bounded attached oracle'),
        'propulsion_model': ('propeller-rpm-lag-v1', 'propeller-shaft-balance-v1', 'turbine-ecu-spool-v1', 'propeller-shaft-coupled-rk4-v1'),
        'propwash_model': ('none', 'tail-slipstream-increment-v1', 'tail-slipstream-axial-transport-v1'),
    }.items():
        if metadata.get(key) not in allowed:
            raise ValueError(f'missing or unsupported {key}')
    turbine = metadata['propulsion_model'] == 'turbine-ecu-spool-v1'
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
    if not isinstance(aux, list) or len(aux) != len(AUX_LAYOUT) or any(
        type(value) not in (int, float) or not math.isfinite(value) for value in aux
    ):
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


def check_coupled_metadata(metadata: dict) -> None:
    """Optional model extension shared by calm, wind and atmosphere readers."""
    if metadata.get('propulsion_model') != 'propeller-shaft-coupled-rk4-v1':
        if any(key in metadata for key in ('shaft_integrator', 'rotor_coupling', 'recording_start_continuous')):
            raise ValueError('coupled shaft metadata has the wrong propulsion model')
        return
    if (metadata.get('shaft_integrator') != 'coupled-rk4'
            or metadata.get('rotor_coupling') != 'relative-spin-locked-inertia-reaction-v1'
            or metadata.get('continuous_layout') != 'axial wash increment m/s, slipstream.pieces order, then propeller shaft rpm; RK4 coupled'):
        raise ValueError('missing or unsupported coupled shaft semantics')
    try:
        continuous = json.loads(metadata['recording_start_continuous'])
        aux = json.loads(metadata['recording_start_aux'])
    except (KeyError, ValueError) as error:
        raise ValueError('missing coupled shaft recording state') from error
    if (not isinstance(continuous, list) or not continuous or any(
            type(value) not in (int, float) or not math.isfinite(value) for value in continuous)
            or continuous[-1] < 0
            or not isinstance(aux, list) or len(aux) != 4
            or type(aux[0]) not in (int, float) or not math.isfinite(aux[0])
            or abs(continuous[-1] - aux[0]) > 1e-9):
        raise ValueError('continuous shaft RPM disagrees with boundary mirror')
    if (metadata.get('propwash_model') == 'tail-slipstream-axial-transport-v1') != (len(continuous) > 1):
        raise ValueError('continuous layout disagrees with transported-wash model')


def check(path: Path, duration: float, hz: int, *, allow_legacy: bool = False,
          aircraft_input: Path | None = None) -> str:
    if not math.isfinite(duration) or duration <= 0 or hz <= 0:
        raise ValueError("duration and tick rate must be finite and positive")
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
    if metadata.get("format") != "openrc-trace v3":
        raise ValueError("expected openrc-trace v3")
    try:
        dt = float(metadata["dt_s"])
    except (KeyError, ValueError) as error:
        raise ValueError("missing or invalid dt_s") from error
    if not math.isfinite(dt) or not math.isclose(dt, 1 / hz, rel_tol=1e-6, abs_tol=0):
        raise ValueError("dt_s does not match the requested tick rate")
    rows = list(csv.reader(line for line in lines if not line.startswith("#")))
    if not rows or rows[0] != COLUMNS:
        raise ValueError("missing or unexpected trace columns")
    if len(rows) - 1 != expected_ticks + 1:
        raise ValueError(f"expected {expected_ticks + 1} samples, got {len(rows) - 1}")
    data = []
    for index, row in enumerate(rows[1:]):
        if len(row) != len(COLUMNS):
            raise ValueError(f"sample {index}: wrong column count")
        try:
            values = [float(cell) for cell in row]
        except ValueError as error:
            raise ValueError(f"sample {index}: nonnumeric value") from error
        if not all(math.isfinite(value) for value in values):
            raise ValueError(f"sample {index}: non-finite value")
        sample = dict(zip(COLUMNS, values))
        if sample["tick"] != index:
            raise ValueError(f"sample {index}: discontinuous tick")
        if abs(sample["t_s"] - index / hz) > TIME_TOLERANCE:
            raise ValueError(f"sample {index}: wrong elapsed time")
        data.append(sample)
    first, last = data[0], data[-1]
    identity = check_input_identity(metadata, allow_legacy, aircraft_input)
    check_metadata(metadata, first)
    for key, tolerance in (("speed_mps", .01), ("pitch_deg", .05), ("alt_m", .05), ("engine_rpm", 1.0)):
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
