"""Portable tests for isolated graphics research preparation."""

from __future__ import annotations

import contextlib
import ctypes
import errno
import io
import json
import os
from pathlib import Path
import shutil
import stat
import tempfile
from types import SimpleNamespace
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

    def prepare_or_skip_symlink(self, **kwargs) -> dict:
        try:
            return prepare_research.prepare(self.source, self.destination, **kwargs)
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
        self.assertNotEqual(receipt["source"]["copied_app_manifest_sha256"],
                            receipt["destination"]["copied_app_manifest_sha256"])
        self.assertEqual(receipt["source"]["project_sha256"], prepare_research._sha256(self.project))
        self.assertEqual(receipt["destination"]["project_sha256"], prepare_research._sha256(copied_app / "project.godot"))
        self.assertEqual(receipt, json.loads((self.destination / prepare_research.RECEIPT).read_text(encoding="utf-8")))
        self.assertTrue(receipt["complete"])
        self.assertEqual(receipt["copy_mode"], "copy")
        self.assertIn("linked, not copied or hashed", receipt["scope"])
        validated = launch._research_project(str(copied_app), cwd=self.root)
        self.assertEqual(validated["project_name"], receipt["destination"]["project_name"])

    def test_explicit_copy_matches_default_copy(self) -> None:
        second = self.root / "output" / "explicit"
        with mock.patch.object(prepare_research.uuid, "uuid4", return_value=SimpleNamespace(hex="a" * 32)):
            default = self.prepare_or_skip_symlink()
            explicit = prepare_research.prepare(self.source, second, copy_mode="copy")
        self.assertEqual(default["copy_mode"], "copy")
        self.assertEqual(explicit["copy_mode"], "copy")
        self.assertEqual(default["source"], explicit["source"])
        for key in ("project_sha256", "profile_sha256", "copied_app_manifest_sha256",
                    "copy_manifest_sha256_before_project_edits", "project_name"):
            self.assertEqual(default["destination"][key], explicit["destination"][key])

    def test_clone_mode_uses_native_ffi_and_retains_verified_contract(self) -> None:
        copied_paths: list[Path] = []
        nested_cache = self.app / "render" / "__pycache__"
        nested_cache.mkdir()
        (nested_cache / "excluded.pyc").write_bytes(b"excluded cache")

        def fake_clone(source: bytes, destination: bytes, flags: int) -> int:
            self.assertEqual(flags, prepare_research._CLONE_NOFOLLOW | prepare_research._CLONE_NOOWNERCOPY)
            source_path, destination_path = Path(os.fsdecode(source)), Path(os.fsdecode(destination))
            copied_paths.append(source_path.relative_to(self.app))
            # A portable stand-in for the syscall; the actual APFS operation is tested on macOS.
            with source_path.open("rb") as source_stream, destination_path.open("xb") as destination_stream:
                shutil.copyfileobj(source_stream, destination_stream)
            return 0

        function = mock.Mock(side_effect=fake_clone)
        library = SimpleNamespace(clonefile=function)
        original = self.project.read_bytes()
        with mock.patch.object(prepare_research.sys, "platform", "darwin"), \
                mock.patch.object(ctypes, "CDLL", return_value=library) as loader, \
                mock.patch.object(prepare_research.shutil, "copy2", side_effect=AssertionError("copy fallback")) as copy2:
            receipt = self.prepare_or_skip_symlink(copy_mode="clone")
        loader.assert_called_once_with(None, use_errno=True)
        copy2.assert_not_called()
        self.assertEqual(function.argtypes, (ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint32))
        self.assertIs(function.restype, ctypes.c_int)
        self.assertEqual(set(copied_paths), {Path("main.gd"), Path("project.godot"),
                                             Path("render/high_graphics_profile.gd"), Path("assets/runtime.txt")})
        self.assertEqual(receipt["copy_mode"], "clone")
        self.assertTrue(receipt["complete"])
        self.assertEqual(receipt["source"]["copied_app_manifest_sha256"],
                         receipt["destination"]["copy_manifest_sha256_before_project_edits"])
        self.assertEqual(receipt["destination"]["project_sha256"],
                         prepare_research._sha256(self.destination / "app" / "project.godot"))
        self.assertEqual(self.project.read_bytes(), original)
        self.assertEqual((self.destination / "app" / "main.gd").read_bytes(), (self.app / "main.gd").read_bytes())
        self.assertEqual(stat.S_IMODE((self.destination / "app" / "main.gd").stat().st_mode),
                         stat.S_IMODE((self.app / "main.gd").stat().st_mode))
        self.assertEqual((self.destination / "app" / "main.gd").stat().st_mtime_ns,
                         (self.app / "main.gd").stat().st_mtime_ns)
        self.assertTrue((self.destination / "assets").is_symlink())
        for name in (".godot", ".tools", "captures", "tmp"):
            self.assertFalse((self.destination / "app" / name).exists())

    def test_clone_mode_refuses_other_platforms_before_destination_creation(self) -> None:
        errors = io.StringIO()
        with mock.patch.object(prepare_research.sys, "platform", "linux"), \
                mock.patch.object(ctypes, "CDLL") as loader, contextlib.redirect_stderr(errors):
            code = prepare_research.main(["--source", str(self.source), "--dest", str(self.destination),
                                          "--copy-mode=clone"])
        self.assertEqual(code, 1)
        self.assertIn("clone copy mode requires macOS", errors.getvalue())
        self.assertFalse(self.destination.exists())
        loader.assert_not_called()

    def test_clonefile_errors_never_fall_back_or_publish_a_receipt(self) -> None:
        for code in (errno.ENOTSUP, errno.EXDEV, errno.EEXIST):
            destination = self.root / "output" / f"clone-error-{code}"
            attempted: list[Path] = []

            def fail_clone(_source: bytes, target: bytes, _flags: int) -> int:
                target_path = Path(os.fsdecode(target))
                attempted.append(target_path)
                if code == errno.EEXIST:
                    target_path.write_bytes(b"existing destination sentinel")
                ctypes.set_errno(code)
                return -1

            function = mock.Mock(side_effect=fail_clone)
            with self.subTest(code=code), mock.patch.object(prepare_research.sys, "platform", "darwin"), \
                    mock.patch.object(ctypes, "CDLL", return_value=SimpleNamespace(clonefile=function)), \
                    mock.patch.object(prepare_research.shutil, "copy2", side_effect=AssertionError("copy fallback")) as copy2:
                with self.assertRaises(prepare_research.PreparationError) as error:
                    prepare_research.prepare(self.source, destination, copy_mode="clone")
            if "cannot create the sibling assets symlink" in str(error.exception):
                self.skipTest(str(error.exception))
            self.assertIn("clonefile failed; copy fallback is disabled", str(error.exception))
            self.assertIn(os.strerror(code), str(error.exception))
            self.assertTrue(destination.is_dir())
            self.assertFalse((destination / prepare_research.RECEIPT).exists())
            self.assertTrue(attempted)
            if code == errno.EEXIST:
                self.assertTrue(all(path.read_bytes() == b"existing destination sentinel" for path in attempted))
            copy2.assert_not_called()

    def test_corrupt_clone_fails_hash_verification(self) -> None:
        def corrupt(source: bytes, destination: bytes, _flags: int) -> int:
            Path(os.fsdecode(destination)).write_bytes(Path(os.fsdecode(source)).read_bytes() + b"corrupt")
            return 0

        library = SimpleNamespace(clonefile=mock.Mock(side_effect=corrupt))
        with mock.patch.object(prepare_research.sys, "platform", "darwin"), \
                mock.patch.object(ctypes, "CDLL", return_value=library), \
                mock.patch.object(prepare_research.shutil, "copy2", side_effect=AssertionError("copy fallback")):
            with self.assertRaises(prepare_research.PreparationError) as error:
                prepare_research.prepare(self.source, self.destination, copy_mode="clone")
        if "cannot create the sibling assets symlink" in str(error.exception):
            self.skipTest(str(error.exception))
        self.assertIn("source changed or copy verification failed", str(error.exception))
        self.assertFalse((self.destination / prepare_research.RECEIPT).exists())

    def test_source_change_during_clone_fails_hash_verification(self) -> None:
        changed = False

        def changing(source: bytes, destination: bytes, _flags: int) -> int:
            nonlocal changed
            source_path = Path(os.fsdecode(source))
            Path(os.fsdecode(destination)).write_bytes(source_path.read_bytes())
            if source_path.name == "main.gd":
                source_path.write_bytes(b"# changed during cloning\n")
                changed = True
            return 0

        library = SimpleNamespace(clonefile=mock.Mock(side_effect=changing))
        with mock.patch.object(prepare_research.sys, "platform", "darwin"), \
                mock.patch.object(ctypes, "CDLL", return_value=library):
            with self.assertRaises(prepare_research.PreparationError) as error:
                prepare_research.prepare(self.source, self.destination, copy_mode="clone")
        if "cannot create the sibling assets symlink" in str(error.exception):
            self.skipTest(str(error.exception))
        self.assertTrue(changed)
        self.assertIn("source changed or copy verification failed", str(error.exception))
        self.assertFalse((self.destination / prepare_research.RECEIPT).exists())

    def test_clone_rejects_a_symlink_destination(self) -> None:
        def fake_link(source: bytes, destination: bytes, _flags: int) -> int:
            Path(os.fsdecode(destination)).symlink_to(Path(os.fsdecode(source)))
            return 0

        library = SimpleNamespace(clonefile=mock.Mock(side_effect=fake_link))
        with mock.patch.object(prepare_research.sys, "platform", "darwin"), \
                mock.patch.object(ctypes, "CDLL", return_value=library):
            with self.assertRaises(prepare_research.PreparationError) as error:
                prepare_research.prepare(self.source, self.destination, copy_mode="clone")
        if "cannot create the sibling assets symlink" in str(error.exception):
            self.skipTest(str(error.exception))
        self.assertIn("clone is not a regular file", str(error.exception))
        self.assertFalse((self.destination / prepare_research.RECEIPT).exists())

    def test_missing_clonefile_symbol_fails_before_creating_destination(self) -> None:
        with mock.patch.object(prepare_research.sys, "platform", "darwin"), \
                mock.patch.object(ctypes, "CDLL", return_value=SimpleNamespace()):
            with self.assertRaisesRegex(prepare_research.PreparationError, "macOS clonefile is unavailable"):
                prepare_research.prepare(self.source, self.destination, copy_mode="clone")
        self.assertFalse(self.destination.exists())

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
            with self.assertRaisesRegex(prepare_research.PreparationError, "partial destination retained") as error:
                prepare_research.prepare(self.source, self.destination)
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

    def test_source_file_added_during_copy_fails_closed(self) -> None:
        actual_copy = prepare_research.shutil.copy2

        def adding_copy(src: Path, dst: Path) -> str:
            result = actual_copy(src, dst)
            if Path(src).name == "main.gd":
                (self.app / "late.gd").write_text("# added while copying\n", encoding="utf-8")
            return str(result)

        with mock.patch.object(prepare_research.shutil, "copy2", side_effect=adding_copy):
            with self.assertRaises(prepare_research.PreparationError) as error:
                prepare_research.prepare(self.source, self.destination)
        if "cannot create the sibling assets symlink" in str(error.exception):
            self.skipTest(str(error.exception))
        self.assertIn("source app changed during preparation", str(error.exception))
        self.assertFalse((self.destination / prepare_research.RECEIPT).exists())

    def test_changed_destination_fails_verification(self) -> None:
        real_validator = launch._research_project

        def changed_after_validation(*args, **kwargs):
            result = real_validator(*args, **kwargs)
            (self.destination / "app" / "main.gd").write_text("# modified copy\n", encoding="utf-8")
            return result

        with mock.patch.object(launch, "_research_project", side_effect=changed_after_validation):
            with self.assertRaises(prepare_research.PreparationError) as error:
                prepare_research.prepare(self.source, self.destination)
        if "cannot create the sibling assets symlink" in str(error.exception):
            self.skipTest(str(error.exception))
        self.assertIn("copied app changed during verification", str(error.exception))
        self.assertFalse((self.destination / prepare_research.RECEIPT).exists())

    def test_failed_receipt_flush_or_publication_never_creates_complete_receipt(self) -> None:
        for target in ("fsync", "link"):
            destination = self.root / "output" / target
            with self.subTest(target=target), mock.patch.object(
                    prepare_research.os, target, side_effect=OSError("simulated receipt failure")):
                with self.assertRaises(prepare_research.PreparationError) as error:
                    prepare_research.prepare(self.source, destination)
            if "cannot create the sibling assets symlink" in str(error.exception):
                self.skipTest(str(error.exception))
            self.assertIn("simulated receipt failure", str(error.exception))
            self.assertTrue((destination / "research-preparation.pending.json").exists())
            self.assertFalse((destination / prepare_research.RECEIPT).exists())

    def test_cli_success_reports_the_prepared_copy(self) -> None:
        output, errors = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
            code = prepare_research.main(["--source", str(self.source), "--dest", str(self.destination)])
        if "cannot create the sibling assets symlink" in errors.getvalue():
            self.skipTest(errors.getvalue())
        self.assertEqual(code, 0, errors.getvalue())
        receipt = json.loads(output.getvalue())
        self.assertTrue(receipt["complete"])
        self.assertEqual(receipt["destination"]["root"], str(self.destination.resolve()))

    def test_cli_failure_is_nonzero_and_leaves_existing_contents(self) -> None:
        self.destination.mkdir(parents=True)
        (self.destination / "sentinel").write_text("keep", encoding="utf-8")
        errors = io.StringIO()
        with contextlib.redirect_stderr(errors):
            code = prepare_research.main(["--source", str(self.source), "--dest", str(self.destination)])
        self.assertEqual(code, 1)
        self.assertIn("already exists", errors.getvalue())
        self.assertEqual((self.destination / "sentinel").read_text(), "keep")

    def test_cli_reports_preflight_io_errors_without_a_traceback(self) -> None:
        errors = io.StringIO()
        with mock.patch.object(prepare_research, "_preflight", side_effect=OSError("inspection failed")):
            with contextlib.redirect_stderr(errors):
                code = prepare_research.main(["--source", str(self.source), "--dest", str(self.destination)])
        self.assertEqual(code, 1)
        self.assertIn("cannot inspect source or destination", errors.getvalue())
        self.assertIn("inspection failed", errors.getvalue())
        self.assertFalse(self.destination.exists())


if __name__ == "__main__":
    unittest.main()
