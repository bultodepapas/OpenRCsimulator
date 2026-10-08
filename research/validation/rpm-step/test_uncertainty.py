#!/usr/bin/env python3
"""VAL-7c: known-answer covariance, branch screens and seeded sampling checks."""
import copy
import json
import math
from pathlib import Path
import random
import statistics
import subprocess
import sys
import tempfile
import unittest

from test_reduce import fixture, m


def uncertain_fixture(decreasing=False):
    d = fixture(initial=1000, final=11000, command=0)
    d['series']['samples'] = [[-.1, 1000], [.2, 1000], [.6, 5000], [1., 9000], [1.2, 11000]]
    if decreasing:
        for key in ('initial_rpm', 'final_rpm'):
            d[key]['value'] = 12000-d[key]['value']
        for row in d['series']['samples']:
            row[1] = 12000-row[1]
    d['uncertainty_model'] = 'independent-inputs v1'
    d['initial_rpm']['u'] = 2.
    d['final_rpm']['u'] = 3.
    d['command_time']['u'] = .001
    d['series']['time_u_s'] = .0001
    d['series']['rpm_u'] = 1.
    return d


def outputs(d):
    r = m.reduce(d)
    values = {f't{name}_s': c['time_s'] for name, c in r['crossings'].items()}
    values.update({f't{name}_after_command_s': c['after_command_s'] for name, c in r['crossings'].items()})
    values.update({key: r['first_order_diagnostic'][key] for key in
                   ('rise_10_90_s', 'tau_s', 'delay_s', 't63_consistency_error_s')})
    return values


def primitives(d):
    for key in ('initial_rpm', 'final_rpm', 'command_time'):
        yield key, d[key], 'value', d[key]['u']
    for index, row in enumerate(d['series']['samples']):
        yield f'time:{index}', row, 0, d['series']['time_u_s']
        yield f'rpm:{index}', row, 1, d['series']['rpm_u']


class Uncertainty(unittest.TestCase):
    def test_explicit_opt_in_and_strict_model(self):
        d = uncertain_fixture()
        del d['uncertainty_model']
        self.assertEqual(m.reduce(d)['measurement_uncertainty'], {'status': 'not_requested', 'metrics': None})
        for bad in (None, True, {}, 'independent', 1):
            d['uncertainty_model'] = bad
            with self.assertRaises(ValueError):
                m.reduce(d)

    def test_zero_uncertainty_exact_knots(self):
        d = fixture()
        d['uncertainty_model'] = 'independent-inputs v1'
        u = m.reduce(d)['measurement_uncertainty']
        self.assertEqual(u['status'], 'available')
        self.assertTrue(all(v['u_s'] == 0 for v in u['metrics'].values()))

    def test_nominal_results_unchanged(self):
        d = uncertain_fixture()
        enabled = m.reduce(d)
        del d['uncertainty_model']
        legacy = m.reduce(d)
        for key in ('crossings', 'first_order_diagnostic', 'observed', 'normalized_residuals'):
            self.assertEqual(enabled[key], legacy[key])

    def test_all_signed_sensitivities_against_finite_differences(self):
        for decreasing in (False, True):
            d = uncertain_fixture(decreasing)
            u = m.reduce(d)['measurement_uncertainty']
            self.assertEqual(u['status'], 'available')
            for key, obj, field, sigma in primitives(d):
                original = obj[field]
                step = sigma*.01
                obj[field] = original+step
                plus = outputs(d)
                obj[field] = original-step
                minus = outputs(d)
                obj[field] = original
                for name, row in u['metrics'].items():
                    numeric = (plus[name]-minus[name])/(2*step)*sigma
                    analytic = row['signed_contributions_s'].get(key, 0.)
                    self.assertAlmostEqual(numeric, analytic, delta=1e-11, msg=f'{decreasing}: {name}/{key}')

    def test_shared_samples_and_endpoints_hand_solution(self):
        d = uncertain_fixture()
        d['series']['samples'] = [[-.1, 1000], [.2, 1000], [1.2, 11000], [1.4, 11000]]
        u = m.reduce(d)['measurement_uncertainty']
        row = u['metrics']['rise_10_90_s']
        # t90-t10=.8*dt*endpoint_span/sample_span. Reused inputs cancel partly.
        expected = {'initial_rpm': -.8/10000*2, 'final_rpm': .8/10000*3,
                    'rpm:1': .8/10000, 'rpm:2': -.8/10000,
                    'time:1': -.8*.0001, 'time:2': .8*.0001}
        for key, value in expected.items():
            self.assertIn(key, row['signed_contributions_s'])
            self.assertAlmostEqual(row['signed_contributions_s'][key], value, places=15)
        self.assertAlmostEqual(row['u_s'], math.hypot(*expected.values()), places=15)
        metrics = u['metrics']
        independent_crossings = math.hypot(metrics['t10_s']['u_s'], metrics['t90_s']['u_s'])
        self.assertNotAlmostEqual(row['u_s'], independent_crossings, places=7)
        self.assertAlmostEqual(u['covariance_s2']['t10_s']['t90_s'],
                               u['covariance_s2']['t90_s']['t10_s'], places=20)

    def test_command_error_cancels_from_tau_and_consistency(self):
        d = uncertain_fixture()
        d['initial_rpm']['u'] = d['final_rpm']['u'] = 0
        d['series']['time_u_s'] = d['series']['rpm_u'] = 0
        u = m.reduce(d)['measurement_uncertainty']['metrics']
        self.assertEqual(u['tau_s']['u_s'], 0)
        self.assertEqual(u['t63_consistency_error_s']['u_s'], 0)
        self.assertEqual(u['delay_s']['u_s'], .001)

    def test_endpoint_covariance_across_disjoint_segments(self):
        d = uncertain_fixture()
        d['series']['time_u_s'] = d['series']['rpm_u'] = 0
        u = m.reduce(d)['measurement_uncertainty']
        # Every segment has slope 10,000 RPM/s. Only independent endpoint errors remain.
        expected = (.9*.1*2**2 + .1*.9*3**2)/10000**2
        self.assertAlmostEqual(u['covariance_s2']['t10_s']['t90_s'], expected, places=20)
        self.assertAlmostEqual(u['metrics']['tau_s']['u_s'],
                               .8*math.hypot(2, 3)/(10000*math.log(9)), places=15)

    def test_covariance_positive_semidefinite_and_diagonal(self):
        u = m.reduce(uncertain_fixture())['measurement_uncertainty']
        keys = list(u['metrics'])
        matrix = u['covariance_s2']
        rng = random.Random(7104)
        for key in keys:
            self.assertAlmostEqual(matrix[key][key], u['metrics'][key]['u_s']**2, places=20)
        for _ in range(50):
            weights = {key: rng.uniform(-1, 1) for key in keys}
            quadratic = math.fsum(weights[a]*weights[b]*matrix[a][b] for a in keys for b in keys)
            self.assertGreaterEqual(quadratic, -1e-20)

    def test_screen_threshold_knots_and_earlier_near_hits(self):
        d = fixture()
        d['uncertainty_model'] = 'independent-inputs v1'
        d['series']['rpm_u'] = 1
        self.assert_unavailable(d, 'bracket')
        d = uncertain_fixture()
        d['series']['samples'].insert(1, [0., 1999.])
        self.assert_unavailable(d, 'bracket')

    def assert_unavailable(self, d, reason):
        u = m.reduce(d)['measurement_uncertainty']
        self.assertEqual(u['status'], 'unavailable')
        self.assertIsNone(u['metrics'])
        self.assertNotIn('covariance_s2', u)
        self.assertTrue(any(reason in r for r in u['screening_reasons']), u)

    def test_screen_endpoint_time_and_command_order(self):
        d = uncertain_fixture(); d['initial_rpm']['u'] = 4000
        self.assert_unavailable(d, 'Endpoint')
        d = uncertain_fixture(); d['series']['time_u_s'] = .1
        self.assert_unavailable(d, 'time ordering')
        d = uncertain_fixture(); d['command_time']['u'] = .2
        self.assert_unavailable(d, 'command ordering')

    def test_screen_recrossing(self):
        d = uncertain_fixture()
        d['series']['samples'].extend([[1.3, 8000], [1.4, 11000]])
        self.assert_unavailable(d, 'repeated')

    def test_affine_rpm_and_time_scaling_of_uncertainty(self):
        d = uncertain_fixture()
        before = m.reduce(d)['measurement_uncertainty']['metrics']
        for key in ('initial_rpm', 'final_rpm'):
            d[key]['value'] = d[key]['value']*3+100
            d[key]['u'] *= 3
        for row in d['series']['samples']:
            row[1] = row[1]*3+100
            row[0] = row[0]*4+100
        d['series']['rpm_u'] *= 3
        d['series']['time_u_s'] *= 4
        d['command_time']['value'] = d['command_time']['value']*4+100
        d['command_time']['u'] *= 4
        after = m.reduce(d)['measurement_uncertainty']['metrics']
        for key in before:
            self.assertAlmostEqual(after[key]['u_s'], 4*before[key]['u_s'], places=13)

    def test_seeded_sampling_matches_standard_uncertainties(self):
        d = uncertain_fixture()
        reference = m.reduce(d)['measurement_uncertainty']
        rng = random.Random(7103)
        draws = {name: [] for name in reference['metrics']}
        # Each shared primitive is perturbed once per trial, never once per crossing.
        sample = copy.deepcopy(d)
        del sample['uncertainty_model']
        targets = list(primitives(sample))
        originals = [obj[field] for _, obj, field, _ in targets]
        for _ in range(12000):
            for (_, obj, field, sigma), original in zip(targets, originals):
                obj[field] = original+rng.gauss(0., sigma)
            for name, value in outputs(sample).items():
                draws[name].append(value)
        for name, row in reference['metrics'].items():
            observed = statistics.stdev(draws[name])
            self.assertAlmostEqual(observed/row['u_s'], 1., delta=.03, msg=name)
        # Covariance is particularly sensitive to accidentally independent crossings.
        covariance = statistics.covariance(draws['tau_s'], draws['delay_s'])
        expected = reference['covariance_s2']['tau_s']['delay_s']
        self.assertAlmostEqual(covariance, expected, delta=2e-9)

    def test_cli_opt_in_is_deterministic_and_keeps_hashes(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)/'input.json'
            path.write_text(json.dumps(uncertain_fixture()))
            command = [sys.executable, str(Path(__file__).with_name('reduce.py')), str(path)]
            first = subprocess.run(command, capture_output=True, check=True)
            second = subprocess.run(command, capture_output=True, check=True)
            self.assertEqual(first.stdout, second.stdout)
            r = json.loads(first.stdout)
            self.assertEqual(r['measurement_uncertainty']['status'], 'available')
            self.assertEqual(len(r['input_sha256']), 64)
            self.assertEqual(len(r['reducer_sha256']), 64)


if __name__ == '__main__':
    unittest.main(verbosity=2)
