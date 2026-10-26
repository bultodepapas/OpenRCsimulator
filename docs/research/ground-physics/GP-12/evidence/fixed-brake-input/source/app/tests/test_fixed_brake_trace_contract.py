import tempfile
import unittest
from pathlib import Path
from fixed_brake_trace_contract import inspect

ROOT = Path(__file__).resolve().parent / 'fixtures'


class FixedBrakeTraceRoles(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.path = Path(self.temporary.name) / 'hostile.csv'
        self.text = (ROOT / 'fixed_brake_trace_stik.csv').read_text(encoding='utf-8')

    def tearDown(self):
        self.temporary.cleanup()

    def reject(self, old, new):
        self.assertIn(old, self.text)
        self.path.write_text(self.text.replace(old, new), encoding='utf-8')
        with self.assertRaises(ValueError):
            inspect(self.path)

    def test_actual_stik_and_fixed_flap_owner_outputs(self):
        for suffix, width in [('stik', 5), ('flaps', 6)]:
            result = inspect(ROOT / f'fixed_brake_trace_{suffix}.csv')
            self.assertEqual(len(result['input_names']), width)
            self.assertFalse(result['physics_validation_available'])
            self.assertEqual(result['rows'], 1)

    def test_unknown_base(self):
        self.reject('# fixed_brake_base_trace_format: openrc-trace v14', '# fixed_brake_base_trace_format: openrc-trace v999')

    def test_gear_base(self):
        self.reject('# fixed_brake_base_trace_format: openrc-trace v14', '# fixed_brake_base_trace_format: openrc-trace v10')

    def test_wrong_index(self):
        self.reject('# wheel_brake_input_index: 4', '# wheel_brake_input_index: 5')

    def test_fractional_index(self):
        self.reject('# wheel_brake_input_index: 4', '# wheel_brake_input_index: 4.0')

    def test_mixed_gear_claim(self):
        self.reject('# format: openrc-trace v17', '# format: openrc-trace v17\n# gear_law: retractable-point-gear-v1')

    def test_ambiguous_role(self):
        self.reject('"wheel_brake"]', '"flaps"]')

    def test_duplicate_role(self):
        self.reject('"wheel_brake"]', '"wheel_brake", "wheel_brake"]')

    def test_missing_identity(self):
        self.reject('fixed-gear-shared-wheel-brake-input-v1', 'unknown')

    def test_duplicate_metadata(self):
        self.reject('# format: openrc-trace v17', '# format: openrc-trace v17\n# format: openrc-trace v17')

    def test_brake_column_missing(self):
        self.reject('cmd_wheel_brake', 'cmd_auxiliary')

    def test_invalid_sample(self):
        for value in ('nan', 'inf', '-0.1', '1.1'):
            with self.subTest(value=value):
                self.path.write_text(self.text.replace('0.700000000', value), encoding='utf-8')
                with self.assertRaises(ValueError): inspect(self.path)

    def test_old_version_cannot_hide_new_role(self):
        self.reject('# format: openrc-trace v17', '# format: openrc-trace v14')


if __name__ == '__main__':
    unittest.main()
