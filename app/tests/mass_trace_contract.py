"""Validate and project accepted mass/CG and finite-liquid trace suffixes."""
import csv
import io
import json
import math
from pathlib import Path
import re
import tempfile

FORMAT = 'openrc-trace v14'
LIQUID_FORMAT = 'openrc-trace v15'
SCHEMA = 'openrc-mass-sample v1'
SAMPLE_TIMING = 'accepted mass_properties sample for this row tick/time'
COLUMNS = ['mass_kg', 'cg_body_x_m', 'cg_body_y_m', 'cg_body_z_m']
LIQUID_SCHEMA = 'openrc-liquid-fuel-trace v1'
LIQUID_COLUMNS = ['fuel_remaining_kg', 'fuel_usable_kg', 'fuel_fill_fraction',
                  'fuel_reserve_fraction', 'fuel_source_latch']
LIQUID_MODEL = 'single-store-finite-liquid-fixed-datum-v1'
LIQUID_FUEL_SCHEMA = 'openrc-liquid-fuel v1'
LIQUID_LAYOUT = 'base propulsion/wheels; usable fuel kg; source latch 0/1'
LIQUID_LAWS = {'gasoline_bsfc_v1', 'turbine_map_v1'}
BASE_FORMATS = {f'openrc-trace v{version}' for version in range(3, 14)}


def _parts(path):
    metadata, data_lines = {}, []
    for line in Path(path).read_text(encoding='utf-8').splitlines():
        if line.startswith('# '):
            key, separator, value = line[2:].partition(': ')
            if not separator or not key or key in metadata:
                raise ValueError('malformed or duplicate trace metadata')
            metadata[key] = value
        elif line.startswith('#'):
            raise ValueError('malformed trace comment')
        elif line:
            data_lines.append(line)
    return metadata, data_lines


def _bool_metadata(metadata, key):
    value = metadata.get(key)
    if value not in ('true', 'false'):
        raise ValueError(f'invalid {key} metadata')
    return value == 'true'


def _validate_liquid_metadata(metadata):
    if (metadata.get('liquid_fuel_trace_schema') != LIQUID_SCHEMA
            or metadata.get('liquid_fuel_model') != LIQUID_MODEL
            or metadata.get('liquid_fuel_schema') != LIQUID_FUEL_SCHEMA
            or metadata.get('fuel_consumption_law') not in LIQUID_LAWS):
        raise ValueError('missing or unsupported finite-liquid trace identity')
    if (not metadata.get('fuel_store_id') or not metadata.get('fuel_blend')
            or not metadata.get('fuel_family')
            or not math.isfinite(float(metadata.get('fuel_density_kg_m3', 'nan')))
            or not math.isfinite(float(metadata.get('fuel_reserve_fraction', 'nan')))):
        raise ValueError('incomplete finite-liquid store identity')
    if not re.fullmatch(r'[0-9a-f]{64}', metadata.get('fuel_registry_sha256', '')):
        raise ValueError('missing or invalid finite-liquid registry SHA-256')
    try:
        capacity = float(metadata['fuel_capacity_kg'])
        unusable = float(metadata['fuel_unusable_kg'])
        density = float(metadata['fuel_density_kg_m3'])
        reserve = float(metadata['fuel_reserve_fraction'])
        state_index = int(metadata['fuel_state_index'])
        fill = float(metadata['fuel_start_fill'])
        start_tick = int(metadata['recording_start_tick'])
        continuous = json.loads(metadata['recording_start_continuous'])
        start_known = _bool_metadata(metadata, 'fuel_start_fill_known')
        reserve_estimated = _bool_metadata(metadata, 'fuel_reserve_estimated')
    except (KeyError, TypeError, ValueError, OverflowError) as error:
        raise ValueError('invalid finite-liquid start metadata') from error
    if (not all(math.isfinite(value) for value in (capacity, unusable, density, reserve, fill))
            or capacity <= 0.0 or unusable < 0.0 or unusable >= capacity or density <= 0.0
            or reserve < unusable / capacity or reserve > 1.0 or fill < 0.0 or fill > 1.0
            or state_index < 0 or start_tick < 0 or str(state_index) != metadata['fuel_state_index']
            or str(start_tick) != metadata['recording_start_tick']):
        raise ValueError('finite-liquid store range or start index is invalid')
    if metadata.get('fuel_reserve_basis') != ('estimated reserve' if reserve_estimated else 'authored reserve'):
        raise ValueError('finite-liquid reserve provenance disagrees')
    if metadata.get('propulsion_model') not in ('propeller-shaft-coupled-rk4-v1', 'turbine-rpm-governor-rk4-v1'):
        raise ValueError('finite-liquid trace has an unsupported propulsion model')
    if not metadata.get('continuous_layout', '').endswith('; ' + LIQUID_LAYOUT):
        raise ValueError('finite-liquid trace layout suffix is missing')
    if (type(continuous) is not list or len(continuous) != state_index + 2
            or state_index != len(continuous) - 2
            or any(type(value) not in (int, float) or not math.isfinite(float(value)) for value in continuous)):
        raise ValueError('finite-liquid continuous tail does not match its declared index')
    usable, source_latch = continuous[state_index:state_index + 2]
    if (usable < 0.0 or usable > capacity - unusable or source_latch not in (0.0, 1.0)
            or (usable == 0.0 and source_latch != 0.0)):
        raise ValueError('finite-liquid start tail is outside its declared domain')
    # The selected fill controls a future reset. A mid-flight recording carries
    # its current inventory in the first row, so only tick-zero traces can compare
    # that inventory directly with the selected launch fill.
    if start_known and start_tick == 0 and abs(usable + unusable - fill * capacity) > max(1e-10, capacity * 1e-10):
        raise ValueError('finite-liquid start fill disagrees with its continuous state')
    return {
        'capacity': capacity, 'unusable': unusable, 'reserve': reserve, 'state_index': state_index,
        'usable_start': float(usable), 'source_start': float(source_latch), 'fill': fill,
        'start_tick': start_tick, 'start_known': start_known,
    }


def _validate_liquid_rows(metadata, rows, dt):
    identity = _validate_liquid_metadata(metadata)
    capacity, unusable = identity['capacity'], identity['unusable']
    tolerance = max(2e-8, capacity * 2e-8)
    previous_remaining = None
    for index, row in enumerate(rows):
        try:
            tick = float(row['tick'])
            time_s = float(row['t_s'])
            remaining = float(row['fuel_remaining_kg'])
            usable = float(row['fuel_usable_kg'])
            fill = float(row['fuel_fill_fraction'])
            reserve = float(row['fuel_reserve_fraction'])
            source_latch = float(row['fuel_source_latch'])
        except (KeyError, TypeError, ValueError) as error:
            raise ValueError('nonnumeric finite-liquid sample') from error
        if (not all(math.isfinite(value) for value in (tick, time_s, remaining, usable, fill, reserve, source_latch))
                or tick < 0 or tick != int(tick) or abs(time_s - tick * dt) > 1e-8
                or remaining < unusable - tolerance or remaining > capacity + tolerance
                or usable < -tolerance or usable > capacity - unusable + tolerance
                or abs(remaining - usable - unusable) > tolerance
                or abs(fill - remaining / capacity) > 2e-8
                or abs(reserve - identity['reserve']) > 2e-8
                or source_latch not in (0.0, 1.0)
                or (usable <= tolerance and source_latch != 0.0)):
            raise ValueError('invalid accepted finite-liquid sample')
        if index == 0:
            if tick != identity['start_tick'] or abs(usable - identity['usable_start']) > tolerance \
                    or source_latch != identity['source_start']:
                raise ValueError('finite-liquid first sample disagrees with recording start state')
            if identity['start_known'] and identity['start_tick'] == 0 and abs(fill - identity['fill']) > 2e-8:
                raise ValueError('finite-liquid first fill disagrees with selected launch fill')
        else:
            if tick != float(rows[index - 1]['tick']) + 1.0:
                raise ValueError('noncontinuous finite-liquid trace ticks')
            if remaining > previous_remaining + tolerance:
                raise ValueError('finite-liquid trace inventory increased without a reset')
        previous_remaining = remaining


def project(path, validator, *args, **kwargs):
    """Validate v14/v15 mass channels and pass an unchanged v3-v13 projection to `validator`.

    The source artifact is never rewritten. `validator` keeps ownership of its existing trace-family
        equations and version contract; this wrapper verifies the v14/v15 extension before projecting it away.
    """
    metadata, data_lines = _parts(path)
    trace_format = metadata.get('format')
    claimed_mass = any(key in metadata for key in ('mass_trace_schema', 'mass_base_trace_format', 'mass_sample_timing'))
    claimed_liquid_trace = 'liquid_fuel_trace_schema' in metadata
    claimed_liquid_model = any(key in metadata for key in (
        'liquid_fuel_model', 'liquid_fuel_schema', 'fuel_consumption_law', 'fuel_store_id',
        'fuel_state_index', 'fuel_capacity_kg', 'fuel_unusable_kg', 'fuel_registry_sha256',
        'fuel_blend', 'fuel_family', 'fuel_density_kg_m3', 'fuel_reserve_fraction',
        'fuel_reserve_basis', 'fuel_reserve_estimated', 'fuel_start_fill', 'fuel_start_fill_known'))
    if trace_format not in (FORMAT, LIQUID_FORMAT):
        if claimed_mass or claimed_liquid_trace:
            raise ValueError('accepted mass/liquid trace metadata requires openrc-trace v14 or v15')
        return False, None
    has_liquid = trace_format == LIQUID_FORMAT
    if has_liquid != claimed_liquid_trace or (not has_liquid and claimed_liquid_model):
        raise ValueError('finite-liquid trace claims require openrc-trace v15')
    if (metadata.get('mass_trace_schema') != SCHEMA
            or metadata.get('mass_sample_timing') != SAMPLE_TIMING):
        raise ValueError('missing or unsupported accepted mass trace contract')
    base_format = metadata.get('mass_base_trace_format')
    if base_format not in BASE_FORMATS:
        raise ValueError('invalid mass trace base format')
    if not data_lines:
        raise ValueError('empty mass trace')
    reader = csv.DictReader(data_lines)
    columns = reader.fieldnames or []
    suffix = LIQUID_COLUMNS + COLUMNS if has_liquid else COLUMNS
    if columns[-len(suffix):] != suffix or len(columns) != len(set(columns)):
        raise ValueError('missing, duplicated or displaced mass/CG columns')
    rows = list(reader)
    if not rows:
        raise ValueError('empty mass trace')
    try:
        dt = float(metadata['dt_s'])
    except (KeyError, TypeError, ValueError) as error:
        raise ValueError('mass trace is missing dt_s') from error
    if not math.isfinite(dt) or dt <= 0.0:
        raise ValueError('invalid mass trace timestep')
    if has_liquid:
        _validate_liquid_metadata(metadata)
        _validate_liquid_rows(metadata, rows, dt)
    for index, row in enumerate(rows):
        if None in row or any(value is None for value in row.values()):
            raise ValueError('malformed mass trace row')
        try:
            tick = float(row['tick'])
            time_s = float(row['t_s'])
            mass = float(row['mass_kg'])
            cg = [float(row[column]) for column in COLUMNS[1:]]
        except (KeyError, TypeError, ValueError) as error:
            raise ValueError('nonnumeric mass/CG sample') from error
        if not all(math.isfinite(value) for value in [tick, time_s, mass, *cg]):
            raise ValueError('non-finite accepted mass/CG sample')
        if (tick < 0 or tick != int(tick) or mass <= 0.0
                or abs(time_s - tick * dt) > 1e-8):
            raise ValueError('invalid accepted mass/CG sample')
        if index and tick != float(rows[index - 1]['tick']) + 1.0:
            raise ValueError('noncontinuous mass trace ticks')

    removed = {'mass_trace_schema', 'mass_base_trace_format', 'mass_sample_timing', 'liquid_fuel_trace_schema'}
    projected = {key: value for key, value in metadata.items() if key not in removed}
    projected['format'] = base_format
    output = io.StringIO()
    for key, value in projected.items():
        output.write(f'# {key}: {value}\n')
    base_columns = columns[:-len(suffix)]
    writer = csv.DictWriter(output, fieldnames=base_columns, extrasaction='ignore', lineterminator='\n')
    writer.writeheader()
    writer.writerows(rows)
    with tempfile.TemporaryDirectory(prefix='openrc-mass-trace-') as directory:
        compatible = Path(directory) / 'base.csv'
        compatible.write_text(output.getvalue(), encoding='utf-8')
        result = validator(compatible, *args, **kwargs)
    if isinstance(result, dict):
        result.update(format=trace_format, mass_trace_schema=SCHEMA,
                      mass_base_trace_format=base_format, mass_samples=len(rows))
        if has_liquid:
            result.update(liquid_fuel_trace_schema=LIQUID_SCHEMA,
                          fuel_samples=len(rows), fuel_store_id=metadata['fuel_store_id'])
        if 'columns' in result:
            result['columns'] = columns
    return True, result
