#!/usr/bin/env python3
"""Analytic, covariance, contract and CLI verification using invented observations."""
import copy
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import random
import statistics
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('roll_video', HERE/'reduce.py')
REDUCER = importlib.util.module_from_spec(spec)
spec.loader.exec_module(REDUCER)


class Reduction(unittest.TestCase):
    def setUp(self):
        self.campaign = json.loads((HERE/'example.synthetic.json').read_text())
        self.csv = (HERE/'example.synthetic.csv').read_bytes()

    def results(self):
        return REDUCER.reduce(self.campaign, self.csv)['intervals']

    def test_analytic_full_turns(self):
        first, second, whole = self.results()
        self.assertEqual(whole['delta_frames'], 1200)
        self.assertEqual(whole['signed_complete_turns'], 2)
        self.assertEqual(whole['duration']['value'], 5.0)
        for item in [first, second, whole]:
            self.assertEqual(item['mean_period']['value'], 2.5)
            self.assertEqual(item['signed_turn_frequency']['value'], 0.4)
            self.assertEqual(item['mean_completed_roll_rate']['value'], 144.0)
            self.assertNotIn('p_radps', item)

    def test_direction_changes_sign_not_duration_or_uncertainty(self):
        before = self.results()[-1]
        self.csv = self.csv.replace(b'0.5,1', b'0.5,-1').replace(b'0.5,2', b'0.5,-2')
        after = self.results()[-1]
        for key in ['duration', 'mean_period']:
            self.assertEqual(before[key], after[key])
        for key in ['signed_turn_frequency', 'mean_completed_roll_rate']:
            self.assertEqual(before[key]['value'], -after[key]['value'])
            self.assertEqual(before[key]['u'], after[key]['u'])
            for name, value in before[key]['standard_uncertainty_contributions'].items():
                self.assertEqual(value, -after[key]['standard_uncertainty_contributions'][name])

    def test_frame_and_turn_origin_invariance(self):
        before = self.results()
        self.csv = b'id,frame,frame_u,turn_index\nentry,220,0.5,10\none,820,0.5,11\ntwo,1420,0.5,12\n'
        self.assertEqual(before, self.results())

    def test_rational_capture_cadence(self):
        self.campaign['video'].update(capture_fps_num=30000, capture_fps_den=1001)
        result = self.results()[-1]
        self.assertAlmostEqual(result['duration']['value'], 1200*1001/30000)
        self.assertAlmostEqual(result['mean_completed_roll_rate']['value'], 720/(1200*1001/30000))

    def test_closed_form_uncertainty_and_signs(self):
        whole = self.results()[-1]
        rel_var = 2*(0.5/1200)**2 + 0.001**2
        for key in ['duration', 'mean_period', 'signed_turn_frequency', 'mean_completed_roll_rate']:
            q = whole[key]
            self.assertAlmostEqual(q['u']**2, q['value']**2*rel_var, places=13)
        terms = whole['mean_completed_roll_rate']['standard_uncertainty_contributions']
        for name, value in {'event:entry': 0.06, 'event:two': -0.06, 'capture_clock': 0.144}.items():
            self.assertAlmostEqual(terms[name], value, places=14)

    def test_shared_middle_event_cancels_in_total_duration(self):
        first, second, whole = self.results()
        def terms(q): return q['duration']['standard_uncertainty_contributions']
        a, b, c = map(terms, [first, second, whole])
        combined = {k: a.get(k, 0)+b.get(k, 0) for k in a.keys() | b.keys()}
        self.assertEqual(combined.pop('event:one'), 0)
        self.assertEqual(combined, c)
        self.assertNotAlmostEqual(first['duration']['u']**2+second['duration']['u']**2, whole['duration']['u']**2, places=10)

    def test_adjacent_rate_covariance_keeps_shared_error_sign(self):
        self.campaign['video']['fps_relative_u'] = 0
        first, second, _ = self.results()
        a, b = [i['mean_completed_roll_rate']['standard_uncertainty_contributions'] for i in [first, second]]
        covariance = sum(value*b.get(k, 0) for k, value in a.items())
        self.assertAlmostEqual(covariance, -0.12**2)
        self.campaign['video']['fps_relative_u'] = 0.001
        first, second, _ = self.results()
        a, b = [i['mean_completed_roll_rate']['standard_uncertainty_contributions'] for i in [first, second]]
        self.assertAlmostEqual(sum(value*b.get(k, 0) for k, value in a.items()), 0.144**2-0.12**2)

    def test_seeded_sampling_matches_standard_uncertainty_and_covariance(self):
        first, second, whole = self.results()
        rng = random.Random(8012026)
        observed = [[], [], []]
        for _ in range(20000):
            f0, f1, f2 = [nominal+rng.gauss(0, 0.5) for nominal in [120, 720, 1320]]
            fps = 240*(1+rng.gauss(0, 0.001))
            for values, k, n in zip(observed, [1, 1, 2], [f1-f0, f2-f1, f2-f0]):
                values.append(360*k*fps/n)
        for samples, item in zip(observed, [first, second, whole]):
            self.assertLess(abs(statistics.stdev(samples)/item['mean_completed_roll_rate']['u']-1), 0.025)
        a, b = [i['mean_completed_roll_rate']['standard_uncertainty_contributions'] for i in [first, second]]
        covariance = sum(value*b.get(k, 0) for k, value in a.items())
        self.assertLess(abs(statistics.covariance(observed[0], observed[1])/covariance-1), 0.12)

    def test_skip_intermediate_annotation_preserves_whole(self):
        before = self.results()[-1]
        self.campaign['intervals'] = [self.campaign['intervals'][-1]]
        self.csv = self.csv.replace(b'one,720,0.5,1\n', b'')
        self.assertEqual(before, self.results()[0])

    def test_large_uncertainty_is_reported_not_clamped(self):
        self.campaign['video']['fps_relative_u'] = 0.2
        result = self.results()[-1]
        self.assertTrue(result['warnings'])
        self.assertGreater(result['mean_completed_roll_rate']['u'], 28.8)

    def test_unknown_and_missing_fields(self):
        for location in [[], ['video'], ['annotation'], ['intervals', 0]]:
            for mode in ['extra', 'missing']:
                campaign = copy.deepcopy(self.campaign)
                node = campaign
                for key in location: node = node[key]
                if mode == 'extra': node['unexpected'] = 1
                else: node.pop(next(iter(node)))
                with self.subTest(location=location, mode=mode), self.assertRaises(ValueError):
                    REDUCER.reduce(campaign, self.csv)

    def test_uncertain_acquisition_or_turn_annotations_refused(self):
        for group, key in [('video', 'original_cfr_verified')]+[('annotation', k) for k in ['sign_verified', 'complete_turns_verified', 'same_phase_verified', 'independent_event_errors']]:
            for value in [False, 1, None, 'true']:
                campaign = copy.deepcopy(self.campaign);campaign[group][key] = value
                with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                    REDUCER.reduce(campaign, self.csv)

    def test_bad_json_numbers(self):
        for key in ['frame_count', 'capture_fps_num', 'capture_fps_den']:
            for value in [0, -1, 1.5, True, '240', 2**53]:
                campaign = copy.deepcopy(self.campaign);campaign['video'][key] = value
                with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                    REDUCER.reduce(campaign, self.csv)
        for value in [True, '0.1', -1, float('nan'), float('inf')]:
            campaign = copy.deepcopy(self.campaign);campaign['video']['fps_relative_u'] = value
            with self.assertRaises(ValueError):REDUCER.reduce(campaign, self.csv)

    def test_duplicate_json_and_nonfinite_literals(self):
        for raw in [b'{"a":1,"a":2}', b'{"a":NaN}', b'{"a":Infinity}']:
            with self.assertRaises(ValueError):REDUCER.load_json(raw)

    def test_bad_csv_refused(self):
        variants = [self.csv.replace(b'frame_u', b'uncertainty'), self.csv.replace(b'one,720', b'entry,720'),
                    self.csv.replace(b'720', b'120'), self.csv.replace(b'1320', b'1500'),
                    self.csv.replace(b'720', b'720.5'), self.csv.replace(b'720', b'0720'),
                    self.csv.replace(b'0.5,1', b'0.5,1.5'), self.csv.replace(b'0.5,1', b'0.5,true'),
                    self.csv.replace(b'0.5,1', b'0.5,'), self.csv.replace(b'0.5,1', b'0.5,1,extra'),
                    self.csv.replace(b'0.5,1', b'-1,1'), self.csv.replace(b'0.5,1', b'nan,1'),
                    self.csv.replace(b'0.5,1', b'inf,1'), self.csv.replace(b'0.5,1', b'0.5,9007199254740992')]
        for value in variants:
            with self.subTest(csv=value), self.assertRaises(ValueError):REDUCER.reduce(self.campaign, value)

    def test_reversed_missing_zero_and_nonmonotone_intervals(self):
        for start, end in [('two', 'entry'), ('absent', 'two'), ('entry', 'entry')]:
            campaign = copy.deepcopy(self.campaign);campaign['intervals'][-1].update(start=start, end=end)
            with self.assertRaises(ValueError):REDUCER.reduce(campaign, self.csv)
        for csv in [self.csv.replace(b'0.5,2', b'0.5,0'), self.csv.replace(b'0.5,1', b'0.5,3'), self.csv.replace(b'0.5,1', b'0.5,0')]:
            with self.assertRaises(ValueError):REDUCER.reduce(self.campaign, csv)

    def test_derived_overflow_refused(self):
        self.campaign['video']['fps_relative_u'] = 1e308
        with self.assertRaises(ValueError):self.results()

    def test_measured_requires_clip_identity(self):
        self.campaign['evidence'] = 'measured'
        with self.assertRaisesRegex(ValueError, 'SHA-256'):self.results()
        self.campaign['video']['sha256'] = 'a'*64
        self.assertEqual(len(self.results()), 3)


class CommandLine(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.campaign = self.root/'campaign.json';self.campaign.write_bytes((HERE/'example.synthetic.json').read_bytes())
        self.events = self.root/'events.csv';self.events.write_bytes((HERE/'example.synthetic.csv').read_bytes())
        self.output = self.root/'report.json'

    def run_cli(self, *extra):
        return subprocess.run([sys.executable, str(HERE/'reduce.py'), str(self.campaign), str(self.events), *map(str, extra)], capture_output=True, text=True, timeout=10)

    def test_deterministic_stdout_and_hashes(self):
        first, second = self.run_cli(), self.run_cli()
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(first.stdout, second.stdout)
        report = json.loads(first.stdout)
        for key, path in [('campaign', self.campaign), ('events_csv', self.events), ('reducer', HERE/'reduce.py')]:
            self.assertEqual(report['input_sha256'][key], hashlib.sha256(path.read_bytes()).hexdigest())
        self.assertIsNone(report['input_sha256']['video'])
        result = self.run_cli('--output', self.output)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, '')
        self.assertEqual(self.output.read_text(), first.stdout)

    def test_verified_clip_required_and_mismatch_refused(self):
        video = self.root/'clip.bin';video.write_bytes(b'synthetic bytes for hash verification, not video evidence')
        campaign = json.loads(self.campaign.read_text());campaign['evidence'] = 'measured'
        campaign['video']['sha256'] = hashlib.sha256(video.read_bytes()).hexdigest()
        self.campaign.write_text(json.dumps(campaign))
        self.assertEqual(self.run_cli().returncode, 1)
        self.assertEqual(self.run_cli('--video', video).returncode, 0)
        video.write_bytes(b'changed');result = self.run_cli('--video', video)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, '')
        self.assertIn('SHA-256 mismatch', result.stderr)

    def test_failed_reduction_preserves_output(self):
        self.output.write_text('previous report')
        self.events.write_text('invalid csv')
        result = self.run_cli('--output', self.output)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, '')
        self.assertEqual(self.output.read_text(), 'previous report')
        self.assertEqual(set(p.name for p in self.root.iterdir()), {'campaign.json', 'events.csv', 'report.json'})

    def test_aliases_do_not_destroy_inputs(self):
        original = self.events.read_bytes()
        for mode in ['direct', 'symlink', 'hardlink']:
            alias = self.root/mode
            if mode == 'direct':alias = self.events
            elif mode == 'symlink':alias.symlink_to(self.events)
            else:os.link(self.events, alias)
            result = self.run_cli('--output', alias)
            self.assertEqual(result.returncode, 1, result.stderr)
            self.assertIn('aliases', result.stderr)
            self.assertEqual(self.events.read_bytes(), original)

    def test_invalid_json_has_no_report(self):
        self.campaign.write_text('{"format":"x","format":"y"}')
        result = self.run_cli()
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, '')
        self.assertIn('duplicate JSON key', result.stderr)


if __name__ == '__main__':
    unittest.main(verbosity=2)
