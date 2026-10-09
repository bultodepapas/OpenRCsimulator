"""Real process weather routes plus negative controls for the v4 diagnostic reader."""
import csv
import io
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

from check_wind_trace import check

ROOT = Path(__file__).resolve().parents[2]


class WeatherCLI(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.engine = os.environ.get('OPENRC_TEST_GODOT') or subprocess.check_output([str(ROOT/'app/get-godot.sh')], text=True).strip()
        cls.work = tempfile.TemporaryDirectory(prefix='openrc-weather-cli-')
        cls.directory = Path(cls.work.name)
        cls.environment = dict(os.environ, XDG_DATA_HOME=str(cls.directory/'data'))
        cls.valid = cls.directory/'gusty.csv'
        cls.run_app(['--weather=gusty', '--trace='+str(cls.valid), '--t=3'])

    @classmethod
    def tearDownClass(cls):
        cls.work.cleanup()

    @classmethod
    def run_app(cls, arguments, success=True):
        result = subprocess.run([cls.engine, '--headless', '--path', str(ROOT/'app'), '--audio-driver', 'Dummy', '--', *arguments],
                                capture_output=True, text=True, timeout=60, env=cls.environment)
        log = result.stdout+result.stderr
        if success:
            if result.returncode != 0 or re.search(r'^(?:SCRIPT |SHADER )?ERROR:', log, re.M):
                raise AssertionError(log)
        elif result.returncode == 0 or 'weather refused:' not in log:
            raise AssertionError('did not reject weather: '+log)
        return log

    def test_real_gust_trace(self):
        result = check(self.valid, 3)
        self.assertEqual(result['rows'], 721)
        self.assertLess(result['max_speed_error_mps'], 1e-6)

    def test_real_vertical_and_steady(self):
        for preset in ('updraft', 'steady'):
            with self.subTest(preset=preset):
                path = self.directory/(preset+'.csv')
                self.run_app(['--weather='+preset, '--gust-delay=0', '--trace='+str(path), '--t=1'])
                self.assertEqual(check(path, 1)['rows'], 241)

    def test_real_file_and_overrides(self):
        lines = self.valid.read_text().splitlines()
        config = json.loads(next(line.split(': ', 1)[1] for line in lines if line.startswith('# weather_config:')))
        source = self.directory/'weather.json'
        source.write_text(json.dumps(config))
        path = self.directory/'file.csv'
        self.run_app(['--weather-file='+str(source), '--wind-from=360', '--gust-up=-1', '--trace='+str(path), '--t=.5'])
        self.assertEqual(check(path, .5)['rows'], 121)

    def test_invalid_options_refused_before_recording(self):
        path = self.directory/'must-not-exist.csv'
        for arguments in (['--weather'], ['--weather=unknown'], ['--wind-speed=nan'], ['--wind-speed=inf'],
                          ['--wind-speed=16'], ['--gust-duration=8', '--gust-period=4'],
                          ['--weather-file=/no/such/weather.json'], ['--weather=steady', '--weather-file=/no/such/weather.json']):
            with self.subTest(arguments=arguments):
                self.run_app([*arguments, '--trace='+str(path), '--t=.1'], success=False)
                self.assertFalse(path.exists())

    def test_invalid_json_and_weather_schema(self):
        path = self.directory/'invalid.json'
        for contents in ('{', '[]', '{"format":"openrc-weather v999"}'):
            with self.subTest(contents=contents):
                path.write_text(contents)
                self.run_app(['--weather-file='+str(path), '--trace='+str(self.directory/'bad.csv'), '--t=.1'], success=False)

    def test_reader_negative_controls(self):
        lines = self.valid.read_text().splitlines()
        metadata = [line for line in lines if line.startswith('#')]
        table = list(csv.reader(line for line in lines if not line.startswith('#')))
        header = table[0]
        changes = [('wind_east_mps', '99'), ('tas_mps', '99'), ('ground_horizontal_mps', '99'),
                   ('loads_t_s', '.0'), ('loads_wind_east_mps', '99'), ('loads_tas_mps', '99'),
                   ('qw', '0'), ('cmd_pitch', 'nan'), ('tick', '99')]
        for column, value in changes:
            with self.subTest(column=column):
                mutated = [row.copy() for row in table]
                mutated[601][header.index(column)] = value
                text = io.StringIO(); writer = csv.writer(text, lineterminator='\n'); writer.writerows(mutated)
                path = self.directory/'mutation.csv'; path.write_text('\n'.join(metadata)+'\n'+text.getvalue())
                with self.assertRaises(ValueError):
                    check(path, 3)
        path = self.directory/'short.csv'
        path.write_text('\n'.join(metadata)+'\n'+','.join(header)+'\n'+','.join(table[1])+'\n')
        with self.assertRaises(ValueError):
            check(path, 3)


if __name__ == '__main__':
    unittest.main()
