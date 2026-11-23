#!/usr/bin/env python3
"""R7's editorial/source contracts; no flight or visual acceptance is implied."""
import copy
import hashlib
import json
import tempfile
import unittest
from collections import Counter
from pathlib import Path

import shot_plan as sp
import title_plan as titles


class DirectionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.plan, cls.digest = sp.read_snapshot(sp.DEFAULT_PLAN)
        cls.legacy = sp.read_json(sp.REPO / 'tools/trailer/preproduction/shot-plan-r6.json')

    def reject(self, mutate, message):
        candidate = copy.deepcopy(self.plan)
        mutate(candidate)
        with self.assertRaisesRegex(sp.PlanError, message):
            sp.validate(candidate, sp.REPO, check_script=False)

    def test_reorder_preserves_each_cut_and_total_source_allocation(self):
        result = sp.validate(self.plan, sp.REPO)
        self.assertEqual((result['shots'], result['duration_frames'], result['source_files_verified']), (62, 9000, 40))
        signature = lambda p: {s['id']:(s['out_frame']-s['in_frame'],s['source_class'],s['cast']) for s in p['shots']}
        self.assertEqual(signature(self.plan), signature(self.legacy))
        totals = Counter()
        for s in self.plan['shots']: totals[s['source_class']] += s['out_frame']-s['in_frame']
        self.assertEqual(totals, {'G':6720,'U':900,'P':1080,'E':300})
        self.assertEqual([s['id'] for s in self.plan['shots'][13:16]], ['R4-20','R4-21','R4-14'])
        self.assertEqual([s['id'] for s in self.plan['shots'][-3:]], ['R4-43','R4-31','R4-45'])
        self.assertEqual(sp.find_shot(self.plan,'R4-39')['in_frame'], 6300)
        self.assertEqual(sp.find_shot(self.plan,'R4-40')['out_frame'], 7260)
        self.assertEqual(sp.find_shot(self.plan,'R4-44')['out_frame'], 7560)

    def test_handoffs_and_complete_chapters_cannot_drift(self):
        self.reject(lambda p: sp.find_shot(p,'R4-40').update(cut_to='R4-41'), 'cut_to')
        self.reject(lambda p: p['chapters'][0].update(out_frame=1079), 'complete cuts')
        self.reject(lambda p: p['chapters'][1].update(id='hook'), 'unique')
        self.reject(lambda p: p['chapters'].pop(), 'cover the master')
        self.reject(lambda p: p['chapters'].__setitem__(0, None), 'expected object')

    def test_orbit_lake_environment_and_preview_trial_identity_are_bound(self):
        self.reject(lambda p: sp.find_shot(p,'R4-40').update(environment='sunset_calm'), 'same|share')
        self.reject(lambda p: sp.find_shot(p,'R4-43').update(screen_direction='screen_left'), 'direction')
        wrong_cast = sp.find_shot(self.plan,'R4-42q')['cast']
        self.reject(lambda p: sp.find_shot(p,'R4-43').update(cast=wrong_cast), 'identity')

    def test_named_time_and_exact_arguments_come_from_the_pinned_source(self):
        env = lambda p: p['environments']['morning_calm']
        self.assertEqual(env(self.plan)['field_world_args'], ['--time=','--time_of_day=morning','--time_scale=0','--sky=clear'])
        self.reject(lambda p: env(p).update(field_world_preset='day'), 'unsupported')
        self.reject(lambda p: env(p).update(field_world_preset={}), 'nonempty string')
        self.reject(lambda p: env(p).update(time_of_day='golden_hour'), 'description')
        self.reject(lambda p: env(p).update(time_scale=20), 'frozen')
        self.reject(lambda p: env(p).update(time_scale=False), 'frozen')
        self.reject(lambda p: env(p).update(field_world_args=['--time-of-day=morning']), 'arguments')
        self.reject(lambda p: env(p).update(sky='unimplemented_sky'), 'unsupported')
        self.reject(lambda p: env(p).update(wind_mps=True), 'invalid')

    def test_water_plane_is_bound_to_lake_source_not_arbitrary_aim_height(self):
        lake = sp.find_shot(self.plan,'R4-40')
        recipe = sp.camera_recipe(self.plan,'R4-40',sp.REPO,self.digest)
        self.assertEqual(recipe['target'], 'presented_cg_water_plane')
        self.assertEqual(recipe['water_down_m'], .45)
        self.assertEqual(recipe['fov_deg'], 34)
        self.assertEqual((recipe['north_m'],recipe['down_m'],recipe['east_offset_m']), (145,-1,-8))
        self.assertEqual(recipe['source_plan_sha256'], self.digest)
        self.assertNotIn('spawn', recipe)
        for value in (4.5, True, None, float('nan')):
            self.reject(lambda p: sp.find_shot(p,'R4-40')['camera'].update(water_down_m=value), 'water_down|non-finite')
        self.reject(lambda p: sp.find_shot(p,'R4-40')['camera'].update(target='presented_cg'), 'requires a water-plane')
        self.assertEqual(lake['blocking']['points'][0]['position_m'], [128,55,-2.55])

    def test_readability_cameras_export_following_eyes_without_flight_commands(self):
        expected={'R4-01':(6,-6.5,-6,32),'R4-03':(10,-2.5,-6,34)}
        for sid, values in expected.items():
            with self.subTest(shot=sid):
                recipe=sp.camera_recipe(self.plan,sid,sp.REPO,self.digest)
                self.assertEqual(recipe['mode'],'parallel_east')
                self.assertEqual(recipe['target'],'presented_cg')
                self.assertNotIn('water_down_m',recipe)
                self.assertEqual(tuple(recipe[k] for k in ['north_m','down_m','east_offset_m','fov_deg']),values)
                committed=sp.read_json(sp.REPO/f'tools/trailer/preproduction/recipes/{sid.lower()}-camera.json')
                self.assertEqual(committed,recipe)

    def test_scaled_trial_cannot_be_exported_as_an_admitted_stock_capture(self):
        for sid in ('R4-36','R4-37'):
            with self.subTest(shot=sid),self.assertRaisesRegex(sp.PlanError,'Workshop trial'):
                sp.camera_recipe(self.plan,sid,sp.REPO,self.digest)
        tiny=sp.find_shot(self.plan,'R4-37')
        self.assertEqual(tiny['execution']['status'],'camera_trial_composition_pending')
        self.assertEqual(tiny['camera']['rig'],{'north_m':28.5,'down_m':-1.2,'east_offset_m':-1})

    def test_generated_storyboard_and_diagrams_match_the_numeric_plan(self):
        folder=sp.REPO/'tools/trailer/preproduction'
        story=(folder/'storyboard-r7.md').read_text()
        cut_table=story.split('<!-- BEGIN GENERATED CUT TABLE -->')[1].split('<!-- END GENERATED CUT TABLE -->')[0].strip()
        self.assertEqual(cut_table,sp.render_storyboard_table(self.plan).strip())
        self.assertEqual((folder/'diagrams/r7-edit-map.svg').read_text(),sp.timeline_svg(self.plan))
        self.assertEqual((folder/'diagrams/r7-lake-blocking.svg').read_text(),sp.map_svg(self.plan,sp.find_shot(self.plan,'R4-40'),sp.REPO))

    def test_legacy_r6_remains_a_valid_separately_named_plan(self):
        self.assertTrue(sp.validate(self.legacy,sp.REPO)['ok'])
        old=sp.camera_recipe(self.legacy,'R4-40',sp.REPO,'a'*64)
        self.assertEqual((old['target'],old['fov_deg']),('presented_cg',42))
        self.assertNotIn('water_down_m',old)


class CurrentTitleTests(unittest.TestCase):
    def test_exact_new_windows_and_larger_labels(self):
        plan=titles.load(titles.DEFAULT_PLAN,shot_plan=sp.DEFAULT_PLAN)
        cues={c['id']:c for c in plan['cues']}
        self.assertEqual(len(cues),23)
        for key, interval in {'hx700':(2340,2580),'xcell':(2580,2820),'liveries':(6300,6900),
                              'hangar':(7560,7680),'phoenix':(7680,7980),'clearview':(7980,8280),
                              'trial':(8280,8460),'lumber':(8460,8700)}.items():
            self.assertEqual((cues[key]['in_frame'],cues[key]['out_frame']),interval)
        self.assertEqual(cues['lumber']['lines'],['TURBO LUMBER'])
        self.assertTrue(all(c['out_frame']<=6900 or c['in_frame']>=7260 for c in cues.values()))
        self.assertTrue(all(c['size']==52 for c in cues.values() if c['role']=='label'))
        self.assertEqual(sum(n for _,n in titles.STUDY_WINDOWS),1365)
        self.assertFalse(plan['metadata']['publication_ready'])

    def test_mixed_revisions_are_rejected_both_ways(self):
        folder=sp.REPO/'tools/trailer/preproduction'
        for title,shot in [('title-plan-r7.json','shot-plan-r6.json'),('title-plan-r6.json','shot-plan-r7.json')]:
            with self.subTest(title=title),self.assertRaisesRegex(ValueError,'revisions'):
                titles.load(folder/title,shot_plan=folder/shot)

    def test_missing_night_identity_or_old_label_size_is_rejected(self):
        source=json.loads(titles.DEFAULT_PLAN.read_text())
        for mutation in ('remove-night','small-label','old-hangar-window'):
            plan=copy.deepcopy(source)
            if mutation=='remove-night':plan['cues']=[c for c in plan['cues'] if c['id']!='lumber']
            elif mutation=='small-label':next(c for c in plan['cues'] if c['id']=='lumber')['size']=38
            else:next(c for c in plan['cues'] if c['id']=='hangar')['in_frame']=7500
            with tempfile.TemporaryDirectory() as tmp:
                path=Path(tmp)/'titles.json';path.write_text(json.dumps(plan))
                with self.subTest(mutation=mutation),self.assertRaises(ValueError):titles.load(path)

    def test_long_trial_qualification_fits_and_covers_the_full_trial(self):
        for basis in ('estimated','donor'):
            plan=titles.load(titles.DEFAULT_PLAN,publication=True,trial_basis=basis,shot_plan=sp.DEFAULT_PLAN)
            cue=next(c for c in plan['cues'] if c['id']=='trial')
            self.assertEqual((cue['in_frame'],cue['out_frame']),(8280,8460))
            self.assertIn(basis.upper()+' PHYSICS',cue['lines'][0])
            self.assertFalse(plan['metadata']['publication_ready'])


if __name__=='__main__':unittest.main()
