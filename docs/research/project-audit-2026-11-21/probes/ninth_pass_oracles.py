#!/usr/bin/env python3
"""Independent R9 algebra against retained observations; requires NumPy.

The 14-DOF mass/Jacobian assembly uses scalar stock JSON, not the GDScript
matrix/contact helpers. A least-norm constraint solution proves capacity
feasibility; it is not a replacement vehicle integrator or a calibrated truck.
The independent nitro calculation covers only the disengaged-clutch interval.
"""
from __future__ import annotations
import argparse
import json
import math
from pathlib import Path
import numpy as np


def records(log):
    result = {}
    for line in log.splitlines():
        if line.startswith("RESULT "):
            _, label, payload = line.split(" ", 2)
            result[label] = json.loads(payload)
        elif line.startswith("R9_") and "=" in line:
            label, payload = line.split("=", 1)
            result[label] = json.loads(payload)
    return result


def mechanics(values):
    """Flat, unsteered, zero-rate state; generalized order v,omega,s_dot,spin."""
    v = values
    ms, mu, g = v['sprung_mass_kg'], v['unsprung_mass_kg'], v['gravity_m_per_s2']
    travel = ms*g/(4*v['suspension_stiffness_n_per_m'])
    radius, arm, inertia = v['tire_radius_m'], v['arm_length_m'], v['wheel_spin_inertia_kg_m2']
    matrix = np.zeros((14, 14))
    matrix[:3, :3] = ms*np.eye(3)
    ix, iy, iz, ixy, ixz, iyz = v['sprung_inertia_kg_m2']
    matrix[3:6, 3:6] = [[ix, ixy, ixz], [ixy, iy, iyz], [ixz, iyz, iz]]
    rows = []
    for corner in range(4):
        lateral = v['corner_y_datum_frd_m'][corner]-v['cg_right_from_datum_m']
        side = math.copysign(1, lateral)
        horizontal = math.sqrt(arm*arm-travel*travel)
        r = np.array([v['corner_x_datum_frd_m'][corner]-v['cg_forward_from_datum_m'],
            lateral+side*(horizontal-arm),
            v['cg_height_above_chassis_datum_m']+v['wheel_center_rest_below_chassis_datum_m']-travel])
        rp = np.array([0., -side*travel/horizontal, -1.])
        jacobian = np.zeros((3, 14))
        jacobian[:, :3] = np.eye(3)
        jacobian[:, 3:6] = [[0, r[2], -r[1]], [-r[2], 0, r[0]], [r[1], -r[0], 0]]
        jacobian[:, 6+corner] = rp
        matrix += mu*jacobian.T@jacobian
        axis = np.array([0., -1., 0.])
        spin = np.zeros(14)
        spin[3:6], spin[10+corner] = axis, 1
        matrix += inertia*np.outer(spin, spin)
        rho = np.array([0., 0., radius])
        for tangent in (np.array([1., 0., 0.]), np.array([0., 1., 0.])):
            row = np.zeros(14)
            row[:3], row[3:6] = tangent, np.cross(r+rho, tangent)
            row[6+corner], row[10+corner] = rp@tangent, axis@np.cross(rho, tangent)
            rows.append(row)
    brake = np.zeros((4, 14))
    brake[np.arange(4), 10+np.arange(4)] = 1
    return matrix, np.array(rows), brake, travel, (ms/4+mu)*g


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--evidence', type=Path, required=True)
    parser.add_argument('--project', type=Path, required=True)
    args = parser.parse_args()
    evidence = json.loads(args.evidence.read_text())
    logs = {row['label']: records(row['engine_log']) for row in evidence['checks']}
    assert evidence['reviewed_commit'] == '77b2d4e64a6a2c6c2a68093e9fdf68c0b111779b'
    assert len(evidence['checks']) == 8
    assert all(row['report']['ok'] and row['report']['counts'] == {'error': 0, 'warning': 0}
               for row in evidence['checks'])
    truck = json.loads((args.project/'data/vehicles/ground/mt8_bisonte.json').read_text())
    v = {key: row['value'] for key, row in truck['parameters'].items()}
    matrix, tangent, brake, travel, load = mechanics(v)
    hull = np.array(v['hull_probe_centers_datum_frd_m'][:3], dtype=float)
    hull -= [v['cg_forward_from_datum_m'], v['cg_right_from_datum_m'], -v['cg_height_above_chassis_datum_m']]
    force = np.array([-1., 0., 0.])
    wall = np.zeros(14)
    wall[:3], wall[3:6] = force, np.cross(hull, force)
    free = np.linalg.solve(matrix, wall)
    measured = logs['walls']['wall_after_solve_adaptive']
    np.testing.assert_allclose(measured['patch_slip_accel_long_lat_m_s2'], tangent@free, rtol=0, atol=1e-10)
    np.testing.assert_allclose(measured['wheel_relative_accel_rad_s2'], brake@free, rtol=0, atol=1e-10)
    assert abs(measured['accel_x_m_s2']-free[0]) < 1e-10
    assert abs(measured['pitch_accel_rad_s2']-free[4]) < 1e-10
    constraints = np.vstack([tangent, brake])
    response = np.linalg.solve(matrix, constraints.T)
    reactions = np.linalg.lstsq(constraints@response, -constraints@free, rcond=None)[0]
    constrained = free+response@reactions
    residual = float(np.max(np.abs(constraints@constrained)))
    assert residual < 1e-10
    capacities = np.array([v['brake_front_fraction']]*2+[1-v['brake_front_fraction']]*2)*2*v['brake_torque_per_wheel_nm']
    assert np.all(np.linalg.norm(reactions[:8].reshape(4, 2), axis=1) < 0.1*0.8*v['tire_friction_scale']*load)
    assert np.all(np.abs(reactions[8:]) < 0.1*capacities)
    output = {'numpy_version': np.__version__, 'wall': {
        'stock_rest_travel_m': travel, 'normal_load_n_per_tyre': load,
        'independent_slip_acceleration_m_s2': (tangent@free).tolist(),
        'independent_relative_wheel_acceleration_rad_s2': (brake@free).tolist(),
        'feasible_constraint_residual': residual, 'feasible_reactions': reactions.tolist(),
        'scope': 'linear zero-velocity frozen-normal stage feasibility, not a trajectory or exact product solve'}}

    # A 10-micrometre lowering increases each normal load by kt*delta.
    # Suspension travel/force and gravity remain unchanged at this instant.
    delta_n = v['tire_stiffness_n_per_m']*1e-5
    extra = np.zeros(14)
    extra[2], extra[6:10] = -4*delta_n, delta_n
    lowered = np.linalg.solve(matrix, extra)
    heading = logs['heading']
    zero, ninety = heading['lowered10um_mu08_heading_0'], heading['lowered10um_mu08_heading_90']
    np.testing.assert_allclose(zero['generalized_accel'], lowered, rtol=0, atol=1e-9)
    np.testing.assert_allclose(zero['slip_accel'], tangent@lowered, rtol=0, atol=1e-9)
    rotated = np.array(ninety['generalized_accel'])
    reactions_90 = np.column_stack([ninety['tire_long_n'], ninety['tire_lat_n']]).reshape(-1)
    np.testing.assert_allclose(matrix@rotated, extra+tangent.T@reactions_90, rtol=0, atol=1e-9)
    assert np.max(np.abs(tangent@rotated)) < 1e-6
    assert zero['sweeps'] == 0 and 0 < ninety['sweeps'] < 128
    for label, tolerance in [('lowered10um_mu0', 1e-10), ('equilibrium_mu08', 1e-9)]:
        np.testing.assert_allclose(heading[label+'_heading_0']['generalized_accel'],
                                   heading[label+'_heading_90']['generalized_accel'], rtol=0, atol=tolerance)
    output['heading'] = {'independent_zero_heading_travel_acceleration_m_s2': lowered[6:10].tolist(),
        'independent_zero_heading_patch_acceleration_m_s2': (tangent@lowered).tolist(),
        'max_travel_acceleration_difference_m_s2': float(np.max(np.abs(lowered[6:10]-rotated[6:10]))),
        'rotated_patch_residual_m_s2': float(np.max(np.abs(tangent@rotated)))}

    nitro = json.loads((args.project/'data/vehicles/ground/monster_car_2.json').read_text())
    p = {key: row['value'] for key, row in nitro['powertrain']['parameters'].items()}
    initial = p['engine_idle_rpm']*math.pi/30
    engage = p['clutch_engage_start_rpm']*math.pi/30
    inertia = p['engine_rotor_inertia_kg_m2']

    def rate(speed, throttle, fuel=True):
        assert 1 < speed < engage
        rpm = speed*30/math.pi
        knots, torques = p['engine_curve_rpm'], p['engine_curve_torque_nm']
        torque = next(torques[i-1]+(torques[i]-torques[i-1])*(rpm-knots[i-1])/(knots[i]-knots[i-1])
                      for i in range(1, len(knots)) if rpm <= knots[i])
        drag = p['engine_drag_torque_nm']+p['engine_viscous_drag_nm_s_per_rad']*speed
        idle = min(p['idle_torque_nm'], drag+max(0., initial-speed)*p['idle_governor_gain_nm_s_per_rad']) if fuel and speed <= initial else 0.
        return ((torque*throttle+idle if fuel else 0.)-drag)/inertia

    def integrate(start, throttle, pieces, fuel=True):
        h = 1/(240*pieces)
        value = start
        for _ in range(pieces): value += h*rate(value+0.5*h*rate(value, throttle, fuel), throttle, fuel)
        return value

    nobs = logs['nitro']['R9_REACTION_RESULT']
    rotor = []
    for row in nobs['results']:
        pieces = row['substeps']
        for throttle, key in [(0, 'neutral'), (1, 'full')]:
            end = integrate(initial, throttle, pieces)
            dh = inertia*(end-initial)
            assert abs(dh-row[key+'_flywheel_delta_h_nms']) < 1e-12
            assert abs(end*30/math.pi-row[key+'_engine_rpm']) < 1e-8
        assert row['body_bytes_equal'] and row['airborne'] and row['clutch_disengaged']
        rotor.append({'pieces': pieces, 'full_delta_h_nms': inertia*(integrate(initial, 1, pieces)-initial)})
    for fuel, key in [(False, 'no_fuel'), (True, 'fuelled')]:
        dh = inertia*(integrate(700., 1, 1, fuel)-700.)
        assert abs(dh-nobs['rundown'][key+'_delta_h_nms']) < 1e-12
    session = logs['session']
    assert session['R9_WALL_SESSION']['accepted_tick'] == 1
    hsession = session['R9_HEADING_SESSION']
    d = max(abs(a-b) for a, b in zip(*[r['travel_rates_after_m_s'] for r in hsession['records']]))
    assert abs(d-hsession['max_travel_rate_difference_m_s']) < 1e-14 and d > 1e-8
    nsession = session['R9_NITRO_SESSION']
    assert nsession['body_bytes_equal']
    for row in nsession['records']:
        assert row['accepted_tick'] == 1
        assert abs(row['flywheel_delta_h_nms']-inertia*(integrate(initial, row['throttle'], 1)-initial)) < 1e-12
    output['nitro'] = {'independent_subdivision_results': rotor, 'no_fuel_delta_h_nms': inertia*(integrate(700., 1, 1, False)-700.),
        'scope': 'scalar rotor change; physical shaft conservation inference requires axis, inventory and external-port definitions'}
    output['session_max_heading_travel_rate_difference_m_s'] = d
    output['ok'] = True
    print('R9_ORACLES='+json.dumps(output, sort_keys=True, allow_nan=False))


if __name__ == '__main__': main()
