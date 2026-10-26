"""Focused v17 role/shape inspector; deliberately performs no force-law validation.

Existing physical trace validators must continue refusing v17 until their
equations include the shared brake. This helper never projects away braking.
"""
import csv
import json
import math
from pathlib import Path

LAW = 'fixed-gear-shared-wheel-brake-input-v1'
BASES = {f'openrc-trace v{i}' for i in range(3, 17)} - {'openrc-trace v10'}


def inspect(path):
    metadata, lines = {}, []
    for line in Path(path).read_text(encoding='utf-8').splitlines():
        if line.startswith('# '):
            key, sep, value = line[2:].partition(': ')
            if not sep or key in metadata:
                raise ValueError('malformed/duplicate metadata')
            metadata[key] = value
        elif line.startswith('#'):
            raise ValueError('malformed comment')
        elif line:
            lines.append(line)
    if metadata.get('format') != 'openrc-trace v17':
        raise ValueError('expected explicit fixed-brake v17')
    if (metadata.get('fixed_brake_input_law') != LAW
            or metadata.get('fixed_brake_base_trace_format') not in BASES
            or metadata.get('wheel_brake_input_index') != '4'):
        raise ValueError('invalid fixed-brake identity/base/index')
    if any(key in metadata for key in ('gear_law', 'gear_aux_index', 'gear_trace_schema', 'recording_start_gear')):
        raise ValueError('mixed fixed/retractable roles')
    expected = ['roll', 'pitch', 'yaw', 'throttle', 'wheel_brake']
    flap_claim = any(k.startswith('flap_') or k == 'recording_start_flap' for k in metadata)
    if flap_claim:
        expected.append('flaps')
        if metadata.get('flap_input_index') != '5':
            raise ValueError('fixed brake flap input must be 5')
    try:
        if len(metadata['input_layout']) > 256:
            raise ValueError('oversized role layout')
        layout = json.loads(metadata['input_layout'])
    except (KeyError, ValueError) as error:
        raise ValueError('invalid named input layout') from error
    if layout != expected or any(type(value) is not str for value in layout):
        raise ValueError('ambiguous named input roles')
    base = metadata['fixed_brake_base_trace_format']
    if base == 'openrc-trace v16' and metadata.get('spatial_base_trace_format') not in BASES - {'openrc-trace v16'}:
        raise ValueError('unsupported spatial base')
    if base in ('openrc-trace v14', 'openrc-trace v15'):
        if metadata.get('mass_base_trace_format') not in BASES - {'openrc-trace v14', 'openrc-trace v15', 'openrc-trace v16'}:
            raise ValueError('unsupported mass base')
    reader = csv.DictReader(lines)
    columns = reader.fieldnames or []
    if (not columns or len(columns) != len(set(columns)) or columns.count('cmd_wheel_brake') != 1
            or any(key in columns for key in ('cmd_gear_down', 'gear_extension', 'gear_target_down'))):
        raise ValueError('missing/duplicate/mixed brake columns')
    if ('cmd_flaps' in columns) != flap_claim:
        raise ValueError('flap claim/column mismatch')
    rows = list(reader)
    if not rows:
        raise ValueError('empty trace')
    previous = None
    for row in rows:
        if None in row or any(value is None for value in row.values()):
            raise ValueError('malformed row width')
        try:
            values = {key: float(value) for key, value in row.items()}
        except (ValueError, TypeError) as error:
            raise ValueError('nonnumeric sample') from error
        if not all(math.isfinite(value) for value in values.values()):
            raise ValueError('nonfinite sample')
        if not 0 <= values['cmd_wheel_brake'] <= 1:
            raise ValueError('brake fraction out of range')
        tick = values.get('tick')
        if tick is None or tick < 0 or tick != math.floor(tick) or (previous is not None and tick != previous + 1):
            raise ValueError('noncontiguous accepted ticks')
        previous = tick
    return dict(format='openrc-trace v17', base_format=base, input_names=layout,
                columns=columns, rows=len(rows), physics_validation_available=False)
