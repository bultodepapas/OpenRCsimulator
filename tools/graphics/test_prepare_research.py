"""Portable tests for isolated graphics research preparation."""

from __future__ import annotations

import contextlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

try:
    from . import launch, prepare_research
except ImportError:
    import launch  # type: ignore[no-redef]
    import prepare_research  # type: ignore[no-redef]


class PrepareResearchTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="openrc-research-prep-")
        self.root = Path(self.temporary.name)
        self.source = self.root / "source"
        self.app = self.source / "app"
        (self.app / "render").mkdir(parents=True)
        (self.app / "assets").mkdir()
        (self.source / "assets").mkdir()
        self.project = self.app / "project.godot"
        self.project.write_bytes(
            b'config_version=5\n[application]\nconfig/name="OpenRC Simulator"\n'
            b'[rendering]\nlights_and_shadows/multi_bounce_occlusion/enabled=true\n'
        )
        (self.app / "render" / "high_graphics_profile.gd").write_bytes(
            (launch.APP_DIR / "render" / "high_graphics_profile.gd").read_bytes()
        )
        (self.app / "main.gd").write_text("# fixture\n", encoding="utf-8")
        (self.app / "assets" / "runtime.txt").write_text("runtime asset\n", encoding="utf-8")
        (self.source / "assets" / "author.txt").write_text("author asset\n", encoding="utf-8")
        for name in (".godot", ".tools", "captures", "tmp"):
            folder = self.app / name
            folder.mkdir()
            (folder / "excluded.txt").write_text(name, encoding="utf-8")
        self.destination = self.root / "output" / "trial"

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def prepare_or_skip_symlink(self) -> dict:
        try:
            return prepare_research.prepare(self.source, self.destination)
        except prepare_research.PreparationError as error:
            if "cannot create the sibling assets symlink" in str(error):
                self.skipTest(str(error))
            raise

    def test_prepares_verified_private_copy_and_receipt_without_touching_source(self) -> None:
        original = self.project.read_bytes()
        receipt = self.prepare_or_skip_symlink()
        copied_app = self.destination / "app"
        copied_project = (copied_app / "project.godot").read_bytes()
        self.assertEqual(self.project.read_bytes(), original)
        self.assertNotEqual(copied_project, original)
        self.assertIn(b'config/name="OpenRC-Research-', copied_project)
        self.assertIn(prepare_research._MULTI_BOUNCE_OFF, copied_project)
        self.assertNotIn(prepare_research._MULTI_BOUNCE_ON, copied_project)
        for name in (".godot", ".tools", "captures", "tmp"):
            self.assertFalse((copied_app / name).exists())
        self.assertEqual((copied_app / "assets" / "runtime.txt").read_text(), "runtime asset\n")
        self.assertTrue((self.destination / "assets").is_symlink())
        self.assertEqual((self.destination / "assets").resolve(), (self.source / "assets").resolve())
        self.assertEqual((self.destination / "assets" / "author.txt").read_text(), "author asset\n")
        self.assertEqual(receipt["source"]["copied_app_manifest_sha256"],
                         receipt["destination"]["copy_manifest_sha256_before_project_edits"])
        self.assertEqual(receipt["source"]["project_sha256"], prepare_research._sha256(self.project))
        self.assertEqual(receipt["destination"]["project_sha256"], prepare_research._sha256(copied_app / "project.godot"))
        self.assertEqual(receipt, json.loads((self.destination / prepare_research.RECEIPT).read_text(encoding="utf-8")))
        self.assertTrue(receipt["complete"])
        self.assertIn("linked, not copied or hashed", receipt["scope"])
        validated = launch._research_project(str(copied_app), cwd=self.root)
        self.assertEqual(validated["project_name"], receipt["destination"]["project_name"])

    def test_existing_destination_and_source_subdirectories_are_never_overwritten(self) -> None:
        self.destination.mkdir(parents=True)
        sentinel = self.destination / "sentinel"
        sentinel.write_text("keep", encoding="utf-8")
        for target in (self.destination, self.source, self.app / "new-trial", self.source / "assets" / "new-trial"):
            with self.subTest(target=target), self.assertRaises(prepare_research.PreparationError):
                prepare_research.prepare(self.source, target)
        self.assertEqual(sentinel.read_text(), "keep")
        self.assertFalse((self.app / "new-trial").exists())
        self.assertFalse((self.source / "assets" / "new-trial").exists())

    def test_refuses_unsafe_project_before_creating_destination(self) -> None:
        original = self.project.read_bytes()
        variants = (
            original.replace(b"OpenRC Simulator", b"Other App"),
            original.replace(b"[rendering]", b"config/use_custom_user_dir=true\n[rendering]"),
            original.replace(b"[rendering]", b'config/name.macos="OpenRC Simulator"\n[rendering]'),
            original.replace(b"[rendering]", b'config/project_settings_override="user://settings.cfg"\n[rendering]'),
            original.replace(prepare_research._MULTI_BOUNCE_ON, b"lights_and_shadows/other=true"),
        )
        for value in variants:
            self.project.write_bytes(value)
            with self.subTest(project=value), self.assertRaises(prepare_research.PreparationError):
                prepare_research.prepare(self.source, self.destination)
            self.assertFalse(self.destination.exists())
        self.project.write_bytes(original)
        (self.app / "override.cfg").write_text("[application]\n", encoding="utf-8")
        with self.assertRaises(prepare_research.PreparationError):
            prepare_research.prepare(self.source, self.destination)
        self.assertFalse(self.destination.exists())

    def test_requires_matching_launcher_profile(self) -> None:
        (self.app / "render" / "high_graphics_profile.gd").write_text("# stale\n", encoding="utf-8")
        with self.assertRaisesRegex(prepare_research.PreparationError, "differs from this launcher"):
            prepare_research.prepare(self.source, self.destination)
        self.assertFalse(self.destination.exists())

    def test_symlink_failure_retains_partial_directory_without_receipt(self) -> None:
        original = self.project.read_bytes()
        with mock.patch.object(Path, "symlink_to", side_effect=OSError("symlink privilege unavailable")):
            with self.assertRaisesRegex(prepare_research.PreparationError, "partial destination retained") as error:
                prepare_research.prepare(self.source, self.destination)
        self.assertIn("symlink", str(error.exception))
        self.assertTrue(self.destination.is_dir())
        self.assertFalse((self.destination / prepare_research.RECEIPT).exists())
        self.assertEqual(self.project.read_bytes(), original)

    def test_copy_failure_is_reported_without_removing_partial_data(self) -> None:
        def failed_copy(_src: Path, dst: Path) -> None:
            Path(dst).write_text("partial", encoding="utf-8")
            raise OSError("simulated disk failure")

        with mock.patch.object(prepare_research.shutil, "copy2", side_effect=failed_copy):
            try:
                with self.assertRaisesRegex(prepare_research.PreparationError, "partial destination retained") as error:
                    prepare_research.prepare(self.source, self.destination)
            except AssertionError:
                # Hosts without symlink privileges cannot reach the copy path.
                raise
        self.assertTrue(self.destination.is_dir())
        self.assertFalse((self.destination / prepare_research.RECEIPT).exists())
        if "cannot create the sibling assets symlink" in str(error.exception):
            self.skipTest(str(error.exception))
        self.assertIn("simulated disk failure", str(error.exception))
        self.assertTrue(any(path.is_file() for path in (self.destination / "app").rglob("*")))

    def test_source_change_during_copy_fails_closed(self) -> None:
        actual_copy = prepare_research.shutil.copy2
        changed = False

        def changing_copy(src: Path, dst: Path) -> str:
            nonlocal changed
            result = actual_copy(src, dst)
            if Path(src).name == "main.gd" and not changed:
                Path(src).write_text("# changed during copy\n", encoding="utf-8")
                changed = True
            return str(result)

        with mock.patch.object(prepare_research.shutil, "copy2", side_effect=changing_copy):
            with self.assertRaises(prepare_research.PreparationError) as error:
                prepare_research.prepare(self.source, self.destination)
        if "cannot create the sibling assets symlink" in str(error.exception):
            self.skipTest(str(error.exception))
        self.assertIn("source changed or copy verification failed", str(error.exception))
        self.assertFalse((self.destination / prepare_research.RECEIPT).exists())

    def test_cli_failure_is_nonzero_and_leaves_existing_contents(self) -> None:
        self.destination.mkdir(parents=True)
        (self.destination / "sentinel").write_text("keep", encoding="utf-8")
        errors = io.StringIO()
        with contextlib.redirect_stderr(errors):
            code = prepare_research.main(["--source", str(self.source), "--dest", str(self.destination)])
        self.assertEqual(code, 1)
        self.assertIn("already exists", errors.getvalue())
        self.assertEqual((self.destination / "sentinel").read_text(), "keep")


if __name__ == "__main__":
    unittest.main()
