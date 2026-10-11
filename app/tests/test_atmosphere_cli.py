"""Real-engine atmospheric traces, independent verification, and replay checks."""
import csv
import io
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

from check_atmosphere_trace import check


ROOT = Path(__file__).resolve().parents[2]
AIRCRAFT = (
    'jensen-das-ugly-stik-60',
    'gp-extra-300s-60',
    'p51d-mustang-120',
    'sebart-avanti-s-a200-p100rx',
)
MIXED_CONFIG = {
    'format': 'openrc-weather v3',
    'speed_mps': 2.0,
    'from_deg': 270.0,
    'gust_mps': 1.0,
    'gust_up_mps': 0.25,
    'gust_duration_s': 2.0,
    'gust_period_s': 5.0,
    'gust_delay_s': 0.25,
    'turbulence_rms_mps': [0.3, 0.5, 0.2],
    'turbulence_tau_s': 0.7,
    'turbulence_seed': 1234567,
    'atmosphere_mode': 'custom',
    'field_elevation_m': 750.0,
    'temperature_c': 28.0,
    'qnh_hpa': 1008.0,
    'relative_humidity_pct': 60.0,
}


def _read_parts(path):
    comments = []
    data_lines = []
    metadata = {}
    for line in path.read_text(encoding='utf-8').splitlines():
        if line.startswith('# '):
            comments.append(line)
            key, separator, value = line[2:].partition(': ')
            if separator:
                metadata[key] = value
        elif line:
            data_lines.append(line)
    return comments, metadata, list(csv.reader(data_lines))


def _rewrite_trace(source, target, metadata_changes=None, row_change=None,
                   header_change=None, remove_row=None):
    comments, _metadata, table = _read_parts(source)
    changes = dict(metadata_changes or {})
    updated_comments = []
    for line in comments:
        key, separator, _value = line[2:].partition(': ')
        if separator and key in changes:
            updated_comments.append('# %s: %s' % (key, changes.pop(key)))
        else:
            updated_comments.append(line)
    if changes:
        raise AssertionError('metadata key missing from fixture: ' + ', '.join(changes))
    changed = [row.copy() for row in table]
    if header_change is not None:
        column, replacement = header_change
        changed[0][changed[0].index(column)] = replacement
    if row_change is not None:
        row_index, column, value = row_change
        changed[row_index][changed[0].index(column)] = value
    if remove_row is not None:
        del changed[remove_row]
    buffer = io.StringIO()
    csv.writer(buffer, lineterminator='\n').writerows(changed)
    target.write_text('\n'.join(updated_comments) + '\n' + buffer.getvalue(), encoding='utf-8')


class AtmosphereCLI(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.engine = os.environ.get('OPENRC_TEST_GODOT') or subprocess.check_output(
            [str(ROOT / 'app/get-godot.sh')], text=True).strip()
        cls.work = tempfile.TemporaryDirectory(prefix='openrc-atmosphere-cli-')
        cls.directory = Path(cls.work.name)
        cls.environment = dict(os.environ, XDG_DATA_HOME=str(cls.directory / 'data'))
        cls.aircraft_traces = {}
        for aircraft in AIRCRAFT:
            for duration in ('.1', '1'):
                trace = cls.directory / f'{aircraft}-{duration}.csv'
                cls._write_real_trace(trace, [
                    '--weather=hot-high', '--aircraft=' + aircraft,
                ], duration)
                cls.aircraft_traces[(aircraft, duration)] = trace

        cls.preset_traces = {}
        for preset in ('hot-high', 'cool-dense'):
            trace = cls.directory / f'{preset}.csv'
            cls._write_real_trace(trace, ['--weather=' + preset], '.1')
            cls.preset_traces[preset] = trace

        cls.mixed_config_path = cls.directory / 'mixed-weather.json'
        cls.mixed_config_path.write_text(json.dumps(MIXED_CONFIG), encoding='utf-8')
        cls.mixed_trace = cls.directory / 'mixed-ou-atmosphere.csv'
        cls._write_real_trace(cls.mixed_trace,
                              ['--weather-file=' + str(cls.mixed_config_path)], '.1')

        cls.default_trace = cls.directory / 'reference-atmosphere.csv'
        cls._write_real_trace(cls.default_trace, [], '.1')

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
    def _write_real_trace(cls, path, weather_arguments, duration):
        cls._run_engine([
            '--', *weather_arguments, '--trace=' + str(path), '--t=' + duration,
        ])
        if not path.is_file():
            raise AssertionError('engine did not write trace: ' + str(path))

    def test_hot_high_trimmed_traces_cover_every_aircraft_and_duration(self):
        for aircraft in AIRCRAFT:
            for duration, rows in (('.1', 25), ('1', 241)):
                with self.subTest(aircraft=aircraft, duration=duration):
                    result = check(self.aircraft_traces[(aircraft, duration)], float(duration))
                    self.assertEqual(result['format'], 'openrc-trace v6')
                    self.assertEqual((result['rows'], result['first_tick'], result['last_tick']),
                                     (rows, 0, rows - 1))
                    self.assertLess(result['rho_kgm3'], 1.0)
                    self.assertLess(result['max_atmosphere_row_error'], 2e-9)
                    self.assertLess(result['max_eas_error_mps'], 1e-6)

    def test_hot_high_and_cool_dense_presets_recompute_density(self):
        hot = check(self.preset_traces['hot-high'], .1)
        cool = check(self.preset_traces['cool-dense'], .1)
        self.assertLess(hot['rho_kgm3'], 1.225)
        self.assertGreater(cool['rho_kgm3'], 1.225)
        self.assertNotEqual(hot['density_altitude_m'], cool['density_altitude_m'])

    def test_custom_v3_weather_file_combines_ou_and_atmosphere(self):
        result = check(self.mixed_trace, .1)
        self.assertEqual(result['rows'], 25)
        self.assertIn('max_turbulence_error_mps', result)
        self.assertLess(result['max_turbulence_error_mps'], 2e-8)
        _comments, metadata, rows = _read_parts(self.mixed_trace)
        config = json.loads(metadata['weather_config'])
        self.assertEqual(config['format'], 'openrc-weather v3')
        self.assertEqual(config['turbulence_seed'], MIXED_CONFIG['turbulence_seed'])
        self.assertEqual(len(rows[0]), len(rows[1]))
        self.assertIn('turbulence_north_mps', rows[0])

    def test_reader_rejects_atmosphere_metadata_rows_columns_and_tick_gaps(self):
        _comments, metadata, rows = _read_parts(self.preset_traces['hot-high'])
        state = json.loads(metadata['atmosphere_state'])
        state['rho_kgm3'] += .01
        config = json.loads(metadata['weather_config'])
        outside_bounds = dict(config, field_elevation_m=4001.0)
        boolean_number = dict(config, temperature_c=True)
        reference_mode = dict(config, atmosphere_mode='reference')
        duplicate_config = metadata['weather_config'].replace(
            '"field_elevation_m":1500.0',
            '"field_elevation_m":1500.0,"field_elevation_m":1499.0',
        )
        cases = (
            ('schema', {'metadata_schema': 'openrc-flight-meta v4'}, None, None, None),
            ('atmosphere model', {'atmosphere_model': 'unknown'}, None, None, None),
            ('kernel state', {'atmosphere_state': json.dumps(state)}, None, None, None),
            ('out-of-range elevation', {'weather_config': json.dumps(outside_bounds)}, None, None, None),
            ('boolean temperature', {'weather_config': json.dumps(boolean_number)}, None, None, None),
            ('duplicate weather key', {'weather_config': duplicate_config}, None, None, None),
            ('reference mode in v6', {'weather_config': json.dumps(reference_mode)}, None, None, None),
            ('density row', {}, (1, 'rho_kgm3', '1.1'), None, None),
            ('equivalent airspeed row', {}, (2, 'equivalent_airspeed_mps', '99'), None, None),
            ('column order/schema', {}, None, ('rho_kgm3', 'temperature_k'), None),
            ('tick gap', {}, None, None, 3),
        )
        for label, metadata_changes, row_change, header_change, remove_row in cases:
            with self.subTest(mutation=label):
                path = self.directory / 'mutated-atmosphere.csv'
                _rewrite_trace(self.preset_traces['hot-high'], path, metadata_changes,
                               row_change, header_change, remove_row)
                with self.assertRaises(ValueError):
                    check(path)

    def test_invalid_weather_is_refused_before_trace_creation_and_reference_v6_is_rejected(self):
        invalid = dict(MIXED_CONFIG, field_elevation_m=4000.1)
        source = self.directory / 'invalid-atmosphere.json'
        source.write_text(json.dumps(invalid), encoding='utf-8')
        refused_trace = self.directory / 'must-not-exist.csv'
        self._run_engine([
            '--', '--weather-file=' + str(source), '--trace=' + str(refused_trace), '--t=.1',
        ], success=False)
        self.assertFalse(refused_trace.exists())
        with self.assertRaisesRegex(ValueError, 'custom-atmosphere trace v6'):
            check(self.default_trace)

    def test_hot_high_checkpoint_hash_is_fixed_frame_rate_independent(self):
        hashes = []
        for fps in (30, 60, 144):
            with self.subTest(fps=fps):
                log = self._run_engine([
                    '--fixed-fps', str(fps), '--script', 'res://tests/run_fixed_step.gd',
                    '--', '--weather=hot-high',
                ])
                match = re.search(r'^flight_sha256=([0-9a-f]{64})$', log, re.M)
                self.assertIsNotNone(match, log)
                self.assertIsNotNone(re.search(r'^ticks=480 ', log, re.M), log)
                hashes.append(match.group(1))
        self.assertEqual(hashes[0], hashes[1])
        self.assertEqual(hashes[1], hashes[2])


if __name__ == '__main__':
    unittest.main()
