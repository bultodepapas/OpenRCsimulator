#!/usr/bin/env python3
"""Known-answer, adverse-data and process checks for VAL-7b (stdlib only)."""
import copy
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('rpm_reduce', HERE / 'reduce.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


def quantity(value, unit):
    return dict(value=value, unit=unit, u=0, kind='synthetic', source='Analytic test fixture, not measurements')


def fixture(initial=2000., final=10000., tau=.25, delay=.08, command=2.):
    # Exact 10/63/90 knots establish analytic recovery independently of sampling error.
    relative = [-.3, 0., delay, delay-tau*math.log(.9), delay+tau,
                delay-tau*math.log(.1), delay+5*tau]
    samples = [[command+t, initial+(final-initial)*(1-math.exp(-(t-delay)/tau) if t>delay else 0.)]
               for t in relative]
    return dict(format='openrc-rpm-step v1', evidence='synthetic', configuration='Synthetic test configuration',
                notes='Known steady endpoints; command and RPM use one clock.',
                command_time=quantity(command, 's'), initial_rpm=quantity(initial, 'rpm'),
                final_rpm=quantity(final, 'rpm'), series=dict(kind='synthetic', source='Analytic samples',
                time_u_s=0, rpm_u=0, samples=samples))


class Reduction(unittest.TestCase):
    def test_exact_exponential(self):
        r = m.reduce(fixture())
        f = r['first_order_diagnostic']
        self.assertAlmostEqual(f['tau_s'], .25, places=13)
        self.assertAlmostEqual(f['delay_s'], .08, places=13)
        self.assertAlmostEqual(f['rise_10_90_s'], .25*math.log(9), places=13)
        self.assertAlmostEqual(f['t63_consistency_error_s'], 0, places=13)
        self.assertLess(f['normalized_rmse'], 1e-14)
        self.assertEqual(r['direction'], 'increasing')

    def test_decreasing(self):
        r = m.reduce(fixture(initial=11000, final=2500))
        self.assertEqual(r['direction'], 'decreasing')
        self.assertAlmostEqual(r['first_order_diagnostic']['tau_s'], .25, places=13)
        self.assertAlmostEqual(r['first_order_diagnostic']['delay_s'], .08, places=13)

    def test_affine_rpm_invariance(self):
        d = fixture()
        a = m.reduce(d)['first_order_diagnostic']
        for key in ('initial_rpm', 'final_rpm'):
            d[key]['value'] = 3*d[key]['value']+700
        for row in d['series']['samples']:
            row[1] = 3*row[1]+700
        b = m.reduce(d)['first_order_diagnostic']
        for key in ('tau_s', 'delay_s', 'rise_10_90_s'):
            self.assertAlmostEqual(a[key], b[key], places=13)

    def test_time_translation(self):
        d = fixture()
        a = m.reduce(d)
        d['command_time']['value'] += 123.
        for row in d['series']['samples']:
            row[0] += 123.
        b = m.reduce(d)
        self.assertAlmostEqual(a['first_order_diagnostic']['tau_s'], b['first_order_diagnostic']['tau_s'], places=12)
        self.assertAlmostEqual(a['first_order_diagnostic']['delay_s'], b['first_order_diagnostic']['delay_s'], places=12)
        self.assertAlmostEqual(b['crossings']['10']['time_s']-a['crossings']['10']['time_s'], 123.)

    def test_time_scaling(self):
        d = fixture()
        for row in d['series']['samples']:
            row[0] *= 4
        d['command_time']['value'] *= 4
        f = m.reduce(d)['first_order_diagnostic']
        self.assertAlmostEqual(f['tau_s'], 1.)
        self.assertAlmostEqual(f['delay_s'], .32)

    def test_irregular_interpolation(self):
        d = fixture(initial=0, final=100, command=0)
        d['series']['samples'] = [[-.1, 0], [.2, 0], [.7, 20], [1.1, 50], [2., 100]]
        r = m.reduce(d)
        self.assertAlmostEqual(r['crossings']['10']['time_s'], .45)
        self.assertAlmostEqual(r['crossings']['90']['time_s'], 1.82)
        self.assertEqual(r['crossings']['10']['sampling_support_s'], [.2, .7])
        self.assertEqual(r['crossings']['90']['sample_indices'], [3, 4])

    def test_sampling_support_contains_analytic_parameters(self):
        for dt in (.03, .01, .002):
            d = fixture(command=0)
            d['series']['samples'] = [[i*dt, 2000+8000*(1-math.exp(-max(0., i*dt-.08)/.25))]
                                      for i in range(-2, int(1.6/dt))]
            f = m.reduce(d)['first_order_diagnostic']
            for key, truth in (('tau_sampling_support_s', .25), ('delay_sampling_support_s', .08)):
                self.assertLessEqual(f[key][0], truth)
                self.assertGreaterEqual(f[key][1], truth)
            self.assertLess(abs(f['tau_s']-.25), dt)

    def test_nonmonotone_first_crossing_overshoot(self):
        d = fixture(initial=0, final=100, command=0)
        d['series']['samples'] = [[0, 0], [1, 20], [2, 5], [3, 70], [4, 110], [5, 100]]
        r = m.reduce(d)
        self.assertAlmostEqual(r['crossings']['10']['time_s'], .5)
        self.assertEqual(r['crossings']['10']['forward_crossing_count'], 2)
        self.assertAlmostEqual(r['observed']['max_backward_fraction_step'], .15)
        self.assertAlmostEqual(r['observed']['overshoot_fraction'], .1)
        self.assertGreater(r['first_order_diagnostic']['normalized_rmse'], 0)
        self.assertGreaterEqual(len(r['warnings']), 3)

    def test_negative_delay_is_not_clamped(self):
        d = fixture(initial=0, final=100, command=0)
        d['series']['samples'] = [[0, 0], [.01, 10], [.5, 70], [1, 90], [2, 100]]
        f = m.reduce(d)['first_order_diagnostic']
        self.assertLess(f['delay_s'], 0)
        self.assertFalse(f['causal_delay'])

    def test_precommand_crossing_refused(self):
        d = fixture()
        d['command_time']['value'] = 2.2
        with self.assertRaisesRegex(ValueError, 'precedes command'):
            m.reduce(d)

    def test_underresolved_flag(self):
        d = fixture(initial=0, final=100, command=0)
        d['series']['samples'] = [[0, 0], [1, 100], [2, 100]]
        r = m.reduce(d)
        self.assertTrue(any('under-resolved' in w for w in r['warnings']))

    def test_threshold_plateau(self):
        d = fixture(initial=0, final=100, command=0)
        d['series']['samples'] = [[0, 0], [1, 10], [2, 10], [3, 90], [4, 100]]
        c = m.reduce(d)['crossings']['10']
        self.assertEqual(c['time_s'], 1)
        self.assertEqual(c['forward_crossing_count'], 1)

    def test_missing_threshold_and_onset(self):
        for change in ('tail', 'onset'):
            d = fixture()
            if change == 'tail':
                d['series']['samples'] = d['series']['samples'][:-2]
            else:
                d['series']['samples'][0][1] = 4000
            with self.assertRaises(ValueError):
                m.reduce(d)

    def test_invalid_sample_values_and_order(self):
        for value in (True, '1', float('nan'), float('inf'), -1):
            d = fixture()
            d['series']['samples'][1][1] = value
            with self.assertRaises(ValueError):
                m.reduce(d)
        for time in (1., 1.7, True, '2', float('nan')):
            d = fixture()
            d['series']['samples'][1][0] = time
            with self.assertRaises(ValueError):
                m.reduce(d)

    def test_bad_contract(self):
        cases = []
        for key, value in (('format', 'wrong'), ('evidence', 'estimated'), ('notes', ''), ('extra', 1)):
            d = fixture(); d[key] = value; cases.append(d)
        for key, value in (('unit', 'Hz'), ('u', -1), ('kind', 'manual'), ('source', ''), ('value', True)):
            d = fixture(); d['initial_rpm'][key] = value; cases.append(d)
        d = fixture(); d['final_rpm']['value'] = 2000; cases.append(d)
        d = fixture(); d['series']['samples'] = [[0, 1]]; cases.append(d)
        for d in cases:
            with self.assertRaises(ValueError):
                m.reduce(d)

    def test_measured_provenance_and_uncertainty_retained(self):
        d = fixture(); d['evidence'] = 'measured'
        with self.assertRaisesRegex(ValueError, 'synthetic'):
            m.reduce(d)
        for key in ('command_time', 'initial_rpm', 'final_rpm', 'series'):
            d[key]['kind'] = 'measured'
        d['series']['rpm_u'] = 37
        d['command_time']['u'] = .01
        r = m.reduce(d)
        self.assertEqual(r['input'], d)
        self.assertEqual(r['input']['series']['rpm_u'], 37)

    def test_json_duplicates_and_nonfinite(self):
        for raw in ('{"x": 1, "x": 2}', '{"x": NaN}', '{"x": Infinity}'):
            with self.assertRaises(ValueError):
                m.load(raw)

    def test_cli_reproducible_and_hashes(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)/'input.json'
            raw = json.dumps(fixture()).encode()
            path.write_bytes(raw)
            cmd = [sys.executable, str(HERE/'reduce.py'), str(path)]
            a = subprocess.run(cmd, capture_output=True)
            b = subprocess.run(cmd, capture_output=True)
            self.assertEqual(a.returncode, 0, a.stderr)
            self.assertEqual(a.stdout, b.stdout)
            r = json.loads(a.stdout)
            self.assertEqual(r['input_sha256'], hashlib.sha256(raw).hexdigest())
            self.assertEqual(r['reducer_sha256'], hashlib.sha256((HERE/'reduce.py').read_bytes()).hexdigest())

    def test_cli_failure_no_partial_report(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)/'bad.json'
            for raw in ('{}', '{"x":NaN}', 'null', '[]', '"a"', '{'):
                path.write_text(raw)
                p = subprocess.run([sys.executable, str(HERE/'reduce.py'), str(path)], capture_output=True)
                self.assertEqual(p.returncode, 1, p.stderr)
                self.assertEqual(p.stdout, b'')
                self.assertIn(b'RPM step reduction failed', p.stderr)
            path.unlink()
            p = subprocess.run([sys.executable, str(HERE/'reduce.py'), str(path)], capture_output=True)
            self.assertEqual(p.returncode, 1)
            self.assertEqual(p.stdout, b'')


if __name__ == '__main__':
    unittest.main(verbosity=2)
