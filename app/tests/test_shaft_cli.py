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
        self.assertAlmostEqual(json.loads(metadata['recording_start_continuous'])[-1],
                               json.loads(metadata['recording_start_aux'])[0], places=10)

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
            for key, value in [('shaft_integrator', 'split'), ('rotor_coupling', 'unknown'),
                               ('propulsion_model', 'propeller-shaft-balance-v1'),
                               ('recording_start_continuous', '[-1]'),
                               ('recording_start_continuous', '[true]'),
                               ('recording_start_continuous', '[123]')]:
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


if __name__ == '__main__':
    unittest.main()
