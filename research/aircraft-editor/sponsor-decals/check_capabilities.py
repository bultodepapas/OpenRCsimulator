#!/usr/bin/env python3
"""Focused study-capability checks with synthetic policies; no brand admission."""
import copy
import unittest
from unittest.mock import patch

import build_catalog
import validate_pack


class CapabilityChecks(unittest.TestCase):
    def setUp(self):
        self.catalog = build_catalog.read_catalog()
        self.stack = validate_pack.read_json((build_catalog.HERE / 'examples/layered-stack.json').read_bytes())
        self.stack['layers'] = [self.stack['layers'][0]]
        self.layer = self.stack['layers'][0]
        self.asset = next(a for a in self.catalog['entries'] if a['id'] == self.layer['asset_id'])
        self.layer.update(rotation_deg=0, flip_u=False, flip_v=False)

    def validate(self):
        with patch.object(validate_pack, 'read_catalog', return_value=self.catalog):
            validate_pack.validate_stack(self.stack)

    def test_restricted_default_pose_is_admitted(self):
        self.asset['study_capabilities'] = {k: False for k in build_catalog.STUDY_CAPABILITIES}
        self.validate()  # Local proposal validation is not an export operation.

    def test_denied_rotation(self):
        self.asset['study_capabilities']['rotate'] = False
        self.layer['rotation_deg'] = 15
        with self.assertRaisesRegex(ValueError, '^Rotation is unavailable'):
            self.validate()

    def test_each_mirror_axis_is_independent(self):
        for flag, field, other in [('flip_x', 'flip_u', 'flip_v'), ('flip_y', 'flip_v', 'flip_u')]:
            with self.subTest(flag=flag):
                self.asset['study_capabilities'] = {k: True for k in build_catalog.STUDY_CAPABILITIES}
                self.asset['study_capabilities'][flag] = False
                self.layer.update(flip_u=False, flip_v=False)
                self.layer[other] = True
                self.validate()
                self.layer[field] = True
                with self.assertRaisesRegex(ValueError, 'mirroring is unavailable'):
                    self.validate()

    def test_repeated_asset_cannot_hide_behind_new_instance_id(self):
        self.asset['study_capabilities']['repeat'] = False
        duplicate = copy.deepcopy(self.layer)
        duplicate.update(id='second-distinct-instance', visible=False)
        self.stack['layers'].append(duplicate)
        with self.assertRaisesRegex(ValueError, '^Repeated placement is unavailable'):
            self.validate()

    def test_export_does_not_disable_local_proposal_validation(self):
        self.asset['study_capabilities']['export'] = False
        self.validate()  # Browser export has its own full-board capability check.

    def test_bad_policy_is_rejected_by_builder_and_validator(self):
        good = copy.deepcopy(self.asset['study_capabilities'])
        for bad in [None, [], {}, {**good, 'rotate': 1}, {**good, 'repeat': 'true'}, {**good, 'recolor': True}]:
            with self.subTest(policy=bad):
                self.asset['study_capabilities'] = bad
                with patch.object(build_catalog, 'read_catalog', return_value=self.catalog):
                    with self.assertRaisesRegex(ValueError, '^invalid study capabilities'):
                        build_catalog.build_outputs()
                with self.assertRaisesRegex(ValueError, '^invalid study capabilities'):
                    self.validate()

    def test_missing_policy_is_not_a_legacy_grant(self):
        del self.asset['study_capabilities']
        with self.assertRaisesRegex(ValueError, '^invalid study capabilities'):
            self.validate()

    def test_source_catalog_keeps_all_external_references_disabled(self):
        fixtures = {'openrc', 'test-race-stripes', 'test-checker-band', 'test-direction-arrow'}
        external = [a for a in self.catalog['entries'] if a['id'] not in fixtures]
        self.assertEqual(len(external), 17)
        for asset in external:
            self.assertIs(asset['demo_placement'], False)
            self.assertTrue(all(v is False for v in build_catalog.read_study_capabilities(asset).values()))

    def test_numeric_underflow_cannot_silently_allow_zero_rotation(self):
        for raw in [b'{"rotation_deg":1e-400}', b'{"rotation_deg":-0.0001e-400}']:
            with self.assertRaisesRegex(ValueError, 'underflows'):
                validate_pack.read_json(raw)
        self.assertEqual(validate_pack.read_json(b'{"rotation_deg":0e-400}'), {'rotation_deg': 0})


if __name__ == '__main__':
    unittest.main(verbosity=2)
