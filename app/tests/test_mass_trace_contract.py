"""Accepted mass/CG v14 and finite-liquid v15 mutations and projection."""
import csv
from pathlib import Path
import tempfile
import unittest

from mass_trace_contract import (
    COLUMNS, FORMAT, LIQUID_COLUMNS, LIQUID_FORMAT, LIQUID_SCHEMA, LIQUID_MODEL,
    LIQUID_FUEL_SCHEMA, LIQUID_LAYOUT, SAMPLE_TIMING, SCHEMA, project,
)


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
        self.assertEqual(table[0], ['tick', 't_s', 'alt_m'])
        self.assertEqual(len(table[1]), 3)
        return {'format': metadata['format'], 'columns': table[0]}

    def test_valid_v14_mass_suffix_is_checked_then_projected(self):
        original = self.path.read_bytes()
        handled, result = project(self.path, self.validate_base)
        self.assertTrue(handled)
        self.assertEqual(result['format'], FORMAT)
        self.assertEqual(result['mass_trace_schema'], SCHEMA)
        self.assertEqual(result['mass_base_trace_format'], 'openrc-trace v3')
        self.assertEqual(result['mass_samples'], 2)
        self.assertEqual(result['columns'], self.header)
        self.assertEqual(self.path.read_bytes(), original, 'projection leaves evidence unchanged')

    def test_valid_v15_liquid_and_mass_suffixes_are_checked_then_projected(self):
        self.metadata.update({
            'format': LIQUID_FORMAT,
            'liquid_fuel_trace_schema': LIQUID_SCHEMA,
            'liquid_fuel_model': LIQUID_MODEL,
            'liquid_fuel_schema': LIQUID_FUEL_SCHEMA,
            'fuel_consumption_law': 'gasoline_bsfc_v1',
            'fuel_store_id': 'main_tank',
            'fuel_capacity_kg': '1.0',
            'fuel_unusable_kg': '0.03',
            'fuel_state_index': '0',
            'fuel_start_fill_known': 'true',
            'fuel_start_fill': '0.6',
            'fuel_registry_sha256': 'a' * 64,
            'fuel_blend': 'gasoline_regular',
            'fuel_family': 'gasoline',
            'fuel_density_kg_m3': '800.0',
            'fuel_reserve_fraction': '0.12',
            'fuel_reserve_basis': 'estimated reserve',
            'fuel_reserve_estimated': 'true',
            'propulsion_model': 'propeller-shaft-coupled-rk4-v1',
            'continuous_layout': 'axial wash increment m/s, slipstream.pieces order, then propeller shaft rpm; RK4 coupled; '
                                 + LIQUID_LAYOUT,
            'recording_start_tick': '0',
            'recording_start_continuous': '[0.57, 1.0]',
        })
        self.header = ['tick', 't_s', 'alt_m', *LIQUID_COLUMNS, *COLUMNS]
        self.rows = [
            ['0', '0.000000000', '10', '0.6', '0.57', '0.6', '0.12', '1', '1.2', '0', '0', '0'],
            ['1', '0.004166667', '10.1', '0.59', '0.56', '0.59', '0.12', '1', '1.19', '0.01', '-0.02', '0.03'],
        ]
        self.write()
        original = self.path.read_bytes()
        handled, result = project(self.path, self.validate_base)
        self.assertTrue(handled)
        self.assertEqual(result['format'], LIQUID_FORMAT)
        self.assertEqual(result['liquid_fuel_trace_schema'], LIQUID_SCHEMA)
        self.assertEqual(result['fuel_samples'], 2)
        self.assertEqual(result['fuel_store_id'], 'main_tank')
        self.assertEqual(result['columns'], self.header)
        self.assertEqual(self.path.read_bytes(), original, 'projection leaves evidence unchanged')

    def test_v15_midflight_recording_keeps_reset_fill_separate_from_live_inventory(self):
        self.metadata.update({
            'format': LIQUID_FORMAT,
            'liquid_fuel_trace_schema': LIQUID_SCHEMA,
            'liquid_fuel_model': LIQUID_MODEL,
            'liquid_fuel_schema': LIQUID_FUEL_SCHEMA,
            'fuel_consumption_law': 'gasoline_bsfc_v1',
            'fuel_store_id': 'main_tank',
            'fuel_capacity_kg': '1.0',
            'fuel_unusable_kg': '0.03',
            'fuel_state_index': '0',
            'fuel_start_fill_known': 'true',
            'fuel_start_fill': '0.6',
            'fuel_registry_sha256': 'a' * 64,
            'fuel_blend': 'gasoline_regular',
            'fuel_family': 'gasoline',
            'fuel_density_kg_m3': '800.0',
            'fuel_reserve_fraction': '0.12',
            'fuel_reserve_basis': 'estimated reserve',
            'fuel_reserve_estimated': 'true',
            'propulsion_model': 'propeller-shaft-coupled-rk4-v1',
            'continuous_layout': 'axial wash increment m/s, slipstream.pieces order, then propeller shaft rpm; RK4 coupled; '
                                 + LIQUID_LAYOUT,
            'recording_start_tick': '12',
            'recording_start_continuous': '[0.55, 1.0]',
        })
        self.header = ['tick', 't_s', 'alt_m', *LIQUID_COLUMNS, *COLUMNS]
        self.rows = [['12', '0.050000000', '10', '0.58', '0.55', '0.58', '0.12', '1',
                      '1.19', '0.01', '-0.02', '0.03']]
        self.write()
        handled, result = project(self.path, self.validate_base)
        self.assertTrue(handled)
        self.assertEqual(result['fuel_samples'], 1)

        # At tick zero the same live inventory would contradict its declared launch fill.
        changed = dict(self.metadata, recording_start_tick='0')
        self.write(metadata=changed)
        with self.assertRaisesRegex(ValueError, 'start fill disagrees'):
            project(self.path, self.validate_base)

    def test_v15_refuses_inconsistent_liquid_identity_or_samples(self):
        self.metadata.update({
            'format': LIQUID_FORMAT,
            'liquid_fuel_trace_schema': LIQUID_SCHEMA,
            'liquid_fuel_model': LIQUID_MODEL,
            'liquid_fuel_schema': LIQUID_FUEL_SCHEMA,
            'fuel_consumption_law': 'gasoline_bsfc_v1',
            'fuel_store_id': 'main_tank',
            'fuel_capacity_kg': '1.0',
            'fuel_unusable_kg': '0.03',
            'fuel_state_index': '0',
            'fuel_start_fill_known': 'true',
            'fuel_start_fill': '0.6',
            'fuel_registry_sha256': 'a' * 64,
            'fuel_blend': 'gasoline_regular',
            'fuel_family': 'gasoline',
            'fuel_density_kg_m3': '800.0',
            'fuel_reserve_fraction': '0.12',
            'fuel_reserve_basis': 'estimated reserve',
            'fuel_reserve_estimated': 'true',
            'propulsion_model': 'propeller-shaft-coupled-rk4-v1',
            'continuous_layout': 'axial wash increment m/s, slipstream.pieces order, then propeller shaft rpm; RK4 coupled; '
                                 + LIQUID_LAYOUT,
            'recording_start_tick': '0',
            'recording_start_continuous': '[0.57, 1.0]',
        })
        header = ['tick', 't_s', 'alt_m', *LIQUID_COLUMNS, *COLUMNS]
        rows = [
            ['0', '0.000000000', '10', '0.6', '0.57', '0.6', '0.12', '1', '1.2', '0', '0', '0'],
            ['1', '0.004166667', '10.1', '0.59', '0.56', '0.59', '0.12', '1', '1.19', '0.01', '-0.02', '0.03'],
        ]
        self.write(header=header, rows=rows)
        cases = [
            ('missing trace schema', {k: v for k, v in self.metadata.items() if k != 'liquid_fuel_trace_schema'}, rows),
            ('wrong store model', dict(self.metadata, liquid_fuel_model='other'), rows),
            ('bad registry identity', dict(self.metadata, fuel_registry_sha256='x' * 64), rows),
            ('wrong continuous suffix', dict(self.metadata, recording_start_continuous='[0.5, 1.0]'), rows),
            ('inventory grew', self.metadata, [rows[0], [*rows[1][:3], '0.61', *rows[1][4:]]]),
            ('fill inconsistent', self.metadata, [rows[0], [*rows[1][:5], '0.5', *rows[1][6:]]]),
            ('source latched with empty store', self.metadata,
             [rows[0], [*rows[1][:3], '0.03', '0.0', '0.03', '0.12', '1', *rows[1][8:]]]),
        ]
        for label, metadata, candidate_rows in cases:
            with self.subTest(label=label):
                self.write(metadata=metadata, header=header, rows=candidate_rows)
                with self.assertRaises(ValueError):
                    project(self.path, self.validate_base)

    def test_non_v14_with_mass_claim_is_refused(self):
        changed = dict(self.metadata, format='openrc-trace v3')
        self.write(metadata=changed)
        with self.assertRaisesRegex(ValueError, 'requires openrc-trace v14 or v15'):
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
