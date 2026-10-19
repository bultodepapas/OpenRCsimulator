"""Validate and project the optional openrc-trace v14 accepted mass/CG suffix."""
import csv
import io
import math
from pathlib import Path
import tempfile

FORMAT = 'openrc-trace v14'
SCHEMA = 'openrc-mass-sample v1'
SAMPLE_TIMING = 'accepted mass_properties sample for this row tick/time'
COLUMNS = ['mass_kg', 'cg_body_x_m', 'cg_body_y_m', 'cg_body_z_m']
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


def project(path, validator, *args, **kwargs):
    """Validate v14 mass channels and pass an unchanged v3-v13 projection to `validator`.

    The source artifact is never rewritten. `validator` keeps ownership of its existing trace-family
    equations and version contract; this wrapper verifies the v14 extension before projecting it away.
    """
    metadata, data_lines = _parts(path)
    claimed = any(key in metadata for key in ('mass_trace_schema', 'mass_base_trace_format', 'mass_sample_timing'))
    if metadata.get('format') != FORMAT:
        if claimed:
            raise ValueError('mass trace metadata requires openrc-trace v14')
        return False, None
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
    if columns[-len(COLUMNS):] != COLUMNS or len(columns) != len(set(columns)):
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
        if (not all(math.isfinite(value) for value in [tick, time_s, mass, *cg])
                or tick < 0 or tick != int(tick) or mass <= 0.0
                or abs(time_s - tick * dt) > 1e-8):
            raise ValueError('invalid accepted mass/CG sample')
        if index and tick != float(rows[index - 1]['tick']) + 1.0:
            raise ValueError('noncontinuous mass trace ticks')

    projected = {key: value for key, value in metadata.items()
                 if key not in ('mass_trace_schema', 'mass_base_trace_format', 'mass_sample_timing')}
    projected['format'] = base_format
    output = io.StringIO()
    for key, value in projected.items():
        output.write(f'# {key}: {value}\n')
    base_columns = columns[:-len(COLUMNS)]
    writer = csv.DictWriter(output, fieldnames=base_columns, extrasaction='ignore', lineterminator='\n')
    writer.writeheader()
    writer.writerows(rows)
    with tempfile.TemporaryDirectory(prefix='openrc-mass-trace-') as directory:
        compatible = Path(directory) / 'base.csv'
        compatible.write_text(output.getvalue(), encoding='utf-8')
        result = validator(compatible, *args, **kwargs)
    if isinstance(result, dict):
        result.update(format=FORMAT, mass_trace_schema=SCHEMA, mass_samples=len(rows))
        if 'columns' in result:
            result['columns'] = columns
    return True, result
