#!/usr/bin/env python3
"""AFC-02-R3: offline checks of tools/companions/rebind.py (no Godot; behaviour parity is checked by the tool)."""
from __future__ import annotations

import gzip
import hashlib
import io
import json
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import rebind  # noqa: E402

OLD = "a" * 64
NEW = "b" * 64


class CsvDifference(unittest.TestCase):
    def write(self, folder: Path, name: str, rows: list[str]) -> Path:
        path = folder / name
        path.write_text("\n".join(rows) + "\n")
        return path

    def test_reports_first_row_and_largest_column(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            base = self.write(folder, "a.csv", ["t,x,y", "0,1,2", "1,1,2", "2,1,2"])
            head = self.write(folder, "b.csv", ["t,x,y", "0,1,2", "1,1.5,2", "2,1,2.25"])
            result = rebind.csv_difference(base, head)
            self.assertFalse(result["header_changed"])
            self.assertEqual(result["first_differing_row"], 2)
            self.assertEqual(result["columns_changed"], 2)
            self.assertEqual(list(result["largest_abs_differences"]), ["x", "y"])
            self.assertAlmostEqual(result["largest_abs_differences"]["x"], 0.5)

    def test_header_change_is_not_a_numeric_difference(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            base = self.write(folder, "a.csv", ["t,x", "0,1"])
            head = self.write(folder, "b.csv", ["t,x,z", "0,1,0"])
            self.assertTrue(rebind.csv_difference(base, head)["header_changed"])

    def test_non_numeric_cell_is_reported_without_a_magnitude(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            base = self.write(folder, "a.csv", ["t,mode", "0,air"])
            head = self.write(folder, "b.csv", ["t,mode", "0,ground"])
            self.assertIsNone(rebind.csv_difference(base, head)["largest_abs_differences"]["mode"])


class Repin(unittest.TestCase):
    def profile(self, folder: Path, text: str) -> Path:
        path = folder / "profile.json"
        path.write_text(text, encoding="utf-8")
        return path

    def test_replaces_only_the_solver_pin(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = self.profile(Path(directory), json.dumps({"solver": {"sha256": OLD}, "other": "x"}))
            rebind.repin_profile(path, OLD, NEW)
            self.assertEqual(json.loads(path.read_text())["solver"]["sha256"], NEW)

    def test_refuses_an_ambiguous_profile(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = self.profile(Path(directory), json.dumps({"solver": {"sha256": OLD}, "copy": OLD}))
            with self.assertRaises(rebind.SetupError):
                rebind.repin_profile(path, OLD, NEW)
            self.assertIn(OLD, path.read_text())

    def test_refuses_when_the_identity_is_not_the_solver_pin(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = self.profile(Path(directory), json.dumps({"solver": {"sha256": "c" * 64}, "note": OLD}))
            with self.assertRaises(rebind.SetupError):
                rebind.repin_profile(path, OLD, NEW)


class Workspace(unittest.TestCase):
    def test_selected_workspace_is_isolated_and_cleaned_after_failure(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            parent = Path(directory) / "external-drive" / "rebind"
            parent.mkdir(parents=True)
            sentinel = parent / "existing.txt"
            sentinel.write_text("preserve")
            created = []

            def fail_build(workspace, _revision, _directories, _scope="solver", _copy_mode="copy"):
                self.assertEqual(workspace.parent, parent.resolve())
                self.assertTrue(workspace.is_dir())
                (workspace / "partial.txt").write_text("partial copy")
                created.append(workspace)
                raise rebind.SetupError("fixture copy failed")

            qualification = {"accepted": {"rev": "fixture"}, "solver_directories": []}
            with patch.object(rebind, "build_baseline", side_effect=fail_build):
                with self.assertRaisesRegex(rebind.SetupError, "fixture copy failed"):
                    rebind.compare("godot", qualification, 1, False, parent)
            self.assertEqual(len(created), 1)
            self.assertFalse(created[0].exists())
            self.assertEqual(sentinel.read_text(), "preserve")


class CloneBaseline(unittest.TestCase):
    def test_scoped_solver_ignores_a_missing_unrelated_promisor_blob(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "repo"
            root.mkdir()
            directories = ["app/physics", "app/sim", "app/failures"]
            for name in directories:
                path = root / name / "fixture.gd"
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes((name + "\n").encode())
            (root / "unrelated.txt").write_bytes(b"unrelated retained evidence\n")
            def git(*args, **kwargs):
                return subprocess.run(["git", "-C", str(root), *args], check=True, stdout=subprocess.PIPE,
                                      stderr=subprocess.PIPE, **kwargs).stdout
            git("init", "-q")
            git("add", ".")
            git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.test",
                "-c", "commit.gpgsign=false", "commit", "-qm", "base")
            expected_bytes = {}
            for name in directories:
                whole = git("archive", "HEAD", name)
                scoped = git("archive", f"--prefix={name}/", f"HEAD:{name}")
                def members(data):
                    with tarfile.open(fileobj=io.BytesIO(data)) as archive:
                        return {item.name: (item.mode, archive.extractfile(item).read())
                                for item in archive if item.isfile()}
                self.assertEqual(members(whole), members(scoped))
                expected_bytes[name] = members(whole)[name + "/fixture.gd"][1]
            missing = git("rev-parse", "HEAD:unrelated.txt").decode().strip()
            blob = root / ".git" / "objects" / missing[:2] / missing[2:]
            self.assertTrue(blob.is_file())
            os.chmod(blob, 0o666)
            blob.unlink()  # Only the unrelated loose blob in this disposable fixture.
            git("config", "core.repositoryformatversion", "1")
            git("config", "extensions.partialClone", "origin")
            git("config", "remote.origin.promisor", "true")
            git("config", "remote.origin.url", "file:///nonexistent-openrc-promisor")
            base = Path(directory) / "base"
            base.mkdir()
            with patch.object(rebind, "ROOT", root), patch.dict(os.environ, {"GIT_NO_LAZY_FETCH": "1"}):
                absent = subprocess.run(["git", "-C", str(root), "cat-file", "-e", "HEAD:unrelated.txt"],
                                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                self.assertNotEqual(absent.returncode, 0)
                rebind._scoped_solver_archive(base, "HEAD", directories)
            for name in directories:
                self.assertEqual((base / name / "fixture.gd").read_bytes(), expected_bytes[name])
            self.assertFalse(blob.exists())

    def test_scoped_solver_refuses_parent_attributes(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "repo"
            path = root / "app/physics/fixture.gd"
            path.parent.mkdir(parents=True)
            path.write_bytes(b"first\nsecond\n")
            (root / ".gitattributes").write_text("/app/physics/*.gd text eol=crlf\n", encoding="utf-8")
            subprocess.run(["git", "init", "-q", str(root)], check=True)
            subprocess.run(["git", "-C", str(root), "add", "."], check=True)
            subprocess.run(["git", "-C", str(root), "-c", "user.name=Fixture", "-c", "user.email=fixture@example.test",
                            "-c", "commit.gpgsign=false", "commit", "-qm", "base"], check=True)
            base = Path(directory) / "base"
            base.mkdir()
            with patch.object(rebind, "ROOT", root):
                with self.assertRaisesRegex(rebind.SetupError, "attributes requiring a full-root archive"):
                    rebind._scoped_solver_archive(base, "HEAD", ["app/physics"])
            self.assertFalse((base / "app/physics/fixture.gd").exists())

    @unittest.skipIf(sys.platform == "darwin", "the non-Mac refusal applies to other hosts")
    def test_clone_is_unavailable_off_macos(self) -> None:
        with self.assertRaisesRegex(rebind.SetupError, "requires macOS"):
            rebind._copy_function("clone")

    def test_clone_requires_the_existing_macos_clonefile_helper(self) -> None:
        with patch.object(rebind, "_macos_clonefile", side_effect=rebind.PreparationError("requires macOS")):
            with self.assertRaisesRegex(rebind.SetupError, "requires macOS"):
                rebind._copy_function("clone")

    def test_clone_error_never_falls_back_to_a_copy(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source"
            target = root / "target"
            source.write_bytes(b"unchanged")
            def refused(_source, _target):
                raise OSError("clone unavailable")
            with patch.object(rebind, "_macos_clonefile", return_value=refused), \
                    patch.object(rebind.shutil, "copy2") as ordinary_copy:
                clone_copy = rebind._copy_function("clone")
                with self.assertRaisesRegex(OSError, "clone unavailable"):
                    clone_copy(source, target)
                ordinary_copy.assert_not_called()
            self.assertFalse(target.exists())
            self.assertEqual(source.read_bytes(), b"unchanged")

    def test_clone_rejects_hardlinks(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, target = root / "source", root / "target"
            source.write_bytes(b"shared")
            def fake_clone(first, second):
                try:
                    os.link(first, second)
                except OSError as error:
                    self.skipTest(f"hardlink fixture unavailable: {error}")
            with patch.object(rebind, "_macos_clonefile", return_value=fake_clone):
                with self.assertRaisesRegex(rebind.SetupError, "independent regular file"):
                    rebind._copy_function("clone")(source, target)
            self.assertEqual(source.read_bytes(), b"shared")

    def test_full_baseline_streams_real_git_archive_and_retains_source(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "repo"
            root.mkdir()
            contents = {"app/physics/example.gd": "old solver", "app/main.gd": "old main",
                        "app/obsolete.gd": "tracked only in accepted revision",
                        "tools/flight_log/flight_log.py": "old replay",
                        "tools/release/macos_reference_receipt.py": "old helper"}
            for name, content in contents.items():
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(content, encoding="utf-8")
            subprocess.run(["git", "init", "-q", str(root)], check=True)
            subprocess.run(["git", "-C", str(root), "add", "."], check=True)
            subprocess.run(["git", "-C", str(root), "-c", "user.name=Fixture", "-c", "user.email=fixture@example.test",
                            "-c", "commit.gpgsign=false", "commit", "-qm", "base"], check=True)
            for name in contents:
                if name != "app/obsolete.gd":
                    (root / name).write_text("current " + name, encoding="utf-8")
            (root / "app/obsolete.gd").unlink()
            extras = ("app/new_tracked.gd", "app/native/kernel/current.dylib", "tools/flight_log/new_tool.py")
            for name in extras:
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("new current-only input", encoding="utf-8")
            subprocess.run(["git", "-C", str(root), "add", "app/new_tracked.gd", "tools/flight_log/new_tool.py"], check=True)
            cache = root / "app/.godot/imported/texture.ctex"
            cache.parent.mkdir(parents=True)
            cache.write_bytes(b"cache")
            (cache.parent.parent / "extension_list.cfg").write_text("current native descriptor", encoding="utf-8")
            (cache.parent.parent / "global_script_class_cache.cfg").write_text("current classes", encoding="utf-8")
            workspace = Path(directory) / "workspace"
            workspace.mkdir()
            with patch.object(rebind, "ROOT", root), \
                    patch.object(rebind, "_macos_clonefile", return_value=lambda src, dst: shutil.copy2(src, dst)):
                base = rebind.build_baseline(workspace, "HEAD", ["app/physics"], "full", "clone")
            for name, content in contents.items():
                self.assertEqual((base / name).read_text(encoding="utf-8"), content)
                if name != "app/obsolete.gd":
                    self.assertEqual((root / name).read_text(encoding="utf-8"), "current " + name)
            for name in extras:
                self.assertFalse((base / name).exists(), name)
                self.assertTrue((root / name).exists(), name)
            self.assertEqual((base / "app/.godot/imported/texture.ctex").read_bytes(), b"cache")
            self.assertFalse((base / "app/.godot/extension_list.cfg").exists())
            self.assertFalse((base / "app/.godot/global_script_class_cache.cfg").exists())
            self.assertFalse((workspace / "base-solver.tar").exists())
            copy_workspace = Path(directory) / "copy-workspace"
            copy_workspace.mkdir()
            with patch.object(rebind, "ROOT", root):
                copied_base = rebind.build_baseline(copy_workspace, "HEAD", ["app/physics"], "full")
            for name, content in contents.items():
                self.assertEqual((copied_base / name).read_text(encoding="utf-8"), content)
            for name in extras:
                self.assertFalse((copied_base / name).exists(), name)
            self.assertEqual((copied_base / "app/.godot/imported/texture.ctex").read_bytes(), b"cache")
            self.assertFalse((copy_workspace / "base-solver.tar").exists())

            # Even an exact archive cannot be used if it does not reproduce
            # the accepted solver identity; no replay may run in that case.
            qualification = {"accepted": {"rev": "HEAD", "solver_sha256": "0" * 64},
                             "solver_directories": ["app/physics"], "tapes": [], "candidate_aircraft": "fixture"}
            def identity(_godot, app):
                self.assertEqual((app / "physics/example.gd").read_text(encoding="utf-8"), "old solver")
                return hashlib.sha256(b"old solver").hexdigest()
            with patch.object(rebind, "ROOT", root), \
                    patch.object(rebind, "_macos_clonefile", return_value=lambda src, dst: shutil.copy2(src, dst)), \
                    patch.object(rebind, "solver_identity", side_effect=identity), \
                    patch.object(rebind, "replay") as replay:
                with self.assertRaisesRegex(rebind.SetupError, "not the accepted"):
                    rebind.compare("godot", qualification, 1, False, workspace, "full", copy_mode="clone")
                replay.assert_not_called()

    def test_scoped_full_matches_complete_git_archive_with_text_attributes(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "repo"
            contents = {".gitattributes": "*.gd text eol=crlf\n",
                        "app/.gitattributes": "*.gd -export-ignore -export-subst\n",
                        "app/physics/example.gd": "first\nsecond\n",
                        "app/main.gd": "main\n",
                        "tools/flight_log/flight_log.py": "flight\n",
                        "tools/release/macos_reference_receipt.py": "receipt $Format:%H$\n",
                        "tools/release/unrelated.py": "not requested\n",
                        "outside.txt": "also not requested\n"}
            for name, content in contents.items():
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(content.encode())
            def git(*args):
                return subprocess.run(["git", "-C", str(root), *args], check=True,
                                      stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout
            git("init", "-q")
            git("config", "core.autocrlf", "false")
            git("add", ".")
            git("update-index", "--chmod=+x", "tools/release/macos_reference_receipt.py")
            git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.test",
                "-c", "commit.gpgsign=false", "commit", "-qm", "base")
            paths = list(rebind.FULL_BASELINE_PATHS)
            reference, actual = Path(directory) / "reference", Path(directory) / "actual"
            reference.mkdir()
            actual.mkdir()
            with tarfile.open(fileobj=io.BytesIO(git("archive", "HEAD", *paths))) as archive:
                archive.extractall(reference, filter="data")
            with patch.object(rebind, "ROOT", root):
                rebind._scoped_full_archive(actual, "HEAD", paths)
            def files(folder):
                return {item.relative_to(folder).as_posix(): item.read_bytes()
                        for item in folder.rglob("*") if item.is_file()}
            self.assertEqual(files(actual), files(reference))
            self.assertEqual(git("show", "HEAD:app/physics/example.gd"), b"first\nsecond\n")
            self.assertEqual((actual / "app/physics/example.gd").read_bytes(), b"first\r\nsecond\r\n")
            self.assertNotIn("tools/release/unrelated.py", files(actual))
            if os.name != "nt":
                for name in files(reference):
                    self.assertEqual((actual / name).stat().st_mode & 0o777,
                                     (reference / name).stat().st_mode & 0o777, name)

    def test_scoped_full_refuses_export_attributes_including_ancestor(self) -> None:
        cases = ((".gitattributes", "app/physics export-ignore\n"),
                 (".gitattributes", "app/main.gd export-subst\n"),
                 ("app/.gitattributes", "physics/*.gd export-ignore\n"))
        for attribute_path, attribute in cases:
            with self.subTest(attribute_path=attribute_path, attribute=attribute), \
                    tempfile.TemporaryDirectory() as directory:
                root = Path(directory) / "repo"
                for name in ("app/physics/fixture.gd", "app/main.gd", "tools/flight_log/replay.py"):
                    path = root / name
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_text("fixture\n", encoding="utf-8")
                (root / attribute_path).write_text(attribute, encoding="utf-8")
                def git(*args):
                    subprocess.run(["git", "-C", str(root), *args], check=True,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                git("init", "-q")
                git("add", ".")
                git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.test",
                    "-c", "commit.gpgsign=false", "commit", "-qm", "base")
                base = Path(directory) / "base"
                base.mkdir()
                with patch.object(rebind, "ROOT", root):
                    with self.assertRaisesRegex(rebind.SetupError, "archive-affecting attribute"):
                        rebind._scoped_full_archive(base, "HEAD", ["app", "tools/flight_log"])
                self.assertFalse(any(base.iterdir()))

    def test_scoped_full_tolerates_unrelated_missing_objects_but_not_selected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "repo"
            for name in ("app/physics/selected.gd", "tools/flight_log/replay.py",
                         "tools/release/macos_reference_receipt.py", "tools/release/unrelated.py",
                         "unrelated.txt"):
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes((name + "\n").encode())
            def git(*args):
                return subprocess.run(["git", "-C", str(root), *args], check=True,
                                      stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout
            git("init", "-q")
            git("add", ".")
            git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.test",
                "-c", "commit.gpgsign=false", "commit", "-qm", "base")
            def remove_blob(name):
                oid = git("rev-parse", "HEAD:" + name).decode().strip()
                blob = root / ".git/objects" / oid[:2] / oid[2:]
                os.chmod(blob, 0o666)
                blob.unlink()
                return blob
            missing = [remove_blob("unrelated.txt"), remove_blob("tools/release/unrelated.py")]
            git("config", "core.repositoryformatversion", "1")
            git("config", "extensions.partialClone", "origin")
            git("config", "remote.origin.promisor", "true")
            git("config", "remote.origin.url", "file:///nonexistent-openrc-promisor")
            base = Path(directory) / "base"
            base.mkdir()
            with patch.object(rebind, "ROOT", root), patch.dict(os.environ, {"GIT_NO_LAZY_FETCH": "1"}):
                rebind._scoped_full_archive(base, "HEAD", list(rebind.FULL_BASELINE_PATHS))
                self.assertTrue((base / "app/physics/selected.gd").is_file())
                self.assertTrue((base / "tools/release/macos_reference_receipt.py").is_file())
                self.assertTrue(all(not path.exists() for path in missing))
                remove_blob("app/physics/selected.gd")
                incomplete = Path(directory) / "incomplete"
                incomplete.mkdir()
                with self.assertRaisesRegex(rebind.SetupError, "git archive"):
                    rebind._scoped_full_archive(incomplete, "HEAD", list(rebind.FULL_BASELINE_PATHS))

    def test_streamed_archive_failure_is_not_success(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "repo"
            root.mkdir()
            subprocess.run(["git", "init", "-q", str(root)], check=True)
            with patch.object(rebind, "ROOT", root):
                with self.assertRaisesRegex(rebind.SetupError, "git archive"):
                    rebind._extract_archive_stream(root, "missing-revision", ["app"])

    def test_clone_mode_is_forwarded_and_recorded(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            profile = root / "profile.json"
            profile.write_text(json.dumps({"solver": {"sha256": OLD}}), encoding="utf-8")
            (root / "tape.orfl").write_bytes(b"fixture")
            qualification = {"profile": "profile.json", "accepted": {"rev": "base", "solver_sha256": OLD},
                             "tapes": ["tape.orfl"], "solver_directories": [], "candidate_aircraft": "aircraft.json"}
            qual_path = root / "qualification.json"
            qual_path.write_text(json.dumps(qualification), encoding="utf-8")
            report = root / "report.json"
            results = [{"identical": True, "tape": "tape.orfl", "rows": 1}]
            with patch.object(rebind, "ROOT", root), patch.object(rebind, "QUALIFICATION", qual_path), \
                    patch.object(rebind, "_macos_clonefile", return_value=lambda _a, _b: None), \
                    patch.object(rebind, "validate_engine"), patch.object(rebind, "solver_identity", return_value=NEW), \
                    patch.object(rebind, "compare", return_value=(results, str(root / "workspace"))) as compare, \
                    patch.object(rebind, "git", return_value="c" * 40), \
                    patch.object(rebind, "solver_tree_is_committed", return_value=True), \
                    patch.object(sys, "argv", ["rebind.py", "--godot", "godot", "--copy-mode", "clone",
                                               "--report", str(report)]):
                self.assertEqual(rebind.main(), 0)
            self.assertEqual(compare.call_args.args[-1], "clone")
            self.assertEqual(json.loads(report.read_text(encoding="utf-8"))["copy_mode"], "clone")


class EngineAndTapeGuards(unittest.TestCase):
    def test_unchanged_solver_still_rejects_a_different_engine(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            profile = root / "profile.json"
            profile.write_text(json.dumps({"solver": {"sha256": OLD}, "engine_version": "4.8.beta1.official.old"}))
            qualification = root / "qualification.json"
            qualification.write_text(json.dumps({"profile": "profile.json", "accepted": {"solver_sha256": OLD}}))
            result = subprocess.CompletedProcess(["godot", "--version"], 0, "4.8.beta2.official.new\n", "")
            with patch.object(rebind, "ROOT", root), patch.object(rebind, "QUALIFICATION", qualification), \
                    patch.object(rebind, "run", return_value=result), patch.object(rebind, "solver_identity") as solver, \
                    patch.object(sys, "argv", ["rebind.py", "--godot", "godot"]):
                self.assertEqual(rebind.main(), 2)
                solver.assert_not_called()
            self.assertEqual(json.loads(profile.read_text())["solver"]["sha256"], OLD)

    def test_missing_duplicate_or_empty_tape_sets_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "valid.orfl").write_bytes(b"fixture")
            with patch.object(rebind, "ROOT", root):
                for tapes in ([], ["missing.orfl"], ["valid.orfl", "valid.orfl"]):
                    with self.subTest(tapes=tapes), self.assertRaises(rebind.SetupError):
                        rebind.qualified_tapes({"tapes": tapes})

    def test_solver_helper_must_inspect_every_requested_tape(self) -> None:
        unchecked = subprocess.CompletedProcess([], 0, 'SOLVER_IDENTITY {"ok":true,"sha256":"abc","inspected_tapes":0}\n', "")
        with patch.object(rebind, "run", return_value=unchecked):
            with self.assertRaises(rebind.SetupError):
                rebind.solver_identity("godot", Path("app"), (Path("stale.orfl"),))

    def test_unchanged_solver_still_rejects_a_stale_tape(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            profile = root / "profile.json"
            profile.write_text(json.dumps({"solver": {"sha256": OLD}, "engine_version": "4.8.beta2.official.new"}))
            (root / "stale.orfl").write_bytes(b"old-engine fixture")
            qualification = root / "qualification.json"
            qualification.write_text(json.dumps({"profile": "profile.json", "accepted": {"solver_sha256": OLD},
                                                  "tapes": ["stale.orfl"]}))
            version = subprocess.CompletedProcess([], 0, "4.8.beta2.official.new\n", "")
            rejected = subprocess.CompletedProcess([], 1,
                'SOLVER_IDENTITY {"ok":false,"sha256":"' + OLD + '","inspected_tapes":0,"errors":["wrong engine"]}\n', "")
            with patch.object(rebind, "ROOT", root), patch.object(rebind, "QUALIFICATION", qualification), \
                    patch.object(rebind, "run", side_effect=[version, rejected]) as execute, \
                    patch.object(rebind, "compare") as compare, \
                    patch.object(sys, "argv", ["rebind.py", "--godot", "godot"]):
                self.assertEqual(rebind.main(), 2)
                self.assertTrue(any(str(arg).endswith("stale.orfl") for arg in execute.call_args_list[1].args[0]))
                compare.assert_not_called()
            self.assertEqual(json.loads(profile.read_text())["solver"]["sha256"], OLD)


class GzipTapeTransport(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.workspace = self.root / "workspace"
        self.data = b"ORFL0001" + bytes(range(128)) * 3
        self.root_patch = patch.object(rebind, "ROOT", self.root)
        self.root_patch.start()
        self.addCleanup(self.root_patch.stop)

    def gzip_fixture(self, name: str = "one.orfl.gz", raw: bytes | None = None,
                     stored: bytes | None = None) -> dict:
        content = self.data if raw is None else raw
        encoded = gzip.compress(content, mtime=0) if stored is None else stored
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(encoded)
        return {"tapes": [name], "tape_identities": {name: {
            "orfl_sha256": hashlib.sha256(content).hexdigest(),
            "stored_sha256": hashlib.sha256(encoded).hexdigest(),
        }}}

    def no_temporary_tapes(self) -> None:
        if self.workspace.exists():
            self.assertFalse(list(self.workspace.glob("companion-rebind-tapes-*")))

    def test_raw_path_is_unchanged_and_does_not_create_a_workspace(self) -> None:
        path = self.root / "raw.orfl"
        path.write_bytes(self.data)
        with rebind.materialized_tapes({"tapes": ["raw.orfl"]}, self.workspace) as tapes:
            self.assertEqual(tapes[0].path, path.resolve())
            self.assertEqual(tapes[0].source, path)
            self.assertFalse(tapes[0].compressed)
            self.assertFalse(self.workspace.exists())
        self.assertEqual(path.read_bytes(), self.data)

    def test_gzip_materialization_preserves_exact_bytes_and_lifetime(self) -> None:
        qualification = self.gzip_fixture()
        with rebind.materialized_tapes(qualification, self.workspace) as tapes:
            tape = tapes[0]
            self.assertTrue(tape.compressed)
            self.assertEqual(tape.path.suffix, ".orfl")
            self.assertNotEqual(tape.path, tape.source)
            self.assertTrue(tape.path.is_file())
            self.assertEqual(tape.path.read_bytes(), self.data)
            self.assertEqual(tape.orfl_sha256, hashlib.sha256(self.data).hexdigest())
            rebind._check_materialized_tapes(tapes)
            materialized = tape.path
        self.assertFalse(materialized.exists())
        self.no_temporary_tapes()

    def test_failure_inside_context_always_cleans_the_expansion(self) -> None:
        qualification = self.gzip_fixture()
        with self.assertRaisesRegex(RuntimeError, "fixture"):
            with rebind.materialized_tapes(qualification, self.workspace) as tapes:
                self.assertTrue(tapes[0].path.is_file())
                raise RuntimeError("fixture")
        self.no_temporary_tapes()

    def test_missing_malformed_and_unexpected_identities_are_refused(self) -> None:
        good = self.gzip_fixture()
        name = good["tapes"][0]
        identity = good["tape_identities"][name]
        variants = [None, {}, {name: {}}, {name: {"orfl_sha256": identity["orfl_sha256"]}},
                    {name: {**identity, "extra": "unverified"}},
                    {name: {**identity, "stored_sha256": "not-a-digest"}},
                    {name: identity, "unexpected.orfl.gz": identity}]
        for identities in variants:
            with self.subTest(identities=identities), self.assertRaises(rebind.SetupError):
                with rebind.materialized_tapes({"tapes": [name], "tape_identities": identities}, self.workspace):
                    self.fail("invalid identities were accepted")
        self.no_temporary_tapes()

    def test_suffix_content_mismatch_is_refused_in_both_directions(self) -> None:
        qualification = self.gzip_fixture()
        (self.root / "one.orfl.gz").write_bytes(self.data)
        with self.assertRaisesRegex(rebind.SetupError, "suffix and gzip content"):
            with rebind.materialized_tapes(qualification, self.workspace):
                pass
        (self.root / "raw.orfl").write_bytes(gzip.compress(self.data, mtime=0))
        with self.assertRaisesRegex(rebind.SetupError, "suffix and gzip content"):
            with rebind.materialized_tapes({"tapes": ["raw.orfl"]}, self.workspace):
                pass
        (self.root / "wrong.gz").write_bytes(gzip.compress(self.data, mtime=0))
        with self.assertRaisesRegex(rebind.SetupError, "must use .orfl.gz"):
            with rebind.materialized_tapes({"tapes": ["wrong.gz"]}, self.workspace):
                pass
        self.no_temporary_tapes()

    def test_bad_crc_and_truncated_trailer_are_refused(self) -> None:
        original = gzip.compress(self.data, mtime=0)
        crc = bytearray(original)
        crc[-8] ^= 1
        for damaged in (bytes(crc), original[:-4], original + b"garbage"):
            qualification = self.gzip_fixture(stored=damaged)
            with self.subTest(stored=damaged), \
                    self.assertRaisesRegex(rebind.SetupError, "invalid or incomplete gzip"):
                with rebind.materialized_tapes(qualification, self.workspace):
                    pass
            self.no_temporary_tapes()

    def test_stored_and_raw_hash_mismatches_are_refused(self) -> None:
        for key in ("stored_sha256", "orfl_sha256"):
            qualification = self.gzip_fixture()
            qualification["tape_identities"]["one.orfl.gz"][key] = "0" * 64
            with self.subTest(key=key), self.assertRaisesRegex(rebind.SetupError, "SHA-256 differs"):
                with rebind.materialized_tapes(qualification, self.workspace):
                    pass
            self.no_temporary_tapes()

    def test_invalid_materialized_orfl_header_is_refused(self) -> None:
        qualification = self.gzip_fixture(raw=b"NOTORFL1" + self.data)
        with self.assertRaisesRegex(rebind.SetupError, "invalid ORFL magic"):
            with rebind.materialized_tapes(qualification, self.workspace):
                pass
        self.no_temporary_tapes()

    def test_bound_matches_reader_and_is_enforced_while_streaming(self) -> None:
        self.assertEqual(rebind.MAX_MATERIALIZED_BYTES, (512 + 2 * 16) * 1024 * 1024)
        qualification = self.gzip_fixture()
        with patch.object(rebind, "MAX_MATERIALIZED_BYTES", len(self.data)):
            with rebind.materialized_tapes(qualification, self.workspace) as tapes:
                self.assertEqual(tapes[0].path.read_bytes(), self.data)
        with patch.object(rebind, "MAX_MATERIALIZED_BYTES", len(self.data) - 1), \
                self.assertRaisesRegex(rebind.SetupError, "decompressed tape exceeds"):
            with rebind.materialized_tapes(qualification, self.workspace):
                pass
        self.no_temporary_tapes()

    def test_logical_output_name_collisions_are_refused(self) -> None:
        qualification = self.gzip_fixture("one/Flight.orfl.gz")
        raw = self.root / "two/flight.orfl"
        raw.parent.mkdir(parents=True)
        raw.write_bytes(self.data)
        qualification["tapes"].append("two/flight.orfl")
        with self.assertRaisesRegex(rebind.SetupError, "duplicate tape output name"):
            with rebind.materialized_tapes(qualification, self.workspace):
                pass
        self.no_temporary_tapes()

    def test_raw_only_names_keep_existing_qualification_behavior(self) -> None:
        for name in ("one/flight.orfl", "two/flight.orfl"):
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(self.data)
        paths = rebind.qualified_tapes({"tapes": ["one/flight.orfl", "two/flight.orfl"]})
        self.assertEqual(paths, ((self.root / "one/flight.orfl").resolve(),
                                 (self.root / "two/flight.orfl").resolve()))

    def test_unchanged_solver_inspects_materialized_tape_before_cleanup(self) -> None:
        qualification = self.gzip_fixture()
        qualification.update(profile="profile.json", accepted={"solver_sha256": OLD})
        (self.root / "profile.json").write_text(json.dumps({"solver": {"sha256": OLD}}), encoding="utf-8")
        qual_path = self.root / "qualification.json"
        qual_path.write_text(json.dumps(qualification), encoding="utf-8")
        inspected = []

        def inspect(_godot, _app, tapes, expected):
            inspected.extend(tapes)
            self.assertEqual(len(tapes), 1)
            self.assertEqual(tapes[0].read_bytes(), self.data)
            self.assertEqual(tapes[0].suffix, ".orfl")
            self.assertEqual(expected, {str(tapes[0]): hashlib.sha256(self.data).hexdigest()})
            return OLD

        with patch.object(rebind, "QUALIFICATION", qual_path), patch.object(rebind, "validate_engine"), \
                patch.object(rebind, "solver_identity", side_effect=inspect), patch.object(rebind, "compare") as compare, \
                patch.object(sys, "argv", ["rebind.py", "--godot", "godot", "--workspace-root", str(self.workspace)]):
            self.assertEqual(rebind.main(), 0)
            compare.assert_not_called()
        self.assertEqual(len(inspected), 1)
        self.assertFalse(inspected[0].exists())
        self.no_temporary_tapes()

    def test_invalid_compressed_identity_never_reaches_engine_inspection(self) -> None:
        qualification = self.gzip_fixture()
        qualification["tape_identities"]["one.orfl.gz"]["orfl_sha256"] = "0" * 64
        qualification.update(profile="profile.json", accepted={"solver_sha256": OLD})
        (self.root / "profile.json").write_text(json.dumps({"solver": {"sha256": OLD}}), encoding="utf-8")
        qual_path = self.root / "qualification.json"
        qual_path.write_text(json.dumps(qualification), encoding="utf-8")
        with patch.object(rebind, "QUALIFICATION", qual_path), patch.object(rebind, "validate_engine"), \
                patch.object(rebind, "solver_identity") as inspect, patch.object(rebind, "compare") as compare, \
                patch.object(sys, "argv", ["rebind.py", "--godot", "godot", "--workspace-root", str(self.workspace)]):
            self.assertEqual(rebind.main(), 2)
            inspect.assert_not_called()
            compare.assert_not_called()
        self.no_temporary_tapes()

    def test_engine_inspection_refusal_cleans_materialized_tape(self) -> None:
        qualification = self.gzip_fixture()
        qualification.update(profile="profile.json", accepted={"solver_sha256": OLD})
        (self.root / "profile.json").write_text(json.dumps({"solver": {"sha256": OLD}}), encoding="utf-8")
        qual_path = self.root / "qualification.json"
        qual_path.write_text(json.dumps(qualification), encoding="utf-8")

        def refuse(_godot, _app, tapes, _expected):
            self.assertTrue(tapes[0].is_file())
            raise rebind.SetupError("fixture stale source/engine")

        with patch.object(rebind, "QUALIFICATION", qual_path), patch.object(rebind, "validate_engine"), \
                patch.object(rebind, "solver_identity", side_effect=refuse), patch.object(rebind, "compare") as compare, \
                patch.object(sys, "argv", ["rebind.py", "--godot", "godot", "--workspace-root", str(self.workspace)]):
            self.assertEqual(rebind.main(), 2)
            compare.assert_not_called()
        self.no_temporary_tapes()

    def test_inspection_hash_required_only_for_compressed_tape_callers(self) -> None:
        tape = self.root / "materialized.orfl"
        tape.write_bytes(self.data)
        digest = hashlib.sha256(self.data).hexdigest()
        common = {"ok": True, "sha256": OLD, "inspected_tapes": 1}
        legacy = subprocess.CompletedProcess([], 0, "SOLVER_IDENTITY " + json.dumps(common) + "\n", "")
        with patch.object(rebind, "run", return_value=legacy):
            self.assertEqual(rebind.solver_identity("godot", self.root, (tape,)), OLD)
            with self.assertRaisesRegex(rebind.SetupError, "did not report per-tape"):
                rebind.solver_identity("godot", self.root, (tape,), {str(tape): digest})
        empty = subprocess.CompletedProcess([], 0, "SOLVER_IDENTITY " + json.dumps(
            {"ok": True, "sha256": OLD, "inspected_tapes": 0}) + "\n", "")
        with patch.object(rebind, "run", return_value=empty):
            self.assertEqual(rebind.solver_identity("godot", self.root), OLD)
        with patch.object(rebind, "run") as child, \
                self.assertRaisesRegex(rebind.SetupError, "not among requested tapes"):
            rebind.solver_identity("godot", self.root, (tape,), {"unexpected.orfl": digest})
        child.assert_not_called()
        for value in ({}, {str(tape): "g" * 64}, {str(tape): "0" * 64}, {str(tape): None}):
            response = {**common, "inspected_tape_sha256": value}
            child = subprocess.CompletedProcess([], 0, "SOLVER_IDENTITY " + json.dumps(response) + "\n", "")
            with self.subTest(value=value), patch.object(rebind, "run", return_value=child), \
                    self.assertRaisesRegex(rebind.SetupError, "inspection tape SHA-256 missing or differs"):
                rebind.solver_identity("godot", self.root, (tape,), {str(tape): digest})
        response = {**common, "inspected_tape_sha256": {str(tape): digest}}
        child = subprocess.CompletedProcess([], 0, "SOLVER_IDENTITY " + json.dumps(response) + "\n", "")
        with patch.object(rebind, "run", return_value=child):
            self.assertEqual(rebind.solver_identity("godot", self.root, (tape,), {str(tape): digest}), OLD)

    def test_inspection_substitute_restored_before_parent_check_is_refused(self) -> None:
        qualification = self.gzip_fixture()
        qualification.update(profile="profile.json", accepted={"solver_sha256": OLD})
        (self.root / "profile.json").write_text(json.dumps({"solver": {"sha256": OLD}}), encoding="utf-8")
        qual_path = self.root / "qualification.json"
        qual_path.write_text(json.dumps(qualification), encoding="utf-8")
        inspected = []

        def fake_inspector(command, **_kwargs):
            path = Path(next(arg.removeprefix("--tape=") for arg in command if arg.startswith("--tape=")))
            original = path.read_bytes()
            self.assertEqual(original, self.data)
            path.write_bytes(b"ORFL0001substitute")
            digest = rebind.sha256_file(path)
            path.write_bytes(original)
            inspected.append(path)
            result = {"ok": True, "sha256": OLD, "inspected_tapes": 1,
                      "inspected_tape_sha256": {str(path): digest}}
            return subprocess.CompletedProcess(command, 0, "SOLVER_IDENTITY " + json.dumps(result) + "\n", "")

        with patch.object(rebind, "QUALIFICATION", qual_path), patch.object(rebind, "validate_engine"), \
                patch.object(rebind, "run", side_effect=fake_inspector), patch.object(rebind, "compare") as compare, \
                patch.object(sys, "argv", ["rebind.py", "--godot", "godot", "--workspace-root", str(self.workspace)]):
            self.assertEqual(rebind.main(), 2)
            compare.assert_not_called()
        self.assertEqual(len(inspected), 1)
        self.assertFalse(inspected[0].exists())
        self.no_temporary_tapes()

    def test_compare_replays_same_materialized_bytes_and_reports_both_hashes(self) -> None:
        qualification = self.gzip_fixture()
        qualification.update(accepted={"rev": "fixture", "solver_sha256": OLD}, solver_directories=[],
                             candidate_aircraft="candidate.json")
        seen = []

        def replay(_godot, project, tape, _candidate, output):
            seen.append((project, tape))
            self.assertTrue(tape.is_file())
            self.assertEqual(tape.read_bytes(), self.data)
            output.mkdir(parents=True, exist_ok=True)
            csv = output / "flight.csv"
            csv.write_text("tick,value\n0,1\n", encoding="utf-8")
            return {"csv": csv, "csv_sha256": rebind.sha256_file(csv), "rows": 1,
                    "source_sha256": rebind.sha256_file(tape)}

        with patch.object(rebind, "build_baseline", side_effect=lambda workspace, *_args: workspace / "base"), \
                patch.object(rebind, "solver_identity", return_value=OLD), patch.object(rebind, "replay", side_effect=replay):
            results, workspace = rebind.compare("godot", qualification, 2, False, self.workspace)
        self.assertEqual(len(seen), 2)
        self.assertEqual(seen[0][1], seen[1][1])
        self.assertFalse(seen[0][1].exists())
        self.assertFalse(Path(workspace).exists())
        self.assertEqual(results[0]["tape"], "one.orfl.gz")
        self.assertEqual(results[0]["tape_encoding"], "gzip")
        self.assertEqual(results[0]["orfl_sha256"], hashlib.sha256(self.data).hexdigest())
        self.assertEqual(results[0]["stored_sha256"], qualification["tape_identities"]["one.orfl.gz"]["stored_sha256"])
        self.assertEqual(results[0]["base_replay_source_sha256"], hashlib.sha256(self.data).hexdigest())
        self.assertEqual(results[0]["head_replay_source_sha256"], hashlib.sha256(self.data).hexdigest())
        self.assertTrue(results[0]["identical"])
        self.no_temporary_tapes()

    def test_each_child_must_report_the_matching_raw_digest(self) -> None:
        qualification = self.gzip_fixture()
        qualification.update(accepted={"rev": "fixture", "solver_sha256": OLD}, solver_directories=[],
                             candidate_aircraft="candidate.json")
        for bad_side in ("base", "head"):
            for invalid in (None, "", 12, "g" * 64, "0" * 64):
                def replay(_godot, _project, tape, _candidate, output):
                    output.mkdir(parents=True, exist_ok=True)
                    csv = output / "flight.csv"
                    csv.write_text("tick\n0\n", encoding="utf-8")
                    value = invalid if output.parent.name == bad_side else rebind.sha256_file(tape)
                    result = {"csv": csv, "csv_sha256": rebind.sha256_file(csv), "rows": 1}
                    if value is not None:
                        result["source_sha256"] = value
                    return result

                with self.subTest(side=bad_side, value=invalid), \
                        patch.object(rebind, "build_baseline", side_effect=lambda workspace, *_args: workspace / "base"), \
                        patch.object(rebind, "solver_identity", return_value=OLD), \
                        patch.object(rebind, "replay", side_effect=replay), \
                        self.assertRaisesRegex(rebind.SetupError, bad_side + " replay source SHA-256 missing or differs"):
                    rebind.compare("godot", qualification, 1, False, self.workspace)
                self.no_temporary_tapes()

    def test_matching_csvs_refuse_child_hashes_from_temporarily_substituted_tape(self) -> None:
        qualification = self.gzip_fixture()
        qualification.update(accepted={"rev": "fixture", "solver_sha256": OLD}, solver_directories=[],
                             candidate_aircraft="candidate.json")
        child_csvs = []
        reported = []
        checks = []
        original_check = rebind._check_materialized_tapes

        def fake_child(command, **_kwargs):
            tape = Path(command[3])
            output = Path(command[-1])
            original = tape.read_bytes()
            self.assertEqual(original, self.data)
            tape.write_bytes(b"ORFL0001substitute")
            source_sha256 = rebind.sha256_file(tape)
            tape.write_bytes(original)  # restored before the parent's post-replay check
            output.mkdir(parents=True, exist_ok=True)
            csv = output / "flight.csv"
            csv.write_text("tick,value\n0,1\n", encoding="utf-8")
            (output / "replay.json").write_text(json.dumps({"complete": True, "source_sha256": source_sha256}),
                                                encoding="utf-8")
            child_csvs.append(rebind.sha256_file(csv))
            reported.append(source_sha256)
            return subprocess.CompletedProcess(command, 0, "", "")

        def record_check(tapes):
            original_check(tapes)
            checks.append(rebind.sha256_file(tapes[0].path))

        with patch.object(rebind, "build_baseline", side_effect=lambda workspace, *_args: workspace / "base"), \
                patch.object(rebind, "solver_identity", return_value=OLD), \
                patch.object(rebind, "run", side_effect=fake_child), \
                patch.object(rebind, "_check_materialized_tapes", side_effect=record_check), \
                self.assertRaisesRegex(rebind.SetupError, "base replay source SHA-256 missing or differs"):
            rebind.compare("godot", qualification, 1, False, self.workspace)
        expected = hashlib.sha256(self.data).hexdigest()
        self.assertEqual(len(child_csvs), 2)
        self.assertEqual(child_csvs[0], child_csvs[1])
        self.assertEqual(len(reported), 2)
        self.assertTrue(all(value != expected for value in reported))
        self.assertEqual(checks, [expected, expected])  # both parent checks saw the restored file
        self.no_temporary_tapes()

    def test_changed_materialization_is_refused_and_cleaned(self) -> None:
        qualification = self.gzip_fixture()
        with self.assertRaisesRegex(rebind.SetupError, "materialized ORFL changed"):
            with rebind.materialized_tapes(qualification, self.workspace) as tapes:
                tapes[0].path.write_bytes(self.data + b"changed")
                rebind._check_materialized_tapes(tapes)
        self.no_temporary_tapes()

    def test_keep_retains_project_workspace_but_not_expanded_tape(self) -> None:
        qualification = self.gzip_fixture()
        qualification.update(accepted={"rev": "fixture", "solver_sha256": OLD}, solver_directories=[],
                             candidate_aircraft="candidate.json")

        def replay(_godot, _project, tape, _candidate, output):
            self.assertEqual(tape.read_bytes(), self.data)
            output.mkdir(parents=True, exist_ok=True)
            csv = output / "flight.csv"
            csv.write_text("tick\n0\n", encoding="utf-8")
            return {"csv": csv, "csv_sha256": rebind.sha256_file(csv), "rows": 1,
                    "source_sha256": rebind.sha256_file(tape)}

        with patch.object(rebind, "build_baseline", side_effect=lambda workspace, *_args: workspace / "base"), \
                patch.object(rebind, "solver_identity", return_value=OLD), patch.object(rebind, "replay", side_effect=replay):
            results, workspace = rebind.compare("godot", qualification, 1, True, self.workspace)
        self.assertTrue(results[0]["identical"])
        self.assertTrue(Path(workspace).is_dir())
        self.no_temporary_tapes()

    def test_full_changed_solver_flow_keeps_tape_alive_and_reports_identities(self) -> None:
        qualification = self.gzip_fixture()
        qualification.update(profile="profile.json", accepted={"rev": "fixture", "solver_sha256": OLD},
                             solver_directories=[], candidate_aircraft="candidate.json")
        (self.root / "profile.json").write_text(json.dumps({"solver": {"sha256": OLD}}), encoding="utf-8")
        qual_path = self.root / "qualification.json"
        qual_path.write_text(json.dumps(qualification), encoding="utf-8")
        report = self.root / "result.json"
        inspected = []
        replayed = []

        def identity(_godot, _app, tapes=(), expected=None):
            if tapes:
                inspected.extend(tapes)
                self.assertEqual(tapes[0].read_bytes(), self.data)
                self.assertEqual(expected, {str(tapes[0]): hashlib.sha256(self.data).hexdigest()})
                return NEW
            self.assertTrue(inspected[0].is_file())
            return OLD

        def replay(_godot, _project, tape, _candidate, output):
            self.assertEqual(tape, inspected[0])
            self.assertEqual(tape.read_bytes(), self.data)
            replayed.append(tape)
            output.mkdir(parents=True, exist_ok=True)
            csv = output / "flight.csv"
            csv.write_text("tick\n0\n", encoding="utf-8")
            return {"csv": csv, "csv_sha256": rebind.sha256_file(csv), "rows": 1,
                    "source_sha256": rebind.sha256_file(tape)}

        def fake_git(*args):
            return "c" * 40 if args[:2] == ("rev-parse", "HEAD") else ""

        with patch.object(rebind, "QUALIFICATION", qual_path), patch.object(rebind, "validate_engine"), \
                patch.object(rebind, "build_baseline", side_effect=lambda workspace, *_args: workspace / "base"), \
                patch.object(rebind, "solver_identity", side_effect=identity), \
                patch.object(rebind, "replay", side_effect=replay), patch.object(rebind, "git", side_effect=fake_git), \
                patch.object(rebind, "solver_tree_is_committed", return_value=True), \
                patch.object(sys, "argv", ["rebind.py", "--godot", "godot", "--jobs", "2", "--report", str(report),
                                           "--workspace-root", str(self.workspace)]):
            self.assertEqual(rebind.main(), 0)
        self.assertEqual(len(replayed), 2)
        self.assertFalse(inspected[0].exists())
        receipt = json.loads(report.read_text(encoding="utf-8"))
        self.assertTrue(receipt["identical"])
        self.assertEqual(receipt["copy_mode"], "copy")
        self.assertEqual(receipt["tapes"][0]["orfl_sha256"], hashlib.sha256(self.data).hexdigest())
        self.assertEqual(receipt["tapes"][0]["stored_sha256"], qualification["tape_identities"]["one.orfl.gz"]["stored_sha256"])
        self.assertEqual(receipt["tapes"][0]["tape_encoding"], "gzip")
        self.assertEqual(receipt["tapes"][0]["base_replay_source_sha256"], hashlib.sha256(self.data).hexdigest())
        self.assertEqual(receipt["tapes"][0]["head_replay_source_sha256"], hashlib.sha256(self.data).hexdigest())
        self.no_temporary_tapes()

    def test_compare_keeps_legacy_raw_receipt_schema(self) -> None:
        raw = self.root / "raw.orfl"
        raw.write_bytes(self.data)
        qualification = {"tapes": ["raw.orfl"], "accepted": {"rev": "fixture", "solver_sha256": OLD},
                         "solver_directories": [], "candidate_aircraft": "candidate.json"}

        def replay(_godot, _project, tape, _candidate, output):
            self.assertEqual(tape, raw.resolve())
            output.mkdir(parents=True, exist_ok=True)
            csv = output / "flight.csv"
            csv.write_text("tick\n0\n", encoding="utf-8")
            return {"csv": csv, "csv_sha256": rebind.sha256_file(csv), "rows": 1}

        with patch.object(rebind, "build_baseline", side_effect=lambda workspace, *_args: workspace / "base"), \
                patch.object(rebind, "solver_identity", return_value=OLD), patch.object(rebind, "replay", side_effect=replay):
            results, _workspace = rebind.compare("godot", qualification, 1, False, self.workspace)
        self.assertEqual(set(results[0]), {"tape", "orfl_sha256", "rows", "base_csv_sha256", "head_csv_sha256", "identical"})
        self.assertEqual(results[0]["orfl_sha256"], hashlib.sha256(self.data).hexdigest())
        self.assertEqual(raw.read_bytes(), self.data)

    def test_changed_stored_gzip_is_refused(self) -> None:
        qualification = self.gzip_fixture()
        with self.assertRaisesRegex(rebind.SetupError, "compressed tape or materialized ORFL changed"):
            with rebind.materialized_tapes(qualification, self.workspace) as tapes:
                tapes[0].source.write_bytes(tapes[0].source.read_bytes() + b"changed")
                rebind._check_materialized_tapes(tapes)
        self.no_temporary_tapes()


class CheckedInQualification(unittest.TestCase):
    """The profile pin and the accepted record must never drift apart."""

    def test_profile_and_accepted_record_agree(self) -> None:
        qualification = json.loads(rebind.QUALIFICATION.read_text(encoding="utf-8"))
        self.assertEqual(qualification["format"], "openrc-ai-solver-qualification v1")
        pinned = rebind.pinned_identity(rebind.ROOT / qualification["profile"])
        self.assertEqual(pinned, qualification["accepted"]["solver_sha256"])
        self.assertRegex(qualification["accepted"]["rev"], r"^[0-9a-f]{40}$")

    def test_inputs_exist(self) -> None:
        qualification = json.loads(rebind.QUALIFICATION.read_text(encoding="utf-8"))
        self.assertTrue((rebind.ROOT / qualification["candidate_aircraft"]).is_file())
        self.assertTrue(qualification["tapes"])
        for tape in qualification["tapes"]:
            self.assertTrue((rebind.ROOT / tape).is_file(), tape)
        for directory in qualification["solver_directories"]:
            self.assertTrue((rebind.ROOT / directory).is_dir(), directory)


if __name__ == "__main__":
    unittest.main()
