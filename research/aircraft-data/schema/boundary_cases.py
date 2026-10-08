"""DATA-4b: independently specified bounds and interacting optional features.

Bounds below come from aircraft_data.gd, never from the schema under test.
These are loader-contract fixtures, not calibrated or flyable configurations.
"""
from copy import deepcopy
from itertools import product

from cases import Case, at


def build_boundary_cases(fleet):
    cases = []
    stik = fleet['jensen_ugly_stik_60']
    p51 = fleet['p51d_mustang_120']
    jet = fleet['sebart_avanti_s_a200']
    smooth = fleet['synthetic_smooth_wash']
    instantaneous = deepcopy(smooth)
    del instantaneous['propulsion']['propeller']['slipstream']['transport_speed_floor']

    def changed(label, raw, path, value, schema_ok=True, loader_ok=True):
        data = deepcopy(raw)
        at(data, path[:-1])[path[-1]] = value
        cases.append(Case('DATA-4b:' + label, data, schema_ok, loader_ok))

    def bounds(raw, path, lo, hi):
        # A relative 1e-6 gap remains distinct after Godot's decimal parsing.
        # Adjacent binary floats would test parser rounding, not field bounds.
        delta = (hi - lo) * 1e-6
        for label, value, valid in [('below', lo - delta, False), ('lower', lo, True),
                                    ('upper', hi, True), ('above', hi + delta, False)]:
            changed('bounds:' + '.'.join(map(str, path)) + ':' + label,
                    raw, path, value, valid, valid)

    for surface in ('aileron', 'elevator', 'rudder'):
        bounds(stik, ('controls', 'max_throw', surface, 'value'), 1, 60)
    bounds(stik, ('controls', 'servo_full_throw_time', 'value'), .01, 2)
    differential = deepcopy(jet)
    differential['controls']['max_throw']['aileron']['value'] = 60
    bounds(differential, ('controls', 'max_throw', 'aileron_down', 'value'), 1, 60)
    bounds(stik, ('landing_gear', 'breakaway_factor', 'value'), 1, 2)
    steering = deepcopy(stik)
    steering['landing_gear']['contacts'][0]['max_steering'] = deepcopy(stik['controls']['max_throw']['rudder'])
    bounds(steering, ('landing_gear', 'contacts', 0, 'max_steering', 'value'), -45, 45)
    bounds(stik, ('aero', 'surfaces', 'horizontal', 'downwash_gradient', 'value'), 0, .9)
    bounds(jet, ('start', 'level_speed', 'value'), 5, 60)
    for key, lo, hi in [('peak_power', 10, 20000), ('peak_power_rpm', 1000, 50000),
                        ('lag_time_constant', .01, 5)]:
        bounds(stik, ('propulsion', 'engine', key, 'value'), lo, hi)
    for key, lo, hi in [('diameter', .05, 2), ('rotating_inertia', 0, .1)]:
        bounds(stik, ('propulsion', 'propeller', key, 'value'), lo, hi)
    for axis in range(3):
        bounds(stik, ('propulsion', 'propeller', 'thrust_line_offset', 'value', axis), -1, 1)
    for axis in range(2):
        bounds(p51, ('propulsion', 'propeller', 'thrust_angles', 'value', axis), -10, 10)
        bounds(p51, ('propulsion', 'engine', 'shaft', 'friction_torque', 'value', axis), 0, 20)
    for raw, label, lo, hi in [(stik, 'ct_table', -.5, .5), (stik, 'cp_table', 0, .5),
                                (p51, 'cp_table', -.3, .5), (p51, 'normal_force', 0, 1),
                                (p51, 'pfactor_moment', 0, 1)]:
        # The first coefficient has an additional positive-static-load rule.
        bounds(raw, ('propulsion', 'propeller', label, 'value', -1, 1), lo, hi)
        # Disambiguate shared paths on different propulsion configurations.
        for case in cases[-4:]:
            case.name += ':shaft' if raw is p51 else ':glow'
    for key, lo, hi in [('installed_factor', .5, 1), ('governor_tau', .02, 2),
                        ('rotor_inertia', 0, .01), ('ram_flow', 0, .001)]:
        bounds(jet, ('propulsion', 'engine', key, 'value'), lo, hi)
    for key, lo, hi in [('static_thrust', 0, 5000), ('mass_flow', .0001, 20),
                        ('fuel_flow', 0, 1), ('accel_limit', 1, 1e6),
                        ('decel_limit', 1, 1e6), ('ram_jet', 0, 10)]:
        bounds(jet, ('propulsion', 'engine', key, 'value', -1, 1), lo, hi)
    wash_path = ('propulsion', 'propeller', 'slipstream')
    for key, lo, hi in [('swirl_factor', 0, 1), ('vertical_drift', 0, 1),
                        ('edge_fraction', .01, .5), ('transport_speed_floor', .1, 5)]:
        bounds(instantaneous if key == 'swirl_factor' else smooth,
               (*wash_path, key, 'value'), lo, hi)
    for axis in range(2):
        bounds(smooth, (*wash_path, 'wash_factor', 'value', axis), 0, 2)

    # All 32 combinations isolate axis dependency from the signed Cp rule.
    features = ('thrust_angles', 'normal_force', 'pfactor_moment', 'slipstream')
    for shaft, *enabled in product((False, True), repeat=5):
        data = deepcopy(p51)
        propeller = data['propulsion']['propeller']
        if not shaft:
            del data['propulsion']['engine']['shaft']
            for row in propeller['cp_table']['value']:
                row[1] = max(0, row[1])
        for feature, present in zip(features, enabled):
            if not present:
                del propeller[feature]
        valid = enabled[0] or not any(enabled[1:])
        label = 'feature-mask:' + ''.join(str(int(v)) for v in [shaft, *enabled])
        cases.append(Case('DATA-4b:' + label, data, valid, valid))
    no_shaft = deepcopy(p51)
    del no_shaft['propulsion']['engine']['shaft']
    cases.append(Case('DATA-4b:negative-cp-without-shaft', no_shaft))

    # Turbine ram corrections and thrust tilt are independently optional.
    for ram_flow, ram_jet, tilt in product((False, True), repeat=3):
        data = deepcopy(jet)
        engine = data['propulsion']['engine']
        for key, present in [('ram_flow', ram_flow), ('ram_jet', ram_jet)]:
            if not present:
                del engine[key]
        if tilt:
            data['propulsion']['thrust_angles'] = deepcopy(p51['propulsion']['propeller']['thrust_angles'])
        else:
            data['propulsion'].pop('thrust_angles', None)
        cases.append(Case(f'DATA-4b:turbine-options:{ram_flow}:{ram_jet}:{tilt}', data, True, True))

    # Explicitly distinguish field validity from coupled physical consistency.
    for label, raw, path, value in [
        ('idle-equals-max', stik, ('propulsion', 'engine', 'idle_rpm', 'value'),
         stik['propulsion']['engine']['max_rpm_static']['value']),
        ('shaft-idle-equals-peak', p51, ('propulsion', 'engine', 'shaft', 'idle_power', 'value'),
         p51['propulsion']['engine']['shaft']['peak_indicated_power']['value']),
        ('differential-exceeds-up', jet, ('controls', 'max_throw', 'aileron_down', 'value'), 31),
        ('smooth-tilted-axis', smooth, ('propulsion', 'propeller', 'thrust_angles', 'value'), [1, 0]),
        ('smooth-equal-fade', smooth, (*wash_path, 'reverse_fade', 'value'), [.1, .1]),
        ('smooth-reversed-fade', smooth, (*wash_path, 'reverse_fade', 'value'), [.2, .1]),
        ('turbine-throttle-endpoint', jet, ('propulsion', 'engine', 'throttle_map', 'value', -1, 1),
         jet['propulsion']['engine']['max_rpm']['value'] - 2),
    ]:
        changed('runtime-only:' + label, raw, path, value, True, False)
    changed('shaft-zero-inertia', p51,
            ('propulsion', 'propeller', 'rotating_inertia', 'value'), 0, False, False)
    changed('transport-with-swirl', smooth, (*wash_path, 'swirl_factor', 'value'), .2, False, False)
    changed('instantaneous-with-swirl', instantaneous, (*wash_path, 'swirl_factor', 'value'), .2)
    legacy_transport = deepcopy(p51)
    legacy_transport['propulsion']['propeller']['slipstream']['transport_speed_floor'] = deepcopy(
        smooth['propulsion']['propeller']['slipstream']['transport_speed_floor'])
    cases.append(Case('DATA-4b:legacy-with-transport', legacy_transport))
    changed('differential-equals-up', jet, ('controls', 'max_throw', 'aileron_down', 'value'),
            jet['controls']['max_throw']['aileron']['value'])
    changed('runtime-only:incidence-nonzero-mean', p51,
            ('aero', 'surfaces', 'wing_station_incidence', 'value'), [.01, 0, 0], True, False)
    return cases
