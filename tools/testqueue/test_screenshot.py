"""Aircraft screenshot admission and receipt checks without launching Godot."""
import hashlib
import json
import os
from pathlib import Path
import struct
import tempfile
import unittest
from unittest import mock
import zlib

from tools.testqueue import adapter


def png(width=1920, height=1080):
    def chunk(kind, value):
        return struct.pack(">I", len(value)) + kind + value + struct.pack(">I", zlib.crc32(kind + value) & 0xffffffff)

    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    row = b"\x00" + bytes(width * 3)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(row * height)) + chunk(b"IEND", b"")


class ScreenshotAdapterTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.image = png()

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="openrc-screenshot-")
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.root = self.directory / "source"
        self.script = self.root / "tools/readme/capture_aircraft.gd"
        self.script.parent.mkdir(parents=True)
        self.script.write_text("# trusted fixture\n")
        self.commit = "a" * 40
        self.options = {"aircraft": "ugly-stik", "headless": False, "argv": [], "timeout": 90}
        self.identity = {"commit": self.commit, "capture_tool_sha256": hashlib.sha256(self.script.read_bytes()).hexdigest()}
        self.folder = self.directory / "screenshots"
        self.folder.mkdir()
        self.image_path = self.folder / "ugly-stik.png"
        self.image_path.write_bytes(self.image)
        self.manifest = {"format": "openrc-readme-renders v2", "source_start": self.identity,
                         "source_end": dict(self.identity), "source_changed_during_capture": False,
                         "stills_size": [1920, 1080], "frame_count": 0,
                         "vehicles": [{"id": "ugly-stik", "still": "ugly-stik.png", "frames": 0,
                                       "still_sha256": hashlib.sha256(self.image).hexdigest()}]}
        self.save_manifest()

    def save_manifest(self):
        (self.folder / "manifest.json").write_text(json.dumps(self.manifest))

    def validate(self):
        return adapter.validate_screenshot(self.directory, self.root, "ugly-stik", self.commit)

    def test_checked_command_and_verified_artifact(self):
        request = {"preset": "aircraft-screenshot", "options": self.options, "manifest": {"commit": self.commit}}
        (self.directory / "request.json").write_text(json.dumps(request))
        (self.directory / "manifest.json").write_text(json.dumps({"import_files": ["prepared"]}))
        checked = {"ok": True, "complete": True, "report": "checked/report.json"}
        with mock.patch.object(adapter, "ROOT", self.root), mock.patch.object(adapter, "inherited", return_value=True), \
                mock.patch.object(adapter, "prepare_history") as history, mock.patch.dict(os.environ, {"OPENRC_GODOT": "engine.exe"}), \
                mock.patch("tools.godot.run_checked.run_checked", return_value=checked) as run:
            self.assertEqual(adapter.main(self.directory), 0)
        history.assert_called_once()
        command = run.call_args.args[0]
        self.assertEqual(command, ["engine.exe", "--path", str(self.root / "app"), "--audio-driver", "Dummy",
                                   "--rendering-driver", "opengl3", "--resolution", "1920x1080",
                                   "--script", str(self.script), "--", "--stills-only", "--aircraft=ugly-stik",
                                   "--out-dir=" + str(self.folder)])
        self.assertEqual(run.call_args.kwargs["required"], ["README_RENDER_OK: 1 vehicles, 0 animation frames"])
        verdict = json.loads((self.directory / "verdict.json").read_text())
        self.assertTrue(verdict["ok"] and verdict["complete"])
        self.assertEqual(verdict["checked"], checked)
        self.assertEqual(verdict["evidence"]["still_sha256"], hashlib.sha256(self.image).hexdigest())

    def test_manifest_mismatch_or_missing_artifacts_fail_closed(self):
        for mutate in (
            lambda m: m.update(source_end={"commit": "b" * 40}),
            lambda m: m.update(source_changed_during_capture=True),
            lambda m: m.update(stills_size=[1280, 720]),
            lambda m: m.update(frame_count=1),
            lambda m: m["vehicles"][0].update(id="other"),
            lambda m: m["vehicles"][0].update(still="../ugly-stik.png"),
            lambda m: m["vehicles"][0].update(frames=1),
            lambda m: m["vehicles"].append(dict(m["vehicles"][0])),
        ):
            with self.subTest(mutate=mutate):
                original = json.loads(json.dumps(self.manifest))
                mutate(self.manifest)
                self.save_manifest()
                with self.assertRaises(ValueError):
                    self.validate()
                self.manifest = original
        self.save_manifest()
        self.image_path.unlink()
        with self.assertRaises(ValueError):
            self.validate()

    def test_image_checksum_structure_and_dimensions_are_checked(self):
        self.image_path.write_bytes(self.image + b"tamper")
        with self.assertRaises(ValueError):
            self.validate()
        for invalid in (self.image + b"tamper", png(1, 1), b"not a PNG"):
            with self.subTest(size=len(invalid)):
                self.image_path.write_bytes(invalid)
                self.manifest["vehicles"][0]["still_sha256"] = hashlib.sha256(invalid).hexdigest()
                self.save_manifest()
                with self.assertRaises(ValueError):
                    self.validate()

    def test_missing_completion_marker_cannot_pass(self):
        (self.directory / "request.json").write_text(json.dumps({"preset": "aircraft-screenshot", "options": self.options,
                                                                  "manifest": {"commit": self.commit}}))
        (self.directory / "manifest.json").write_text(json.dumps({"import_files": ["prepared"]}))
        with mock.patch.object(adapter, "ROOT", self.root), mock.patch.object(adapter, "inherited", return_value=True), \
                mock.patch.object(adapter, "prepare_history"), mock.patch.dict(os.environ, {"OPENRC_GODOT": "engine.exe"}), \
                mock.patch("tools.godot.run_checked.run_checked", return_value={"ok": False, "complete": True}):
            self.assertNotEqual(adapter.main(self.directory), 0)
        self.assertFalse(json.loads((self.directory / "verdict.json").read_text())["ok"])


if __name__ == "__main__":
    unittest.main()
