"""Report contracts with temporary PNGs and synthetic states, not rendered flights."""
import contextlib
import copy
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest

from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
SPEC = importlib.util.spec_from_file_location("runway_report", HERE / "scenario_report.py")
REPORT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(REPORT)


def frame(view="pilot", time=0.0):
    row = {key: 0.0 for key in REPORT.STATE_TOL}
    row.update(view=view, t_s=time, tick=round(time * 240), sim_clock=time, phase="idle" if time < 2 else "climb",
               image=f"{view}/{time:g}.png", airplane_px=[640.0, 360.0], shadow_px=[640.0, 360.0],
               commands={"throttle": 0.5}, draw_calls=10, rpm=1200.0,
               height_m=20.0 if time >= 2 else 0.0)
    return row


def manifest(frames):
    return {"format": "openrc-runway-scenario v1", "aircraft": "stik-electric-6s", "scenery": True,
            "start": {"north": 0.0, "east": 0.0, "heading_deg": 0.0}, "adapter": "synthetic fixture",
            "godot": "fixture", "dt_s": 1 / 240, "views": sorted({r["view"] for r in frames}),
            "times_s": sorted({r["t_s"] for r in frames}), "frames": frames}


def write_images(root, data, color=(0, 0, 0), size=(2, 2)):
    for row in data["frames"]:
        path = root / row["image"]
        path.parent.mkdir(parents=True, exist_ok=True)
        Image.new("RGB", size, color).save(path)
        row["sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()


class ScenarioEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="scenario-evidence-", dir=ROOT / "tmp")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.current, self.previous = self.root / "current", self.root / "previous"
        self.current.mkdir()
        self.previous.mkdir()

    def pair(self, current=None, previous=None):
        cur = manifest([frame()]) if current is None else current
        old = copy.deepcopy(cur) if previous is None else previous
        write_images(self.current, cur)
        write_images(self.previous, old)
        return cur, old

    def compare(self, cur, old):
        return REPORT.compare(self.current, self.previous, cur, old)

    def test_unchanged_images_and_sampled_state_have_scoped_result(self):
        result = self.compare(*self.pair())
        self.assertEqual(result["verdict"], "matched frames unchanged")
        self.assertTrue(result["coverage"]["complete"])
        self.assertEqual(result["context"]["accepted_source_status"], "unknown")
        self.assertFalse(result["errors"])

    def test_actual_png_difference_produces_heatmap(self):
        cur, old = self.pair()
        write_images(self.current, cur, color=(20, 30, 40))
        result = self.compare(cur, old)
        self.assertEqual(result["verdict"], "image bytes changed")
        self.assertEqual(result["frames"][0]["changed_pixels"], 4)
        self.assertTrue((self.current / result["frames"][0]["diff"]).is_file())

    def test_identical_pixels_cannot_hide_sampled_state_change(self):
        cur, old = self.pair()
        cur["frames"][0]["height_m"] = 1.0
        result = self.compare(cur, old)
        self.assertEqual(result["verdict"], "sampled state changed")
        self.assertEqual(result["frames"][0]["state_changes"]["height_m"], 1.0)

    def test_no_or_partial_overlap_never_claims_unchanged(self):
        cur, old = self.pair(manifest([frame(time=1)]), manifest([frame(time=0)]))
        result = self.compare(cur, old)
        self.assertEqual(result["coverage"]["matched"], 0)
        self.assertIn("not comparable", result["verdict"])
        self.assertEqual({r["status"] for r in result["frames"]}, {"new frame", "removed frame"})
        cur, old = self.pair(manifest([frame()]), manifest([frame(), frame(time=1)]))
        result = self.compare(cur, old)
        self.assertEqual(result["verdict"], "incomplete frame coverage")
        self.assertEqual(result["coverage"]["previous_only"], [{"view": "pilot", "t_s": 1}])

    def test_duplicate_frame_identity_is_ambiguous(self):
        cur, old = self.pair()
        cur["frames"].append(copy.deepcopy(cur["frames"][0]))
        result = self.compare(cur, old)
        self.assertEqual(result["verdict"], "invalid comparison evidence")
        self.assertIn("duplicate frame", result["errors"][0])

    def test_context_changes_and_invalid_source_claims_are_explicit(self):
        cur, old = self.pair()
        cur["aircraft"] = "other-aircraft"
        result = self.compare(cur, old)
        self.assertEqual(result["verdict"], "declared context changed")
        self.assertIn("aircraft", result["context"]["changes"])
        for data in (cur, old):
            data.update(aircraft_input_sha256="oops", power_source_mode="unknown")
        self.assertEqual(self.compare(cur, old)["context"]["accepted_source_status"], "unknown")
        for data in (cur, old):
            data.update(aircraft_input_sha256="a" * 64, power_source_mode="pack")
        self.assertEqual(self.compare(cur, old)["context"]["accepted_source_status"], "declared same")

    def test_missing_or_tampered_images_cannot_pass_hash_shortcut(self):
        for kind in ("missing", "tampered"):
            with self.subTest(kind=kind):
                cur, old = self.pair()
                path = self.current / cur["frames"][0]["image"]
                if kind == "missing":
                    path.unlink()
                else:
                    path.write_bytes(b"not the recorded image")
                result = self.compare(cur, old)
                self.assertEqual(result["verdict"], "invalid comparison evidence")
                self.assertTrue(result["errors"])

    def test_image_dimension_mismatch_is_reported_without_broadcast_crash(self):
        cur, old = self.pair()
        write_images(self.current, cur, size=(3, 2))
        result = self.compare(cur, old)
        self.assertEqual(result["frames"][0]["status"], "incompatible image dimensions")
        self.assertTrue(result["errors"])

    def test_history_distinguishes_missing_partial_malformed_and_complete_receipts(self):
        good = [{"check": name, "ok": True} for name in REPORT.SYNC_CHECK_NAMES]
        failed = copy.deepcopy(good)
        failed[0]["ok"] = False
        nonboolean = copy.deepcopy(good)
        nonboolean[0]["ok"] = "false"
        cases = {"missing": (None, "UNKNOWN"), "empty": ([], "UNKNOWN"), "partial": (good[:1], "UNKNOWN"),
                 "duplicate": (good + [good[0]], "UNKNOWN"), "malformed": ('{"bad":', "UNKNOWN"),
                 "nonboolean": (nonboolean, "UNKNOWN"), "complete": (good, "pass"), "failed": (failed, "FAIL")}
        history = self.root / "history"
        history.mkdir()
        for name, (receipt, status) in cases.items():
            run = history / name
            run.mkdir()
            (run / "scenario.json").write_text(json.dumps(manifest([frame()])))
            if receipt is not None:
                (run / "sync.json").write_text(receipt if isinstance(receipt, str) else json.dumps(receipt))
            self.assertEqual(REPORT.sync_receipt_status(run / "sync.json")[0], status)
        with contextlib.redirect_stdout(io.StringIO()):
            REPORT.history_index(history)
        output = (history / "index.html").read_text()
        self.assertIn("missing · <span class=unknown>sync UNKNOWN", output)
        self.assertIn("complete · <span class=ok>sync pass", output)
        self.assertIn("legacy observation coverage unverified", output)

    def test_sync_checks_require_actual_observations(self):
        data = manifest([frame(), frame(time=2)])
        data["frames"][1]["rpm"] = 2400.0
        checks = {c["check"]: c for c in REPORT.sync_checks(data)}
        for name in ("all cameras of an instant share one state", "propeller angle follows the rpm",
                     "shadow under the airplane while rolling"):
            self.assertFalse(checks[name]["ok"])
            self.assertEqual(checks[name]["observations"], 0)
            self.assertEqual(REPORT.sync_check_outcome(checks[name]), "UNKNOWN")
        empty = REPORT.sync_checks(manifest([]))
        self.assertFalse(any(c["ok"] for c in empty))

    def test_observed_failure_takes_precedence_over_unknown_coverage(self):
        receipt = [{"check": name, "ok": True, "observations": 1} for name in REPORT.SYNC_CHECK_NAMES]
        receipt[0].update(ok=False, observations=0)
        path = self.root / "sync.json"
        path.write_text(json.dumps(receipt))
        self.assertEqual(REPORT.sync_receipt_status(path)[0], "UNKNOWN")
        receipt[1]["ok"] = False
        path.write_text(json.dumps(receipt))
        self.assertEqual(REPORT.sync_receipt_status(path)[0], "FAIL")

    def test_observed_sync_positive_control_and_html_keep_coverage(self):
        data = manifest([frame(), frame("chase"), frame(time=1), frame(time=2)])
        checks = REPORT.sync_checks(data)
        self.assertEqual({c["check"] for c in checks}, set(REPORT.SYNC_CHECK_NAMES))
        self.assertTrue(all(c["ok"] and c["observations"] > 0 for c in checks))
        cur, old = self.pair(data)
        comparison = self.compare(cur, old)
        REPORT.write_html(self.current, cur, {}, checks, comparison)
        html = (self.current / "report.html").read_text()
        self.assertIn("Accepted source identity: unknown", html)
        self.assertIn("matched", html)


if __name__ == "__main__":
    unittest.main()
