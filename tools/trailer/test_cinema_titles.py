#!/usr/bin/env python3
"""Focused title-graphics checks; no simulator capture or full film render."""
import hashlib
import json
import shutil
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import cinema_titles as ct
from PIL import Image, ImageDraw, features


def cue(**overrides):
    data = {
        "id": "test-title", "role": "headline", "lines": ["EVERY INPUT"],
        "in_frame": 10, "out_frame": 50, "x": 200, "y": 200, "align": "left",
        "size": 96, "tracking": 4, "fade_in_frames": 6, "fade_out_frames": 4,
    }
    data.update(overrides)
    return data


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def max_alpha(image):
    return image.getchannel("A").getextrema()[1]


class CinemaCueTests(unittest.TestCase):
    def test_half_open_times_and_fade_boundaries(self):
        title = ct.CinemaCue(cue())
        self.assertEqual(title.frame(10).mode, "RGBA")
        self.assertEqual(title.frame(10).size, (1920, 1080))
        self.assertIsNone(title.frame(9).getchannel("A").getbbox())
        self.assertEqual(max_alpha(title.frame(10)), 0)
        self.assertGreater(max_alpha(title.frame(11)), 0)
        self.assertLess(max_alpha(title.frame(11)), 255)
        self.assertEqual(max_alpha(title.frame(16)), 255)
        self.assertEqual(max_alpha(title.frame(45)), 255)
        self.assertLess(max_alpha(title.frame(48)), 255)
        self.assertEqual(max_alpha(title.frame(49)), 0)
        self.assertEqual(max_alpha(title.frame(50)), 0)

    def test_disclosure_remains_opaque_at_both_included_boundaries(self):
        label = ct.CinemaCue(cue(role="label", lines=["PRESENTATION ONLY"], size=32,
                                 in_frame=100, out_frame=104,
                                 fade_in_frames=0, fade_out_frames=0))
        first, last = label.frame(100), label.frame(103)
        self.assertEqual(max_alpha(first), 255)
        self.assertEqual(first.tobytes(), last.tobytes())
        self.assertEqual(max_alpha(label.frame(104)), 0)

    def test_label_uses_warm_ink_and_shadow_against_bright_background(self):
        label = ct.CinemaCue(cue(role="label", lines=["CLEAR LABEL"], size=32,
                                 fade_in_frames=0, fade_out_frames=0, shadow_alpha=140))
        image = label.frame(10)
        components = iter(image.crop((190, 190, 600, 270)).tobytes())
        pixels = list(zip(components, components, components, components))
        self.assertIn((242, 239, 231, 255), pixels)
        self.assertTrue(any(r < 15 and g < 15 and b < 15 and a > 0 for r, g, b, a in pixels))
        backdrop = Image.new("RGBA", image.size, "white")
        backdrop.alpha_composite(image)
        self.assertLess(backdrop.crop((190, 190, 600, 270)).convert("L").getextrema()[0], 242)

    def test_tracking_expands_visible_ink_and_three_lines_are_allowed(self):
        plain = ct.CinemaCue(cue(lines=["AV"], tracking=0))
        tracked = ct.CinemaCue(cue(lines=["AV"], tracking=12))
        width = lambda item: item.ink_boxes[0][2] - item.ink_boxes[0][0]
        self.assertGreaterEqual(width(tracked) - width(plain), 10)
        self.assertLessEqual(width(tracked) - width(plain), 14)
        # Independent Pillow whole-string draw: with no added tracking, the
        # visible width should retain the same A/V pair kerning.
        face = ct._font(96, "headline")
        reference = Image.new("L", (512, 256))
        feature_flags = ["-liga", "-clig"] if features.check_feature("raqm") else None
        ImageDraw.Draw(reference).text((20, 20), "AV", font=face, fill=255, features=feature_flags)
        box = reference.getbbox()
        self.assertLessEqual(abs(width(plain) - (box[2] - box[0])), 1)
        endcard = ct.CinemaCue(cue(role="endcard", lines=["OPENRC", "PLAY FREE", "OPENRC.SIM"],
                                    align="center", x=960, y=200))
        self.assertEqual(len(endcard.ink_boxes), 3)
        self.assertTrue(all(96 <= a < c <= 1824 and 80 <= b < d <= 1000
                            for a, b, c, d in endcard.ink_boxes))

    def test_invalid_values_and_unsafe_motion_are_rejected(self):
        invalid = [
            {"x": float("nan")}, {"tracking": float("inf")}, {"x": True}, {"x": 10**1000},
            {"in_frame": 10.0}, {"out_frame": 10}, {"align": "LEFT"},
            {"role": "caption"}, {"lines": []}, {"lines": [" "]},
            {"lines": ["one\ntwo"]}, {"lines": ["OPENRC 💥"]}, {"size": 0}, {"color": "#oops"},
            {"fade_in_frames": 31, "fade_out_frames": 9},
            {"y": 950, "drift_px": 80},
            {"x": 96, "size": 240, "lines": ["W" * 40]},
            {"fade_otu_frames": 12},
        ]
        for values in invalid:
            with self.subTest(values=values), self.assertRaises(ValueError):
                ct.validate_cue(cue(**values))


class SequenceTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)

    def test_global_phase_is_continuous_across_separate_shots(self):
        items = [cue()]
        ct.render_sequence(self.root / "whole", items, 12, 10)
        ct.render_sequence(self.root / "part-a", items, 12, 5)
        ct.render_sequence(self.root / "part-b", items, 17, 5)
        for index in range(10):
            separate = self.root / ("part-a" if index < 5 else "part-b") / f"{index % 5:05d}.png"
            self.assertEqual(digest(self.root / "whole" / f"{index:05d}.png"), digest(separate))

    def test_collision_rejected_before_directory_reservation(self):
        first = cue()
        overlap = cue(id="other", lines=["OTHER"], in_frame=20, out_frame=60)
        target = self.root / "collision"
        with self.assertRaisesRegex(ValueError, "overlap"):
            ct.render_sequence(target, [first, overlap], 0, 1)
        self.assertFalse(target.exists())
        # The same ink position is allowed when cue times only touch.
        adjacent = cue(id="other", lines=["OTHER"], in_frame=50, out_frame=90)
        self.assertEqual(ct.render_sequence(self.root / "adjacent", [first, adjacent], 49, 2), 2)

    def test_fresh_directory_static_reuse_and_copy_fallback(self):
        label = cue(role="label", size=32, lines=["PRESENTATION ONLY"],
                    fade_in_frames=0, fade_out_frames=0)
        target = self.root / "linked"
        with mock.patch.object(ct.os, "link", wraps=ct.os.link) as link:
            ct.render_sequence(target, [label], 10, 3)
        self.assertEqual(link.call_count, 2)
        self.assertEqual(digest(target / "00000.png"), digest(target / "00002.png"))
        before = digest(target / "00000.png")
        with self.assertRaises(FileExistsError):
            ct.render_sequence(target, [label], 10, 1)
        self.assertEqual(before, digest(target / "00000.png"))
        fallback = self.root / "fallback"
        with mock.patch.object(ct.os, "link", side_effect=OSError("links unavailable")):
            ct.render_sequence(fallback, [label], 10, 2)
        self.assertEqual(digest(fallback / "00000.png"), digest(fallback / "00001.png"))

    def test_duplicate_ids_are_rejected(self):
        with self.assertRaisesRegex(ValueError, "unique"):
            ct.render_sequence(self.root / "duplicate", [cue(), cue(in_frame=50, out_frame=90)], 0, 1)


class DependenciesTests(unittest.TestCase):
    def test_identity_checks_fonts_license_and_rendering_libraries(self):
        identity = ct.dependency_identity()
        self.assertEqual(identity["assets"]["BarlowCondensed-SemiBold.ttf"]["sha256"],
                         "7b619d14bc2327509a9ef32b0890f709626f7ecc9ff61191c2a4314c5499d2d9")
        self.assertTrue(identity["pillow"])
        self.assertTrue(identity["freetype"])
        json.dumps(identity)
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "fonts"
            shutil.copytree(ct.FONT_DIR, target)
            (target / "BarlowCondensed-Regular.ttf").write_bytes(b"tampered")
            with self.assertRaisesRegex(ValueError, "digest mismatch"):
                ct.dependency_identity(target)


if __name__ == "__main__":
    unittest.main()
