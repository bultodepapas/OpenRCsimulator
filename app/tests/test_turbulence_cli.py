"""Real-engine turbulence traces, independent OU verification, and replay checks."""
import csv
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

from check_wind_trace import check


ROOT = Path(__file__).resolve().parents[2]
AIRCRAFT = (
    'jensen-das-ugly-stik-60',
    'gp-extra-300s-60',
    'p51d-mustang-120',
    'sebart-avanti-s-a200-p100rx',
)
BASE_CONFIG = {
    'format': 'openrc-weather v2',
    'speed_mps': 3.0,
    'from_deg': 270.0,
    'gust_mps': 0.0,
    'gust_up_mps': 0.0,
    'gust_duration_s': 4.0,
    'gust_period_s': 12.0,
    'gust_delay_s': 2.0,
    'turbulence_rms_mps': [0.0, 0.6, 0.4],
    'turbulence_tau_s': 0.7,
    'turbulence_seed': 4294967295,
}


def _header_and_rows(path):
    lines = path.read_text(encoding='utf-8').splitlines()
    metadata = {}
    comments = []
    data = []
    for line in lines:
        if line.startswith('# '):
            comments.append(line)
            key, separator, value = line[2:].partition(': ')
            if separator:
                metadata[key] = value
        elif line:
            data.append(line)
    rows = list(csv.reader(data))
    return comments, metadata, rows


def _write_trace(path, comments, rows, metadata_changes=None, row_change=None, remove_row=None):
    changes = metadata_changes or {}
    updated = []
    for line in comments:
        key, separator, _value = line[2:].partition(': ')
        if separator and key in changes:
            updated.append('# %s: %s' % (key, changes.pop(key)))
        else:
            updated.append(line)
    if changes:
        raise AssertionError('metadata key missing from fixture: ' + ', '.join(changes))
    table = [row.copy() for row in rows]
    if row_change is not None:
        row_index, column, value = row_change
        table[row_index][table[0].index(column)] = value
    if remove_row is not None:
        del table[remove_row]
    buffer = io.StringIO()
    writer = csv.writer(buffer, lineterminator='\n')
    writer.writerows(table)
    path.write_text('\n'.join(updated) + '\n' + buffer.getvalue(), encoding='utf-8')


class TurbulenceCLI(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.engine = os.environ.get('OPENRC_TEST_GODOT') or subprocess.check_output(
            [str(ROOT / 'app/get-godot.sh')], text=True).strip()
        cls.work = tempfile.TemporaryDirectory(prefix='openrc-turbulence-cli-')
        cls.directory = Path(cls.work.name)
        cls.environment = dict(os.environ, XDG_DATA_HOME=str(cls.directory / 'data'))
        cls.default_trace = cls.directory / 'default.csv'
        cls.custom_trace = cls.directory / 'custom.csv'
        cls.zero_trace = cls.directory / 'zero-rms-v4.csv'
        cls._write_real_trace(cls.default_trace, ['--weather=turbulent'])
        cls.custom_config = dict(BASE_CONFIG)
        cls._write_weather_file_trace(cls.custom_trace, cls.custom_config)
        zero_config = dict(BASE_CONFIG)
        zero_config.update(speed_mps=1.0, turbulence_rms_mps=[0.0, 0.0, 0.0])
        cls._write_weather_file_trace(cls.zero_trace, zero_config)

        # The GDScript flight contract writes a short trace from tick 40, carrying
        # the exact OU window and raw RNG state captured when recording starts.
        cls._run_engine(['--script', 'res://tests/test_turbulence_flight.gd'])
        cls.midflight_trace = cls.directory / 'midflight.csv'
        shutil.copyfile('/tmp/openrc-turbulence-midflight.csv', cls.midflight_trace)
        cls.long_clock_trace = cls.directory / 'long-clock.csv'
        shutil.copyfile('/tmp/openrc-turbulence-long-clock.csv', cls.long_clock_trace)

    @classmethod
    def tearDownClass(cls):
        cls.work.cleanup()

    @classmethod
    def _run_engine(cls, arguments, success=True):
        result = subprocess.run(
            [cls.engine, '--headless', '--path', str(ROOT / 'app'), '--audio-driver', 'Dummy', *arguments],
            capture_output=True, text=True, timeout=180, env=cls.environment,
        )
        log = result.stdout + result.stderr
        if success:
            if result.returncode != 0 or re.search(r'^(?:SCRIPT |SHADER )?ERROR:', log, re.M):
                raise AssertionError(log)
        elif result.returncode == 0 or 'weather refused:' not in log:
            raise AssertionError('invalid weather was not refused: ' + log)
        return log

    @classmethod
    def _write_real_trace(cls, path, arguments):
        cls._run_engine(['--', *arguments, '--trace=' + str(path), '--t=.1'])
        if not path.is_file():
            raise AssertionError('engine did not write trace: ' + str(path))

    @classmethod
    def _write_weather_file_trace(cls, path, config):
        source = cls.directory / (path.stem + '-weather.json')
        source.write_text(json.dumps(config), encoding='utf-8')
        cls._run_engine(['--', '--weather-file=' + str(source), '--trace=' + str(path), '--t=.1'])
        if not path.is_file():
            raise AssertionError('engine did not write trace: ' + str(path))

    def test_real_default_and_nondefault_pcgs_match_independent_decoder(self):
        default = check(self.default_trace, .1)
        self.assertEqual((default['rows'], default['first_tick'], default['last_tick']), (25, 0, 24))
        custom = check(self.custom_trace, .1)
        self.assertEqual((custom['rows'], custom['first_tick'], custom['last_tick']), (25, 0, 24))
        self.assertTrue(-(1 << 63) <= custom['recording_start_rng_state'] < (1 << 63))
        _, metadata, _ = _header_and_rows(self.custom_trace)
        config = json.loads(metadata['weather_config'])
        self.assertEqual(config['turbulence_tau_s'], .7)
        self.assertEqual(config['turbulence_seed'], 4294967295)

    def test_real_trace_reader_supports_all_flyable_aircraft(self):
        for aircraft in AIRCRAFT:
            with self.subTest(aircraft=aircraft):
                trace = self.directory / (aircraft + '.csv')
                self._write_real_trace(trace, ['--weather=turbulent', '--aircraft=' + aircraft])
                result = check(trace, .1)
                self.assertEqual(result['rows'], 25)
                self.assertGreaterEqual(result['turbulence_aux_index'], 4)

    def test_midflight_recording_resumes_from_exact_window_and_rng_state(self):
        result = check(self.midflight_trace)
        self.assertEqual((result['rows'], result['first_tick'], result['last_tick']), (9, 40, 48))
        self.assertGreaterEqual(result['recording_start_rng_state'], -(1 << 63))

    def test_late_recording_preserves_weather_timestep_precision(self):
        result = check(self.long_clock_trace)
        self.assertEqual((result['rows'], result['first_tick'], result['last_tick']),
                         (9, 100000000, 100000008))

    def test_v4_reader_allows_v2_config_with_zero_rms(self):
        result = check(self.zero_trace, .1)
        self.assertEqual((result['rows'], result['first_tick'], result['last_tick']), (25, 0, 24))
        self.assertNotIn('max_turbulence_error_mps', result)
        _, metadata, _ = _header_and_rows(self.zero_trace)
        self.assertEqual(metadata['format'], 'openrc-trace v4')
        self.assertEqual(json.loads(metadata['weather_config'])['turbulence_rms_mps'], [0.0, 0.0, 0.0])

    def test_reader_rejects_turbulence_state_config_and_cadence_mutations(self):
        comments, metadata, rows = _header_and_rows(self.midflight_trace)
        raw_state = int(metadata['recording_start_rng_state'])
        config = json.loads(metadata['weather_config'])
        cases = (
            ('current noise', {}, (2, 'turbulence_north_mps', '99'), None),
            ('force noise', {}, (3, 'loads_turbulence_down_mps', '99'), None),
            ('nonfinite row', {}, (2, 'tas_mps', 'nan'), None),
            ('raw PCG state', {'recording_start_rng_state': str(raw_state + 1)}, None, None),
            ('noncanonical raw PCG state', {'recording_start_rng_state': '01'}, None, None),
            ('raw PCG state overflow', {'recording_start_rng_state': '9223372036854775808'}, None, None),
            ('tau replay', {'weather_config': json.dumps({**config, 'turbulence_tau_s': .71}, separators=(',', ':'))}, None, None),
            ('nonfinite tau', {'weather_config': json.dumps({**config, 'turbulence_tau_s': float('inf')}, separators=(',', ':'))}, None, None),
            ('tick gap', {}, None, 4),
            ('window origin', {'recording_start_turbulence': '[0,0,0,0,0,0,0.17]'}, None, None),
            ('nonfinite window', {'recording_start_turbulence': '[NaN,0,0,0,0,0,0.1625]'}, None, None),
            ('out-of-range RMS', {'weather_config': json.dumps({**config, 'turbulence_rms_mps': [3.01, .5, .1]}, separators=(',', ':'))}, None, None),
            ('uint32 seed overflow', {'weather_config': json.dumps({**config, 'turbulence_seed': 4294967296}, separators=(',', ':'))}, None, None),
        )
        for label, metadata_changes, row_change, remove_row in cases:
            with self.subTest(mutation=label):
                path = self.directory / 'mutation.csv'
                _write_trace(path, comments.copy(), rows, metadata_changes.copy(), row_change, remove_row)
                with self.assertRaises(ValueError):
                    check(path)

    def test_zero_rms_component_stays_exactly_zero(self):
        comments, _metadata, rows = _header_and_rows(self.custom_trace)
        for column in ('turbulence_north_mps', 'loads_turbulence_north_mps'):
            with self.subTest(column=column):
                path = self.directory / 'zero-axis-mutation.csv'
                _write_trace(path, comments.copy(), rows, row_change=(2, column, '0.000000001'))
                with self.assertRaises(ValueError):
                    check(path)

    def test_tick_zero_reader_reconstructs_stationary_seed_and_start_body(self):
        comments, metadata, rows = _header_and_rows(self.default_trace)
        raw_state = int(metadata['recording_start_rng_state'])
        window = json.loads(metadata['recording_start_turbulence'])
        previous = json.loads(metadata['recording_start_previous_state'])
        config = json.loads(metadata['weather_config'])
        changed_window = window.copy()
        changed_window[0] += .001
        changed_previous = previous.copy()
        changed_previous[0] += .01
        changed_config = config.copy()
        changed_config['turbulence_seed'] = (config['turbulence_seed'] + 1) % (1 << 32)
        cases = (
            ('raw state', {'recording_start_rng_state': str(raw_state + 1)}),
            ('initial sample', {'recording_start_turbulence': json.dumps(changed_window, separators=(',', ':'))}),
            ('previous body', {'recording_start_previous_state': json.dumps(changed_previous, separators=(',', ':'))}),
            ('seed', {'weather_config': json.dumps(changed_config, separators=(',', ':'))}),
        )
        for label, metadata_changes in cases:
            with self.subTest(mutation=label):
                path = self.directory / 'tick-zero-mutation.csv'
                _write_trace(path, comments.copy(), rows, metadata_changes.copy())
                with self.assertRaises(ValueError):
                    check(path)

        forged = Path('/tmp/openrc-forged-tick0.csv')
        if forged.is_file():
            with self.assertRaises(ValueError):
                check(forged)

    def test_engine_refuses_invalid_uint32_turbulence_seed_before_recording(self):
        for seed in (-1, 4294967296, 1.5):
            with self.subTest(seed=seed):
                config = dict(BASE_CONFIG, turbulence_seed=seed)
                source = self.directory / 'invalid-seed.json'
                trace = self.directory / 'refused.csv'
                source.write_text(json.dumps(config), encoding='utf-8')
                self._run_engine(['--', '--weather-file=' + str(source), '--trace=' + str(trace), '--t=.1'], success=False)
                self.assertFalse(trace.exists())

    def test_turbulent_checkpoint_hash_is_fixed_frame_rate_independent(self):
        hashes = []
        for fps in (30, 60, 144):
            with self.subTest(fps=fps):
                log = self._run_engine([
                    '--fixed-fps', str(fps), '--script', 'res://tests/run_fixed_step.gd', '--', '--weather=turbulent',
                ])
                match = re.search(r'^flight_sha256=([0-9a-f]{64})$', log, re.M)
                self.assertIsNotNone(match, log)
                hashes.append(match.group(1))
                self.assertIsNotNone(re.search(r'^ticks=480 ', log, re.M), log)
        self.assertEqual(hashes[0], hashes[1])
        self.assertEqual(hashes[1], hashes[2])


if __name__ == '__main__':
    unittest.main()
