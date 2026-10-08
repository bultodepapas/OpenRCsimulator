import csv
import io
import json
import math
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import audit as A
from check_trimmed_flight import INPUT_HASH_CONVENTION, SEMANTIC_HASH_CONVENTION


def q(value, unit='1'):
    return dict(value=value, unit=unit, kind='estimated', source='synthetic test')


def model():
    return {'format': 'openrc-aircraft v1', 'propulsion': {'propeller': {
        'diameter': q(1.0, 'm'), 'ct_table': q([[0, .1], [.5, .05], [1, 0]]),
        'cp_table': q([[0, .05], [1, .01]])}}}


def sample(tick=0, u=.5, rpm=60, **kwargs):
    result = dict.fromkeys(A.COLUMNS, 0.0)
    result.update(tick=tick, t_s=tick/240, u_mps=u, engine_rpm=rpm)
    result.update(kwargs)
    return result


def trace(data, samples, **changes):
    first = samples[0]
    meta = {'format': 'openrc-trace v3', 'metadata_schema': 'openrc-flight-meta v2',
            'aircraft_input_format': 'openrc-aircraft v1', 'aircraft_input_hash_convention': INPUT_HASH_CONVENTION,
            'aircraft_input_sha256': A.digest(data), 'aircraft_semantic_sha256': 'a'*64,
            'aircraft_semantic_hash_convention': SEMANTIC_HASH_CONVENTION,
            'propulsion_model': 'propeller-rpm-lag-v1', 'engine_rpm_semantics': 'propeller shaft rpm',
            'dt_s': str(1/240), 'state_layout': json.dumps(A.STATE_LAYOUT),
            'aux_layout': json.dumps(A.AUX_LAYOUT), 'loads': A.LOAD_TIMING,
            'state_timing': A.STATE_TIMING, 'frames': A.FRAMES,
            'recording_start_tick': str(int(first['tick'])),
            'recording_start_aux': json.dumps([first[k] for k in A.AUX_LAYOUT])}
    meta.update(changes)
    output = io.StringIO()
    for key, value in meta.items():
        output.write(f'# {key}: {value}\n')
    writer = csv.writer(output)
    writer.writerow(A.COLUMNS)
    writer.writerows([[s[k] for k in A.COLUMNS] for s in samples])
    return output.getvalue().encode()


class AuditTests(unittest.TestCase):
    def setUp(self):
        self.data = json.dumps(model()).encode()
        self.samples = [sample(), sample(1)]
        self.diameter, self.axis, self.tables = A.propeller(model())

    def run_audit(self, samples=None, data=None, **kwargs):
        samples = self.samples if samples is None else samples
        data = self.data if data is None else data
        return A.audit(trace(data, samples), data, ticks=len(samples)-1, still_air=True, **kwargs)

    def classify(self, **kwargs):
        return A.classify(sample(**kwargs), self.diameter, self.axis, self.tables, {})

    def coverage(self):
        entry = {'source': 'synthetic campaign', 'j_gaps': [[0, .3]],
                 'source_regions': [{'j_range': [0, 0], 'rpm_range': [30, 100], 'source': 'static'},
                                    {'j_range': [.3, 1], 'rpm_range': [60, 70], 'source': 'dynamic'}]}
        return {'format': 'openrc-propeller-coverage v1', 'aircraft_input_sha256': A.digest(self.data),
                'relationship': 'synthetic', 'tables': {'ct_table': entry}}

    def test_advance_uses_axial_speed_and_rotations_per_second(self):
        p = self.classify(u=1, rpm=120, v_mps=90, w_mps=10, speed_mps=100)
        self.assertEqual(p['advance_ratio'], .5)
        self.assertEqual(p['axial_mps'], 1)

    def test_thrust_axis_down_and_right(self):
        data = model()
        data['propulsion']['propeller']['thrust_angles'] = q([10, 0], 'deg')
        diameter, axis, tables = A.propeller(data)
        p = A.classify(sample(u=0, w_mps=2), diameter, axis, tables, {})
        self.assertAlmostEqual(p['advance_ratio'], 2*math.sin(math.radians(10)))
        data['propulsion']['propeller']['thrust_angles'] = q([0, 10], 'deg')
        diameter, axis, tables = A.propeller(data)
        self.assertAlmostEqual(A.classify(sample(u=0, v_mps=3), diameter, axis, tables, {})['advance_ratio'], 3*math.sin(math.radians(10)))

    def test_stopped_threshold_and_reverse(self):
        for rpm in [0, .999999999]:
            p = self.classify(rpm=rpm, u=-10)
            self.assertIsNone(p['advance_ratio'])
            self.assertEqual(p['tables']['ct_table'], ['stopped'])
        self.assertIsNotNone(self.classify(rpm=1)['advance_ratio'])
        p = self.classify(u=-10)
        self.assertEqual(p['advance_ratio'], 0)
        self.assertIn('reverse_flow_clamped', p['tables']['ct_table'])

    def test_table_bounds_are_inclusive(self):
        for u in [0, .5, 1]:
            self.assertNotIn('above_table', self.classify(u=u)['tables']['ct_table'])
        self.assertIn('above_table', self.classify(u=1+1e-10)['tables']['ct_table'])

    def test_each_table_uses_own_domain(self):
        self.tables['cp_table']['j_range'][1] = .4
        p = self.classify()
        self.assertNotIn('above_table', p['tables']['ct_table'])
        self.assertIn('above_table', p['tables']['cp_table'])

    def test_known_gap_has_open_endpoints(self):
        coverage = A.coverage_contract(self.coverage(), A.digest(self.data), self.tables)
        for j, gap in [(0, False), (.1, True), (.3, False)]:
            p = A.classify(sample(u=j), 1, self.axis, self.tables, coverage)
            self.assertEqual('documented_j_gap' in p['tables']['ct_table'], gap)

    def test_rpm_regions_do_not_extend_static_range_to_dynamic_j(self):
        coverage = A.coverage_contract(self.coverage(), A.digest(self.data), self.tables)
        for u, rpm, outside in [(0, 90, False), (.75, 90, True), (.5, 60, False), (7/12, 70, False)]:
            p = A.classify(sample(u=u, rpm=rpm), 1, self.axis, self.tables, coverage)
            self.assertEqual('outside_source_rpm' in p['tables']['ct_table'], outside)
        p = A.classify(sample(u=.1), 1, self.axis, self.tables, coverage)
        self.assertIn('source_j_uncovered', p['tables']['ct_table'])
        self.assertIn('rpm_coverage_unknown', p['tables']['ct_table'])

    def test_unknown_coverage_is_not_accepted_coverage(self):
        flags = self.classify()['tables']['ct_table']
        self.assertIn('rpm_coverage_unknown', flags)
        self.assertIn('j_gap_coverage_unknown', flags)

    def test_nominal_run_rpm_does_not_invent_a_band(self):
        c = self.coverage()
        c['tables']['ct_table']['source_regions'][1]['rpm_range'] = None
        support = A.coverage_contract(c, A.digest(self.data), self.tables)
        p = A.classify(sample(), 1, self.axis, self.tables, support)
        self.assertIn('rpm_coverage_unknown', p['tables']['ct_table'])

    def test_load_query_uses_previous_velocity_and_current_rpm(self):
        result = self.run_audit([sample(u=2, rpm=60), sample(1, u=0, rpm=240), sample(2, u=9, rpm=120)])
        self.assertEqual(result['active_j_range'], [0, .5])
        self.assertEqual(result['load_query_samples'], 2)
        self.assertEqual(result['counts']['ct_table']['above_table'], 0)
        self.assertIn('above_table', result['initial_state_point']['tables']['ct_table'])

    def test_initial_sample_does_not_inflate_counts(self):
        result = self.run_audit([sample(rpm=0), sample(1, rpm=0)])
        self.assertEqual(result['counts']['ct_table']['stopped'], 1)
        self.assertEqual(result['first_occurrence']['ct_table']['stopped']['tick'], 1)
        self.assertIsNone(result['active_j_range'])

    def test_midflight_initial_load_is_not_reconstructible(self):
        result = self.run_audit([sample(20), sample(21)])
        self.assertFalse(result['initial_is_recorded_load_query'])

    def test_explicit_still_air_required(self):
        with self.assertRaisesRegex(ValueError, 'still-air'):
            A.audit(trace(self.data, self.samples), self.data, ticks=1)

    def test_identity_timing_layout_and_turbine_rejected(self):
        changes = [{'aircraft_input_sha256': 'b'*64}, {'metadata_schema': 'openrc-flight-meta v1'},
                   {'loads': 'different timing'}, {'engine_rpm_semantics': 'turbine spool rpm'},
                   {'state_layout': '[]'}, {'dt_s': 'nan'}, {'dt_s': '.1'},
                   {'recording_start_tick': '99'}, {'recording_start_aux': '[0,0,0,0]'}]
        changes += [{'state_timing': 'different timing'}, {'frames': 'body FLU'}]
        for change in changes:
            with self.subTest(change=change), self.assertRaises(ValueError):
                A.audit(trace(self.data, self.samples, **change), self.data, ticks=1, still_air=True)

    def test_missing_duplicate_and_nonfinite_trace_rows_rejected(self):
        cases = [[sample(), sample(2)], [sample(), sample(0)], [sample(), sample(1, t_s=.1)],
                 [sample(), sample(1, rpm=-1)], [sample(), sample(1, u=float('nan'))]]
        for samples in cases:
            with self.subTest(samples=samples), self.assertRaises(ValueError):
                self.run_audit(samples)
        with self.assertRaises(ValueError):
            A.audit(trace(self.data, self.samples), self.data, ticks=2, still_air=True)
        with self.assertRaises(ValueError):
            A.audit(b'# dt_s: 0.1\n'+trace(self.data, self.samples), self.data, ticks=1, still_air=True)

    def test_aircraft_contract(self):
        mutations = [('diameter', q(0, 'm')), ('diameter', q(True, 'm')), ('diameter', q('1', 'm')),
                     ('ct_table', q([[0, .1], [0, .2]])), ('ct_table', q([[0, .1], [1, float('inf')]])),
                     ('cp_table', q([[.1, .1], [1, .2]])), ('cp_table', q([[0, .1]], 'N'))]
        for key, value in mutations:
            data = model(); data['propulsion']['propeller'][key] = value
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                A.propeller(data)
        data = model(); data['propulsion']['kind'] = 'turbine'
        with self.assertRaises(ValueError):
            A.propeller(data)

    def test_coverage_contract(self):
        for key, value in [('aircraft_input_sha256', 'b'*64), ('relationship', 'validated'), ('tables', {})]:
            data = self.coverage(); data[key] = value
            with self.assertRaises(ValueError):
                A.coverage_contract(data, A.digest(self.data), self.tables)
        for field, value in [('j_gaps', [[.3, .2]]), ('j_gaps', [[0, 2]]),
                             ('j_gaps', [[0, .4], [.3, .5]]), ('source_regions', [])]:
            data = self.coverage(); data['tables']['ct_table'][field] = value
            with self.assertRaises(ValueError):
                A.coverage_contract(data, A.digest(self.data), self.tables)

    def test_duplicate_and_nonfinite_json_rejected(self):
        for blob in [b'{"x":1,"x":2}', b'{"x":NaN}', b'{"x":Infinity}', b'[]']:
            with self.assertRaises(ValueError):
                A.decode(blob)

    def test_malformed_nested_objects_and_angle_bounds(self):
        for key in ('propulsion', 'propeller'):
            for value in ([], None, 'invalid', 1):
                data = model()
                if key == 'propulsion':
                    data[key] = value
                else:
                    data['propulsion'][key] = value
                with self.assertRaises(ValueError):
                    A.propeller(data)
        data = model(); data['propulsion']['propeller']['thrust_angles'] = q([11, 0], 'deg')
        with self.assertRaises(ValueError):
            A.propeller(data)
        c = self.coverage(); c['tables']['ct_table']['source_regions'] = [None]
        with self.assertRaises(ValueError):
            A.coverage_contract(c, A.digest(self.data), self.tables)

    def test_cli_success_failure_and_input_protection(self):
        with tempfile.TemporaryDirectory() as directory:
            d = Path(directory); aircraft=d/'aircraft.json'; flight=d/'flight.csv'; out=d/'report.json'
            aircraft.write_bytes(self.data); flight.write_bytes(trace(self.data, self.samples))
            command = [sys.executable, str(Path(A.__file__)), str(flight), '--aircraft', str(aircraft),
                       '--ticks', '1', '--output', str(out)]
            failed = subprocess.run(command, capture_output=True)
            self.assertEqual(failed.returncode, 1); self.assertFalse(out.exists())
            passed = subprocess.run(command+['--assume-still-air'], capture_output=True)
            self.assertEqual(passed.returncode, 0, passed.stderr)
            report = json.loads(out.read_text())
            self.assertEqual(report['trace_sha256'], A.digest(flight.read_bytes()))
            self.assertEqual(report['tool_sha256'], A.digest(Path(A.__file__).read_bytes()))
            command[-1] = str(aircraft)
            self.assertEqual(subprocess.run(command+['--assume-still-air'], capture_output=True).returncode, 1)
            self.assertEqual(aircraft.read_bytes(), self.data)


if __name__ == '__main__':
    unittest.main()
