"""Source selection and artifact acceptance regressions; run with the visual venv."""
import copy
import csv
import gzip
import json
import math
from pathlib import Path
import tempfile
import unittest

from PIL import Image, ImageDraw
from prepare import EVIDENCE, STATE, prepare, select_frames
from checks import check_records, check_images, render_basis
from kit import parameters


class KitTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = prepare()
        cls.result = json.loads((EVIDENCE/'report.json').read_text())['results'][0]
        raw = gzip.decompress((EVIDENCE/'circuit.csv.gz').read_bytes()).decode()
        cls.rows = [{k: float(v) for k, v in r.items()} for r in csv.DictReader(
            line for line in raw.splitlines() if not line.startswith('#'))]
        cls.eye, cls.throws = parameters()

    def fixture(self):
        capture = dict(manifest_sha256='source', frames=[], camera_contract=dict(base_fov_deg=50, min_fov_deg=6, target_px=30, inspect_offset=[-2,1,2], auto_zoom_span=1.5))
        for f in self.manifest['frames']:
            c, s = f['surfaces'], f['state']
            hinges = dict(aileron_right=[-math.radians(20*c['roll']), 0, 0],
                          aileron_left=[math.radians(20*c['roll']), 0, 0],
                          elevator=[-math.radians(20*c['pitch']), 0, 0],
                          rudder=[0, math.radians(25*c['yaw']), 0])
            for view in ('pilot', 'inspect'):
                capture['frames'].append(dict(id=f['id'], tick=f['tick'], time_s=f['time_s'],
                    state=s, view=view, rendered_cg=[s[1], -s[2], -s[0]], root_basis=render_basis(s[6:10]),
                    shader_clock_s=f['time_s'], prop_angle_rad=f['prop_angle_rad'], surfaces=c,
                    hinge_rotations=hinges, sim_tick_before=0, sim_tick_after=0, cg_behind=False, shadow_visible=True, background_shadow_visible=True,
                    cg_pixel=[480,270], fov_deg=50, camera_position=self.eye, png='on.png', background_png='off.png'))
        for r in capture['frames']:
            cg = r['rendered_cg']
            r['root_origin'] = cg
            if r['view'] == 'pilot':
                r['fov_deg'] = min(50,max(6,math.degrees(2*math.atan(1.5*540/(2*math.dist(cg,self.eye)*30)))))
            else:
                r['camera_position'] = [cg[i]+sum(r['root_basis'][j*3+i]*[-2,1,2][j] for j in range(3)) for i in range(3)]
        return capture

    def validate(self, capture):
        check_records(self.manifest, capture, 'source', self.eye, self.throws)

    def test_exact_selected_ticks_and_final_sample(self):
        self.assertEqual(len(self.manifest['frames']), 12)
        for frame in self.manifest['frames']:
            row = self.rows[frame['tick']]
            self.assertEqual(frame['state'], [row[k] for k in STATE])
            self.assertEqual(frame['surfaces']['pitch'], row['srv_pitch'])
            self.assertGreaterEqual(frame['prop_angle_rad'], 0)
            self.assertLess(frame['prop_angle_rad'], math.tau)
        self.assertEqual(self.manifest['frames'][-1]['tick'], len(self.rows)-1)

    def test_phase_report_disagreement(self):
        result = copy.deepcopy(self.result)
        result['phases'][5]['north_m'] += 1
        with self.assertRaisesRegex(ValueError, 'disagrees'):
            select_frames(self.rows, result)

    def test_missing_phase(self):
        result = copy.deepcopy(self.result)
        result['phases'].pop(5)
        with self.assertRaisesRegex(ValueError, 'phases'):
            select_frames(self.rows, result)

    def test_selected_nonunit_attitude(self):
        rows = self.rows.copy()
        rows[0] = dict(rows[0], qw=2)
        with self.assertRaisesRegex(ValueError, 'non-unit'):
            select_frames(rows, self.result)

    def test_actual_servo_bound(self):
        rows = self.rows.copy()
        rows[0] = dict(rows[0], srv_pitch=2)
        with self.assertRaisesRegex(ValueError, 'surfaces'):
            select_frames(rows, self.result)

    def test_known_frame_mapping(self):
        self.assertEqual(render_basis([1,0,0,0]), [1,0,0,0,1,0,0,0,1])
        q = [math.sqrt(.5),0,0,math.sqrt(.5)]
        actual = render_basis(q)
        expected = [0,0,1, 0,1,0, -1,0,0]
        for a, b in zip(actual, expected):
            self.assertAlmostEqual(a, b, places=14)

    def test_positive_capture_contract(self):
        self.validate(self.fixture())

    def test_source_identity_mismatch(self):
        r = self.fixture(); r['manifest_sha256'] = 'other'
        with self.assertRaisesRegex(ValueError, 'another manifest'): self.validate(r)

    def test_missing_and_duplicate_views(self):
        r = self.fixture(); r['frames'].pop()
        with self.assertRaisesRegex(ValueError, 'missing'): self.validate(r)
        r = self.fixture(); r['frames'][-1] = r['frames'][0]
        with self.assertRaisesRegex(ValueError, 'duplicate'): self.validate(r)

    def test_pose_hinge_clock_camera_and_tick_corruptions(self):
        changes = [('rendered_cg', [1000,0,0], 'datum'), ('root_basis', [0]*9, 'attitude'),
                   ('shader_clock_s', 1000, 'clock'), ('sim_tick_after', 1, 'advanced'),
                   ('camera_position', [0,50,0], 'pilot eye'), ('tick', 99, 'tick/time'),
                   ('fov_deg', 90, 'FOV'), ('shadow_visible', False, 'shadow'),
                   ('cg_pixel', [500,270], 'aim')]
        for key, value, message in changes:
            with self.subTest(key=key):
                r = self.fixture(); r['frames'][0][key] = value
                with self.assertRaisesRegex(ValueError, message): self.validate(r)
        r = self.fixture(); r['frames'][0]['hinge_rotations']['elevator'][0] += .1
        with self.assertRaisesRegex(ValueError, 'hinge'): self.validate(r)

    def test_nonfinite_and_path_escape_rejected(self):
        for key, value in [('root_basis', [float('nan')]*9), ('png', '../on.png')]:
            with self.subTest(key=key):
                r = self.fixture(); r['frames'][0][key] = value
                with self.assertRaises(ValueError): self.validate(r)

    def test_image_ablation_repeat_and_blank(self):
        with tempfile.TemporaryDirectory() as d:
            first, second = Path(d)/'a', Path(d)/'b'
            first.mkdir(); second.mkdir()
            bg = Image.new('RGB',(960,540),'#234567')
            ImageDraw.Draw(bg).rectangle((0,270,959,539),fill='#426344')
            on = bg.copy(); ImageDraw.Draw(on).rectangle((478,268,481,271),fill='white')
            for folder in (first,second):
                bg.save(folder/'off.png'); on.save(folder/'on.png')
            records = [dict(id='test',view='pilot',png='on.png',background_png='off.png')]
            self.assertEqual(check_images(first,records,second)[0]['changed_pixels'],16)
            bg.save(second/'on.png')
            with self.assertRaisesRegex(ValueError,'repeated'): check_images(first,records,second)
            bg.save(first/'on.png')
            with self.assertRaisesRegex(ValueError,'no visible'): check_images(first,records,second)
            Image.new('RGB',(960,540),'white').save(first/'on.png')
            with self.assertRaisesRegex(ValueError,'blank'): check_images(first,records,second)


if __name__ == '__main__':
    unittest.main()
