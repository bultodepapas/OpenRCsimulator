"""TOD-05/07: actual entry-point rejection, visual provenance and physics independence."""
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class TimeOfDayCLI(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.engine = os.environ.get('OPENRC_TEST_GODOT') or subprocess.check_output(
            [str(ROOT / 'app/get-godot.sh')], text=True).strip()

    def setUp(self):
        self.work = tempfile.TemporaryDirectory(prefix='openrc-tod-')
        self.addCleanup(self.work.cleanup)
        self.directory = Path(self.work.name)
        self.environment = dict(os.environ, XDG_DATA_HOME=str(self.directory / 'data'))

    def run_flight(self, name, options, fps=60, success=True):
        trace = self.directory / (name + '.csv')
        command = [self.engine, '--headless', '--path', str(ROOT / 'app'),
                   '--audio-driver', 'Dummy', '--fixed-fps', str(fps), '--',
                   '--trace=' + str(trace), '--t=.1', *options]
        run = subprocess.run(command, capture_output=True, text=True, timeout=60,
                             env=self.environment)
        log = run.stdout + run.stderr
        self.assertIsNone(re.search(r'^(?:SCRIPT |SHADER )?ERROR:', log, re.M), log)
        if not success:
            self.assertNotEqual(run.returncode, 0, log)
            self.assertIn('lighting:', log)
            self.assertFalse(trace.exists(), 'invalid lighting must not start a flight')
            return None
        self.assertEqual(run.returncode, 0, log)
        lines = trace.read_text().splitlines()
        context = [line.split(': ', 1)[1] for line in lines if line.startswith('# visual_context: ')]
        physics = '\n'.join(line for line in lines if not line.startswith(('# visual_context: ', '# created_utc: ')))
        return physics, json.loads(context[0]) if context else None

    def test_time_never_changes_physics_or_default_trace(self):
        from test_atmosphere_cli import MIXED_CONFIG
        weather_path = self.directory / 'mixed-weather.json'
        weather_path.write_text(json.dumps(MIXED_CONFIG))
        for weather in ([], ['--weather=hot-high'], ['--weather-file=' + str(weather_path)]):
            with self.subTest(weather=weather):
                baseline, context = self.run_flight('baseline', weather)
                self.assertIsNone(context)
                for time in ('00:00', '05:45', '12:00', '18:00', '23:59:59'):
                    result, context = self.run_flight('selected', [*weather, '--time-of-day=' + time])
                    self.assertEqual(result, baseline)
                    self.assertEqual(context['format'], 'openrc-visual-context v1')
                    self.assertEqual(context['config']['mode'], 'astronomical')
                    self.assertEqual(context['moon'], 'not-modelled')
                    self.assertEqual(len(context['config_sha256']), 64)

    def test_fleet_physics_is_independent(self):
        for aircraft in ("gp-extra-300s-60", "p51d-mustang-120", "sebart-avanti-s-a200-p100rx"):
            flags = ["--aircraft=" + aircraft]
            legacy, _ = self.run_flight("fleet-day", flags)
            night, _ = self.run_flight("fleet-night", [*flags, "--time-of-day=00:00"])
            self.assertEqual(legacy, night)

    def test_visual_context_and_physics_are_fps_independent(self):
        baseline = self.run_flight('fps30', ['--time-of-day=05:45'], 30)
        for fps in (60, 144):
            self.assertEqual(self.run_flight('fps' + str(fps), ['--time-of-day=05:45'], fps), baseline)

    def test_invalid_cli_is_rejected_before_trace(self):
        for flags in (['--time-of-day=24:00'], ['--time-of-day=nan'], ['--time-of-day'],
                      ['--date=2026-02-30'], ['--lighting=unknown'],
                      ['--lighting=legacy', '--time-of-day=12:00'],
                      ['--lighting-config=' + str(self.directory / 'missing.json')]):
            with self.subTest(flags=flags):
                self.run_flight('invalid', flags, success=False)

    def test_complete_config_preserves_location_offset_and_date(self):
        config = dict(format='openrc-lighting v1', mode='astronomical', date='2026-12-21',
                      local_seconds=3600, utc_offset_minutes=330, latitude_deg=-33.45,
                      longitude_deg=-70.667, location_name='Test site')
        path = self.directory / 'lighting.json'
        path.write_text(json.dumps(config))
        _, context = self.run_flight('config', ['--lighting-config=' + str(path)])
        self.assertEqual(context['config'], config)
        self.run_flight('conflict', ['--lighting-config=' + str(path), '--date=2026-01-01'], success=False)
        config['format'] = 'openrc-lighting v99'
        path.write_text(json.dumps(config))
        self.run_flight('future', ['--lighting-config=' + str(path)], success=False)


if __name__ == '__main__':
    unittest.main()
