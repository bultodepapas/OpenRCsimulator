"""G2a/G2b real-app launch, telemetry refusal, weather and fixed-frame replay."""
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

from check_trimmed_flight import check as check_calm
from check_trimmed_flight import check_coupled_metadata
from check_wind_trace import check as check_wind
from check_atmosphere_trace import check as check_air
from test_atmosphere_cli import MIXED_CONFIG, _read_parts, _rewrite_trace

ROOT = Path(__file__).resolve().parents[2]
AIRCRAFT = 'p51d-mustang-120'
MODE = ['--aircraft=' + AIRCRAFT, '--shaft-integrator=coupled-rk4']


class ShaftCLI(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.engine = os.environ.get('OPENRC_TEST_GODOT') or subprocess.check_output(
            [str(ROOT / 'app/get-godot.sh')], text=True).strip()
        cls.work = tempfile.TemporaryDirectory(prefix='openrc-shaft-cli-')
        cls.directory = Path(cls.work.name)

    @classmethod
    def tearDownClass(cls):
        cls.work.cleanup()

    def run_engine(self, arguments, success=True, prefix=()):
        result = subprocess.run([self.engine, '--headless', '--audio-driver', 'Dummy',
                                 '--path', str(ROOT / 'app'), *prefix, '--', *arguments],
                                capture_output=True, text=True, timeout=45)
        log = result.stdout + result.stderr
        self.assertEqual(result.returncode == 0, success, log)
        self.assertNotRegex(log, r'(?m)^(?:SCRIPT |SHADER )?ERROR:')
        return log

    def trace(self, name, options):
        path = self.directory / (name + '.csv')
        self.run_engine([*MODE, *options, '--trace=' + str(path), '--t=0.25'])
        return path

    def test_reference_trim_and_model_identity(self):
        path = self.trace('reference', [])
        check_calm(path, 0.25, 240)
        _, metadata, table = _read_parts(path)
        self.assertEqual(metadata['propulsion_model'], 'propeller-shaft-coupled-rk4-v1')
        self.assertEqual(metadata['shaft_integrator'], 'coupled-rk4')
        self.assertEqual(len(table) - 1, 61)
        wheel_layout = json.loads(metadata['wheel_state_layout'])
        self.assertEqual(metadata['metadata_schema'], 'openrc-flight-meta v6')
        self.assertEqual(metadata['wheel_state_model'], 'relative-wheel-rim-speed-rk4-v1')
        battery_slots = 3 if metadata['continuous_layout'].startswith(
            'axial wash increment m/s, slipstream.pieces order, then propeller shaft rpm, remaining charge C,') else 0
        shaft_index = wheel_layout[0]['index'] - battery_slots - 1
        self.assertGreaterEqual(shaft_index, 0)
        self.assertAlmostEqual(json.loads(metadata['recording_start_continuous'])[shaft_index],
                               json.loads(metadata['recording_start_aux'])[0], places=10)
        self.assertEqual(wheel_layout[-1]['index'] + 1,
                         len(json.loads(metadata['recording_start_continuous'])))

    def test_explicit_split_preserves_default_rows(self):
        rows = []
        for name, options in [('default', []), ('split', ['--shaft-integrator=split'])]:
            path = self.directory / (name + '.csv')
            self.run_engine(['--aircraft=' + AIRCRAFT, *options,
                             '--trace=' + str(path), '--t=0.25'])
            check_calm(path, 0.25, 240)
            rows.append(_read_parts(path)[2])
        self.assertEqual(*rows)

    def test_invalid_mode_and_unsupported_models_refuse_before_recording(self):
        cases = [
            ['--shaft-integrator=unknown'], ['--shaft-integrator'],
            ['--shaft-integrator=coupled-rk4'],
            ['--aircraft=sebart-avanti-s-a200-p100rx', '--shaft-integrator=coupled-rk4'],
            [*MODE, '--scripted'],
        ]
        for index, options in enumerate(cases):
            with self.subTest(options=options):
                path = self.directory / f'refused-{index}.csv'
                log = self.run_engine([*options, '--trace=' + str(path), '--t=0.1'], False)
                self.assertIn('shaft integrator refused', log)
                self.assertFalse(path.exists())

    def test_stage_weather_and_custom_air_traces(self):
        wind = self.trace('wind', ['--weather=crosswind'])
        check_wind(wind, 0.25)
        custom = self.trace('hot-high', ['--weather=hot-high'])
        check_air(custom, 0.25)
        weather_path = self.directory / 'mixed.json'
        weather_path.write_text(json.dumps(MIXED_CONFIG))
        mixed = self.trace('mixed', ['--weather-file=' + str(weather_path)])
        result = check_air(mixed, 0.25)
        self.assertEqual(result['rows'], 61)

    def test_corrupted_coupled_metadata_is_rejected(self):
        for name, options, reader in [
            ('calm-negative', [], lambda p: check_calm(p, 0.25, 240)),
            ('air-negative', ['--weather=hot-high'], lambda p: check_air(p, 0.25)),
        ]:
            source = self.trace(name, options)
            _, metadata, _ = _read_parts(source)
            wheel_layout = json.loads(metadata['wheel_state_layout'])
            wheel_brakes = json.loads(metadata['wheel_brakes'])
            duplicate_indices = [dict(entry) for entry in wheel_layout]
            duplicate_indices[1]['index'] = duplicate_indices[0]['index']
            wrong_contact_brakes = [dict(brake) for brake in wheel_brakes]
            wrong_contact_brakes[0]['contact'] = 'unexpected-contact'
            mutations = [
                ('shaft_integrator', 'split'), ('rotor_coupling', 'unknown'),
                ('propulsion_model', 'propeller-shaft-balance-v1'),
                ('recording_start_continuous', '[-1]'),
                ('recording_start_continuous', '[true]'),
                ('recording_start_continuous', '[123]'),
                ('metadata_schema', 'openrc-flight-meta v5'),
                ('wheel_state_model', 'relative-wheel-rim-speed-euler-v1'),
                ('wheel_state_layout', '[]'),
                ('wheel_state_layout', json.dumps(duplicate_indices)),
                ('wheel_profile_status', 'missing'),
                ('wheel_profile_sha256', 'not-a-sha256'),
                ('wheel_profile_input_sha256', 'A' * 64),
                ('wheel_profile_hash_convention', 'sha256 of unspecified JSON'),
                ('launch_continuous', '[]'),
                ('launch_continuous', '[NaN]'),
                ('wheel_brakes', json.dumps(wrong_contact_brakes)),
                ('continuous_layout', metadata['continuous_layout'].replace(
                    'wheel rim speeds in m/s, landing-gear contact order, appended continuous tail',
                    'wheels somewhere in the state')),
            ]
            for key, value in mutations:
                with self.subTest(trace=name, key=key, value=value):
                    changed = self.directory / 'corrupted.csv'
                    _rewrite_trace(source, changed, {key: value})
                    with self.assertRaises(ValueError):
                        reader(changed)

    def test_complete_coupled_checkpoint_is_frame_rate_independent(self):
        hashes = []
        for fps in (30, 60, 144):
            log = self.run_engine([*MODE, '--weather=hot-high'], prefix=[
                '--fixed-fps', str(fps), '--script', 'res://tests/run_fixed_step.gd'])
            match = re.search(r'^flight_sha256=([0-9a-f]{64})$', log, re.M)
            self.assertIsNotNone(match, log)
            self.assertRegex(log, r'(?m)^ticks=480 ')
            hashes.append(match.group(1))
        self.assertEqual(hashes[0], hashes[1])
        self.assertEqual(hashes[1], hashes[2])

    def test_signed_transport_is_distinct_from_nonnegative_rpm(self):
        metadata = {
            'propulsion_model': 'propeller-shaft-coupled-rk4-v1', 'shaft_integrator': 'coupled-rk4',
            'rotor_coupling': 'relative-spin-locked-inertia-reaction-v1',
            'continuous_layout': 'axial wash increment m/s, slipstream.pieces order, then propeller shaft rpm; RK4 coupled',
            'propwash_model': 'tail-slipstream-axial-transport-v1',
            'recording_start_continuous': '[-0.25, 1234.0]', 'recording_start_aux': '[1234.0, 0, 0, 0]',
        }
        check_coupled_metadata(metadata)
        metadata['recording_start_continuous'] = '[-0.25, -1]'
        with self.assertRaises(ValueError):
            check_coupled_metadata(metadata)
        metadata['recording_start_continuous'] = '[-0.25, 1234.0]'
        metadata['propwash_model'] = 'tail-slipstream-increment-v1'
        with self.assertRaises(ValueError):
            check_coupled_metadata(metadata)

    @staticmethod
    def wheel_metadata(*, shaft=True, battery=False):
        contacts = ['main_left', 'main_right']
        wash_count = 1 if shaft else 0
        shaft_slots = 1 if shaft else 0
        battery_slots = 3 if battery else 0
        first_wheel = wash_count + shaft_slots + battery_slots
        continuous = [-0.25, 1234.0, 3600.0, 120.0, 4.0] if battery else (
            [-0.25, 1234.0] if shaft else [])
        continuous.extend([0.2, -0.1])
        base_layout = (
            'axial wash increment m/s, slipstream.pieces order, then propeller shaft rpm, '
            'remaining charge C, terminal energy J, pack heat J; RK4 coupled' if battery else
            'axial wash increment m/s, slipstream.pieces order, then propeller shaft rpm; RK4 coupled'
            if shaft else 'none'
        )
        metadata = {
            'metadata_schema': 'openrc-flight-meta v6',
            'propulsion_model': ('electric-ocv-resistance-coupled-events-v1' if battery else
                                 'propeller-shaft-coupled-rk4-v1' if shaft else 'propeller-rpm-lag-v1'),
            'propwash_model': 'tail-slipstream-axial-transport-v1' if shaft else 'none',
            'shaft_integrator': 'coupled-rk4' if shaft else None,
            'rotor_coupling': 'relative-spin-locked-inertia-reaction-v1' if shaft else None,
            'continuous_layout': base_layout + '; wheel rim speeds in m/s, landing-gear contact order, appended continuous tail',
            'recording_start_aux': '[1234.0, 0, 0, 0]',
            'recording_start_continuous': json.dumps(continuous),
            'launch_continuous': json.dumps(continuous),
            'wheel_state_model': 'relative-wheel-rim-speed-rk4-v1',
            'wheel_state_layout': json.dumps([
                {'index': first_wheel + index, 'contact': contact, 'unit': 'm/s rim speed'}
                for index, contact in enumerate(contacts)
            ]),
            'wheel_profile_status': 'applied',
            'wheel_profile_sha256': 'a' * 64,
            'wheel_profile_input_sha256': 'b' * 64,
            'wheel_profile_hash_convention': (
                'profile_sha256 is canonical JSON for the selected aircraft profile; '
                'input_sha256 is SHA-256 of exact wheel_profiles.json bytes'),
            'wheel_brakes': json.dumps([
                {'contact': contact, 'availability': 'none', 'max_torque_nm': 0.0}
                for contact in contacts
            ]),
        }
        if not shaft:
            metadata.pop('shaft_integrator')
            metadata.pop('rotor_coupling')
        return metadata

    def test_wheeled_v6_states_follow_shaft_and_battery_prefixes(self):
        shaft = self.wheel_metadata()
        check_coupled_metadata(shaft)
        battery = self.wheel_metadata(battery=True)
        check_coupled_metadata(battery)
        self.assertEqual(json.loads(battery['recording_start_continuous'])[1],
                         json.loads(battery['recording_start_aux'])[0])

    def test_wheeled_v6_without_shaft_keeps_legacy_nonshaft_contract(self):
        metadata = self.wheel_metadata(shaft=False)
        metadata['continuous_layout'] = 'none; wheel rim speeds in m/s, landing-gear contact order, appended continuous tail'
        check_coupled_metadata(metadata)

    def test_malformed_wheel_tail_is_rejected(self):
        good = self.wheel_metadata()
        bad_cases = []
        for key, value in [
            ('wheel_state_layout', json.dumps([
                {'index': 1, 'contact': 'main_left', 'unit': 'm/s rim speed'},
                {'index': 3, 'contact': 'main_right', 'unit': 'm/s rim speed'},
            ])),
            ('wheel_state_layout', json.dumps([
                {'index': 2, 'contact': 'main_left', 'unit': 'm/s'},
                {'index': 3, 'contact': 'main_right', 'unit': 'm/s rim speed'},
            ])),
            ('recording_start_continuous', '[-0.25, 1234.0, NaN, -0.1]'),
            ('launch_continuous', '[-0.25, 1234.0, 0.2]'),
            ('wheel_brakes', '[{"contact":"main_left","availability":"none","max_torque_nm":NaN}]'),
        ]:
            changed = dict(good)
            changed[key] = value
            bad_cases.append((key, changed))
        omitted = dict(good)
        omitted.pop('wheel_profile_input_sha256')
        bad_cases.append(('missing wheel_profile_input_sha256', omitted))
        oversized = dict(good)
        oversized['recording_start_continuous'] = json.dumps([-0.25, 1234.0, 10 ** 400, -0.1])
        bad_cases.append(('oversized wheel speed', oversized))
        for key, changed in bad_cases:
            with self.subTest(key=key):
                with self.assertRaises(ValueError):
                    check_coupled_metadata(changed)


if __name__ == '__main__':
    unittest.main()
