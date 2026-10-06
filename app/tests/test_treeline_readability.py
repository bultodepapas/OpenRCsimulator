"""L6c: inventory, background composition guards, blinded kit and scoring tests (no Godot needed)."""
import csv
import json
import math
from pathlib import Path
import tempfile
import unittest

import numpy as np
from PIL import Image

import compare_captures as cc
import treeline_readability as l6c


def camera_evidence(pitch_deg, fov_deg=50.0):
    """A pilot camera pitched up by pitch_deg: Godot looks along −z, so z = −forward."""
    pitch = math.radians(pitch_deg)
    forward = [0.0, math.sin(pitch), -math.cos(pitch)]
    return {"camera": {"fov_deg": fov_deg, "viewport": [1280, 720],
                       "transform": {"position": [0, 1.7, 0],
                                     "basis_columns": [[1, 0, 0], [0, math.cos(pitch), math.sin(pitch)], [-f for f in forward]]}}}


def scene(trees_rows=(300, 340), horizon=360, plane=None):
    """Synthetic 1280×720 frames: sky above the horizon, grass below, a dark tree band, an optional red airplane."""
    image = np.zeros((720, 1280, 3), dtype=np.float32)
    image[:horizon] = (0.75, 0.85, 0.9)
    image[horizon:] = (0.2, 0.45, 0.15)
    without_trees = image.copy()
    image[trees_rows[0]:trees_rows[1], :] = (0.2, 0.3, 0.15)
    with_plane = image.copy()
    if plane is not None:
        r0, r1, c0, c1 = plane
        with_plane[r0:r1, c0:c1] = (0.7, 0.05, 0.1)
    return with_plane, image, without_trees


class InventoryTests(unittest.TestCase):
    def test_fixed_inventory_is_two_views_four_backgrounds_two_references_six_attitudes(self):
        cases = l6c.capture_cases()
        ids = [case.case_id for case in cases]
        self.assertEqual(len(cases), 64)
        self.assertEqual(len(set(ids)), 64)
        self.assertEqual(ids[:8], ["l6c-game-sky-noplane", "l6c-game-sky-notrees", "l6c-game-sky-level",
                                   "l6c-game-sky-inverted", "l6c-game-sky-knife_left", "l6c-game-sky-knife_right",
                                   "l6c-game-sky-climb", "l6c-game-sky-dive"])
        self.assertTrue(all(case.family == "treeline-readability" and case.route == "synthetic-inspection" for case in cases))
        self.assertTrue(all(case.visual_distance_m == 100.0 and case.kind == "flight" for case in cases))

    def test_every_case_declares_view_elevation_and_shadow_off(self):
        for case in l6c.capture_cases():
            view, background = case.repeat_group.split("-", 1)
            args = case.arguments
            self.assertIn("--scripted", args)
            self.assertIn("--shadow=off", args)
            self.assertIn("--t=1.5", args)
            self.assertIn(f"--autozoom={1 if l6c.VIEWS[view] else 0}", args)
            self.assertEqual(case.autozoom, l6c.VIEWS[view])
            self.assertIn(f"--visual_elevation={l6c.BACKGROUNDS[background]['elevation_deg']:g}", args)
            self.assertIn(f"--visual_azimuth={l6c.AZIMUTH_DEG:g}", args)
            self.assertIn(f"--case={case.case_id}", args)
            if case.case_id.endswith("-noplane"):
                self.assertIn("--hide_airplane", args)
                self.assertNotIn("--hide_treeline", args)
                self.assertFalse(case.pilot_visible)
            elif case.case_id.endswith("-notrees"):
                self.assertIn("--hide_airplane", args)
                self.assertIn("--hide_treeline", args)
                self.assertFalse(case.pilot_visible)
            else:
                self.assertNotIn("--hide_airplane", args)
                self.assertNotIn("--hide_treeline", args)
                self.assertTrue(case.pilot_visible)
                self.assertIn(f"--visual_pose={case.visual_pose}", args)

    def test_evidence_must_agree_on_elevation_and_treeline_visibility(self):
        import test_visual_quality_cases as helpers
        case = next(case for case in l6c.capture_cases() if case.case_id == "l6c-fixed-trees-notrees")
        evidence = helpers.evidence_for(case)
        evidence["visual_elevation_deg"] = l6c.BACKGROUNDS["trees"]["elevation_deg"]
        evidence["visual_azimuth_deg"] = l6c.AZIMUTH_DEG
        evidence["state"]["treeline_visible"] = False
        manifest = {"visual_evidence": evidence, "capture_scene": "field"}
        l6c.validate_evidence(case, manifest)
        evidence["visual_azimuth_deg"] = 0.0
        with self.assertRaisesRegex(RuntimeError, "azimuth"):
            l6c.validate_evidence(case, manifest)
        evidence["visual_azimuth_deg"] = l6c.AZIMUTH_DEG
        evidence["state"]["treeline_visible"] = True
        with self.assertRaisesRegex(RuntimeError, "treeline visibility"):
            l6c.validate_evidence(case, manifest)
        evidence["state"]["treeline_visible"] = False
        evidence["visual_elevation_deg"] = 10.0
        with self.assertRaisesRegex(RuntimeError, "elevation"):
            l6c.validate_evidence(case, manifest)


class MetricTests(unittest.TestCase):
    def test_horizon_row_follows_camera_pitch(self):
        self.assertAlmostEqual(l6c.horizon_row(camera_evidence(0.0)), 360.0, places=6)
        focal = 360.0 / math.tan(math.radians(25.0))
        self.assertAlmostEqual(l6c.horizon_row(camera_evidence(10.0)), 360.0 + focal * math.tan(math.radians(10.0)), places=6)
        self.assertLess(l6c.horizon_row(camera_evidence(-0.5)), 360.0)
        narrow = l6c.horizon_row(camera_evidence(1.6, fov_deg=20.0))
        self.assertGreater(narrow, l6c.horizon_row(camera_evidence(1.6, fov_deg=50.0)))

    def test_composition_reports_trees_sky_and_ground_around_the_airplane(self):
        with_plane, with_trees, without_trees = scene(plane=(314, 326, 630, 650))
        tree_mask = cc.difference_mask(with_trees, without_trees)
        result = cc.measure_pair(with_plane, with_trees, tree_mask, 360.0)
        self.assertEqual(result["pixels"], 12 * 20)
        self.assertEqual(result["bbox_px"]["width"], 20)
        self.assertEqual(result["bbox_px"]["height"], 12)
        self.assertEqual(result["background"]["trees"], 1.0)
        self.assertEqual(result["background"]["sky"], 0.0)
        self.assertEqual(result["background"]["ground"], 0.0)
        self.assertGreater(abs(result["weber_contrast"]), 0.3)  # a bright red blob over a dark band
        self.assertGreater(result["delta_e"], 20.0)
        self.assertLessEqual(result["delta_e_p10"], result["delta_e"])
        sky_plane, _, _ = scene(plane=(100, 112, 630, 650))
        sky = cc.measure_pair(sky_plane, with_trees, tree_mask, 360.0)
        self.assertEqual(sky["background"]["sky"], 1.0)
        edge_plane, _, _ = scene(plane=(354, 366, 630, 650))
        edge = cc.measure_pair(edge_plane, with_trees, tree_mask, 360.0)
        self.assertGreater(edge["background"]["sky"], 0.3)
        self.assertGreater(edge["background"]["ground"], 0.3)
        self.assertEqual(edge["background"]["trees"], 0.0)
        self.assertAlmostEqual(edge["background"]["sky"] + edge["background"]["ground"] + edge["background"]["other"], 1.0, places=3)

    def test_plain_readability_output_is_unchanged_without_masks(self):
        with_plane, with_trees, _ = scene(plane=(314, 326, 630, 650))
        result = cc.measure_pair(with_plane, with_trees)
        self.assertEqual(set(result), {"pixels", "weber_contrast", "share_low_contrast", "delta_e", "background_saturation"})

    def test_background_guard_rejects_a_mislabelled_case(self):
        l6c.check_background("x", "trees", {"trees": 0.8, "sky": 0.2, "ground": 0.0})
        with self.assertRaisesRegex(RuntimeError, "trees"):
            l6c.check_background("x", "trees", {"trees": 0.3, "sky": 0.7, "ground": 0.0})
        l6c.check_background("x", "horizon", {"trees": 0.4, "sky": 0.5, "ground": 0.1})
        with self.assertRaisesRegex(RuntimeError, "sky"):
            l6c.check_background("x", "horizon", {"trees": 0.95, "sky": 0.05, "ground": 0.0})
        with self.assertRaisesRegex(RuntimeError, "ground"):
            l6c.check_background("x", "ground", {"trees": 0.0, "sky": 0.5, "ground": 0.5})

    def test_missing_airplane_fails_the_group(self):
        with tempfile.TemporaryDirectory() as temp:
            out = Path(temp)
            with_plane, with_trees, without_trees = scene(plane=None)
            for name, image in (("noplane", with_trees), ("notrees", without_trees)):
                Image.fromarray((image * 255).astype(np.uint8)).save(out / f"l6c-game-trees-{name}.png")
            for pose in l6c.POSES:
                Image.fromarray((with_plane * 255).astype(np.uint8)).save(out / f"l6c-game-trees-{pose}.png")
            evidence = {"l6c-game-trees-noplane": camera_evidence(1.6)}
            with self.assertRaisesRegex(RuntimeError, "not visible"):
                l6c.measure_group(out, "game", "trees", evidence)


class KitTests(unittest.TestCase):
    def make_images(self, out):
        hashes = {}
        for number, case_id in enumerate(l6c.kit_item_ids()):
            image = Image.new("RGB", (4, 3), (number, 0, 0))
            path = out / f"{case_id}.png"
            image.save(path)
            hashes[case_id] = l6c.vq.sha256_file(path)
            path.with_suffix(".json").write_text("{}")
        return hashes

    def test_kit_is_blinded_deterministic_and_keyed_apart(self):
        with tempfile.TemporaryDirectory() as temp:
            out = Path(temp)
            hashes = self.make_images(out)
            first = l6c.build_kit(out, hashes)
            key_a = json.loads((out / "kit" / "key" / "answer-key.json").read_text())
            second = l6c.build_kit(out, hashes)
            self.assertEqual(first, second)
            key_b = json.loads((out / "kit" / "key" / "answer-key.json").read_text())
            self.assertEqual(key_a, key_b)
            names = sorted(path.name for path in (out / "kit" / "images").iterdir())
            self.assertEqual(names, [f"{n:02d}.png" for n in range(1, 25)])
            for name in names:
                for word in (*l6c.POSES, *l6c.BACKGROUNDS):
                    self.assertNotIn(word, name)
            self.assertFalse(list((out / "kit" / "images").glob("*.json")))
            case_ids = [item["case_id"] for item in key_a["items"]]
            self.assertEqual(sorted(case_ids), sorted(l6c.kit_item_ids()))
            self.assertNotEqual(case_ids, sorted(case_ids))
            self.assertNotEqual(case_ids, l6c.kit_item_ids())
            self.assertEqual([item["image"] for item in key_a["items"]], names)
            for item in key_a["items"]:
                self.assertEqual(item["sha256"], hashes[item["case_id"]])
                self.assertEqual(l6c.vq.sha256_file(out / "kit" / "images" / item["image"]), hashes[item["case_id"]])
            viewer = (out / "kit" / "index.html").read_text()
            self.assertNotIn("answer-key", viewer)
            self.assertNotIn("l6c-game", viewer)
            with (out / "kit" / "responses-template.csv").open(newline="") as stream:
                template = list(csv.reader(stream))
            self.assertEqual(template[0], ["image", "answer", "notes"])
            self.assertEqual([row[0] for row in template[1:]], [f"{n:02d}" for n in range(1, 25)] + list(l6c.KIT_FLIGHT_ROWS))
            self.assertEqual(first["answer_key_sha256"], l6c.vq.sha256_file(out / "kit" / "key" / "answer-key.json"))

    def write_responses(self, out, key, wrong=0, blank=0, flight=("4", "5")):
        rows = [["image", "answer", "notes"]]
        for index, item in enumerate(key["items"]):
            answer = item["pose"]
            if index < wrong:
                answer = next(pose for pose in l6c.POSES if pose != item["pose"])
            if wrong <= index < wrong + blank:
                answer = ""
            rows.append([item["image"][:2], answer, ""])
        rows.append(["flight-pass", flight[0], "pasada"])
        rows.append(["flight-turn", flight[1], ""])
        path = out / "responses.csv"
        with path.open("w", newline="") as stream:
            csv.writer(stream).writerows(rows)
        return path

    def test_scoring_threshold_missing_and_bad_answers(self):
        with tempfile.TemporaryDirectory() as temp:
            out = Path(temp)
            l6c.build_kit(out, self.make_images(out))
            kit = out / "kit"
            key = json.loads((kit / "key" / "answer-key.json").read_text())
            perfect = l6c.score(self.write_responses(out, key), kit)
            self.assertEqual((perfect["correct"], perfect["total"], perfect["passed"]), (24, 24, True))
            self.assertEqual(perfect["flight"]["flight-pass"], {"rating": 4, "notes": "pasada"})
            self.assertTrue(perfect["flight_complete"])
            self.assertEqual(sum(counts["total"] for counts in perfect["by_background"].values()), 24)
            two = l6c.score(self.write_responses(out, key, wrong=2), kit)
            self.assertEqual((two["correct"], two["passed"], len(two["wrong"])), (22, True, 2))
            three = l6c.score(self.write_responses(out, key, wrong=3), kit)
            self.assertFalse(three["passed"])
            self.assertEqual(three["wrong"][0]["expected"], key["items"][0]["pose"])
            blank = l6c.score(self.write_responses(out, key, blank=1, flight=("", "")), kit)
            self.assertEqual((blank["correct"], blank["passed"], blank["missing"]), (23, False, [key["items"][0]["image"][:2]]))
            self.assertFalse(blank["flight_complete"])
            path = self.write_responses(out, key)
            text = path.read_text().replace(f"{key['items'][0]['image'][:2]},{key['items'][0]['pose']}", f"{key['items'][0]['image'][:2]},upside")
            path.write_text(text)
            with self.assertRaisesRegex(RuntimeError, "unknown answer"):
                l6c.score(path, kit)
            with self.assertRaisesRegex(RuntimeError, "rating"):
                l6c.score(self.write_responses(out, key, flight=("9", "")), kit)


if __name__ == "__main__":
    unittest.main()
