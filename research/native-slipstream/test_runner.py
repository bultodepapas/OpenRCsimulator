#!/usr/bin/env python3
"""Prove that Gate P's cross-language flight comparator fails closed."""
import array
import importlib.util
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('gate_p_run', Path(__file__).with_name('run.py'))
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class FlightComparison(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.left = Path(self.temp.name) / 'oracle'
        self.right = Path(self.temp.name) / 'native'
        self.left.mkdir()
        self.right.mkdir()
        self.policy = {'components': {key: {'absolute': value} for key, value in {
            'position': 1e-6, 'velocity': 1e-6, 'attitude': 1e-9, 'rate': 1e-6,
            'rpm': 1e-5, 'servo': 1e-9}.items()}}
        self.record = {'fingerprint_ticks': 1, 'aircraft': []}
        for i in range(4):
            self.record['aircraft'].append({'id': str(i), 'regimes': {name: {
                'fingerprint': {'ticks': 1, 'fault': '', 'sha256': 'diagnostic-only'},
                'timing': {'fault': ''}}
                for name in ['trim', 'stall', 'spin', 'ground']}})
        for i in range(16):
            values = array.array('d', [0.0] * 38)
            values[18] = 0
            values[37] = 1
            for folder in [self.left, self.right]:
                (folder / f'{i:02d}.bin').write_bytes(values.tobytes())

    def compare(self):
        return runner.compare_flights(self.record, self.record, self.left, self.right, self.policy)

    def test_identical_passes(self):
        self.assertTrue(all(row['ok'] for row in self.compare()))

    def test_component_nan_discrete_and_clock_mutations_fail(self):
        for column, value in [(0, 2e-6), (3, 2e-6), (6, 2e-9), (10, 2e-6),
                              (13, 2e-5), (14, 2e-9), (0, float('nan')),
                              (0, float('inf')), (17, 1), (18, 2)]:
            with self.subTest(column=column, value=value):
                data = array.array('d')
                data.frombytes((self.left/'00.bin').read_bytes())
                data[19+column] = value
                (self.right/'00.bin').write_bytes(data.tobytes())
                self.assertFalse(self.compare()[0]['ok'])

    def test_truncated_samples_refused(self):
        (self.right/'00.bin').write_bytes(array.array('d', [0]).tobytes())
        with self.assertRaises(AssertionError):
            self.compare()


if __name__ == '__main__':
    unittest.main()
