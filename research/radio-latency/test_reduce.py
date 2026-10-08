#!/usr/bin/env python3
"""F6b analytic, interval, provenance and CLI regression checks."""
import copy
import csv
import hashlib
import importlib.util
import io
import itertools
import json
import math
from pathlib import Path
import random
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('latency_reduce', HERE/'reduce.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


def fixture(count=20):
    condition = dict(id='60-on', build='synthetic-build', system='Synthetic OS/GPU/driver',
                     radio='Synthetic radio/firmware/USB/RF-off', display_refresh_hz=60,
                     vsync='on', frame_cap_fps=60, achieved_fps=60,
                     marker='axis 0, threshold 0, central patch region black to white',
                     notes='Synthetic fixture, not hardware acceptance')
    clip = dict(id='clip1', condition='60-on', source='Invented clip; no video exists',
                sha256='a'*64, frame_count=10000, timebase='constant-acquisition-cadence',
                acquisition_fps=dict(value=240, min=240, max=240, kind='synthetic', source='Exact synthetic cadence'),
                timing_notes='Synthetic instantaneous exposure; same scanline; no dropped frames')
    manifest = dict(format='openrc-latency-video v1', evidence='synthetic',
                    notes='Invented frame pairs', conditions=[condition], clips=[clip])
    rows = [dict(zip(m.COLUMNS, ['60-on', str(i+1), 'clip1', str(100+100*i),
                               str(112+100*i), '0', '0', ''])) for i in range(count)]
    return manifest, rows


def csv_text(rows):
    out = io.StringIO()
    writer = csv.DictWriter(out, fieldnames=m.COLUMNS, lineterminator='\n')
    writer.writeheader()
    writer.writerows(rows)
    return out.getvalue()


class Reduction(unittest.TestCase):
    def test_exact_240fps_and_one_frame_bound(self):
        d, rows = fixture()
        r = m.reduce(d, rows)
        trial = r['trials'][0]
        self.assertEqual(trial['latency_ms'], 50.)
        self.assertEqual(trial['frame_and_cadence_bounds_ms'], [11000/240, 13000/240])
        c = r['conditions'][0]
        self.assertEqual(c['statistics']['median_ms'], 50)
        self.assertEqual(c['statistics']['p95_nearest_rank_ms'], 50)
        self.assertTrue(c['minimum_20_trials_met'])
        self.assertFalse(r['video_hashes_verified'])

    def test_pick_radii_add_and_do_not_shrink_with_count(self):
        d, rows = fixture()
        for row in rows:
            row['stick_pick_radius'], row['patch_pick_radius'] = '2', '3'
        r = m.reduce(d, rows)
        bounds = [6000/240, 18000/240]
        self.assertEqual(r['trials'][0]['frame_and_cadence_bounds_ms'], bounds)
        self.assertEqual(r['conditions'][0]['statistics']['median_bounds_ms'], bounds)

    def test_fps_corners_for_positive_negative_and_zero(self):
        for delta in (-12, 0, 12):
            d, rows = fixture(1)
            rows[0]['patch_frame'] = str(100+delta)
            d['clips'][0]['acquisition_fps'].update(min=200, max=250)
            r = m.reduce(d, rows)
            expected = sorted(1000*x/f for x in (delta-1, delta+1) for f in (200, 250))
            self.assertEqual(r['trials'][0]['frame_and_cadence_bounds_ms'], [expected[0], expected[-1]])
            self.assertEqual(r['trials'][0]['latency_ms'], 1000*delta/240)
            if delta <= 0:
                self.assertTrue(any('negative latency' in w.lower() for w in r['conditions'][0]['warnings']))

    def test_nearest_rank_and_even_median(self):
        d, rows = fixture(20)
        for i, row in enumerate(rows):
            row['patch_frame'] = str(int(row['stick_frame'])+i+1)
        r = m.reduce(d, rows)['conditions'][0]['statistics']
        self.assertAlmostEqual(r['median_ms'], 10.5*1000/240)
        self.assertAlmostEqual(r['p95_nearest_rank_ms'], 19*1000/240)
        self.assertEqual(m.p95(list(range(1, 22))), 20)
        self.assertEqual(m.median([1, 9, 5]), 5)

    def test_order_statistic_bounds_under_reordering(self):
        # Overlapping intervals can reorder trials; sorting nominal ranks is wrong.
        d, rows = fixture(3)
        d['clips'][0]['acquisition_fps'].update(value=1000, min=1000, max=1000)
        for row, delta, radius in zip(rows, (10, 20, 30), (0, 15, 0)):
            row['patch_frame'] = str(int(row['stick_frame'])+delta)
            row['patch_pick_radius'] = str(radius)
        r = m.reduce(d, rows)
        trials = r['trials']
        for name, fn in (('median', m.median), ('p95_nearest_rank', m.p95)):
            bounds = r['conditions'][0]['statistics'][name+'_bounds_ms']
            values = [fn(corner) for corner in itertools.product(*(t['frame_and_cadence_bounds_ms'] for t in trials))]
            self.assertEqual(bounds, [min(values), max(values)])
        self.assertEqual(r['conditions'][0]['statistics']['median_bounds_ms'], [9, 31])

    def test_seeded_events_with_shared_cadence_stay_in_bounds(self):
        d, rows = fixture()
        d['clips'][0]['acquisition_fps'].update(min=239, max=241)
        for i, row in enumerate(rows):
            row['patch_frame'] = str(int(row['stick_frame'])+i)
            row['stick_pick_radius'] = str(i % 2)
        r = m.reduce(d, rows)
        rng = random.Random(6002)
        for _ in range(3000):
            fps = rng.uniform(239, 241)  # One cadence per clip, never per trial.
            latencies = []
            for row, trial in zip(rows, r['trials']):
                s, p, rs, rp = (int(row[k]) for k in m.COLUMNS[3:7])
                observed = 1000*(rng.uniform(p-1-rp, p+rp)-rng.uniform(s-1-rs, s+rs))/fps
                lo, hi = trial['frame_and_cadence_bounds_ms']
                self.assertLessEqual(lo, observed)
                self.assertLessEqual(observed, hi)
                latencies.append(observed)
            stats = r['conditions'][0]['statistics']
            for name, fn in (('median', m.median), ('p95_nearest_rank', m.p95)):
                lo, hi = stats[name+'_bounds_ms']
                self.assertLessEqual(lo, fn(latencies))
                self.assertLessEqual(fn(latencies), hi)

    def test_exclusions_preserved_and_not_counted(self):
        d, rows = fixture()
        rows[0]['exclusion_reason'] = 'gray patch; paused'
        for k in m.COLUMNS[3:7]:
            rows[0][k] = ''
        r = m.reduce(d, rows)
        self.assertEqual(r['trials'][0]['annotation'], rows[0])
        self.assertTrue(r['trials'][0]['excluded'])
        c = r['conditions'][0]
        self.assertEqual((c['trial_count'], c['usable_count'], c['excluded_count']), (20, 19, 1))
        self.assertFalse(c['minimum_20_trials_met'])
        self.assertTrue(c['warnings'])

    def test_all_excluded_and_empty_conditions_remain_visible(self):
        d, rows = fixture(1)
        rows[0]['exclusion_reason'] = 'occluded'
        d['conditions'].append(dict(d['conditions'][0], id='unused'))
        r = m.reduce(d, rows)
        for c in r['conditions']:
            self.assertIsNone(c['statistics'])
            self.assertFalse(c['minimum_20_trials_met'])
        self.assertEqual(r['conditions'][1]['trial_count'], 0)

    def test_conditions_remain_separate(self):
        d, rows = fixture()
        d['conditions'].append(dict(d['conditions'][0], id='144-off', display_refresh_hz=144, vsync='off'))
        d['clips'].append(dict(d['clips'][0], id='clip2', condition='144-off', sha256='b'*64))
        rows.append(dict(rows[0], condition='144-off', clip='clip2', patch_frame='106'))
        r = m.reduce(d, rows)
        self.assertEqual([c['usable_count'] for c in r['conditions']], [20, 1])
        self.assertEqual([c['statistics']['median_ms'] for c in r['conditions']], [50, 25])

    def test_annotation_order_does_not_change_statistics(self):
        d, rows = fixture()
        a = m.reduce(d, rows)
        random.Random(1).shuffle(rows)
        self.assertEqual(a['conditions'], m.reduce(d, rows)['conditions'])

    def test_csv_round_trip_and_strict_header_width(self):
        _, rows = fixture()
        rows[0]['exclusion_reason'] = 'obscured, see notes\nsecond line'
        self.assertEqual(m.read_trials(csv_text(rows)), rows)
        for bad in ('', 'condition,condition\nx,y\n', csv_text(rows)+',extra\n',
                    ','.join(m.COLUMNS)+'\na,b,c\n'):
            with self.assertRaises(ValueError):
                m.read_trials(bad)

    def test_invalid_frame_values_and_clip_edges(self):
        for key in m.COLUMNS[3:7]:
            for value in ('', '-1', '1.0', 'nan', 'true', ' 1', '9007199254740992'):
                d, rows = fixture(1); rows[0][key] = value
                with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                    m.reduce(d, rows)
        for key, value in (('stick_frame', '0'), ('patch_frame', '10000'), ('stick_pick_radius', '100')):
            d, rows = fixture(1); rows[0][key] = value
            with self.assertRaises(ValueError):
                m.reduce(d, rows)

    def test_duplicate_trials_events_and_clip_aliases(self):
        for mode in ('trial', 'event', 'patch_event', 'hash', 'clip', 'condition'):
            d, rows = fixture()
            if mode == 'trial': rows[1]['trial'] = rows[0]['trial']
            if mode == 'event': rows[1]['stick_frame'] = rows[0]['stick_frame']
            if mode == 'patch_event': rows[1]['patch_frame'] = rows[0]['patch_frame']
            if mode == 'hash': d['clips'].append(dict(d['clips'][0], id='alias'))
            if mode == 'clip': d['clips'].append(dict(d['clips'][0], sha256='b'*64))
            if mode == 'condition': d['conditions'].append(d['conditions'][0])
            with self.subTest(mode=mode), self.assertRaises(ValueError):
                m.reduce(d, rows)

    def test_unknown_or_mismatched_references(self):
        for target, key in (('row', 'condition'), ('row', 'clip'), ('clip', 'condition')):
            d, rows = fixture()
            (rows[0] if target == 'row' else d['clips'][0])[key] = 'missing'
            with self.assertRaises(ValueError): m.reduce(d, rows)
        d, rows = fixture()
        d['conditions'].append(dict(d['conditions'][0], id='other'))
        rows[0]['condition'] = 'other'
        with self.assertRaises(ValueError): m.reduce(d, rows)

    def test_acquisition_rate_and_evidence_refusals(self):
        for key in ('value', 'min', 'max'):
            for value in (0, -1, True, '240', float('nan'), float('inf')):
                d, rows = fixture(); d['clips'][0]['acquisition_fps'][key] = value
                with self.subTest(key=key, value=value), self.assertRaises(ValueError): m.reduce(d, rows)
        for change in ('bounds', 'playback', 'evidence', 'hash', 'frame_count'):
            d, rows = fixture()
            if change == 'bounds': d['clips'][0]['acquisition_fps']['min'] = 241
            if change == 'playback': d['clips'][0]['timebase'] = 'playback'
            if change == 'evidence': d['evidence'] = 'measured'
            if change == 'hash': d['clips'][0]['sha256'] = 'xyz'
            if change == 'frame_count': d['clips'][0]['frame_count'] = True
            with self.subTest(change=change), self.assertRaises(ValueError): m.reduce(d, rows)
        d, rows = fixture(); d['evidence'] = 'measured'; d['clips'][0]['acquisition_fps']['kind'] = 'measured'
        self.assertEqual(m.reduce(d, rows)['input']['evidence'], 'measured')

    def test_empty_and_malformed_contracts(self):
        for bad in (None, [], {}, 'x'):
            with self.assertRaises(ValueError): m.reduce(bad, [])
        d, rows = fixture()
        for bad in ([], None, [dict(rows[0], extra='x')]):
            with self.assertRaises(ValueError): m.reduce(d, bad)
        for key in ('conditions', 'clips'):
            bad = copy.deepcopy(d); bad[key] = []
            with self.assertRaises(ValueError): m.reduce(bad, rows)
        for value in (' ', None):
            bad = copy.deepcopy(rows); bad[0]['exclusion_reason'] = value
            with self.assertRaises(ValueError): m.reduce(d, bad)

    def test_json_duplicate_and_nonfinite_refused(self):
        for raw in ('{"x":1,"x":2}', '{"x":NaN}', '{"x":Infinity}'):
            with self.assertRaises(ValueError): m.load(raw)

    def test_cli_deterministic_exact_hashes_and_clean_failure(self):
        d, rows = fixture()
        with tempfile.TemporaryDirectory() as tmp:
            manifest, trials = Path(tmp)/'manifest.json', Path(tmp)/'trials.csv'
            manifest.write_text(json.dumps(d)); trials.write_text(csv_text(rows))
            cmd = [sys.executable, str(HERE/'reduce.py'), str(manifest), str(trials)]
            first = subprocess.run(cmd, capture_output=True, check=True)
            second = subprocess.run(cmd, capture_output=True, check=True)
            self.assertEqual(first.stdout, second.stdout)
            r = json.loads(first.stdout)
            for key, path in (('manifest', manifest), ('trials_csv', trials), ('reducer', HERE/'reduce.py')):
                self.assertEqual(r['sha256'][key], hashlib.sha256(path.read_bytes()).hexdigest())
            self.assertEqual(r['input'], d)
            for bad in ('', 'bad-header\n', csv_text([dict(rows[0], stick_frame='-1')])):
                trials.write_text(bad)
                p = subprocess.run(cmd, capture_output=True)
                self.assertEqual(p.returncode, 1)
                self.assertEqual(p.stdout, b'')
                self.assertIn(b'Latency reduction failed:', p.stderr)
            trials.unlink()
            self.assertEqual(subprocess.run(cmd, capture_output=True).returncode, 1)


if __name__ == '__main__':
    unittest.main(verbosity=2)
