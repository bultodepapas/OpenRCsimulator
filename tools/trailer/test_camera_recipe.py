#!/usr/bin/env python3
"""Camera-only exports must preserve plan identity and never encode flight state."""
import copy
import hashlib
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import shot_plan as sp


class CameraRecipeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.path = sp.REPO / 'docs/plans/trailer-v2/shot-plan-r6.json'
        cls.plan = sp.read_json(cls.path)
        cls.digest = hashlib.sha256(cls.path.read_bytes()).hexdigest()

    def test_real_plan_preserves_source_pins_and_timing(self):
        result = sp.validate(self.plan, sp.REPO)
        old = sp.read_json(sp.REPO / 'docs/plans/trailer-v2/shot-plan-r5.json')
        self.assertEqual(result['shots'], 62)
        self.assertEqual(result['duration_frames'], 9000)
        self.assertEqual(self.plan['source_files'], old['source_files'])
        self.assertEqual([(s['id'], s['in_frame'], s['out_frame'], s['source_class']) for s in self.plan['shots']],
                         [(s['id'], s['in_frame'], s['out_frame'], s['source_class']) for s in old['shots']])

    def test_generated_script_cards_cannot_silently_drift(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for name in [self.plan['storyboard_path'], self.plan['script_path']]:
                target = root/name; target.parent.mkdir(parents=True,exist_ok=True)
                target.write_bytes((sp.REPO/name).read_bytes())
            script = root/self.plan['script_path']
            text = script.read_text()
            # Change the first numeric eye in the generated cards, not the author prose.
            before, cards = text.split('<!-- BEGIN GENERATED SHOT CARDS -->',1)
            cards = cards.replace('FOV 38°', 'FOV 39°', 1)
            script.write_text(before+'<!-- BEGIN GENERATED SHOT CARDS -->'+cards)
            with self.assertRaisesRegex(sp.PlanError,'shot cards drifted'):
                sp.validate(self.plan,sp.REPO,root)

    def test_r6_script_path_cannot_be_omitted(self):
        for value in (None, ''):
            plan = copy.deepcopy(self.plan)
            if value is None:
                del plan['script_path']
            else:
                plan['script_path'] = value
            with self.subTest(value=value), self.assertRaisesRegex(sp.PlanError,'R6 script_path'):
                sp.validate(plan, sp.REPO)

    def test_recipe_snapshot_hash_cannot_reread_changed_file(self):
        with tempfile.TemporaryDirectory() as folder:
            file = Path(folder)/'plan.json'; file.write_bytes(self.path.read_bytes())
            plan, digest = sp.read_snapshot(file)
            file.write_text('{"changed":true}')
            recipe = sp.camera_recipe(plan,'R4-40',sp.REPO,digest)
            self.assertEqual(recipe['source_plan_sha256'],self.digest)
            self.assertNotEqual(recipe['source_plan_sha256'],hashlib.sha256(file.read_bytes()).hexdigest())

    def test_lake_recipe_tracks_actual_cg_not_nominal_trajectory(self):
        recipe = sp.camera_recipe(self.plan, 'R4-40', sp.REPO, self.digest)
        self.assertEqual(recipe, {'format':'openrc-trailer-camera', 'version':1, 'shot_id':'R4-40',
            'vehicle_id':'f4u-corsair-250', 'source_plan_sha256':self.digest,
            'target':'presented_cg', 'mode':'parallel_east', 'fov_deg':42,
            'north_m':145.0, 'down_m':-1.0, 'east_offset_m':-8.0})
        # An off-corridor aircraft must move the eye by the same E delta.
        self.assertEqual([e + recipe['east_offset_m'] for e in [55,124,193,125.5]], [47,116,185,117.5])
        self.assertNotIn('blocking', recipe)
        self.assertNotIn('spawn', recipe)
        self.assertNotIn('controls', recipe)

    def test_fixed_eye_and_actual_target_are_explicit(self):
        recipe = sp.camera_recipe(self.plan, 'R4-01', sp.REPO, self.digest)
        self.assertEqual(recipe['mode'], 'fixed_world')
        self.assertEqual(recipe['eye_ned_m'], [0,0,-1.6])
        self.assertEqual(recipe['target'], 'presented_cg')
        self.assertEqual(recipe['fov_deg'], 38)

    def test_no_conversion_of_unsupported_sources_or_cameras(self):
        for sid in ['R4-02','R4-20','R4-21','R4-28','R4-39','R4-42a','R4-43','R4-45']:
            with self.subTest(sid=sid), self.assertRaises(sp.PlanError):
                sp.camera_recipe(self.plan, sid, sp.REPO, self.digest)
        plan = copy.deepcopy(self.plan)
        sp.find_shot(plan,'R4-01')['camera']['mode'] = 'unimplemented_spline'
        with self.assertRaisesRegex(sp.PlanError, 'no capture recipe adapter'):
            sp.camera_recipe(plan,'R4-01',sp.REPO,self.digest)

    def test_rig_mark_drift_and_invalid_fov_fail_before_export(self):
        plan = copy.deepcopy(self.plan)
        sp.find_shot(plan,'R4-40')['camera']['points'][1]['position_m'][1] += 1
        with self.assertRaisesRegex(sp.PlanError, 'marks disagree'):
            sp.validate(plan, sp.REPO)
        for value in [True, float('nan'), 1, 121]:
            plan = copy.deepcopy(self.plan); sp.find_shot(plan,'R4-01')['camera']['fov_deg'] = value
            with self.subTest(value=value), self.assertRaisesRegex(sp.PlanError, 'FOV'):
                sp.camera_recipe(plan,'R4-01',sp.REPO,self.digest)
        with self.assertRaisesRegex(sp.PlanError, 'SHA-256'):
            sp.camera_recipe(self.plan,'R4-01',sp.REPO,'a'*40)

    def test_cli_recipe_is_bound_to_file_and_never_overwrites(self):
        with tempfile.TemporaryDirectory() as folder:
            out = Path(folder)/'camera.json'
            cmd=[sys.executable,str(Path(sp.__file__)),'--plan',str(self.path),'camera-recipe','R4-40','--out',str(out)]
            first=subprocess.run(cmd,capture_output=True,text=True)
            self.assertEqual(first.returncode,0,first.stderr)
            before=out.read_bytes()
            self.assertEqual(json.loads(before)['source_plan_sha256'],self.digest)
            second=subprocess.run(cmd,capture_output=True,text=True)
            self.assertEqual(second.returncode,2)
            self.assertEqual(out.read_bytes(),before)


if __name__ == '__main__':
    unittest.main()
