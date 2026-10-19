"""Mass/CG trace v14 mutations and base-family projection."""
import csv
from pathlib import Path
import tempfile
import unittest

from mass_trace_contract import COLUMNS, FORMAT, SAMPLE_TIMING, SCHEMA, project


class MassTraceContract(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix='openrc-mass-contract-test-')
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / 'mass.csv'
        self.metadata = {
            'format': FORMAT,
            'mass_trace_schema': SCHEMA,
            'mass_base_trace_format': 'openrc-trace v3',
            'mass_sample_timing': SAMPLE_TIMING,
            'dt_s': '0.004166666666666667',
        }
        self.header = ['tick', 't_s', 'alt_m', *COLUMNS]
        self.rows = [
            ['0', '0.000000000', '10', '1.2', '0', '0', '0'],
            ['1', '0.004166667', '10.1', '1.19', '0.01', '-0.02', '0.03'],
        ]
        self.write()

    def write(self, metadata=None, header=None, rows=None):
        metadata = self.metadata if metadata is None else metadata
        header = self.header if header is None else header
        rows = self.rows if rows is None else rows
        with self.path.open('w', encoding='utf-8', newline='') as stream:
            for key, value in metadata.items():
                stream.write(f'# {key}: {value}\n')
            writer = csv.writer(stream, lineterminator='\n')
            writer.writerow(header)
            writer.writerows(rows)

    def validate_base(self, path):
        lines = path.read_text(encoding='utf-8').splitlines()
        metadata = dict(line[2:].split(': ', 1) for line in lines if line.startswith('# '))
        self.assertEqual(metadata['format'], 'openrc-trace v3')
        self.assertNotIn('mass_trace_schema', metadata)
        table = list(csv.reader(line for line in lines if not line.startswith('#')))
        self.assertEqual(table[0], self.header[:-len(COLUMNS)])
        self.assertEqual(len(table[1]), len(self.header) - len(COLUMNS))
        return {'format': metadata['format'], 'columns': table[0]}

    def test_valid_v14_mass_suffix_is_checked_then_projected(self):
        original = self.path.read_bytes()
        handled, result = project(self.path, self.validate_base)
        self.assertTrue(handled)
        self.assertEqual(result['format'], FORMAT)
        self.assertEqual(result['mass_trace_schema'], SCHEMA)
        self.assertEqual(result['mass_samples'], 2)
        self.assertEqual(result['columns'], self.header)
        self.assertEqual(self.path.read_bytes(), original, 'projection leaves evidence unchanged')

    def test_non_v14_with_mass_claim_is_refused(self):
        changed = dict(self.metadata, format='openrc-trace v3')
        self.write(metadata=changed)
        with self.assertRaisesRegex(ValueError, 'requires openrc-trace v14'):
            project(self.path, self.validate_base)

    def test_missing_or_unknown_mass_identity_is_refused(self):
        for key, value in [('mass_trace_schema', None), ('mass_trace_schema', 'openrc-mass-sample v2'),
                           ('mass_sample_timing', None), ('mass_base_trace_format', 'openrc-trace v14')]:
            with self.subTest(key=key, value=value):
                changed = dict(self.metadata)
                if value is None:
                    changed.pop(key)
                else:
                    changed[key] = value
                self.write(metadata=changed)
                with self.assertRaises(ValueError):
                    project(self.path, self.validate_base)

    def test_suffix_order_width_and_values_are_gated(self):
        cases = [
            ('displaced column', self.header[:-2] + [self.header[-1], self.header[-2]], self.rows),
            ('duplicate column', self.header[:-1] + [self.header[-2]], self.rows),
            ('bad mass', self.header, [self.rows[0], [*self.rows[1][:-4], '-1', *self.rows[1][-3:]]]),
            ('nan cg', self.header, [self.rows[0], [*self.rows[1][:-1], 'nan']]),
            ('wrong time', self.header, [self.rows[0], [self.rows[1][0], '0.5', *self.rows[1][2:]]]),
            ('skipped tick', self.header, [self.rows[0], ['2', '0.008333333', *self.rows[1][2:]]]),
        ]
        for label, header, rows in cases:
            with self.subTest(label=label):
                self.write(header=header, rows=rows)
                with self.assertRaises(ValueError):
                    project(self.path, self.validate_base)


if __name__ == '__main__':
    unittest.main()
