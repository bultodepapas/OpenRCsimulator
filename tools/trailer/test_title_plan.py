#!/usr/bin/env python3
"""Test the title plan and a short synthetic study, not simulator footage."""
import copy
import hashlib
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from PIL import Image

import cinema_titles as cinema
import title_plan as titles


LEGACY_PLAN = titles.REPO / "docs/plans/trailer-v2/title-plan-r6.json"


class PlanTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.source = json.loads(LEGACY_PLAN.read_text(encoding="utf-8"))
        self.shots = titles.REPO / "docs/plans/trailer-v2/shot-plan-r5.json"

    def write_plan(self, plan):
        path = self.root / "plan.json"
        path.write_text(json.dumps(plan, ensure_ascii=False), encoding="utf-8")
        return path

    def test_exact_headlines_required_labels_and_open_lake(self):
        plan = titles.load(LEGACY_PLAN, shot_plan=self.shots)
        headlines = [(cue["lines"][0], cue["in_frame"], cue["out_frame"])
                     for cue in plan["cues"] if cue["role"] == "headline"]
        self.assertEqual(headlines, [("A SKY WITHIN REACH", 855, 1050),
                                    ("FEEL EVERY INPUT", 3615, 3885),
                                    ("EXPAND YOUR HANGAR", 7500, 7620)])
        self.assertTrue(all(cue["out_frame"] <= 7140 or cue["in_frame"] >= 7500
                            for cue in plan["cues"]))
        self.assertIn("source-known", plan["metadata"]["website"])
        self.assertEqual(plan["metadata"]["trial_basis_binding"], "unresolved")
        self.assertFalse(plan["metadata"]["publication_ready"])
        self.assertEqual(plan["source_sha256"], hashlib.sha256(LEGACY_PLAN.read_bytes()).hexdigest())
        self.assertEqual(plan["shot_plan_sha256"], hashlib.sha256(self.shots.read_bytes()).hexdigest())
        self.assertTrue(any("trial" in item.lower() for item in plan["metadata"]["production_blockers"]))
        for cue in plan["cues"]:
            if cue["role"] == "label":
                overlay = cinema.CinemaCue(cue)
                self.assertEqual(overlay.frame(cue["in_frame"]).getchannel("A").getextrema()[1], 255)
                self.assertEqual(overlay.frame(cue["out_frame"] - 1).getchannel("A").getextrema()[1], 255)

    def test_trial_basis_is_required_for_publication_and_binds_the_whole_interval(self):
        with self.assertRaisesRegex(ValueError, "basis is unresolved"):
            titles.load(LEGACY_PLAN, publication=True)
        for basis in ("estimated", "donor"):
            plan = titles.load(LEGACY_PLAN, publication=True, trial_basis=basis)
            trial = next(cue for cue in plan["cues"] if cue["id"] == "trial")
            self.assertEqual(trial["lines"], [f"EXPERIMENTAL TEST FLIGHT · {basis.upper()} PHYSICS"])
            self.assertEqual((trial["in_frame"], trial["out_frame"]), (8220, 8400))
            rendered = cinema.CinemaCue(trial)
            self.assertEqual(rendered.frame(8220).tobytes(), rendered.frame(8399).tobytes())
            self.assertTrue(plan["metadata"]["production_blockers"])
        for bad in ("likely", "ESTIMATED", "", True):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                titles.load(LEGACY_PLAN, trial_basis=bad)

    def test_plan_mutations_cannot_remove_coverages_or_inject_copy(self):
        def changed(identifier, **values):
            plan = copy.deepcopy(self.source)
            next(c for c in plan["cues"] if c["id"] == identifier).update(values)
            return plan
        invalid = [
            changed("phoenix", out_frame=7890),
            changed("trial", fade_in_frames=1),
            changed("size-comparison", lines=["MAKE IT YOURS"]),
            changed("hangar", lines=["300+ MODELS"]),
            changed("sky", size=30),
            changed("sky", fade_in_frames=140),
            changed("liveries", out_frame=7160),
            changed("end-cta", fade_in_frames=1),
            changed("scale-10", y=870),
        ]
        for text in ("PUBLIC BETA", "MUSIC: UPRISING"):
            injected = copy.deepcopy(self.source)
            injected["cues"].append({"id": "unverified", "role": "label", "lines": [text],
                                      "in_frame": 8430, "out_frame": 8490, "x": 112, "y": 900,
                                      "align": "left", "size": 38, "fade_in_frames": 0, "fade_out_frames": 0})
            invalid.append(injected)
        for plan in invalid:
            with self.subTest(cue=plan["cues"]), self.assertRaises(ValueError):
                titles.load(self.write_plan(plan))

    def test_optional_shot_plan_detects_incompatible_edit(self):
        shots = json.loads(self.shots.read_text(encoding="utf-8"))
        self.assertEqual(titles.load(LEGACY_PLAN, shot_plan=shots)["duration_frames"], 9000)
        shots["fps"] = 30
        with self.assertRaisesRegex(ValueError, "60 fps"):
            titles.load(LEGACY_PLAN, shot_plan=shots)
        shots["fps"] = 60
        shots["shots"][0]["out_frame"] -= 1
        shots["shots"][1]["in_frame"] -= 1
        with self.assertRaisesRegex(ValueError, "R4-05|contiguous|boundary"):
            # Keep continuity but move a required title-related cut.
            index = next(i for i, shot in enumerate(shots["shots"]) if shot["id"] == "R4-05")
            shots["shots"][index]["out_frame"] -= 1
            shots["shots"][index + 1]["in_frame"] -= 1
            titles.load(LEGACY_PLAN, shot_plan=shots)

    def test_duplicate_json_keys_are_rejected(self):
        path = self.root / "duplicate.json"
        original = LEGACY_PLAN.read_text(encoding="utf-8")
        path.write_text(original.replace('"fps": 60,', '"fps": 60, "fps": 30,', 1), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "duplicate JSON key"):
            titles.load(path)
        path.write_text(original.replace('"id":"sky"', '"id":"sky","id":"sky"', 1), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "duplicate JSON key"):
            titles.load(path)

    def test_load_hashes_exact_bytes_it_parses_even_if_the_file_changes(self):
        path = self.write_plan(self.source)
        original = path.read_bytes()
        expected = hashlib.sha256(original).hexdigest()
        actual_read_bytes = Path.read_bytes
        def read_then_replace(target):
            data = actual_read_bytes(target)
            if target == path:
                path.write_bytes(b'{"changed": true}')
            return data
        with mock.patch.object(Path, "read_bytes", autospec=True, side_effect=read_then_replace):
            loaded = titles.load(path)
        self.assertEqual(loaded["source_sha256"], expected)
        self.assertNotEqual(hashlib.sha256(path.read_bytes()).hexdigest(), expected)
        self.assertEqual(len(loaded["cues"]), 22)

    def test_study_windows_cover_each_full_headline_and_end_card(self):
        self.assertEqual(sum(length for _, length in titles.STUDY_WINDOWS_R6), 1125)
        for key in ("sky", "input", "hangar", "end-brand"):
            _, _, start, end = titles.REQUIRED_R6[key]
            self.assertIn((start, end - start), titles.STUDY_WINDOWS_R6)


@unittest.skipUnless(shutil.which("ffmpeg") and shutil.which("ffprobe"), "FFmpeg and ffprobe are required")
class StudyTests(unittest.TestCase):
    def test_small_study_has_a_permanent_label_and_probed_frames(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "study"
            plan_path = Path(tmp) / "plan.json"
            plan_path.write_bytes(LEGACY_PLAN.read_bytes())
            expected_plan_sha = hashlib.sha256(plan_path.read_bytes()).hexdigest()
            original_load = titles.load
            def load_then_replace(*args, **kwargs):
                result = original_load(*args, **kwargs)
                plan_path.write_bytes(b'{"changed": true}')
                return result
            with mock.patch.object(titles, "load", side_effect=load_then_replace):
                summary = titles.preview(plan_path, target, windows=((855, 4), (7620, 3), (8700, 2)))
            self.assertEqual(summary["study_frames"], 9)
            self.assertEqual(summary["watermark"], titles.STUDY_MARK)
            self.assertEqual(summary["ffprobe"]["streams"][0]["nb_frames"], "9")
            self.assertEqual(summary["ffprobe"]["streams"][0]["avg_frame_rate"], "60/1")
            self.assertEqual(summary["plan_sha256"], expected_plan_sha)
            self.assertIn("no game footage", summary["kind"])
            self.assertTrue((target / "typography-contact.jpg").is_file())
            self.assertTrue((target / "study-summary.json").is_file())
            movie = target / "typography-study.mp4"
            # Decode the first and last actual encoded frames and inspect the
            # marked margin; the background itself is a much darker grey.
            subprocess.run(["ffmpeg", "-v", "error", "-i", str(movie), "-vf",
                            "select=eq(n\\,0)+eq(n\\,8)", "-vsync", "0", "-frames:v", "2",
                            str(Path(tmp) / "frame-%d.png")], check=True, capture_output=True)
            for index in (1, 2):
                with Image.open(Path(tmp) / f"frame-{index}.png") as frame:
                    marked = frame.convert("L").crop((108, 1015, 700, 1065))
                    self.assertGreater(marked.getextrema()[1], 120)
            with self.assertRaises(FileExistsError):
                titles.preview(LEGACY_PLAN, target, windows=((855, 1),))


if __name__ == "__main__":
    unittest.main()
