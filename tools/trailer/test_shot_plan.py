#!/usr/bin/env python3
"""Independent examples for offline shot-plan validation and geometry."""
import copy
import hashlib
import json
import math
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import shot_plan as sp


class GeometryTests(unittest.TestCase):
    def test_ned_render_axes_and_surface_is_not_converted(self):
        shot = {'blocking': {'space': 'NED', 'points': [{'frame': 0, 'position_m': [4, 5, -6]}]},
                'camera': {'space': 'NED', 'points': [{'frame': 0, 'position_m': [-3, -2, 7]}]}}
        converted = sp.enrich_shot(shot)
        self.assertEqual(converted['blocking']['points'][0]['render_position_m'], [5, 6, -4])
        self.assertEqual(converted['camera']['points'][0]['render_position_m'], [-2, -7, 3])
        self.assertNotIn('render_position_m', shot['blocking']['points'][0])
        shot['blocking']['space'] = 'NE_surface'
        self.assertNotIn('render_position_m', sp.enrich_shot(shot)['blocking']['points'][0])

    def test_clips_to_segment_not_infinite_line(self):
        square = [(0, 0), (10, 0), (10, 10), (0, 10)]
        examples = [((-5, 5), (15, 5), 10), ((2, 5), (8, 5), 6),
                    ((-5, 5), (-1, 5), 0), ((15, 5), (5, 5), 5),
                    ((0, 0), (10, 0), 10), ((-5, -5), (0, 0), 0),
                    ((5, 5), (5, 5), 0)]
        for start, end, expected in examples:
            with self.subTest(start=start, end=end):
                self.assertAlmostEqual(sp.segment_water_length(start, end, square), expected, places=8)

    def test_concave_polygon_multiple_water_intervals(self):
        # At y=3 this C-shaped polygon intersects x=0..1 and x=3..4.
        poly = [(0,0),(4,0),(4,4),(3,4),(3,1),(1,1),(1,4),(0,4)]
        self.assertAlmostEqual(sp.segment_water_length((-1,3), (5,3), poly), 2.0)

    def test_json_pointer_escaping_and_bad_index(self):
        self.assertEqual(sp.pointer_get({'a/b': {'~x': [17]}}, '/a~1b/~0x/0'), 17)
        for ptr in ('/a~2b', '/a~1b/~0x/01', '/a~1b/~0x/1'):
            with self.subTest(ptr=ptr), self.assertRaises(sp.PlanError):
                sp.pointer_get({'a/b': {'~x': [17]}}, ptr)


class PlanTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        # R5 director order differs deliberately from the manifest order below.
        self.liveries = ['midnight','p40','japan','luftwaffe','italy','scarlet','thunderbirds',
                         'blueangels','chrome','carbon','spectrum','splash','three_tone']
        manifest_order = [self.liveries[0], self.liveries[-1], *self.liveries[1:-1]]
        docs = {
            'app/data/fields/default.json': {'pilot': {'north': {'value': 0}, 'east': {'value': 0}},
                'surfaces': [{'type': 'runway',
                'center_north': {'value': 0}, 'center_east': {'value': 0},
                'width_north_south': {'value': 2}, 'length_east_west': {'value': 10}}]},
            sp.TRACK: {'ramps': [{'id':'tabletop','north_m':5,'east_m':4,'height_m':0.48,'approach_m':1,'deck_m':0.45,'descent_m':1.8,'width_m':3.2}]},
            'app/data/fields/lake.json': {'origin': {'north_m': 0, 'east_m': 0},
                'shoreline_offsets_ne_m': [[0,0],[0,10],[10,10],[10,0]]},
            'app/data/aircraft_models/test.json': {'family_id': 'test-paint', 'liveries': [{'id': x} for x in manifest_order]},
            'app/data/aircraft/test.json': {'id': 'test-aircraft'},
            'app/data/aircraft/other.json': {'id': 'test-other'},
            'app/data/vehicles/ground/truck.json': {'id': 'test-truck'},
            'app/data/vehicles/ground/monster.json': {'id': 'test-monster'},
            'app/data/airships/blimp.json': {'id': 'test-blimp'},
            'app/data/multirotors/quad.json': {'id': 'test-quad'},
            'app/data/vehicle_paints.json': {'vehicles': {'test-paint': {'skins': [{'id': 'red'}]}}},
        }
        hashes = {}
        for name, data in docs.items():
            path = self.root / name; path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps(data), encoding='utf-8')
            hashes[name] = hashlib.sha256(path.read_bytes()).hexdigest()
        sources = {
            sp.AIRCRAFT_CATALOG: '''const ENTRIES := [
 {
  id = "test-aircraft",
  data = "res://data/aircraft/test.json",
  visual_family = "test-paint",
 },
 {
  id = "test-other",
  data = "res://data/aircraft/other.json",
  visual_family = "other-family",
 },
 {
  id = "test-hidden",
  data = "res://data/aircraft/test.json",
  visual_family = "test-paint",
  player_selectable = false,
 },
]
static func is_player_selectable(id: String) -> bool:
 var e := entry(canonical_id(id))
 return not e.is_empty() and bool(e.get("player_selectable", true))
''',
            sp.VEHICLE_ROSTER: '''const GROUND := "ground"
const AIRSHIP := "airship"
const MULTIROTOR := "multirotor"
const ACTIVITIES := [
 {
  id = "test-truck", family = GROUND,
 },
 {
  id = "test-monster", family = GROUND,
 },
 {
  id = "test-blimp", family = AIRSHIP,
 },
 {
  id = "test-quad", family = MULTIROTOR,
 },
]
''',
            sp.AIRSHIP_CATALOG: '''const STOCK_ID := "test-blimp"
const VISUAL_FAMILY := "test-blimp-visual"
const DATA_PATH := "res://data/airships/blimp.json"
''',
            sp.MULTIROTOR_CATALOG: '''const ID := "test-quad"
const DATA_PATH := "res://data/multirotors/quad.json"
''',
            sp.GROUND_DATA: '''const DEFAULT_PATH := "res://data/vehicles/ground/truck.json"
const MONSTER_CAR_2_PATH := "res://data/vehicles/ground/monster.json"
static func load_default() -> Dictionary:
 return load_file(DEFAULT_PATH)
static func load_vehicle(vehicle_id: String) -> Dictionary:
 match vehicle_id:
  "test-truck":
   return load_default()
  "test-monster":
   return load_file(MONSTER_CAR_2_PATH)
  _:
   return _result([])
static func load_file(path: String) -> Dictionary:
 return {}
''',
        }
        for name, text in sources.items():
            path = self.root / name; path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding='utf-8')
            hashes[name] = hashlib.sha256(path.read_bytes()).hexdigest()
        default_skin = {'kind': 'factory', 'asset_id': None, 'selection_value': '', 'label': 'Factory'}
        def cast(skin):
            return {'kind': 'stock', 'vehicle_id': 'test-aircraft', 'data_path': 'app/data/aircraft/test.json',
                    'model_family': 'test-paint', 'skin': skin}
        def manifest_skin(index):
            return {'kind': 'manifest', 'asset_id': self.liveries[index],
                    'selection_value': '' if index == 0 else self.liveries[index], 'label': 'Test',
                    'source_path': 'app/data/aircraft_models/test.json'}
        self.cast = {'factory': cast(default_skin), 'orbit': cast(manifest_skin(0)), 'lake': cast(manifest_skin(12))}
        # Deliberately specified independently as frame lengths from the published storyboard.
        durations = [240,240,180,180,240,90,270,120,150,150,120,240,120,180,120,90,90,120,120,
                     240,240,60,300,120,180,180,240,240,240,240,240,165,90,165,90,105,105,240,600,360,120]
        ids = [f'R4-{i:02d}' for i in range(1,42)]
        ids += [f'R4-42{chr(ord("a")+i)}' for i in range(18)] + ['R4-43','R4-44','R4-45']
        durations += [60]+[30]*8+[60]+[30]*8+[180,300,300]
        self.assertEqual(sum(durations), 9000)
        shots = []; now = 0
        for sid, duration in zip(ids, durations):
            source_class = ('P' if sid in {'R4-20','R4-38','R4-39'} else
                            'U' if sid in {'R4-33','R4-35','R4-41'} or sid.startswith('R4-42') else
                            'E' if sid == 'R4-45' else 'G')
            s = {'id': sid, 'in_frame': now, 'out_frame': now + duration, 'source_class': source_class,
                 'cast': 'orbit' if sid == 'R4-39' else 'lake' if sid == 'R4-40' else 'factory',
                 'environment': 'field', 'setup': 'prepare', 'start_condition': 'ready',
                 'blocking': {'space': 'none', 'role': 'none', 'points': [], 'notes': ''},
                 'camera': {'space': 'none', 'mode': 'none', 'points': [], 'fov_deg': None, 'notes': ''},
                 'actions': ['act'], 'exit_condition': 'done', 'continuity': 'cut', 'transition': 'cut',
                 'checks': ['verify'], 'execution': {'route': 'manual', 'status': 'proposed', 'notes': ''}}
            if sid == 'R4-40':
                s['blocking'] = {'space': 'NED', 'role': 'proposed', 'notes': '', 'points': [
                    {'frame': 0, 'position_m': [5,-5,-3]}, {'frame': 360, 'position_m': [5,15,-3]}]}
            shots.append(s); now += duration
        cues = []
        for i, aid in enumerate(self.liveries):
            cues.append({'shot_id': 'R4-39', 'start_frame': i*45, 'end_frame': (i+1)*45 if i<12 else 600,
                         'asset_id': aid, 'selection_value': '' if i==0 else aid})
        self.plan = {'format':'openrc-trailer-shot-plan','version':1,'revision':'R5','fps':60,'duration_frames':9000,
                     'source_baseline':'a'*40,'source_files':hashes,
                     'source_assertions':[{'path':'app/data/aircraft/test.json','pointer':'/id','equals':'test-aircraft'}],
                     'cast':self.cast,'environments':{'field':{'landscape':'club_field'}},'shots':shots,'livery_cues':cues,
                     'continuity_links':[{'from':'R4-39','to':'R4-40','rule':'final_skin'}],
                     'lake_analysis':{'shot_id':'R4-40','source_path':'app/data/fields/lake.json','nominal_speed_mps':2},
                     'storyboard_path':'tools/trailer/preproduction/storyboard-150s.md'}

    def validate(self, plan=None): return sp.validate(self.plan if plan is None else plan, self.root)

    def test_valid_plan_and_independent_water_estimate(self):
        result = self.validate(); self.assertEqual(result['shots'], 62)
        self.assertEqual(result['lake_analysis']['clip_seconds'], 6)
        self.assertAlmostEqual(result['lake_analysis']['water_length_m'], 10)
        self.assertAlmostEqual(result['lake_analysis']['nominal_water_seconds'], 5)
        svg = sp.map_svg(self.plan, self.plan['shots'][39], self.root)
        self.assertIn('proposed, unflown', svg)
        self.assertIn('not recorded trajectories', svg)

    def test_gaps_overlaps_and_frame_count_rejected(self):
        for field, change in [('in_frame', 1), ('out_frame', -1)]:
            plan = copy.deepcopy(self.plan); plan['shots'][1][field] += change
            with self.subTest(field=field), self.assertRaisesRegex(sp.PlanError, 'contiguous'):
                self.validate(plan)
        plan = copy.deepcopy(self.plan); plan['shots'][-1]['out_frame'] -= 1
        with self.assertRaisesRegex(sp.PlanError, '9000'): self.validate(plan)
        plan = copy.deepcopy(self.plan); plan['shots'][41]['source_class'] = 'G'
        with self.assertRaisesRegex(sp.PlanError, 'source classes'): self.validate(plan)

    def test_wrong_skin_and_final_mismatch_rejected(self):
        plan = copy.deepcopy(self.plan); skin = plan['cast']['orbit']['skin']; skin['asset_id'] = 'invalid'
        with self.assertRaisesRegex(sp.PlanError, 'unknown manifest'): self.validate(plan)
        plan = copy.deepcopy(self.plan); skin = plan['cast']['lake']['skin']
        skin['asset_id'] = self.liveries[11]; skin['selection_value'] = self.liveries[11]
        with self.assertRaisesRegex(sp.PlanError, 'final orbit skin'): self.validate(plan)
        plan = copy.deepcopy(self.plan); plan['livery_cues'][0]['selection_value'] = self.liveries[0]
        with self.assertRaisesRegex(sp.PlanError, 'incorrect selection'): self.validate(plan)
        plan = copy.deepcopy(self.plan); plan['livery_cues'][-2]['end_frame'] = 599
        plan['livery_cues'][-1]['start_frame'] = 599
        with self.assertRaisesRegex(sp.PlanError, 'expected 45 frames'): self.validate(plan)
        plan = copy.deepcopy(self.plan)
        for field in ('asset_id','selection_value'):
            plan['livery_cues'][1][field], plan['livery_cues'][2][field] = plan['livery_cues'][2][field], plan['livery_cues'][1][field]
        with self.assertRaisesRegex(sp.PlanError, 'R5 director schedule'): self.validate(plan)

    def test_unknown_paint_and_source_hash_drift_rejected(self):
        plan = copy.deepcopy(self.plan)
        plan['cast']['factory']['skin'] = {'kind':'paint','asset_id':'green','selection_value':'green','label':'Green',
                                           'source_path':'app/data/vehicle_paints.json'}
        with self.assertRaisesRegex(sp.PlanError, 'unknown paint'): self.validate(plan)
        (self.root/'app/data/aircraft/test.json').write_text('{"id":"changed"}', encoding='utf-8')
        with self.assertRaisesRegex(sp.PlanError, 'hash drift'): self.validate()

    def test_source_assertion_and_reference_fail_closed(self):
        plan = copy.deepcopy(self.plan); plan['source_assertions'][0]['equals'] = 'other'
        with self.assertRaisesRegex(sp.PlanError, 'differs'): self.validate(plan)
        plan = copy.deepcopy(self.plan); plan['shots'][0]['cast'] = 'missing'
        with self.assertRaisesRegex(sp.PlanError, 'unknown cast'): self.validate(plan)
        plan = copy.deepcopy(self.plan); plan['shots'][0]['cast'] = ['missing']
        with self.assertRaisesRegex(sp.PlanError, 'expected nonempty string'): self.validate(plan)
        plan = copy.deepcopy(self.plan); plan['cast']['factory']['data_path'] = '../secret'
        with self.assertRaisesRegex(sp.PlanError, 'repo-relative'): self.validate(plan)

    def test_stock_ids_come_from_pinned_literal_registries(self):
        plan = copy.deepcopy(self.plan); plan['cast']['factory']['vehicle_id'] = 'test-aircraf'
        with self.assertRaisesRegex(sp.PlanError, 'unknown stock source ID'): self.validate(plan)
        plan = copy.deepcopy(self.plan); plan['cast']['factory']['vehicle_id'] = 'test-other'
        with self.assertRaisesRegex(sp.PlanError, 'does not match source binding'): self.validate(plan)
        plan = copy.deepcopy(self.plan); plan['cast']['factory']['vehicle_id'] = 'test-hidden'
        with self.assertRaisesRegex(sp.PlanError, 'not player selectable'): self.validate(plan)
        plan = copy.deepcopy(self.plan); plan['cast']['factory']['data_path'] = 'app/data/aircraft/other.json'
        with self.assertRaisesRegex(sp.PlanError, 'does not match source binding'): self.validate(plan)
        plan = copy.deepcopy(self.plan); plan['cast']['factory']['model_family'] = 'other-family'
        with self.assertRaisesRegex(sp.PlanError, 'does not match source binding'): self.validate(plan)
        plan = copy.deepcopy(self.plan); plan['cast']['factory']['vehicle_id'] = 'test-truck'
        plan['cast']['factory']['data_path'] = 'app/data/vehicles/ground/truck.json'
        plan['cast']['factory']['model_family'] = 'test-truck'
        self.assertTrue(self.validate(plan)['ok'])
        plan['cast']['factory']['data_path'] = 'app/data/vehicles/ground/monster.json'
        with self.assertRaisesRegex(sp.PlanError, 'does not match source binding'): self.validate(plan)
        for vid, data_path, family in [('test-quad','app/data/multirotors/quad.json','test-quad'),
                                       ('test-blimp','app/data/airships/blimp.json','test-blimp-visual')]:
            plan = copy.deepcopy(self.plan); plan['cast']['factory'].update(vehicle_id=vid,data_path=data_path,model_family=family)
            self.assertTrue(self.validate(plan)['ok'])
        plan = copy.deepcopy(self.plan); del plan['source_files'][sp.VEHICLE_ROSTER]
        with self.assertRaisesRegex(sp.PlanError, 'no pinned hash'): self.validate(plan)
        catalog = self.root / sp.AIRCRAFT_CATALOG
        original = catalog.read_text(encoding='utf-8')
        catalog.write_text(original.replace('player_selectable = false', 'player_selectable = computed'), encoding='utf-8')
        plan = copy.deepcopy(self.plan); plan['source_files'][sp.AIRCRAFT_CATALOG] = hashlib.sha256(catalog.read_bytes()).hexdigest()
        with self.assertRaisesRegex(sp.PlanError, 'non-literal player_selectable'): self.validate(plan)
        catalog = self.root / sp.AIRCRAFT_CATALOG
        catalog.write_text('const ENTRIES := [\n {\n  id = COMPUTED,\n },\n]\n', encoding='utf-8')
        plan = copy.deepcopy(self.plan); plan['source_files'][sp.AIRCRAFT_CATALOG] = hashlib.sha256(catalog.read_bytes()).hexdigest()
        with self.assertRaisesRegex(sp.PlanError, 'non-literal id'): self.validate(plan)

    def test_truck_map_uses_pinned_ramp_and_distinguishes_ground_markers(self):
        shot = copy.deepcopy(self.plan['shots'][0]); shot['id'] = 'R4-02'
        shot['blocking'] = {'space':'NE_surface','points':[{'frame':0,'position_m':[5,0,0]}, {'frame':60,'position_m':[5,9,0]}]}
        svg = sp.map_svg(self.plan, shot, self.root)
        self.assertIn('Tabletop · height 0.48 m', svg)
        self.assertIn('tabletop footprint and deck', svg)
        self.assertIn('actual supported height must be solved', svg)
        plan = copy.deepcopy(self.plan); del plan['source_files'][sp.TRACK]
        with self.assertRaisesRegex(sp.PlanError, 'map requires pinned'):
            sp.map_svg(plan, shot, self.root)

    def test_map_requires_matching_field_and_world_positions(self):
        shot = copy.deepcopy(self.plan['shots'][39])
        foreign = copy.deepcopy(self.plan); foreign['environments']['field']['landscape'] = 'phoenix_panorama'
        with self.assertRaisesRegex(sp.PlanError, 'club_field environment'):
            sp.map_svg(foreign, shot, self.root)
        shot['blocking'] = {'space':'model_local', 'points':[{'frame':0,'position_m':[0,0,0]}]}
        shot['camera'] = {'space':'none', 'points':[]}
        with self.assertRaisesRegex(sp.PlanError, 'requires at least one'):
            sp.map_svg(self.plan, shot, self.root)

    def test_nonfinite_and_out_of_range_points_fail(self):
        plan = copy.deepcopy(self.plan); plan['shots'][39]['blocking']['points'][0]['position_m'][1] = math.nan
        with self.assertRaisesRegex(sp.PlanError, 'non-finite'): self.validate(plan)
        plan = copy.deepcopy(self.plan); plan['shots'][39]['blocking']['points'][1]['frame'] = 361
        with self.assertRaisesRegex(sp.PlanError, 'local frames'): self.validate(plan)
        plan = copy.deepcopy(self.plan); plan['shots'][39]['blocking']['points'][1]['position_m'][0] = 10**1000
        with self.assertRaisesRegex(sp.PlanError, 'finite'): self.validate(plan)

    def test_duplicate_json_keys_rejected(self):
        path = self.root / 'duplicate.json'; path.write_text('{"fps":60,"fps":30}', encoding='utf-8')
        with self.assertRaisesRegex(sp.PlanError, 'duplicate JSON key'): sp.read_json(path)

    def test_cli_show_and_exclusive_output(self):
        planfile = self.root/'plan.json'; planfile.write_text(json.dumps(self.plan), encoding='utf-8')
        out = self.root/'new-run'/'nested'/'show.json'
        cmd = [sys.executable, str(Path(sp.__file__)), '--plan',str(planfile), 'show', 'R4-40',
               '--source-root',str(self.root),'--out',str(out)]
        first = subprocess.run(cmd, capture_output=True, text=True, check=False)
        self.assertEqual(first.returncode, 0, first.stderr)
        data = json.loads(out.read_text(encoding='utf-8'))
        self.assertEqual(data['shot']['blocking']['points'][0]['render_position_m'], [-5,3,-5])
        before = out.read_bytes()
        second = subprocess.run(cmd, capture_output=True, text=True, check=False)
        self.assertEqual(second.returncode, 2)
        self.assertEqual(out.read_bytes(), before)


if __name__ == '__main__': unittest.main()
