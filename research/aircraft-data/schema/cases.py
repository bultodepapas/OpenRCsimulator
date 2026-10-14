"""Independent fixture mutations, derived from v1 files and loader contracts."""
from copy import deepcopy
from dataclasses import dataclass
import importlib.util

from check import FLEET, ROOT, read_json

NO_GEAR_FIXTURE_ID = 'schema-contract-no-gear-fixture'


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
    # DATA-4 pins historical v1 acceptance (including permissive metadata and
    # optional/null defaults). AS has a separate strict v2 agreement corpus.
    spec = importlib.util.spec_from_file_location(
        'aircraft_standardization_migration', ROOT / 'research/aircraft-standardization/migrate.py')
    migration = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(migration)
    fleet = {path.stem: migration.legacy_input(read_json(path)) for path in sorted(FLEET.glob('*.json'))}
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
    legacy_electric_id = deepcopy(fleet['synthetic_stik_electric_4s'])
    legacy_electric_id['propulsion']['id'] = 'propulsion_main'
    cases.append(Case('v1:unsupported-electric-propulsion-id', legacy_electric_id))
    # Canonical synthetic demo aircraft are already part of the fleet files above.
    electric_fixtures = {
        name: fleet[name]
        for name in ('synthetic_stik_electric_4s', 'synthetic_stik_electric_6s')
    }
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

    def change(label, raw, path, value=None, *, delete=False, valid=False, physical=False,
               aircraft_id=None):
        data = deepcopy(raw)
        if delete:
            del at(data, path[:-1])[path[-1]]
        else:
            at(data, path[:-1])[path[-1]] = value
        if aircraft_id is not None:
            data['id'] = aircraft_id
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
        change('optional-absent:' + str(path), stik, path, delete=True, valid=True,
               aircraft_id=NO_GEAR_FIXTURE_ID if path == ('landing_gear',) else None)
    for value in [None, {}]:
        change('optional-gear:' + repr(value), stik, ('landing_gear',), value, valid=True,
               aircraft_id=NO_GEAR_FIXTURE_ID)
    for path in [('landing_gear', 'contacts', 0, 'max_steering'),
                 ('landing_gear', 'breakaway_factor')]:
        change('nullable:' + str(path), stik, path, None, valid=True)
    # M5-GE-1: the Stik's aero.ground_effect module requires the free tail law, so nulling downwash_gradient
    # alone is a schema-pass/loader-fail coupled case; without the module it stays a valid nullable optional.
    downwash = ('aero', 'surfaces', 'horizontal', 'downwash_gradient')
    change('nullable-with-ground-effect:' + str(downwash), stik, downwash, None, physical=True)
    stik_free_air = deepcopy(stik)
    del stik_free_air['aero']['ground_effect']
    change('nullable:' + str(downwash), stik_free_air, downwash, None, valid=True)
    change('ground-effect-unknown-field', stik, ('aero', 'ground_effect', 'gain'),
           dict(value=1.0, unit='1', kind='estimated', source='x'))
    change('ground-effect-exponent-out-of-range', stik, ('aero', 'ground_effect', 'induced_exponent', 'value'), 9.0)
    for path in [('description',), ('frames',), ('id',)]:
        change('ignored-metadata:' + str(path), stik, path, delete=True, valid=True)
    change('extra-metadata', stik, ('notes',), {'not_a_quantity': [1, 2]}, valid=True)
    for kind in ['manual', 'measured', 'borrowed', 'estimated', 'derived']:
        change('allowed-kind:' + kind, stik, ('reference', 'wing_span', 'kind'), kind, valid=True)
    for value in ['\u00a0', '\u2003']:
        change('source-unicode-space:' + repr(value), stik, ('reference', 'wing_span', 'source'), value, valid=True)
    change('source-ascii-control', stik, ('reference', 'wing_span', 'source'), '\x1f')

    # EL1b electric fixtures are deliberately test-only synthetic configurations. They
    # retain the Stik geometry and original mass distribution, not a conversion claim.
    electric = electric_fixtures['synthetic_stik_electric_4s']
    electric_integer = deepcopy(electric)
    at(electric_integer, ('propulsion', 'motor', 'kv_rpm_per_volt'))['value'] = 800
    at(electric_integer, ('propulsion', 'battery', 'voltage_v'))['value'] = 14
    cases.append(Case('electric-integer-json-numbers', electric_integer, True, True))
    change('electric-unknown-root-field', electric, ('propulsion', 'extra_controller'), {})
    change('electric-wrong-selector', electric, ('propulsion', 'kind'), 'electric')
    change('electric-mixed-glow-field', electric, ('propulsion', 'engine'), {})
    change('electric-unknown-motor-field', electric, ('propulsion', 'motor', 'gear_ratio'), 2.0)
    change('electric-unknown-quantity-field', electric,
           ('propulsion', 'motor', 'no_load_current_a', 'instrument'), 'synthetic')
    change('electric-wrong-resistance-scope', electric,
           ('propulsion', 'motor', 'resistance_scope'), 'motor_plus_esc')
    change('electric-wrong-battery-kind', electric, ('propulsion', 'battery', 'kind'), 'ocv_sag')
    change('electric-wrong-esc-mapping', electric,
           ('propulsion', 'esc', 'command_mapping'), 'receiver_pulse')
    change('electric-wrong-kv-unit', electric,
           ('propulsion', 'motor', 'kv_rpm_per_volt', 'unit'), 'V/rpm')
    change('electric-missing-i0-context', electric,
           ('propulsion', 'motor', 'no_load_context', 'temperature_c'), delete=True)
    change('electric-zero-rotor-inertia', electric,
           ('propulsion', 'propeller', 'rotating_inertia', 'value'), 0.0)
    electric_small_carrier = deepcopy(electric)
    for part in electric_small_carrier['inventory']:
        part['position']['value'] = [0.1209, 0.0, 0.0]
        part['size'] = {
            'value': [0.01, 0.01, 0.01], 'unit': 'm', 'kind': 'estimated',
            'source': 'EL1b synthetic cross-inertia negative control; not an aircraft geometry claim',
        }
    cases.append(Case('electric-runtime-only:carrier-inertia', electric_small_carrier, True, False))
    change('electric-runtime-only:no-load-context', electric,
           ('propulsion', 'motor', 'no_load_context', 'rpm', 'value'), 15000.0, physical=True)
    change('electric-negative-static-cp', electric,
           ('propulsion', 'propeller', 'cp_table', 'value', 0, 1), -0.01)
    change('electric-unknown-propeller-field', electric,
           ('propulsion', 'propeller', 'gear_ratio'), 2.0)

    # EL2a battery data uses strict quantity provenance and a closed OCV curve.
    battery = fleet['synthetic_stik_electric_4s_battery']
    battery_integer = deepcopy(battery)
    battery_raw = battery_integer['propulsion']['battery']
    for key, value in [('capacity_ah', 3), ('resistance_ohm', 0),
                       ('auxiliary_current_a', 0), ('initial_soc', 1)]:
        battery_raw[key]['value'] = value
    battery_raw['ocv_points'] = [
        {'soc': {'value': 0, 'unit': '1', 'kind': 'estimated', 'source': 'EL2a synthetic authored integer control; not Timber data or a measured LiPo fit'},
         'voltage': {'value': 12, 'unit': 'V', 'kind': 'estimated', 'source': 'EL2a synthetic authored integer control; not Timber data or a measured LiPo fit'}},
        {'soc': {'value': 1, 'unit': '1', 'kind': 'estimated', 'source': 'EL2a synthetic authored integer control; not Timber data or a measured LiPo fit'},
         'voltage': {'value': 17, 'unit': 'V', 'kind': 'estimated', 'source': 'EL2a synthetic authored integer control; not Timber data or a measured LiPo fit'}},
    ]
    cases.append(Case('electric-battery-integer-json-numbers', battery_integer, True, True))
    change('electric-battery-unknown-field', battery,
           ('propulsion', 'battery', 'controller_mode'), 'ideal')
    change('electric-battery-mixed-fixed-voltage-field', battery,
           ('propulsion', 'battery', 'voltage_v'), {
               'value': 14.8, 'unit': 'V', 'kind': 'estimated',
               'source': 'EL2a mixed-field negative control',
           })
    change('electric-battery-point-unknown-field', battery,
           ('propulsion', 'battery', 'ocv_points', 0, 'temperature_c'), 25.0)
    change('electric-battery-missing-initial-soc', battery,
           ('propulsion', 'battery', 'initial_soc'), delete=True)
    change('electric-battery-zero-capacity', battery,
           ('propulsion', 'battery', 'capacity_ah', 'value'), 0.0)
    change('electric-battery-negative-resistance', battery,
           ('propulsion', 'battery', 'resistance_ohm', 'value'), -0.01)
    change('electric-battery-negative-auxiliary-current', battery,
           ('propulsion', 'battery', 'auxiliary_current_a', 'value'), -0.1)
    change('electric-battery-zero-initial-soc', battery,
           ('propulsion', 'battery', 'initial_soc', 'value'), 0.0)
    change('electric-battery-first-soc-not-zero', battery,
           ('propulsion', 'battery', 'ocv_points', 0, 'soc', 'value'), 0.1)
    change('electric-battery-no-full-soc-endpoint', battery,
           ('propulsion', 'battery', 'ocv_points', 1, 'soc', 'value'), 0.9)
    change('electric-battery-zero-ocv', battery,
           ('propulsion', 'battery', 'ocv_points', 0, 'voltage', 'value'), 0.0)
    change('electric-battery-wrong-voltage-unit', battery,
           ('propulsion', 'battery', 'ocv_points', 0, 'voltage', 'unit'), 'mV')
    change('electric-battery-missing-soc-source', battery,
           ('propulsion', 'battery', 'ocv_points', 0, 'soc', 'source'), delete=True)
    change('electric-battery-too-few-points', battery,
           ('propulsion', 'battery', 'ocv_points'), battery['propulsion']['battery']['ocv_points'][:1])

    def fixture_point(soc, voltage):
        source = 'EL2a synthetic authored runtime control; not Timber data or a measured LiPo fit'
        return {
            'soc': {'value': soc, 'unit': '1', 'kind': 'estimated', 'source': source},
            'voltage': {'value': voltage, 'unit': 'V', 'kind': 'estimated', 'source': source},
        }

    # Array ordering and physical feasibility remain production-loader checks.
    curve_order = deepcopy(battery)
    curve_order['propulsion']['battery']['ocv_points'] = [
        fixture_point(0.0, 12.0), fixture_point(1.0, 16.0), fixture_point(0.5, 16.8),
    ]
    cases.append(Case('electric-battery-runtime-only:soc-order', curve_order, True, False))
    curve_voltage = deepcopy(battery)
    curve_voltage['propulsion']['battery']['ocv_points'] = [
        fixture_point(0.0, 12.0), fixture_point(0.5, 16.0), fixture_point(1.0, 15.0),
    ]
    cases.append(Case('electric-battery-runtime-only:voltage-order', curve_voltage, True, False))
    infeasible = deepcopy(battery)
    infeasible['propulsion']['battery']['resistance_ohm']['value'] = 60.0
    cases.append(Case('electric-battery-runtime-only:minimum-ocv-feasibility', infeasible, True, False))
    slope_overflow = deepcopy(battery)
    slope_overflow['propulsion']['battery']['ocv_points'] = [
        fixture_point(0.0, 12.0), fixture_point(3e-308, 24.0), fixture_point(1.0, 25.0),
    ]
    cases.append(Case('electric-battery-runtime-only:ocv-slope-overflow', slope_overflow, True, False))
    coulomb_overflow = deepcopy(battery)
    coulomb_overflow['propulsion']['battery']['capacity_ah']['value'] = 1e308
    cases.append(Case('electric-battery-runtime-only:coulomb-overflow', coulomb_overflow, True, False))
    initial_charge_underflow = deepcopy(battery)
    initial_charge_underflow['propulsion']['battery']['capacity_ah']['value'] = 3e-308
    initial_charge_underflow['propulsion']['battery']['initial_soc']['value'] = 1e-21
    cases.append(Case('electric-battery-runtime-only:initial-charge-underflow', initial_charge_underflow, True, False))
    auxiliary_overflow = deepcopy(battery)
    auxiliary_overflow['propulsion']['battery']['resistance_ohm']['value'] = 1e308
    auxiliary_overflow['propulsion']['battery']['auxiliary_current_a']['value'] = 1e308
    cases.append(Case('electric-battery-runtime-only:auxiliary-sag-overflow', auxiliary_overflow, True, False))

    # Shape cannot enforce relationships between measured quantities. These must
    # pass schema validation while the physics authority refuses them.
    change('runtime-only:reference-area', stik, ('reference', 'wing_area', 'value'), .6, physical=True)
    change('runtime-only:inventory-balance', stik, ('inventory', 0, 'position', 'value'), [1, 0, 0], physical=True)
    change('runtime-only:table-order', stik, ('propulsion', 'propeller', 'ct_table', 'value'),
           [[0, .1], [1, .05], [.5, .02]], physical=True)
    from boundary_cases import build_boundary_cases
    cases.extend(build_boundary_cases(fleet))
    return cases
