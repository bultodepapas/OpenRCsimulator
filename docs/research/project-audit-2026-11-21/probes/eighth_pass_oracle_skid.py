#!/usr/bin/env python3
"""Independent stdlib cross-check of the R8 skid diagnostic log.

`verify(log_text, stock_json_dict)` returns a JSON-serializable success report
and raises AssertionError on disagreement. It does not run Godot or edit files.
Inputs must be the full log of eighth_pass_skid_admission.gd and the parsed
stock X-Cell JSON from the source under review. Engine/check-runner receipt,
source/dependency identities and generated custom-data bytes are separate gates.
"""
import json
import math
import sys


def verify(log_text, stock_json_dict):
    checks = 0

    def check(condition, label):
        nonlocal checks
        checks += 1
        if not condition:
            raise AssertionError(label)

    def close(actual, expected, label, *, rel=1e-10, abs_=1e-14):
        check(math.isfinite(actual) and math.isfinite(expected)
              and math.isclose(actual, expected, rel_tol=rel, abs_tol=abs_),
              f'{label}: {actual!r} != {expected!r}')

    def read_rows(prefix):
        return [json.loads(line[len(prefix):]) for line in log_text.splitlines()
                if line.startswith(prefix)]

    samples = read_rows('R8_SKID ')
    traces = read_rows('R8_SKID_TRACE ')
    calm = read_rows('R8_SKID_CALM ')
    check('R8 skid admission: 70 checks, 0 failed' in log_text, 'completion marker')
    check(len(samples) == 4 and len(traces) == 2 and len(calm) == 1,
          'four observations, two ordinary traces and one calm control')
    by_key = {(r['kind'], r['path']): r for r in samples}
    check(len(by_key) == 4, 'duplicate sample identities')
    stock_path = 'res://data/aircraft/xcell_60_research.json'
    half_path = 'res://r8_skid_0.5.json'
    one_path = 'res://r8_skid_1.0.json'
    expected_keys = {('wind_first_tick', stock_path), ('wind_first_tick', half_path),
                     ('calm_constructed_mode', half_path),
                     ('calm_constructed_mode', one_path)}
    check(set(by_key) == expected_keys, 'sample kind/path identities')
    stock, half = by_key['wind_first_tick', stock_path], by_key['wind_first_tick', half_path]
    local_half, local_one = by_key['calm_constructed_mode', half_path], by_key['calm_constructed_mode', one_path]

    value = lambda block, key: stock_json_dict[block][key]['value']
    m, inertia, k, c = value('body', 'mass_kg'), value('body', 'inertia_kg_m2'), value('skids', 'spring_n_m'), value('skids', 'damping_n_s_m')
    g, original_points = stock_json_dict['gravity_m_s2']['value'], value('skids', 'points_body_frd_m')
    check(len(original_points) == 12 and len(inertia) == 6, 'stock geometry and inertia shapes')
    check(inertia[3:] == [0, 0, 0] and min(inertia[:3]) > 0, 'diagonal positive inertia for local derivation')
    xs, ys, hs = original_points[::3], original_points[1::3], original_points[2::3]
    x, stock_y, h = abs(xs[0]), abs(ys[0]), hs[0]
    check(all(math.isclose(z, h, abs_tol=1e-14) for z in hs)
          and set(xs) == {-x, x} and set(ys) == {-stock_y, stock_y}
          and set(zip(xs, ys)) == {(a, b) for a in (-x, x) for b in (-stock_y, stock_y)},
          'symmetric stock supports assumed by independent model')
    j = inertia[0]
    main_hub = value('main_rotor', 'hub_position_body_frd_m')
    main_reach = math.sqrt(sum(a*a for a in main_hub)) + value('main_rotor', 'rotor_radius_m')
    tail_reach = math.hypot(value('tail_rotor', 'hub_distance_aft_m'),
                            value('tail_rotor', 'hub_height_above_cg_m')) + value('tail_rotor', 'tail_rotor_radius_m')
    spring_ratio, damper_ratio = math.sqrt(4*k/m)/240, 4*c/(m*240)
    check(spring_ratio <= .5 and damper_ratio <= 1.0, 'declared mass-only reader guard')
    output = {'independent_checks': 0, 'mass_guard': [spring_ratio, damper_ratio],
              'stock_wind': {}, 'wide_wind': {}, 'local_modes': {}}

    for r in samples:
        width = stock_y if r['path'] == stock_path else (.5 if r['path'] == half_path else 1.)
        expected_points = list(original_points)
        for i in range(1, 12, 3):
            expected_points[i] = math.copysign(width, original_points[i])
        check(r['geometry']['points'] == expected_points, f'{r["path"]}: physical geometry difference')
        constants = r['constants']
        check(constants['mass'] == m and constants['inertia'] == inertia and constants['k'] == k
              and constants['c'] == c and constants['gravity'] == g
              and constants['friction'] == value('skids', 'friction'), 'stock physical constants')
        close(r['dt_s'], 1/240, 'fixed step')
        close(r['admission_ratios'][0], spring_ratio, 'reader spring guard')
        close(r['admission_ratios'][1], damper_ratio, 'reader damping guard')
        # The fixture declares a centered 6 m square pad with 1.25 m envelope.
        # Compare those declared values against the separate source field file
        # when packaging evidence; stock_json_dict contains aircraft data only.
        check(max(x, width) < 3.0, 'four supports fit centered flat pad')
        skid_reach = max(math.sqrt(sum(expected_points[i+j]**2 for j in range(3)))
                         for i in (0, 3, 6, 9))
        expected_envelope = max(skid_reach, main_reach, tail_reach)
        close(r['geometry']['reach_m'], skid_reach, 'skid reach')
        close(r['geometry']['authored_envelope_m'], 1.25, 'declared pad envelope')
        close(r['geometry']['actual_envelope_m'], expected_envelope, 'geometric envelope')
        check(expected_envelope <= r['geometry']['authored_envelope_m'], 'envelope admitted')
        check(r['backend'].get('backend') == 'gdscript_reference', 'reference backend reported')
        check(r['accepted_tick'] == 1 and not r['fault'] and not r['crash'], 'actual first tick accepted')
        check(r['actual_continuous'][0] == 0.0, 'actual held rotor stayed stopped')
        check(r['unsplit_vs_actual_max_difference_excluding_heading_memory'] <= 1e-13,
              'reported actual/unsplit agreement')
        stages = r['refinements']
        check([x['pieces'] for x in stages] == [1, 8, 16, 32, 64], 'diagnostic refinement sizes')
        for stage in stages:
            n, out = stage['pieces'], stage['result']
            check(out['ok'] and len(out['state']) == 27 and all(map(math.isfinite, out['state'])),
                  f'{r["kind"]} {width} {n}: finite result')
            check(out['stage_calls'] == 4*n and out['events'] == [] and out['max_rotor_speed'] == 0.0,
                  f'{r["kind"]} {width} {n}: 4n stage calls, no stop event')
            check(math.isfinite(out['min_normal']) and out['min_normal'] > 0
                  and math.isfinite(out['max_normal']) and out['max_normal'] >= out['min_normal']
                  and math.isfinite(out['max_traction_fraction']) and 0 <= out['max_traction_fraction'] < 1,
                  f'{r["kind"]} {width} {n}: loaded/unsaturated contact')
        full = r['actual_body'] + r['actual_continuous']
        unsplit = stages[0]['result']['state']
        check(len(full) == 27 and all(math.isclose(full[i], unsplit[i], rel_tol=1e-12, abs_tol=1e-13)
              for i in range(27) if i not in (17, 18)), 'actual endpoint versus independently read one-piece result')

    def characteristic(lam, y):
        d = m*lam**2 + 4*c*lam + 4*k
        r = j*lam**2 + 4*c*y*y*lam + 4*k*y*y - m*g*h
        return d*r + 4*m*h*h*lam**2*(k+c*lam)

    def most_negative_root(y):
        # Scan negative axis to bracket real roots; bisection, no logged lambda.
        points = [-10**(-4 + 10*i/4000) for i in range(4001)]
        roots = []
        for left, right in zip(points, points[1:]):
            fl, fr = characteristic(left, y), characteristic(right, y)
            if fl*fr >= 0:
                continue
            for _ in range(100):
                mid = .5*(left+right)
                fm = characteristic(mid, y)
                if fl*fm > 0:
                    left, fl = mid, fm
                else:
                    right = mid
            roots.append(.5*(left+right))
        check(bool(roots), f'y={y}: quartic has a bracketed negative root')
        return min(roots)

    def r4(z):
        return 1 + z + z*z/2 + z*z*z/6 + z*z*z*z/24

    for y, r in ((.5, local_half), (1., local_one)):
        check(r.get('reset_accepted') is True, 'constructed local reset accepted')
        check(r['weather']['speed_mps'] == 0.0, 'constructed mode in calm air')
        lam = most_negative_root(y)
        b = -m*h*lam**2/(m*lam**2+4*c*lam+4*k)
        v = lam*(h+b)
        config, initial = r['config'], r['initial']
        eps = config['eps']
        close(config['lambda'], lam, 'independent local eigenvalue', rel=1e-10)
        close(config['b'], b, 'independent eigenvector bristle', rel=1e-9)
        close(config['v'], v, 'independent eigenvector lateral velocity', rel=1e-9)
        check(eps > 0 and initial[8] == 0.0 and initial[9] == 0.0,
              'constructed local mode uses zero yaw/pitch')
        phi = 2*math.atan2(initial[7], initial[6])
        close(phi, eps, 'initial roll quaternion', rel=1e-10, abs_=1e-20)
        close(initial[10], lam*phi, 'initial roll rate', rel=1e-9, abs_=1e-18)
        close(initial[4], v*phi, 'initial lateral body velocity', rel=1e-9, abs_=1e-18)
        for i in range(4):
            close(initial[20+2*i], b*phi, 'four common east bristles', rel=1e-9, abs_=1e-20)
            close(initial[19+2*i], 0.0, 'zero north bristle', abs_=1e-20)
        z = lam/240
        gain = r4(z)
        check(z < -2.785 and gain > 1.0, 'negative-real RK4 stability violation')
        stages = {x['pieces']: x['result'] for x in r['refinements']}
        observed = stages[1]['roll']/phi
        close(observed, gain, 'one-piece local RK4 gain', rel=3e-6, abs_=1e-8)
        # At y=1 the 16/32/64-piece answers are close to floating-point noise.
        # Compare only 1 and 8 there, then use a conservative absolute bound.
        for n in ([1, 8, 16, 32, 64] if y == .5 else [1, 8]):
            expected_roll = phi*r4(z/n)**n
            close(stages[n]['roll'], expected_roll, f'y={y} n={n} local RK4',
                  rel=1e-5, abs_=1e-16)
        if y == .5:
            close(stages[64]['roll'], phi*math.exp(z), 'fine half-width approaches decay',
                  rel=2e-5, abs_=1e-16)
        else:
            check(all(abs(stages[n]['roll']) < 1e-16 for n in (16, 32, 64)),
                  'one-meter fine results near roundoff floor; absolute bound only')
        output['local_modes'][str(y)] = {'lambda_per_s': lam, 'z': z, 'predicted_gain': gain,
                                        'observed_gain': observed, 'initial_roll_rad': phi,
                                        'fine_roll_rad': stages[64]['roll'],
                                        'floor_caveat': y == 1.}

    check(stock['initial'] == half['initial'] and stock['commands'] == half['commands'],
          'ordinary wind starts share the identical initial frame and controls')
    check(stock['weather'] == half['weather'] and stock['weather']['speed_mps'] == 3.0
          and stock['weather']['from_deg'] == 45.0 and stock['weather']['gust_mps'] == 0.0,
          'ordinary wind starts share steady 3 m/s 45-degree weather')
    close(stock['initial'][2], -h + m*g/(4*k), 'four-support static sag')
    for name, r in (('stock_wind', stock), ('wide_wind', half)):
        p = {x['pieces']: x['result']['state'][10] for x in r['refinements']}
        check(abs(p[8]-p[16]) > abs(p[16]-p[32]) > abs(p[32]-p[64]),
              f'{name}: successive fine roll-rate differences shrink')
        close(r['actual_body'][10], p[1], f'{name}: accepted initial tick roll rate', abs_=1e-15)
        output[name] = {'actual_p_rad_s': p[1], 'fine_p_rad_s': p[64],
                        'absolute_difference_rad_s': abs(p[1]-p[64]),
                        'actual_over_fine': p[1]/p[64]}
    check(abs(output['stock_wind']['actual_p_rad_s'] - output['stock_wind']['fine_p_rad_s']) < 1e-6,
          'stock geometry first-tick negative control')
    check(output['wide_wind']['actual_over_fine'] > 1.8
          and output['wide_wind']['absolute_difference_rad_s'] > 1e-4,
          'wide geometry first-tick refinement discrepancy')

    trace_by_path = {t['path']: t for t in traces}
    check(set(trace_by_path) == {stock_path, half_path}, 'two same-start traces')
    for path, trace in trace_by_path.items():
        check(trace['accepted'] and not trace['fault'] and not trace['crash']
              and [r['tick'] for r in trace['rows']] == list(range(2, 49)),
              f'{path}: continued ticks 2–48 accepted')
        check(all(r['rotor_speed'] == 0.0 and len(r['body']) == 13
                  and all(math.isfinite(z) for z in r['body']) for r in trace['rows']),
              f'{path}: held rotor and finite body states throughout trace')
    control = calm[0]
    check(control['accepted'] and control['tick'] == 48 and not control['fault'] and not control['crash'],
          'separate unforced calm control accepted 48 ticks')
    check(abs(control['final'][10]) < 1e-12, 'calm control roll rate remains at rest')
    output['independent_checks'] = checks
    output['ok'] = True
    return output


if __name__ == '__main__':
    if len(sys.argv) != 3:
        raise SystemExit('usage: verify_r8_skid_log.py ENGINE_LOG STOCK_AIRCRAFT_JSON')
    with open(sys.argv[1], encoding='utf-8') as f:
        log = f.read()
    with open(sys.argv[2], encoding='utf-8') as f:
        stock_data = json.load(f)
    print(json.dumps(verify(log, stock_data), indent=2, sort_keys=True))
