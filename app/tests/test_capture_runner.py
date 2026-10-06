"""Failure-path and evidence-integrity tests for capture_runner.run_capture."""
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest

from PIL import Image

from capture_runner import run_capture


SCENE = "empty atmosphere fixture"


# The subprocess models the two real capture producers: flight writes a native
# manifest and render log record; UI writes only a PNG and its normal save line.
PRODUCER = r'''
import hashlib
import json
from pathlib import Path
import sys
import time

from PIL import Image

out = Path(sys.argv[1])
mode = sys.argv[2]
scene = sys.argv[3]
manifest = out.with_suffix(".json")

def save_png(size=(1280, 720)):
    Image.new("RGB", size, (32, 96, 160)).save(out, format="PNG")

def write_flight_manifest(image=None, sha=None, capture_scene=None):
    data = {
        "image": image if image is not None else out.name,
        "sha256": sha if sha is not None else hashlib.sha256(out.read_bytes()).hexdigest(),
        "capture_scene": capture_scene if capture_scene is not None else scene,
        "draw_calls": {"visible": 1, "shadow": 0},
        "primitives": {"visible": 2, "shadow": 0},
    }
    if mode == "sky_only":
        data["draw_calls"]["visible"] = 0
        data["primitives"]["visible"] = 0
    manifest.write_text(json.dumps(data))

def flight_log():
    print(f"saved {out} (error 0) draw_calls=1 primitives=2 sun_px=behind "
          "sim_clock=1.5 shadow_px=behind below_px=0,0", flush=True)

if mode == "exit42":
    print("producer exit 42", flush=True)
    sys.exit(42)
if mode == "sleep":
    print("producer waiting", flush=True)
    time.sleep(30)
    sys.exit(0)
if mode == "no_artifacts":
    flight_log()
    sys.exit(0)

if mode == "corrupt_png":
    out.write_bytes(b"not a PNG")
else:
    size = (32, 32) if mode == "wrong_dimensions" else (1280, 720)
    save_png(size)

if mode not in ("missing_manifest", "ui"):
    image = "different.png" if mode == "image_wrong_name" else None
    sha = "0" * 64 if mode == "hash_wrong" else None
    capture_scene = scene + "-wrong" if mode == "scene_wrong" else None
    write_flight_manifest(image=image, sha=sha, capture_scene=capture_scene)
    if mode == "malformed_manifest":
        manifest.write_text("{this is not JSON")

if mode == "ui":
    print(f"saved {out} (error 0)", flush=True)
else:
    flight_log()
    if mode == "exit42_after_save":
        sys.exit(42)
    if mode == "engine_error":
        print("  SHADER ERROR: deliberate capture failure", flush=True)
'''


class CaptureRunnerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.directory = Path(self.temp.name)
        # Spaces exercise argument-list handling without shell quoting.
        self.output = self.directory / "capture with spaces.png"

    def tearDown(self):
        self.temp.cleanup()

    def command(self, mode):
        return [sys.executable, "-c", PRODUCER, str(self.output), mode, SCENE]

    @property
    def manifest_path(self):
        return self.output.with_suffix(".json")

    @property
    def log_path(self):
        return self.output.with_suffix(".log")

    def seed_stale_evidence(self):
        Image.new("RGB", (1280, 720), (250, 0, 250)).save(self.output, format="PNG")
        self.manifest_path.write_text(json.dumps({
            "image": self.output.name, "sha256": hashlib.sha256(self.output.read_bytes()).hexdigest(),
            "capture_scene": SCENE, "draw_calls": {"visible": 1, "shadow": 0},
            "primitives": {"visible": 2, "shadow": 0},
        }))

    def assert_failed_and_clean(self, mode, kind="flight", timeout=60.0):
        with self.assertRaises(RuntimeError):
            run_capture(self.command(mode), self.output, kind, SCENE, timeout=timeout)
        self.assertFalse(self.output.exists(), "failed capture must remove any PNG")
        self.assertFalse(self.manifest_path.exists(), "failed capture must remove any manifest")
        self.assertTrue(self.log_path.is_file(), "failure diagnostics should remain in the log")

    def test_nonzero_exit_cannot_reuse_old_png_or_manifest(self):
        self.seed_stale_evidence()
        self.assert_failed_and_clean("exit42")
        self.assertIn("producer exit 42", self.log_path.read_text())

    def test_nonzero_exit_fails_even_after_writing_valid_artifacts(self):
        self.assert_failed_and_clean("exit42_after_save")

    def test_timeout_cannot_reuse_old_png_or_manifest(self):
        self.seed_stale_evidence()
        self.assert_failed_and_clean("sleep", timeout=0.15)

    def test_zero_exit_without_artifacts_fails_for_both_capture_kinds(self):
        for kind in ("flight", "ui"):
            with self.subTest(kind=kind):
                self.seed_stale_evidence()
                self.assert_failed_and_clean("no_artifacts", kind=kind)

    def test_flight_success_requires_matching_native_manifest_and_capture_log(self):
        result = run_capture(self.command("valid"), self.output, "flight", SCENE)

        self.assertIsInstance(result, dict)
        with Image.open(self.output) as image:
            image.verify()
            self.assertEqual(image.size, (1280, 720))
        manifest = json.loads(self.manifest_path.read_text())
        image_hash = hashlib.sha256(self.output.read_bytes()).hexdigest()
        self.assertEqual(manifest["image"], self.output.name)
        self.assertEqual(manifest["sha256"], image_hash)
        self.assertEqual(manifest["capture_scene"], SCENE)
        self.assertEqual(manifest["draw_calls"], {"visible": 1, "shadow": 0})
        self.assertEqual(manifest["primitives"], {"visible": 2, "shadow": 0})
        expected = (
            f"saved {self.output} (error 0) draw_calls=1 primitives=2 "
            "sun_px=behind sim_clock=1.5 shadow_px=behind below_px=0,0"
        )
        self.assertIn(expected, self.log_path.read_text())

    def test_ui_success_writes_harness_manifest_without_native_counters(self):
        result = run_capture(self.command("ui"), self.output, "ui", SCENE)

        with Image.open(self.output) as image:
            image.verify()
            self.assertEqual(image.size, (1280, 720))
        manifest = json.loads(self.manifest_path.read_text())
        image_hash = hashlib.sha256(self.output.read_bytes()).hexdigest()
        self.assertEqual(result, manifest)
        self.assertEqual(manifest["format"], "openrc-ui-capture v1")
        self.assertEqual(manifest["producer"], "capture_runner")
        self.assertEqual(manifest["image"], self.output.name)
        self.assertEqual(manifest["sha256"], image_hash)
        self.assertEqual(manifest["size"], [1280, 720])
        self.assertEqual(manifest["capture_scene"], SCENE)
        self.assertEqual(manifest["process_exit"], 0)
        self.assertNotIn("draw_calls", manifest)
        self.assertNotIn("primitives", manifest)

    def test_sky_only_capture_can_have_zero_visible_mesh_counters(self):
        result = run_capture(self.command("sky_only"), self.output, "flight", SCENE)
        self.assertEqual(result["draw_calls"]["visible"], 0)
        self.assertEqual(result["primitives"]["visible"], 0)

    def test_flight_missing_manifest_fails(self):
        self.assert_failed_and_clean("missing_manifest")

    def test_flight_malformed_manifest_fails(self):
        self.assert_failed_and_clean("malformed_manifest")

    def test_flight_manifest_hash_mismatch_fails(self):
        self.assert_failed_and_clean("hash_wrong")

    def test_flight_manifest_image_name_mismatch_fails(self):
        self.assert_failed_and_clean("image_wrong_name")

    def test_flight_manifest_scene_mismatch_fails(self):
        self.assert_failed_and_clean("scene_wrong")

    def test_corrupt_png_fails_even_when_manifest_hash_matches(self):
        self.assert_failed_and_clean("corrupt_png")

    def test_wrong_png_dimensions_fails(self):
        self.assert_failed_and_clean("wrong_dimensions")

    def test_indented_engine_error_fails_even_with_exit_zero_and_artifacts(self):
        self.assert_failed_and_clean("engine_error")
        self.assertIn("SHADER ERROR", self.log_path.read_text())


if __name__ == "__main__":
    unittest.main()
