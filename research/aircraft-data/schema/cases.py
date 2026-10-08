"""Independent fixture mutations, derived from v1 files and loader contracts."""
from copy import deepcopy
from dataclasses import dataclass

from check import FLEET, ROOT, read_json


@dataclass
class Case:
    name: str
    data: object
    schema_ok: bool = False
    loader_ok: bool = False


def at(data, path):
    for key in path:
        data = data[key]
    return data


def quantities(node, path=()):
    if isinstance(node, dict):
        if all(key in node for key in ('value', 'unit', 'kind', 'source')):
            yield path, node
        else:
            for key, value in node.items():
                yield from quantities(value, (*path, key))
    elif isinstance(node, list) and node:
        # Every element shares a contract; additional late-row tests below.
        yield from quantities(node[0], (*path, 0))


def build_cases():
    fleet = {path.stem: read_json(path) for path in sorted(FLEET.glob('*.json'))}
    # Existing E0b3b geometry, with the same uncalibrated test settings as
    # test_wash_profile.gd. Exercise the opt-in branch without enabling flight data.
    smooth = deepcopy(fleet['jensen_ugly_stik_60'])
    wash = read_json(ROOT / 'app/tests/fixtures/stik_wash_profile.json')
    def fixture_quantity(value, unit):
        return dict(value=value, unit=unit, kind='estimated',
                    source='DATA-4a synthetic contract fixture; E0b3b test settings, not calibration')
    wash['hub'] = fixture_quantity(wash['hub'], 'm')
    for piece in wash['pieces']:
        for key in ['root', 'span_dir', 'span', 'area', 'profile']:
            piece[key] = fixture_quantity(piece[key], 'm2' if key == 'area' else '1' if key == 'span_dir' else 'm')
    for key, value, unit in [('wash_factor', [1, 1.4], '1'), ('swirl_factor', 0, '1'),
                             ('vertical_drift', .543, '1'), ('edge_fraction', .15, '1'),
                             ('reverse_fade', [.1, .2], '1'), ('transport_speed_floor', 1, 'm/s')]:
        wash[key] = fixture_quantity(value, unit)
    smooth['propulsion']['propeller']['thrust_angles'] = fixture_quantity([0, 0], 'deg')
    smooth['propulsion']['propeller']['slipstream'] = wash
    fleet['synthetic_smooth_wash'] = smooth
    cases = [Case(name, data, True, True) for name, data in fleet.items()]
    seen = set()
    for name, raw in fleet.items():
        for path, quantity in quantities(raw):
            # Units and value shape distinguish the shared prop/turbine paths.
            signature = (path, quantity['unit'])
            if signature in seen:
                continue
            seen.add(signature)
            prefix = name + ':' + '.'.join(map(str, path))
            for key in ('value', 'unit', 'kind', 'source'):
                data = deepcopy(raw)
                del at(data, path)[key]
                cases.append(Case(prefix + ':missing-' + key, data))
            for key, value in [('value', True), ('value', '1.0'), ('unit', 'wrong-unit'),
                               ('kind', 'guess'), ('source', ' \t\n'), ('source', 123)]:
                data = deepcopy(raw)
                at(data, path)[key] = value
                cases.append(Case(prefix + ':bad-' + key + ':' + repr(value), data))
            value = quantity['value']
            if isinstance(value, list):
                data = deepcopy(raw)
                at(data, path)['value'] = []
                cases.append(Case(prefix + ':empty-array', data))
                if value and isinstance(value[0], list):
                    # Tables: test the last row as well as the first row shape.
                    for column in range(len(value[-1])):
                        data = deepcopy(raw)
                        at(data, path)['value'][-1][column] = '0'
                        cases.append(Case(prefix + f':last-row-string-{column}', data))
                    data = deepcopy(raw)
                    at(data, path)['value'][0].append(0)
                    cases.append(Case(prefix + ':extra-column', data))
                else:
                    data = deepcopy(raw)
                    at(data, path)['value'].append(0)
                    cases.append(Case(prefix + ':extra-vector-entry', data))

    stik = fleet['jensen_ugly_stik_60']
    p51 = fleet['p51d_mustang_120']
    jet = fleet['sebart_avanti_s_a200']

    def change(label, raw, path, value=None, *, delete=False, valid=False, physical=False):
        data = deepcopy(raw)
        if delete:
            del at(data, path[:-1])[path[-1]]
        else:
            at(data, path[:-1])[path[-1]] = value
        cases.append(Case(label, data, valid or physical, valid))

    for path in [('reference',), ('inventory',), ('aero',), ('aero', 'surfaces', 'horizontal'),
                 ('controls',), ('propulsion', 'engine'), ('landing_gear', 'contacts')]:
        change('wrong-container:' + str(path), stik, path, 'invalid')
    change('unknown-format', stik, ('format',), 'v0')
    change('unknown-planform', stik, ('reference', 'planform'), 'delta')
    change('missing-controls', stik, ('controls',), delete=True)
    change('missing-coefficient', stik, ('aero', 'coefficients', 'Cnr'), delete=True)
    change('empty-inventory', stik, ('inventory',), [])
    change('unnamed-inventory', stik, ('inventory', 0, 'name'), delete=True)
    change('two-wheels', stik, ('landing_gear', 'contacts'), stik['landing_gear']['contacts'][:2])
    change('unnamed-contact', stik, ('landing_gear', 'contacts', 0, 'name'), delete=True)
    change('short-hull', stik, ('crash_hull', 'value'), stik['crash_hull']['value'][:3])
    change('negative-mass', stik, ('inventory', 0, 'mass', 'value'), -0.1)
    change('excess-throw', stik, ('controls', 'max_throw', 'aileron', 'value'), 90)
    change('bad-propulsion-kind', stik, ('propulsion', 'kind'), 'rocket')
    change('turbine-forbidden-propeller', jet, ('propulsion', 'propeller'), {})
    change('turbine-forbidden-shaft', jet, ('propulsion', 'engine', 'shaft'), {})
    change('missing-slipstream-axis', p51, ('propulsion', 'propeller', 'thrust_angles'), delete=True)
    wash_path = ('propulsion', 'propeller', 'slipstream')
    change('smooth-missing-fade', smooth, (*wash_path, 'reverse_fade'), delete=True)
    change('smooth-empty-pieces', smooth, (*wash_path, 'pieces'), [])
    change('smooth-conflicting-chords', smooth, (*wash_path, 'pieces', 0, 'chords'), fixture_quantity([.1, .1], 'm'))
    change('legacy-forbidden-profile', p51, (*wash_path, 'pieces', 0, 'profile'), wash['pieces'][0]['profile'])

    # Optional/metadata positive controls guard against over-restrictive schemas.
    for path in [('landing_gear',), ('inventory', 0, 'size'), ('aero', 'conventions')]:
        change('optional-absent:' + str(path), stik, path, delete=True, valid=True)
    for value in [None, {}]:
        change('optional-gear:' + repr(value), stik, ('landing_gear',), value, valid=True)
    for path in [('landing_gear', 'contacts', 0, 'max_steering'),
                 ('landing_gear', 'breakaway_factor'),
                 ('aero', 'surfaces', 'horizontal', 'downwash_gradient')]:
        change('nullable:' + str(path), stik, path, None, valid=True)
    for path in [('description',), ('frames',), ('id',)]:
        change('ignored-metadata:' + str(path), stik, path, delete=True, valid=True)
    change('extra-metadata', stik, ('notes',), {'not_a_quantity': [1, 2]}, valid=True)
    for kind in ['manual', 'measured', 'borrowed', 'estimated', 'derived']:
        change('allowed-kind:' + kind, stik, ('reference', 'wing_span', 'kind'), kind, valid=True)
    for value in ['\u00a0', '\u2003']:
        change('source-unicode-space:' + repr(value), stik, ('reference', 'wing_span', 'source'), value, valid=True)
    change('source-ascii-control', stik, ('reference', 'wing_span', 'source'), '\x1f')

    # Shape cannot enforce relationships between measured quantities. These must
    # pass schema validation while the physics authority refuses them.
    change('runtime-only:reference-area', stik, ('reference', 'wing_area', 'value'), .6, physical=True)
    change('runtime-only:inventory-balance', stik, ('inventory', 0, 'position', 'value'), [1, 0, 0], physical=True)
    change('runtime-only:table-order', stik, ('propulsion', 'propeller', 'ct_table', 'value'),
           [[0, .1], [1, .05], [.5, .02]], physical=True)
    from boundary_cases import build_boundary_cases
    cases.extend(build_boundary_cases(fleet))
    return cases
