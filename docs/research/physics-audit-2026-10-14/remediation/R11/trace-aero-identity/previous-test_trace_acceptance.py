"""C7-R1: real trace mutations and CLI failures must fail as processes, not just print errors."""
import csv
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from check_trimmed_flight import check_coupled_metadata, check, check_fixed_bus_sample

APP = Path(__file__).resolve().parents[1]
CHECKER = APP / 'tests/check_trimmed_flight.py'


class TraceAcceptance(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.godot = os.environ.get('OPENRC_TEST_GODOT') or subprocess.check_output(
            [str(APP / 'get-godot.sh')], text=True).strip()
        cls.temp = tempfile.TemporaryDirectory(prefix='openrc-trace-acceptance-')
        cls.addClassCleanup(cls.temp.cleanup)
        cls.directory = Path(cls.temp.name)
        cls.engine_log_index = 0
        cls.environment = dict(os.environ, XDG_DATA_HOME=str(cls.directory / 'data'))
        if os.name == 'nt':
            for variable, name in (('APPDATA', 'appdata'), ('LOCALAPPDATA', 'localappdata')):
                user_directory = cls.directory / name
                user_directory.mkdir()
                cls.environment[variable] = str(user_directory)
        cls.source = cls.directory / 'valid.csv'
        result = cls.run_app('--trace=' + str(cls.source), '--t=3')
        if result.returncode or 'ERROR:' in result.stdout:
            raise AssertionError(result.stdout)
        lines = cls.source.read_text().splitlines()
        cls.meta = [line for line in lines if line.startswith('#')]
        cls.table = list(csv.reader(line for line in lines if not line.startswith('#')))

    @classmethod
    def run_app(cls, *args, probe=False, mode=''):
        cls.engine_log_index += 1
        log_file = cls.directory / ('godot-%03d.log' % cls.engine_log_index)
        command = [cls.godot, '--headless', '--path', str(APP), '--audio-driver', 'Dummy',
                   '--log-file', str(log_file)]
        if probe:
            command += ['--script', 'res://tests/probe_trace_failure.gd']
        return subprocess.run(command + ['--', *args], stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT, text=True, timeout=30,
                              env={**cls.environment, 'OPENRC_TRACE_FAILURE': mode})

    def checker(self, table=None, meta=None, *options):
        if table is None:
            table = self.table
        if meta is None:
            meta = self.meta
        stream = io.StringIO()
        stream.write('\n'.join(meta) + '\n')
        csv.writer(stream).writerows(table)
        path = self.directory / 'candidate.csv'
        path.write_text(stream.getvalue(), newline="")
        return subprocess.run([sys.executable, str(CHECKER), str(path), '--duration=3', *options],
                              capture_output=True, text=True, timeout=10)

    def rejected(self, table=None, meta=None, diagnostic='', options=()):
        result = self.checker(table, meta, *options)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn('FAIL', result.stderr)
        self.assertIn(diagnostic, result.stderr)

    def test_complete_real_flight_passes(self):
        result = self.checker()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('720 ticks', result.stdout)

    def test_checkpoint_wheel_state_keeps_unknown_launch_explicit(self):
        metadata = dict(line[2:].split(': ', 1) for line in self.meta)
        check_coupled_metadata(metadata)
        metadata['launch_continuous'] = '[]'
        with self.assertRaises(ValueError):
            check_coupled_metadata(metadata)
        metadata.update(launch_kind='checkpoint_restore', launch_choice='unknown')
        check_coupled_metadata(metadata)
        metadata['recording_start_continuous'] = '[]'
        with self.assertRaises(ValueError):
            check_coupled_metadata(metadata)

    def test_active_aircraft_metadata(self):
        cases = [
            ('jensen-das-ugly-stik-60', 'propeller-rpm-lag-v1', 'none', False),
            ('gp-extra-300s-60', 'propeller-rpm-lag-v1', 'none', False),
            ('p51d-mustang-120', 'propeller-shaft-balance-v1', 'tail-slipstream-increment-v1', True),
            ('sebart-avanti-s-a200-p100rx', 'turbine-rpm-governor-rk4-v1', 'none', False),
            ('turbo-lumber-evolution', 'electric-fixed-bus-coupled-stop-v1', 'none', False),
        ]
        for aircraft, propulsion, propwash, crossflow in cases:
            with self.subTest(aircraft=aircraft):
                path = self.directory / (aircraft + '.csv')
                result = self.run_app('--aircraft=' + aircraft, '--trace=' + str(path), '--t=.05')
                self.assertEqual(result.returncode, 0, result.stdout)
                self.assertNotIn('ERROR:', result.stdout)
                metadata = dict(line[2:].split(': ', 1) for line in path.read_text().splitlines()
                                if line.startswith('# '))
                self.assertEqual(metadata['propulsion_model'], propulsion)
                self.assertEqual(metadata['propwash_model'], propwash)
                source = APP / metadata['aircraft'].split('(res://', 1)[1].removesuffix(')')
                self.assertEqual(metadata['metadata_schema'], 'openrc-flight-meta v8' if aircraft == 'sebart-avanti-s-a200-p100rx' else 'openrc-flight-meta v6')
                if aircraft == 'sebart-avanti-s-a200-p100rx':
                    self.assertEqual(metadata['format'], 'openrc-trace v10')
                    self.assertEqual(json.loads(metadata['input_layout']),
                                     ['roll', 'pitch', 'yaw', 'throttle', 'gear_down', 'wheel_brake'])
                    self.assertEqual(metadata['gear_law'], 'retractable-point-gear-v1')
                    self.assertEqual(metadata['gear_trace_schema'], 'openrc-gear-trace v1')
                    self.assertEqual(len(json.loads(metadata['recording_start_gear'])), 2)
                    self.assertEqual(len(json.loads(metadata['recording_start_continuous'])), 4)
                    header = next(csv.reader(line for line in path.read_text().splitlines()
                                             if line and not line.startswith('#')))
                    self.assertEqual(header[-4:], ['gear_extension', 'gear_target_down',
                                                   'cmd_gear_down', 'cmd_wheel_brake'])
                self.assertEqual(metadata['aircraft_input_format'], json.loads(source.read_text())['format'])
                self.assertEqual(metadata['aircraft_input_sha256'], hashlib.sha256(source.read_bytes()).hexdigest())
                features = json.loads(metadata['propulsion_features'])
                self.assertEqual(features['propeller_normal_force'], crossflow)
                self.assertEqual(features['propeller_pfactor'], crossflow)
                checked = subprocess.run([sys.executable, str(CHECKER), str(path), '--duration=.05',
                                          '--aircraft-input', str(source)],
                                         capture_output=True, text=True, timeout=10)
                self.assertEqual(checked.returncode, 0, checked.stderr)

    def test_active_avanti_gear_contract_rejects_incomplete_metadata_and_rows(self):
        path = self.directory / 'avanti-gear.csv'
        result = self.run_app('--aircraft=sebart-avanti-s-a200-p100rx', '--trace=' + str(path), '--t=.05')
        self.assertEqual(result.returncode, 0, result.stdout)
        lines = path.read_text().splitlines()
        metadata = dict(line[2:].split(': ', 1) for line in lines if line.startswith('# '))
        self.assertIn('gear_trace_schema', metadata)
        self.assertIn('wheel_state_layout', metadata)
        self.assertIn('gear_extension', next(line for line in lines if not line.startswith('#')))

        from check_trimmed_flight import check
        self.assertIn('12 ticks', check(path, .05, 240))

        header = next(csv.reader(line for line in lines if line and not line.startswith('#')))
        table = list(csv.reader(line for line in lines if line and not line.startswith('#')))
        mutations = [
            ('gear schema', [line for line in lines if not line.startswith('# gear_trace_schema:')]),
            ('wheel provenance', [line for line in lines if not line.startswith('# wheel_profile_sha256:')]),
        ]
        for label, changed_lines in mutations:
            with self.subTest(mutation=label):
                candidate = self.directory / ('avanti-' + label.replace(' ', '-') + '.csv')
                candidate.write_text('\n'.join(changed_lines) + '\n', encoding='utf-8')
                with self.assertRaises(ValueError):
                    check(candidate, .05, 240)

        for column, value in [('gear_extension', '1.01'), ('cmd_gear_down', '.5'),
                              ('cmd_wheel_brake', '-.01')]:
            with self.subTest(column=column):
                changed = [row.copy() for row in table]
                changed[1][header.index(column)] = value
                candidate = self.directory / 'avanti-bad-gear-row.csv'
                with candidate.open('w', newline='', encoding='utf-8') as stream:
                    writer = csv.writer(stream, lineterminator='\n')
                    writer.writerows(changed)
                comments = [line for line in lines if line.startswith('#')]
                candidate.write_text('\n'.join(comments) + '\n' + candidate.read_text(), encoding='utf-8')
                with self.assertRaises(ValueError):
                    check(candidate, .05, 240)

    def test_continuous_turbine_metadata_rejects_mixed_sampling(self):
        path = self.directory / 'turbine-metadata.csv'
        result = self.run_app('--aircraft=sebart-avanti-s-a200-p100rx', '--trace=' + str(path), '--t=.05')
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertNotIn('ERROR:', result.stdout)
        metadata = dict(line[2:].split(': ', 1) for line in path.read_text().splitlines()
                        if line.startswith('# '))
        check_coupled_metadata(metadata)
        for key, value in [
            ('metadata_schema', 'openrc-flight-meta v6'),
            ('wheel_state_layout', '[]'),
            ('wheel_profile_status', 'applied'),
            ('turbine_integrator', 'sampled'),
            ('continuous_layout', 'none'),
            ('recording_start_continuous', '[true]'),
            ('recording_start_continuous', '[]'),
            ('recording_start_continuous', '[0, 1]'),
            ('recording_start_continuous', '[-1]'),
            ('recording_start_continuous', '[NaN]'),
            ('recording_start_continuous', '[1]'),
            ('recording_start_aux', '[44000, null, 0, 0]'),
            ('shaft_integrator', 'coupled-rk4'),
            ('propulsion_model', 'turbine-ecu-spool-v1'),
        ]:
            with self.subTest(key=key, value=value):
                with self.assertRaises(ValueError):
                    check_coupled_metadata({**metadata, key: value})
        for key in ['turbine_integrator', 'recording_start_continuous']:
            with self.subTest(missing=key):
                with self.assertRaises(ValueError):
                    check_coupled_metadata({k: v for k, v in metadata.items() if k != key})

    def test_timber_electric_endpoint_equations_reject_corruption(self):
        path = self.directory / 'timber-electric.csv'
        result = self.run_app('--aircraft=turbo-lumber-evolution', '--trace=' + str(path), '--t=.05')
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertNotIn('ERROR:', result.stdout)
        self.assertIn('12 ticks', check(path, .05, 240))
        lines = path.read_text().splitlines()
        meta = dict(line[2:].split(': ', 1) for line in lines if line.startswith('# '))
        row = next(csv.DictReader(line for line in lines if not line.startswith('#')))
        sample = {key: float(value) for key, value in row.items()}
        for column in ('motor_current_a', 'source_torque_nm', 'shaft_power_w',
                       'copper_loss_w', 'rotational_loss_w', 'drive_bus_current_a'):
            with self.subTest(column=column):
                changed = dict(sample); changed[column] += 1
                with self.assertRaisesRegex(ValueError, 'equation disagrees'):
                    check_fixed_bus_sample(meta, changed)
        for key, value in [('electric_configuration', '{}'), ('electric_sample_timing', 'k1'),
                           ('propulsion_model', 'propeller-rpm-lag-v1')]:
            with self.subTest(metadata=key):
                changed = dict(meta); changed[key] = value
                with self.assertRaises(ValueError):
                    check_fixed_bus_sample(changed, sample)

    def test_missing_or_inconsistent_flight_metadata_fails(self):
        metadata = dict(line[2:].split(': ', 1) for line in self.meta)
        keys = ['metadata_schema', 'aero_model', 'propulsion_model', 'propwash_model',
                'propulsion_features', 'engine_rpm_semantics', 'state_layout', 'aux_layout',
                'recording_start_tick', 'recording_start_aux', 'recording_start_engine_running',
                'aircraft_input_format', 'aircraft_input_sha256', 'aircraft_input_hash_convention',
                'aircraft_semantic_sha256', 'aircraft_semantic_hash_convention']
        for key in keys:
            with self.subTest(missing=key):
                self.rejected(meta=[line for line in self.meta if not line.startswith('# ' + key + ':')])
        mutations = [
            ('metadata_schema', 'openrc-flight-meta v999'),
            ('aircraft_input_format', 'openrc-aircraft v999'),
            ('aircraft_input_hash_convention', 'sha256 of reserialized JSON'),
            ('aircraft_semantic_hash_convention', 'sha256 of exact aircraft input file bytes'),
            ('aero_model', 'local-surfaces-v1 with bounded attached oracle; no propwash'),
            ('propulsion_model', 'turbine-ecu-spool-v1'),
            ('engine_rpm_semantics', 'turbine spool rpm'),
            ('recording_start_tick', '1'), ('recording_start_engine_running', 'false'),
            ('aux_layout', '["srv_roll", "engine_rpm", "srv_pitch", "srv_yaw"]'),
            ('state_layout', '[]'), ('recording_start_aux', 'null'),
            ('recording_start_aux', '[0, 0, 0, 0]'),
            ('recording_start_aux', '[NaN, 0, 0, 0]'),
            ('recording_start_aux', '[true, 0, 0, 0]'),
            ('propulsion_features', '{}'), ('propulsion_features', 'null'),
            ('propulsion_features', 'not-json'),
        ]
        for key in ['aircraft_input_sha256', 'aircraft_semantic_sha256']:
            mutations += [(key, value) for value in ['', 'a' * 63, 'a' * 65, 'g' * 64, 'A' * 64,
                                                      'unavailable: in-memory input']]
        features = json.loads(metadata['propulsion_features'])
        mutations.append(('propulsion_features', json.dumps({**features, 'turbine_ram_flow': True})))
        mutations.append(('propulsion_features', json.dumps({**features, 'propeller_pfactor': 'false'})))
        for key, value in mutations:
            with self.subTest(key=key, value=value):
                self.rejected(meta=[f'# {key}: {value}' if line.startswith('# ' + key + ':') else line
                                    for line in self.meta])

    def test_exact_input_artifact_verification(self):
        source = APP / 'data/aircraft/jensen_ugly_stik_60.json'
        saved = self.directory / 'aircraft.json'
        saved.write_bytes(source.read_bytes())
        result = self.checker(None, None, '--aircraft-input', str(saved))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('exact aircraft input bytes verified', result.stdout)
        for content in [source.read_bytes() + b'\n',
                        source.read_bytes().replace(b'"value": 0.1068,', b'"value": 0.1068000000000001,')]:
            saved.write_bytes(content)
            self.rejected(diagnostic='do not match recorded SHA-256', options=('--aircraft-input', str(saved)))
        saved.unlink()
        self.rejected(options=('--aircraft-input', str(saved)))

    def test_legacy_metadata_is_explicit_and_cannot_verify_file_bytes(self):
        legacy = [line for line in self.meta if not line.startswith(('# aircraft_input_', '# wheel_', '# recording_start_continuous:', '# launch_continuous:'))]
        legacy = ['# continuous_layout: none' if line.startswith('# continuous_layout:') else line for line in legacy]
        legacy = [line.replace('# metadata_schema: openrc-flight-meta v6',
                               '# metadata_schema: openrc-flight-meta v1')
                  .replace('# aircraft_semantic_sha256:', '# aircraft_data_sha256:')
                  .replace('# aircraft_semantic_hash_convention:', '# aircraft_data_hash_convention:')
                  for line in legacy]
        self.rejected(meta=legacy, diagnostic='legacy metadata v1')
        result = self.checker(None, legacy, '--allow-legacy-metadata')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('legacy semantic-only metadata; exact input identity unavailable', result.stdout)
        self.rejected(meta=legacy + ['# aircraft_input_sha256: ' + 'a' * 64],
                      diagnostic='cannot contain v2', options=('--allow-legacy-metadata',))
        self.rejected(meta=legacy, diagnostic='legacy metadata cannot verify',
                      options=('--allow-legacy-metadata', '--aircraft-input', str(APP / 'project.godot')))
        unversioned = [line for line in legacy if not line.startswith('# metadata_schema:')]
        self.rejected(meta=unversioned, diagnostic='unversioned legacy', options=('--allow-legacy-metadata',))
        self.rejected(meta=self.meta + ['# aircraft_data_sha256: ' + 'a' * 64],
                      diagnostic='explicit input/semantic hash names')
        # Opting into legacy support must not let a v2 input identity disappear.
        self.rejected(meta=[line for line in self.meta if not line.startswith('# aircraft_input_sha256:')],
                      options=('--allow-legacy-metadata',))

    def test_partial_and_extra_samples_fail(self):
        for table in [[], self.table[:1], self.table[:2], self.table[:-1],
                      self.table[:361], self.table + [self.table[-1]]]:
            with self.subTest(rows=len(table)):
                self.rejected(table)

    def test_nonfinite_any_column_any_time_fails(self):
        # Cover every column and each time region without an expensive Cartesian product.
        cases = [(column, 360, 'nan') for column in range(len(self.table[0]))]
        cases += [(self.table[0].index('alt_m'), position, value)
                  for position in [1, 360, 721] for value in ['inf', '-inf']]
        cases += [(self.table[0].index('alt_m'), position, 'nan') for position in [1, 721]]
        for column, position, value in cases:
            with self.subTest(column=self.table[0][column], position=position, value=value):
                table = [row.copy() for row in self.table]
                table[position][column] = value
                self.rejected(table, diagnostic='non-finite')

    def test_clock_and_schema_mutations_fail(self):
        mutations = [
            ('duplicate tick', 360, 'tick', '358'),
            ('skipped tick', 360, 'tick', '360'),
            ('fractional tick', 360, 'tick', '359.5'),
            ('wrong clock', 360, 't_s', '1.0'),
            ('wrong endpoint', 721, 't_s', '2.9'),
            ('invalid number', 360, 'u_mps', 'not-a-number'),
            ('trim drift', 721, 'alt_m', '40'),
        ]
        for name, index, column, value in mutations:
            with self.subTest(name=name):
                table = [row.copy() for row in self.table]
                table[index][table[0].index(column)] = value
                self.rejected(table)
        for index in [0, 360]:
            table = [row.copy() for row in self.table]
            table[index].pop()
            self.rejected(table)
        self.rejected([self.table[0]] + list(reversed(self.table[1:])))
        self.rejected(options=('--duration=1.5',))
        self.rejected(options=('--hz=120',))
        for key in ['format', 'dt_s', 'ground']:
            self.rejected(meta=[line for line in self.meta if not line.startswith('# ' + key + ':')])
        for dt in ['nan', '0', '0.01']:
            self.rejected(meta=[('# dt_s: ' + dt) if line.startswith('# dt_s:') else line for line in self.meta])
        self.rejected(meta=self.meta + ['# format: openrc-trace v3'])

    def test_invalid_checker_request_fails(self):
        for option in ['--duration=0', '--duration=-1', '--duration=nan', '--duration=inf',
                       '--duration=1e100', '--duration=1e-10', '--hz=0', '--hz=-1']:
            with self.subTest(option=option):
                self.rejected(options=(option,))

    def test_invalid_duration_and_path_fail_without_output(self):
        path = self.directory / 'invalid.csv'
        for arg in ['--t=-1', '--t=0', '--t=nan', '--t=inf', '--t=-inf', '--t=', '--t',
                    '--t=abc', '--t=3junk', '--t=1e100', '--t=1e-10']:
            with self.subTest(arg=arg):
                result = self.run_app('--trace=' + str(path), arg)
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertIn('--trace requires', result.stdout)
                self.assertFalse(path.exists())
        for arg in ['--trace', '--trace=']:
            result = self.run_app(arg, '--t=3')
            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertIn('--trace requires', result.stdout)

    def test_default_duration_and_fractional_tick_rounding(self):
        path = self.directory / 'rounded.csv'
        for options, duration, ticks in [((), '3', 720), (('--t=0.01',), '.01', 2),
                                         (('--t=1.5',), '1.5', 360)]:
            result = self.run_app('--trace=' + str(path), *options)
            self.assertEqual(result.returncode, 0, result.stdout)
            checked = subprocess.run([sys.executable, str(CHECKER), str(path), '--duration='+duration],
                                     capture_output=True, text=True, timeout=10)
            self.assertEqual(checked.returncode, 0, checked.stderr)
            self.assertIn(f'{ticks} ticks', checked.stdout)

    def test_faults_and_missing_samples_fail_without_overwriting(self):
        path = self.directory / 'failed.csv'
        for mode in ['initial', 'first_tick', 'last_tick', 'missing_sample']:
            with self.subTest(mode=mode):
                path.write_text('existing evidence\n')
                result = self.run_app('--trace='+str(path), '--t=.05', probe=True, mode=mode)
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertRegex(result.stdout, r'--trace (aborted|refused)')
                self.assertEqual(path.read_text(), 'existing evidence\n')

    def test_write_failure_is_nonzero(self):
        result = self.run_app('--trace='+str(self.directory), '--t=.01')
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn('trace save failed', result.stdout)


if __name__ == '__main__':
    unittest.main()
