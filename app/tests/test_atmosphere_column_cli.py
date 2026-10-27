"""Check calm standard-column v11 traces; use temporary output unless fresh evidence is opted in."""
import csv
import io
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

from check_atmosphere_trace import check_column


ROOT = Path(__file__).resolve().parents[2]
CHECKER = ROOT / 'app/tests/check_atmosphere_trace.py'
EVIDENCE_ENV = 'OPENRC_ATMOS_COLUMN_EVIDENCE'
FAMILIES = (
    ('stik', 'jensen-das-ugly-stik-60', (), 'openrc-flight-meta v6', 'rpm-lag'),
    ('jet', 'sebart-avanti-s-a200-p100rx', (), 'openrc-flight-meta v9', 'retractable-gear'),
    ('p51-shaft', 'p51d-mustang-120', ('--shaft-integrator=coupled-rk4',), 'openrc-flight-meta v9', 'shaft'),
    # BAT-13: the Lumber defaults to its finite pack (trace v13); this family checks the fixed-bus column trace.
    ('timber-electric', 'turbo-lumber-evolution', ('--battery=ideal',), 'openrc-flight-meta v6', 'electric'),
    ('glow', 'stik-glow-61fx-2t', (), 'openrc-flight-meta v10', 'glow'),
)


def _read_trace(path):
    comments = []
    data_lines = []
    for line in path.read_text(encoding='utf-8').splitlines():
        if line.startswith('# '):
            comments.append(line)
        elif line.startswith('#'):
            raise AssertionError('unexpected malformed comment')
        elif line:
            data_lines.append(line)
    metadata = {}
    for line in comments:
        key, separator, value = line[2:].partition(': ')
        if not separator:
            raise AssertionError('malformed metadata line')
        metadata[key] = value
    table = list(csv.reader(data_lines))
    return comments, metadata, table


def _rewrite(source, target, *, metadata_changes=None, header_change=None, row_change=None, remove_last=False):
    comments, _metadata, table = _read_trace(source)
    changes = dict(metadata_changes or {})
    updated = []
    for line in comments:
        key, separator, _value = line[2:].partition(': ')
        if separator and key in changes:
            updated.append(f'# {key}: {changes.pop(key)}')
        else:
            updated.append(line)
    if changes:
        raise AssertionError('metadata key not found: ' + ', '.join(changes))
    rows = [row.copy() for row in table]
    if header_change is not None:
        column, value = header_change
        rows[0][rows[0].index(column)] = value
    if row_change is not None:
        row_index, column, value = row_change
        rows[row_index][rows[0].index(column)] = value
    if remove_last:
        rows.pop()
    output = io.StringIO()
    csv.writer(output, lineterminator='\n').writerows(rows)
    target.write_text('\n'.join(updated) + '\n' + output.getvalue(), encoding='utf-8')


def _output_directory(default_directory, evidence_path=None):
    if not evidence_path:
        return default_directory
    target = Path(evidence_path).expanduser().resolve()
    target.mkdir(parents=True, exist_ok=False)
    return target


class AtmosphereColumnCLI(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.engine = os.environ.get('OPENRC_TEST_GODOT') or subprocess.check_output(
            [str(ROOT / 'app/get-godot.sh')], text=True,
        ).strip()
        cls.work = tempfile.TemporaryDirectory(prefix='openrc-atmosphere-column-cli-')
        cls.directory = Path(cls.work.name)
        cls.output_directory = _output_directory(
            cls.directory, os.environ.get(EVIDENCE_ENV),
        )
        cls.environment = dict(os.environ, XDG_DATA_HOME=str(cls.directory / 'data'))
        if os.name == 'nt':
            for variable, name in (('APPDATA', 'appdata'), ('LOCALAPPDATA', 'localappdata')):
                user_directory = cls.directory / name
                user_directory.mkdir()
                cls.environment[variable] = str(user_directory)
        cls.traces = {}
        cls.logs = {}
        for family, aircraft, options, _schema, _kind in FAMILIES:
            trace = cls.output_directory / f'{family}-standard-column.csv'
            log = cls.output_directory / f'{family}-cli.log'
            cls._write_real_trace(trace, log, aircraft, options)
            cls.traces[family] = trace
            cls.logs[family] = log
        cls.reader_results = {
            family: check_column(trace, 0.1)
            for family, trace in cls.traces.items()
        }
        (cls.output_directory / 'reader-results.json').write_text(
            json.dumps(cls.reader_results, indent=2, sort_keys=True, allow_nan=False) + '\n',
            encoding='utf-8',
        )

    @classmethod
    def tearDownClass(cls):
        cls.work.cleanup()

    @classmethod
    def _write_real_trace(cls, trace, log_path, aircraft, options):
        log_file = cls.directory / (trace.stem + '.godot.log')
        command = [
            cls.engine, '--headless', '--path', str(ROOT / 'app'), '--audio-driver', 'Dummy',
            '--log-file', str(log_file), '--', '--weather=standard-column',
            '--aircraft=' + aircraft, *options, '--trace=' + str(trace), '--t=0.1',
        ]
        process = subprocess.run(
            command, capture_output=True, text=True, timeout=180, env=cls.environment,
        )
        output = process.stdout + process.stderr
        log_path.write_text(output, encoding='utf-8')
        if process.returncode != 0 or re.search(r'^(?:SCRIPT |SHADER )?ERROR:', output, re.M):
            raise AssertionError(f'{aircraft} CLI failed:\n{output}')
        if not trace.is_file() or 'trace saved:' not in output or '(25 rows)' not in output:
            raise AssertionError(f'{aircraft} --trace did not complete 24 ticks:\n{output}')

    def test_standard_column_preset_emits_complete_v11_for_all_propulsion_families(self):
        for family, _aircraft, _options, schema, kind in FAMILIES:
            with self.subTest(family=family):
                result = self.reader_results[family]
                has_flaps = family in ('jet', 'p51-shaft')
                finite_liquid = family in ('jet', 'p51-shaft')
                self.assertEqual(result['format'], 'openrc-trace v15' if finite_liquid else 'openrc-trace v14')
                self.assertEqual(result['mass_trace_schema'], 'openrc-mass-sample v1')
                self.assertEqual(result['mass_base_trace_format'],
                                 'openrc-trace v12' if has_flaps else 'openrc-trace v11')
                self.assertEqual(result['metadata_schema'], schema)
                self.assertEqual((result['rows'], result['first_tick'], result['last_tick']), (25, 0, 24))
                self.assertAlmostEqual(result['elapsed_s'], 0.1, places=8)
                comments, metadata, table = _read_trace(self.traces[family])
                self.assertEqual(metadata['atmosphere_model'], 'standard-column-dry-isa-troposphere-v1')
                self.assertEqual(json.loads(metadata['weather_config'])['format'], 'openrc-weather v4')
                self.assertEqual(json.loads(metadata['weather_config'])['atmosphere_mode'], 'standard_column')
                header = table[0]
                self.assertIn('geometric_altitude_m', header)
                self.assertIn('loads_rho_kgm3', header)
                self.assertIn('loads_pressure_pa', header)
                self.assertIn('loads_temperature_k', header)
                if kind == 'electric':
                    self.assertIn('drive_enabled', header)
                    self.assertEqual(metadata['engine_atmosphere'],
                                     'electric motor constants independent of density; propeller loads use stage density')
                elif kind == 'glow':
                    self.assertIn('glow_fuel_kg', header)
                    self.assertIn('glow_line_fuel_kg', header)
                    self.assertIn('glow_fuel_source_mode', header)
                    self.assertEqual(metadata['glow_trace_schema'], 'openrc-glow-trace v2')
                    self.assertRegex(metadata['glow_fuel_registry_sha256'], r'^[0-9a-f]{64}$')
                elif kind == 'retractable-gear':
                    self.assertIn('gear_extension', header)
                    self.assertEqual(metadata['gear_trace_schema'], 'openrc-gear-trace v1')
                elif kind == 'shaft':
                    self.assertEqual(metadata['shaft_integrator'], 'coupled-rk4')
                self.assertGreaterEqual(len(comments), 20)

    def test_reader_script_column_flag_accepts_v11_trace(self):
        process = subprocess.run(
            [sys.executable, str(CHECKER), str(self.traces['stik']), '--duration', '0.1', '--column'],
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(process.returncode, 0, process.stderr)
        result = json.loads(process.stdout)
        self.assertEqual(result['format'], 'openrc-trace v14')
        self.assertEqual(result['mass_base_trace_format'], 'openrc-trace v11')
        self.assertEqual(result['rows'], 25)

    def test_reader_rejects_glow_v3_schema_identity_and_source_mutations(self):
        source = self.traces['glow']
        mutations = (
            ('old metadata version', {'metadata_schema': 'openrc-flight-meta v7'}, None, None),
            ('old trace schema with v3 law', {'glow_trace_schema': 'openrc-glow-trace v1'}, None, None),
            ('missing selected tank identity', {'glow_fuel_tank_id': ''}, None, None),
            ('invalid registry digest', {'glow_fuel_registry_sha256': 'bad'}, None, None),
            ('line source without inventory', {}, ('glow_fuel_source_mode', '2'), None),
        )
        for index, (label, metadata_changes, row_change, header_change) in enumerate(mutations):
            with self.subTest(mutation=label):
                target = self.directory / f'mutated-glow-v3-{index}.csv'
                _rewrite(source, target, metadata_changes=metadata_changes,
                         header_change=header_change,
                         row_change=(1, row_change[0], row_change[1]) if row_change else None)
                with self.assertRaises(ValueError):
                    check_column(target, 0.1)

    def test_evidence_output_refuses_an_existing_directory(self):
        existing = self.directory / 'existing-evidence'
        existing.mkdir()
        marker = existing / 'keep.txt'
        marker.write_text('preserve', encoding='utf-8')
        with self.assertRaises(FileExistsError):
            _output_directory(self.directory, existing)
        self.assertEqual(marker.read_text(encoding='utf-8'), 'preserve')

    def test_independent_reader_rejects_stale_versions_preview_column_and_sample_corruption(self):
        source = self.traces['stik']
        _comments, metadata, table = _read_trace(source)
        preview = json.loads(metadata['atmosphere_state'])
        preview['rho_kgm3'] += 0.1
        config = json.loads(metadata['weather_config'])
        stale_config = dict(config, format='openrc-weather v3')
        changed_datum = dict(config, field_elevation_m=300.0)
        mutations = (
            ('trace version', {'format': 'openrc-trace v10'}, None, None, False),
            ('weather version', {'weather_config': json.dumps(stale_config)}, None, None, False),
            ('atmosphere law', {'atmosphere_model': 'uniform-field-qnh-isa-buck-liquid-v1'}, None, None, False),
            ('field datum preview', {'atmosphere_state': json.dumps(preview)}, None, None, False),
            ('stale field datum config', {'weather_config': json.dumps(changed_datum)}, None, None, False),
            ('missing column', {}, ('loads_temperature_k', 'removed_load_temperature'), None, False),
            ('endpoint density', {}, None, (1, 'rho_kgm3', '1.400000000'), False),
            ('load density', {}, None, (2, 'loads_rho_kgm3', '1.400000000'), False),
            ('endpoint geometric altitude', {}, None, (2, 'geometric_altitude_m', '900.000000000'), False),
            ('nonfinite endpoint', {}, None, (2, 'rho_kgm3', 'nan'), False),
            ('nonfinite load pressure', {}, None, (2, 'loads_pressure_pa', 'nan'), False),
            ('incomplete trace', {}, None, None, True),
        )
        for index, (label, metadata_changes, header_change, row_change, remove_last) in enumerate(mutations):
            with self.subTest(mutation=label):
                changed = Path(self.work.name) / f'mutated-{index}.csv'
                _rewrite(source, changed, metadata_changes=metadata_changes, header_change=header_change,
                         row_change=row_change, remove_last=remove_last)
                with self.assertRaises(ValueError):
                    check_column(changed, 0.1)


if __name__ == '__main__':
    unittest.main()
