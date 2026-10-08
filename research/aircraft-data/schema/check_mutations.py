#!/usr/bin/env python3
"""Check weakened and over-restrictive schemas, in memory only (DATA-4a/b)."""
from copy import deepcopy
import json

from jsonschema import Draft202012Validator

from cases import build_cases
from check import SCHEMA, read_json


def main():
    schema = read_json(SCHEMA)
    cases = build_cases()
    mutations = []
    missing_unit = deepcopy(schema)
    missing_unit['$defs']['evidence']['required'].remove('unit')
    mutations.append(('missing-unit-accepted', missing_unit, ':missing-unit'))
    numeric_strings = deepcopy(schema)
    del numeric_strings['properties']['reference']['properties']['wing_span']['properties']['value']['type']
    mutations.append(('scalar-type-removed', numeric_strings, ':reference.wing_span:bad-value'))
    wide_vector = deepcopy(schema)
    del wide_vector['properties']['reference']['properties']['aero_reference_point']['properties']['value']['maxItems']
    mutations.append(('vector-width-removed', wide_vector, ':reference.aero_reference_point:extra-vector-entry'))
    for bound in ('minimum', 'maximum'):
        weakened = deepcopy(schema)
        del weakened['properties']['controls']['properties']['servo_full_throw_time']['properties']['value'][bound]
        mutations.append(('servo-' + bound + '-removed', weakened,
                          'DATA-4b:bounds:controls.servo_full_throw_time.value:'))
    exclusive = deepcopy(schema)
    value = exclusive['properties']['controls']['properties']['servo_full_throw_time']['properties']['value']
    value['exclusiveMinimum'] = value.pop('minimum')
    mutations.append(('inclusive-bound-made-exclusive', exclusive,
                      'DATA-4b:bounds:controls.servo_full_throw_time.value:lower'))
    axis = deepcopy(schema)
    del axis['$defs']['glowPropulsion']['properties']['propeller']['dependentRequired']['normal_force']
    mutations.append(('normal-force-axis-dependency-removed', axis, 'DATA-4b:feature-mask:'))
    transport = deepcopy(schema)
    del transport['$defs']['slipstream']['allOf'][1]['then']['properties']['swirl_factor']
    mutations.append(('transport-zero-swirl-removed', transport, 'DATA-4b:transport-with-swirl'))
    results = []
    for name, mutated, selector in mutations:
        Draft202012Validator.check_schema(mutated)
        validator = Draft202012Validator(mutated)
        detected = [c.name for c in cases if selector in c.name
                    and validator.is_valid(c.data) != c.schema_ok]
        if not detected:
            raise AssertionError(f'corpus did not detect weakened schema: {name}')
        results.append({'mutation': name, 'detected_by_cases': len(detected), 'example': detected[0]})
    print(json.dumps({'format': 'openrc-schema-mutations v1', 'mutations': results}, indent=2))


if __name__ == '__main__':
    main()
