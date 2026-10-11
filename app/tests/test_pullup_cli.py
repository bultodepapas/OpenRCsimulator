"""CLI contract for the opt-in D8b-R2 wing-polar candidate route."""
import csv
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

APP = Path(__file__).resolve().parents[1]
REPO = APP.parent
CANDIDATE = REPO / 'research/flight-robustness/d8b-r2/candidates/intermediate.json'
REFERENCE = APP / 'data/aircraft/jensen_ugly_stik_60.json'


class PullupCandidateCli(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.godot = os.environ.get('OPENRC_TEST_GODOT') or subprocess.check_output(
            [str(APP / 'get-godot.sh')], text=True).strip()
        if not CANDIDATE.is_file():
            raise AssertionError(f'research candidate fixture is missing: {CANDIDATE}')
        cls.temp = tempfile.TemporaryDirectory(prefix='openrc-pullup-cli-')
        cls.addClassCleanup(cls.temp.cleanup)
        cls.directory = Path(cls.temp.name)

    @classmethod
    def run_app(cls, *args):
        command = [cls.godot, '--headless', '--path', str(APP), '--audio-driver', 'Dummy', '--', *args]
        return subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                              text=True, timeout=30)

    def trace_path(self, name):
        path = self.directory / name
        path.unlink(missing_ok=True)
        return path

    def assert_refused_without_trace(self, name, options, message='experimental aircraft data refused'):
        trace = self.trace_path(name + '.csv')
        result = self.run_app(*options, '--trace=' + str(trace), '--t=.1')
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn(message, result.stdout.lower(), result.stdout)
        self.assertFalse(trace.exists(), result.stdout)

    def test_candidate_trace_uses_exact_input_bytes(self):
        trace = self.trace_path('candidate.csv')
        result = self.run_app('--experimental-aircraft-data=' + str(CANDIDATE.resolve()),
                              '--trace=' + str(trace), '--t=.1')
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn('EXPERIMENTAL AIRCRAFT DATA: wing polar', result.stdout)
        self.assertNotIn('ERROR:', result.stdout)
        lines = trace.read_text().splitlines()
        metadata = dict(line[2:].split(': ', 1) for line in lines if line.startswith('# '))
        self.assertEqual(metadata['aircraft_input_sha256'], hashlib.sha256(CANDIDATE.read_bytes()).hexdigest())
        self.assertIn('jensen-das-ugly-stik-60', metadata['aircraft'])
        self.assertIn('tabulated-wing-v1', metadata['wing_polar_model'])
        rows = list(csv.reader(line for line in lines if not line.startswith('#')))
        self.assertEqual(len(rows), 26)  # header plus initial state and 24 x 240 Hz ticks

    def test_cli_rejects_noncandidate_launch_contexts(self):
        candidate_arg = '--experimental-aircraft-data=' + str(CANDIDATE.resolve())
        cases = [
            ('missing-value', ['--experimental-aircraft-data']),
            ('relative-path', ['--experimental-aircraft-data=research/flight-robustness/d8b-r2/candidates/intermediate.json']),
            ('missing-file', ['--experimental-aircraft-data=' + str(self.directory / 'missing.json')]),
            ('scripted', [candidate_arg, '--scripted']),
            ('electric-demo', [candidate_arg, '--electric-demo=4s']),
            ('other-aircraft', [candidate_arg, '--aircraft=gp-extra-300s-60']),
        ]
        for name, options in cases:
            with self.subTest(case=name):
                self.assert_refused_without_trace(name, options)

    def test_cli_rejects_bad_json_types_and_reference_changes(self):
        baseline = json.loads(REFERENCE.read_text())
        candidate = json.loads(CANDIDATE.read_text())
        cases = []
        cases.append(('malformed-json', b'{not json'))
        cases.append(('wrong-root-type', b'[]'))
        no_polar = json.loads(json.dumps(candidate))
        no_polar['aero'].pop('wing_polar', None)
        cases.append(('missing-polar', json.dumps(no_polar).encode()))
        bad_polar = json.loads(json.dumps(candidate))
        bad_polar['aero']['wing_polar'] = 'not an object'
        cases.append(('wrong-polar-type', json.dumps(bad_polar).encode()))
        bad_id = json.loads(json.dumps(candidate))
        bad_id['id'] = 'gp-extra-300s-60'
        cases.append(('wrong-id', json.dumps(bad_id).encode()))

        changed_geometry = json.loads(json.dumps(candidate))
        changed_geometry['reference'] = json.loads(json.dumps(baseline['reference']))
        geometry_field = next((key for key in ('wing_span', 'mean_chord', 'wing_area', 'aero_reference_point')
                               if key in changed_geometry['reference']), None)
        if geometry_field is None:
            self.fail('catalog aircraft reference JSON has no recognized span/chord/area/CG geometry field')
        value = changed_geometry['reference'][geometry_field]
        if isinstance(value, dict) and 'value' in value:
            value['value'] = float(value['value']) + 0.01
        elif isinstance(value, (int, float)):
            changed_geometry['reference'][geometry_field] = value + 0.01
        else:
            self.fail(f'unrecognized geometry field shape for {geometry_field}')
        cases.append(('changed-reference-geometry', json.dumps(changed_geometry).encode()))

        for name, content in cases:
            with self.subTest(case=name):
                path = self.directory / (name + '.json')
                path.write_bytes(content)
                self.assert_refused_without_trace(name, ['--experimental-aircraft-data=' + str(path.resolve())])


if __name__ == '__main__':
    unittest.main()
