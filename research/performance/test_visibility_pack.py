from __future__ import annotations

import hashlib
import json
import tempfile
import unittest
from pathlib import Path

from PIL import Image

try:
    from .visibility_pack import package_capture, validate_capture
except ImportError:  # Also support direct execution from this directory.
    from visibility_pack import package_capture, validate_capture


CAMERA_TRANSFORM = [1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0]


def write_capture(root: Path, colors: list[tuple[int, int, int, int]], *, fps: int = 30) -> dict:
    frames_dir = root / "frames"
    frames_dir.mkdir(parents=True, exist_ok=True)
    frames = []
    for index, color in enumerate(colors):
        relative_png = f"frames/frame-{index:04d}.png"
        png_path = root / relative_png
        Image.new("RGBA", (8, 6), color).save(png_path, format="PNG")
        frames.append({
            "index": index,
            "time_s": index / fps,
            "png": relative_png,
            "sha256": hashlib.sha256(png_path.read_bytes()).hexdigest(),
            "position_ned": [float(index), 1.0, 2.0],
            "yaw_deg": float(index * 2),
            "pitch_deg": 1.5,
            "roll_deg": -0.5,
            "distance_m": 20.0 + index,
            "fov_deg": 75.0,
            "projected_span_px": 35.0 + index,
            "cg_screen_px": [4.0, 3.0],
            "camera_transform": CAMERA_TRANSFORM,
        })
    manifest = {
        "schema_version": 1,
        "fps": fps,
        "width": 8,
        "height": 6,
        "frame_count": len(colors),
        "source_commit": "a" * 40,
        "case_id": "synthetic-moving-forward",
        "aircraft_id": "test-aircraft",
        "view": "pilot",
        "auto_zoom": True,
        "manual_zoom": 1.0,
        "route": "synthetic-visibility-motion",
        "background": {"requested_label": "not validated"},
        "frames": frames,
    }
    write_manifest(root, manifest)
    return manifest


def write_manifest(root: Path, manifest: dict) -> None:
    (root / "manifest.json").write_text(json.dumps(manifest, allow_nan=True, indent=2), encoding="utf-8")


class VisibilityCaptureValidationTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name) / "capture"
        self.root.mkdir()

    def tearDown(self):
        self.temp_dir.cleanup()

    def valid_capture(self, colors=None):
        if colors is None:
            colors = [(255, 0, 0, 255), (0, 0, 255, 255)]
        return write_capture(self.root, colors)

    def test_moving_capture_validates_with_configured_count(self):
        self.valid_capture()

        errors, details = validate_capture(self.root, expected_frame_count=2)

        self.assertEqual(errors, [])
        self.assertIsNotNone(details)
        self.assertEqual(details["frame_count"], 2)
        self.assertEqual(len(details["pixel_sha256"]), 2)

    def test_manifest_frame_hash_mismatch_is_rejected(self):
        manifest = self.valid_capture()
        png_path = self.root / manifest["frames"][0]["png"]
        Image.new("RGBA", (8, 6), (3, 5, 7, 255)).save(png_path, format="PNG")

        errors, _ = validate_capture(self.root, expected_frame_count=2)

        self.assertTrue(any("sha256 does not match" in error for error in errors))

    def test_absolute_and_parent_path_forms_are_rejected(self):
        for unsafe_path in ("../outside.png", r"..\outside.png", r"C:\outside.png", r"\\server\share\frame.png"):
            with self.subTest(path=unsafe_path):
                manifest = self.valid_capture()
                manifest["frames"][0]["png"] = unsafe_path
                write_manifest(self.root, manifest)

                errors, _ = validate_capture(self.root, expected_frame_count=2)

                self.assertTrue(any("relative path" in error or "stay inside" in error for error in errors))
                for png_path in (self.root / "frames").glob("*.png"):
                    png_path.unlink()
                (self.root / "manifest.json").unlink()

    def test_missing_frame_file_is_rejected(self):
        manifest = self.valid_capture()
        (self.root / manifest["frames"][1]["png"]).unlink()

        errors, _ = validate_capture(self.root, expected_frame_count=2)

        self.assertTrue(any("missing or escapes" in error for error in errors))

    def test_non_finite_json_value_is_rejected(self):
        manifest = self.valid_capture()
        manifest["frames"][0]["yaw_deg"] = float("inf")
        write_manifest(self.root, manifest)

        errors, _ = validate_capture(self.root, expected_frame_count=2)

        self.assertTrue(any("non-finite JSON value" in error for error in errors))

    def test_frame_time_must_match_index_over_fps(self):
        manifest = self.valid_capture()
        manifest["frames"][1]["time_s"] = 0.03
        write_manifest(self.root, manifest)

        errors, _ = validate_capture(self.root, expected_frame_count=2)

        self.assertTrue(any("time_s must equal index / fps" in error for error in errors))

    def test_manifest_dimensions_must_match_png_dimensions(self):
        manifest = self.valid_capture()
        manifest["width"] = 9
        write_manifest(self.root, manifest)

        errors, _ = validate_capture(self.root, expected_frame_count=2)

        self.assertTrue(any("dimensions" in error and "do not match manifest" in error for error in errors))

    def test_distance_fov_and_projected_span_must_be_in_valid_ranges(self):
        mutations = (
            ("distance_m", 0.0, "distance_m must be positive"),
            ("distance_m", -1.0, "distance_m must be positive"),
            ("fov_deg", 0.0, "fov_deg must be greater than 0"),
            ("fov_deg", -1.0, "fov_deg must be greater than 0"),
            ("fov_deg", 180.0, "fov_deg must be greater than 0"),
            ("projected_span_px", 0.0, "projected_span_px must be positive"),
            ("projected_span_px", -1.0, "projected_span_px must be positive"),
        )
        for field, value, expected_error in mutations:
            with self.subTest(field=field, value=value):
                manifest = self.valid_capture()
                manifest["frames"][0][field] = value
                write_manifest(self.root, manifest)

                errors, _ = validate_capture(self.root, expected_frame_count=2)

                self.assertTrue(any(expected_error in error for error in errors))

    def test_cg_screen_center_must_be_inside_image_bounds(self):
        for center in ([-0.01, 3.0], [8.0, 3.0], [4.0, -0.01], [4.0, 6.0]):
            with self.subTest(center=center):
                manifest = self.valid_capture()
                manifest["frames"][0]["cg_screen_px"] = center
                write_manifest(self.root, manifest)

                errors, _ = validate_capture(self.root, expected_frame_count=2)

                self.assertTrue(any("cg_screen_px must be inside image bounds" in error for error in errors))

    def test_optional_bbox_accepts_edge_tolerance_and_rejects_invalid_bounds(self):
        manifest = self.valid_capture()
        manifest["frames"][0]["bbox_px"] = [-0.0005, 0.0, 8.0, 6.0]
        write_manifest(self.root, manifest)

        errors, _ = validate_capture(self.root, expected_frame_count=2)

        self.assertEqual(errors, [])

        mutations = (
            ([1.0, 1.0, 0.0, 2.0], "width and height must be positive"),
            ([1.0, 1.0, 2.0, 0.0], "width and height must be positive"),
            ([-0.002, 0.0, 1.0, 1.0], "must be inside image bounds"),
            ([7.1, 1.0, 1.0, 1.0], "must be inside image bounds"),
            ([1.0, 1.0, 2.0], "must contain exactly 4 numbers"),
            ([1.0, 1.0, float("inf"), 1.0], "non-finite JSON value"),
        )
        for bbox, expected_error in mutations:
            with self.subTest(bbox=bbox):
                manifest = self.valid_capture()
                manifest["frames"][0]["bbox_px"] = bbox
                write_manifest(self.root, manifest)

                errors, _ = validate_capture(self.root, expected_frame_count=2)

                self.assertTrue(any(expected_error in error for error in errors))

    def test_identical_frames_are_rejected_for_lack_of_pixel_motion(self):
        self.valid_capture([(90, 80, 70, 255)] * 3)

        errors, _ = validate_capture(self.root, expected_frame_count=3)

        self.assertTrue(any("no actual pixel motion" in error for error in errors))


class VisibilityApngPackagingTests(unittest.TestCase):
    def test_moving_capture_packages_as_exact_apng_and_keeps_duplicate_frame(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir) / "capture"
            root.mkdir()
            colors = [
                (255, 0, 0, 255),
                (255, 0, 0, 255),  # Adjacent identical frames must not be merged.
                (0, 0, 255, 0),
                (0, 255, 0, 128),
            ]
            manifest = write_capture(root, colors)
            output = Path(temp_dir) / "blind-pack"

            summary = package_capture(root, output, expected_frame_count=4)

            clip_path = output / "clip.png"
            self.assertTrue(clip_path.is_file())
            self.assertTrue((output / "summary.json").is_file())
            self.assertEqual(summary["frame_count"], 4)
            self.assertEqual(summary["fps"], 30)
            self.assertEqual(summary["duration_ms"], 133)
            self.assertEqual(len(summary["frame_hashes"]), 4)
            self.assertEqual(summary["frame_hashes"][0], summary["frame_hashes"][1])
            self.assertNotIn("case_id", summary)
            self.assertNotIn("aircraft_id", summary)
            self.assertIn("no CPU or render performance result", summary["scope"])
            self.assertEqual(summary["output_sha256"], hashlib.sha256(clip_path.read_bytes()).hexdigest())

            with Image.open(clip_path) as clip:
                self.assertEqual(clip.format, "PNG")
                self.assertTrue(clip.is_animated)
                self.assertEqual(clip.n_frames, len(manifest["frames"]))
                actual_durations = []
                for index, color in enumerate(colors):
                    clip.seek(index)
                    self.assertEqual(clip.convert("RGBA").getpixel((0, 0)), color)
                    actual_durations.append(clip.info["duration"])
                self.assertEqual(actual_durations, [33, 34, 33, 33])

    def test_packager_refuses_an_existing_output_directory(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir) / "capture"
            root.mkdir()
            write_capture(root, [(255, 0, 0, 255), (0, 0, 255, 255)])
            output = Path(temp_dir) / "package"
            output.mkdir()

            with self.assertRaisesRegex(ValueError, "already exists"):
                package_capture(root, output, expected_frame_count=2)


if __name__ == "__main__":
    unittest.main()
