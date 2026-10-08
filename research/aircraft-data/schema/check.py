#!/usr/bin/env python3
"""DATA-4a: offline structural preflight; Godot remains the physics authority."""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import sys

from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parents[3]
SCHEMA = ROOT / 'app/data/schema/openrc-aircraft-v1.schema.json'
FLEET = ROOT / 'app/data/aircraft'


def reject_constant(value: str):
    raise ValueError(f'non-JSON numeric constant: {value}')


def finite_float(value: str) -> float:
    number = float(value)
    if not math.isfinite(number):
        raise ValueError(f'number exceeds finite float64 range: {value}')
    return number


def finite_int(value: str) -> int:
    finite_float(value)
    return int(value)


def read_json(path: Path):
    # NaN and infinities are not JSON numbers. Exponents can also overflow the
    # runtime's float64 domain even when their JSON syntax is valid.
    return json.loads(path.read_text(encoding='utf-8'),
                      parse_constant=reject_constant, parse_float=finite_float,
                      parse_int=finite_int)


def validator(schema_path: Path = SCHEMA) -> Draft202012Validator:
    schema = read_json(schema_path)
    Draft202012Validator.check_schema(schema)
    return Draft202012Validator(schema)


def pointer(parts) -> str:
    return '/' + '/'.join(str(p).replace('~', '~0').replace('/', '~1') for p in parts)


def problems(data, contract: Draft202012Validator) -> list[str]:
    return sorted(f'{pointer(error.absolute_path)}: {error.message}'
                  for error in contract.iter_errors(data))


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('files', type=Path, nargs='*', help='default: every fleet aircraft JSON')
    args = parser.parse_args(argv)
    contract = validator()
    files = args.files or sorted(FLEET.glob('*.json'))
    if not files:
        parser.error('no aircraft files found')
    failed = 0
    for path in files:
        try:
            errors = problems(read_json(path), contract)
        except (OSError, ValueError) as error:
            errors = [str(error)]
        if errors:
            failed += 1
            for error in errors:
                print(f'{path}: {error}', file=sys.stderr)
        else:
            print(f'PASS {path.name}')
    print(f'{len(files)} aircraft, {failed} failed structural preflight')
    return int(failed > 0)


if __name__ == '__main__':
    sys.exit(main())
