"""Validate the optional v12 flap suffix before reusing the base flight verifier."""
import csv
import io
import json
import math
from pathlib import Path
import tempfile

COLUMNS = ['cmd_flaps', 'flap_fraction', 'flap_deg']
LAW = 'controls.flaps.hinged_trailing_edge.v1'


def project(path, validator, *args, **kwargs):
    """Return (handled, result); original CSV and its identities remain untouched."""
    metadata, lines = {}, []
    for line in Path(path).read_text(encoding='utf-8').splitlines():
        if line.startswith('# '):
            key, separator, value = line[2:].partition(': ')
            if not separator or key in metadata:
                raise ValueError('malformed or duplicate trace metadata')
            metadata[key] = value
        elif line.startswith('#'):
            raise ValueError('malformed trace comment')
        elif line:
            lines.append(line)
    claimed = any(k.startswith('flap_') or k == 'recording_start_flap' for k in metadata)
    if metadata.get('format') != 'openrc-trace v12':
        if claimed or metadata.get('metadata_schema') == 'openrc-flight-meta v9':
            raise ValueError('flap metadata requires trace v12')
        return False, None
    if (metadata.get('metadata_schema') != 'openrc-flight-meta v9'
            or metadata.get('flap_law') != LAW
            or metadata.get('flap_trace_schema') != 'openrc-flap-trace v1'):
        raise ValueError('missing or unsupported flap contract')
    base_format = metadata.get('flap_base_trace_format')
    base_schema = metadata.get('flap_base_metadata_schema')
    if (base_format not in {f'openrc-trace v{i}' for i in range(3, 12)}
            or base_schema not in {f'openrc-flight-meta v{i}' for i in range(2, 9)}):
        raise ValueError('invalid flap base trace contract')
    try:
        aux_index = int(metadata['flap_aux_index'])
        input_index = int(metadata['flap_input_index'])
        maximum = float(metadata['flap_max_angle_deg'])
        initial = float(metadata['recording_start_flap'])
        layout = json.loads(metadata['input_layout'])
        gear_aux = int(metadata['gear_aux_index']) if 'gear_law' in metadata else None
        turbulence_aux = int(metadata['turbulence_aux_index']) if 'turbulence_aux_index' in metadata else None
    except (KeyError, ValueError, TypeError) as error:
        raise ValueError('invalid flap metadata') from error
    gear = 'gear_law' in metadata
    expected = ['roll', 'pitch', 'yaw', 'throttle']
    if gear:
        expected += ['gear_down', 'wheel_brake']
    if (layout != expected + ['flaps'] or input_index != len(expected)
            or aux_index < 4 or not math.isfinite(maximum) or not 0 < maximum <= 90
            or not math.isfinite(initial) or not 0 <= initial <= 1):
        raise ValueError('invalid flap layout or start state')
    if gear and (base_schema != 'openrc-flight-meta v8'
                 or aux_index != gear_aux + 2):
        raise ValueError('flap state must follow the complete gear pair')
    if turbulence_aux is not None:
        if turbulence_aux != aux_index + 1:
            raise ValueError('turbulence must follow the flap state')
    reader = csv.DictReader(lines)
    columns = reader.fieldnames or []
    if columns[-3:] != COLUMNS or len(columns) != len(set(columns)):
        raise ValueError('missing, duplicated or displaced flap columns')
    rows = list(reader)
    if not rows:
        raise ValueError('empty flap trace')
    for index, row in enumerate(rows):
        if None in row or any(v is None for v in row.values()):
            raise ValueError('malformed flap row')
        try:
            command, actual, degrees = (float(row[k]) for k in COLUMNS)
        except (ValueError, TypeError) as error:
            raise ValueError('nonnumeric flap state') from error
        if (not all(math.isfinite(v) for v in (command, actual, degrees))
                or not 0 <= command <= 1 or not 0 <= actual <= 1
                or abs(degrees - actual * maximum) > 6e-8):
            raise ValueError('invalid flap command or actual angle')
        if index == 0 and abs(actual - initial) > 1e-9:
            raise ValueError('flap recording-start mismatch')
    projected = {k: v for k, v in metadata.items()
                 if not k.startswith('flap_') and k != 'recording_start_flap'}
    projected['format'] = base_format
    projected['metadata_schema'] = base_schema
    projected['input_layout'] = json.dumps(expected)
    if 'turbulence_aux_index' in projected:
        projected['turbulence_aux_index'] = str(int(projected['turbulence_aux_index']) - 1)
    output = io.StringIO()
    for key, value in projected.items():
        output.write(f'# {key}: {value}\n')
    writer = csv.DictWriter(output, fieldnames=columns[:-3], extrasaction='ignore', lineterminator='\n')
    writer.writeheader()
    writer.writerows(rows)
    with tempfile.TemporaryDirectory(prefix='openrc-flap-trace-') as directory:
        compatible = Path(directory) / 'base.csv'
        compatible.write_text(output.getvalue(), encoding='utf-8')
        result = validator(compatible, *args, **kwargs)
    if isinstance(result, dict):
        result.update(format=metadata['format'], metadata_schema=metadata['metadata_schema'],
                      flap_law=LAW, flap_samples=len(rows))
        if 'columns' in result:
            result['columns'] = columns
    return True, result
