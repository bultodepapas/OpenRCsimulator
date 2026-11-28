"""Exercise stock propulsion maps through the standalone native production headers.

Run: python3 propulsion_probe.py /path/to/OpenRCsimulator
Requires an x86-64 GCC-compatible compiler or Apple ARM64 Clang and Python 3.
The compiled executable lives in a temporary directory. No repository files are changed.
"""
import argparse
import collections
import json
import math
import os
from pathlib import Path
import subprocess
import tempfile


def value(fields, name):
    return fields[name]['value']


def flatten_table(fields, name):
    knots = value(fields, name)
    return [len(knots), *(term for pair in knots for term in pair)]


def encode_aircraft(repo):
    aircraft = repo / 'app/data/aircraft'
    inputs, gas_oracles = [], {}
    for name in ('p51d_mustang_120', 'f4u_corsair_250'):
        prop = json.loads((aircraft / (name + '.json')).read_text())['propulsion']
        blade, engine, fuel = prop['propeller'], prop['engine'], prop['fuel_consumption']
        shaft = engine['shaft']
        offset = value(blade, 'thrust_line_offset')
        row = ['gas', name, value(blade, 'diameter'), value(blade, 'rotating_inertia'), *offset, *value(blade, 'thrust_angles')]
        for table in ('ct_table', 'cp_table', 'normal_force', 'pfactor_moment'):
            row.extend(flatten_table(blade, table))
        idle, idle_rpm = value(shaft, 'idle_power'), value(engine, 'idle_rpm')
        friction = value(shaft, 'friction_torque')
        idle_flow, bsfc = value(fuel, 'idle_flow'), value(fuel, 'bsfc')
        omega = idle_rpm * math.tau / 60
        idle_loss = (friction[0] + friction[1] * idle_rpm / 1000) * omega
        gas_oracles[name] = dict(idle_indicated_w=idle, idle_brake_w=idle-idle_loss,
                                 idle_friction_w=idle_loss, bsfc=bsfc, idle_flow_kg_s=idle_flow, offset=offset)
        row.extend([*flatten_table(shaft, 'power_curve'), *friction, idle, value(shaft, 'peak_indicated_power'), idle_rpm, bsfc, idle_flow])
        inputs.append(row)
    for path in sorted((repo / 'app/data/glow').glob('*.json')):
        installation = json.loads(path.read_text())
        if installation.get('format') != 'openrc-glow-installation v2':
            continue
        blade = installation['propeller']
        keys = ('diameter_m', 'pitch_m', 'chord_m', 'lift_slope', 'cd0', 'induced_drag', 'blades')
        inputs.append(['glow', path.stem, *(value(blade, key) for key in keys), blade.get('zero_lift_angle_rad', {}).get('value', 0)])
    for name in ('os_max_55ax_candidate', 'os_fs_64v_candidate'):
        p = json.loads((repo / 'app/data/glow' / (name + '.json')).read_text())
        fuel, op, params = p['fuel'], p['operation'], p['parameters']
        nitro, oil = value(fuel, 'nitromethane_volume_fraction'), value(fuel, 'lubricant_volume_fraction')
        methanol_mass = (1-nitro-oil)*value(fuel, 'methanol_density_kg_m3')
        nitro_mass = nitro*value(fuel, 'nitromethane_density_kg_m3')
        oil_mass = oil*value(fuel, 'lubricant_density_kg_m3')
        combustible = methanol_mass+nitro_mass
        def weighted(key):
            return (methanol_mass*value(fuel, 'methanol_'+key) + nitro_mass*value(fuel, 'nitromethane_'+key))/combustible
        two = p['family'] == 'glow_2t'
        row = ['glow_source', name, 2 if two else 4, value(op, 'max_rpm'), value(params, 'displacement_m3'),
               oil_mass/(combustible+oil_mass), weighted('stoich_air_fuel_ratio'), weighted('lhv_j_kg'),
               0 if two else value(params, 'intake_pressure_drop_pa')]
        for table in ('delivery_ratio' if two else 'volumetric_efficiency', 'scavenge_pressure_pa' if two else 'pumping_pressure_pa',
                      'mechanical_torque_nm', 'combustion_efficiency', 'indicated_efficiency',
                      'trapping_efficiency' if two else 'valve_torque_nm'):
            row.extend(flatten_table(params, table))
        row.extend(value(op, key) for key in ('rated_rpm', 'nominal_mixture', 'reference_dry_density_kg_m3', 'rated_power_w'))
        inputs.append(row)
    name = 'sebart_avanti_s_a200'
    engine = json.loads((aircraft / (name + '.json')).read_text())['propulsion']['engine']
    keys = ('max_rpm', 'governor_tau', 'installed_factor', 'ram_flow', 'rotor_inertia', 'rotor_sense')
    row = ['turbine', name, *(value(engine, key) for key in keys)]
    for table in ('throttle_map', 'accel_limit', 'decel_limit', 'static_thrust', 'mass_flow', 'ram_jet', 'fuel_flow'):
        row.extend(flatten_table(engine, table))
    inputs.append(row)
    return '\n'.join(' '.join(map(str, row)) for row in inputs), gas_oracles


def summarize(raw, gas_oracles):
    records = collections.defaultdict(lambda: collections.defaultdict(list))
    for line in raw.splitlines():
        name, test, *values = line.split()
        records[name][test].append(list(map(float, values)))
    closures = {}
    for name, expected in gas_oracles.items():
        group = records[name]
        assert group['hub_zero'] == [[0] * 9]
        delta = group['hub_pitch'][0]
        # In FRD, r=[-offset_aft, right, -offset_up], omega=[0,2,0].
        expected_delta = [-2*expected['offset'][2], 0, 2*expected['offset'][0]]
        assert all(math.isclose(a, b, abs_tol=2e-14) for a, b in zip(delta[:3], expected_delta))
        assert any(abs(number) > 1e-3 for number in delta[3:])
        brake_50, actual_flow = group['fuel_50'][0]
        assert math.isclose(brake_50, expected['idle_brake_w'] + 50, abs_tol=1e-11)
        assert actual_flow == expected['idle_flow_kg_s']
        physical_reference_flow = expected['idle_flow_kg_s'] + expected['bsfc']*50/3_600_000
        sampled = {(rpm, u): [thrust, torque, off_rate] for rpm, u, thrust, torque, off_rate in group['advance']}
        assert all(sampled[0, u] == [0, 0, 0] for u in (0, 20, 30, 40))
        assert sampled[4500, -20][:2] == sampled[4500, 0][:2]
        assert sampled[100, 20][:2] == sampled[100, 40][:2]
        closures[name] = {
            'uniform_to_spatial_velocity_delta_m_s': delta[:3],
            'uniform_to_spatial_wrench_delta_N_Nm': delta[3:],
            'idle_indicated_brake_loss_W': [expected['idle_indicated_w'], expected['idle_brake_w'], expected['idle_friction_w']],
            'brake_50W_above_idle_W': brake_50,
            'fuel_current_vs_brake_anchored_kg_h_at_idle_plus50W': [actual_flow*3600, physical_reference_flow*3600],
            'fuel_current_vs_brake_anchored_kg_h_at_idle_plus500W': [group['fuel_500'][0][1]*3600, (expected['idle_flow_kg_s']+expected['bsfc']*500/3_600_000)*3600],
            'thrust_N_torque_Nm_source_off_rpm_per_s_at_RPM0_U40': sampled[0, 40],
            'thrust_N_torque_Nm_source_off_rpm_per_s_at_RPM100_U20_or40': sampled[100, 20],
            'thrust_N_torque_Nm_source_off_rpm_per_s_at_RPM3000_U30': sampled[3000, 30],
            'thrust_N_torque_Nm_at_RPM4500_Uminus20_or0': sampled[4500, 0][:2],
        }
    for name, group in records.items():
        if 'glow_stopped' in group:
            stopped = next(row for row in group['glow_stopped'] if row[0] == 20)
            assert stopped[1] < 0 and stopped[2] < 0
            ratio = group['glow_min_positive_thrust_power_ratio'][0][0]
            assert ratio >= 1
            closures[name] = {'stopped_U20_thrust_N_torque_Nm_dissipation_W': stopped[1:], 'min_power_ratio_glow_J0_to2': ratio}
        if 'turbine' in group:
            mid = [row for row in group['turbine'] if row[0] == 110000]
            assert mid[0][2] == mid[1][2] and mid[0][4] == mid[1][4] and mid[0][3] < 0 < mid[1][3]
            runs = {tuple(row[:2]): row[2:] for row in group['turbine_six_seconds']}
            for command in (0, 1):
                assert all(abs(a-b) < 2e-5 for a, b in zip(runs[240, command][:2], runs[480, command][:2]))
                assert abs(runs[240, command][2]-runs[480, command][2]) < 1e-7
            closures[name] = {'rpm_command_installed_thrust_N_spool_rate_rpm_s_fuel_kg_s_rotor_power_W': group['turbine'],
                              'scalar_RK4_hz_command_t10_s_t90_s_six_second_burn_kg': group['turbine_six_seconds']}
        if 'glow_source' in group:
            results = []
            for row in group['glow_source']:
                strokes, dry, rpm, rated, freq, torque, brake, indicated, chemical, fuel_power, delivered, burned, unburned, *losses = row
                assert math.isclose(freq, rpm / (60 if strokes == 2 else 120), rel_tol=1e-14)
                assert math.isclose(brake, torque*rpm*math.tau/60, rel_tol=1e-14)
                assert math.isclose(brake, indicated-sum(losses), rel_tol=1e-14)
                assert 0 <= brake <= indicated <= chemical <= fuel_power
                assert math.isclose(delivered, burned+unburned, rel_tol=1e-14)
                results.append([dry, rated, freq, brake, torque, indicated, delivered])
            assert math.isclose(results[1][5]/results[0][5], 0.85, rel_tol=1e-12)
            closures[name] = {'dry_density_ratio_rating_W_opportunities_Hz_brake_W_torque_Nm_indicated_W_premix_kg_s': results}
    return closures


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('repo', type=Path, default=Path.cwd(), nargs='?')
    args = parser.parse_args()
    inputs, gas = encode_aircraft(args.repo)
    with tempfile.TemporaryDirectory() as tmp:
        exe = str(Path(tmp) / 'propulsion_probe')
        compiler = os.environ.get('CXX', 'g++')
        flags = ['-std=c++17', '-O1', '-fno-fast-math', '-ffp-contract=off']
        headers = args.repo / 'research/native-kernel/src'
        subprocess.run([compiler, *flags, '-I', str(headers), str(Path(__file__).with_suffix('.cpp')), '-o', exe], check=True)
        run = subprocess.run([exe], input=inputs, text=True, capture_output=True, check=True)
    print(json.dumps(summarize(run.stdout, gas), indent=2, sort_keys=True))


if __name__ == '__main__':
    main()
