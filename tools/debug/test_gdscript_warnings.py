"""PT1h-R8: gdscript_warnings.py pieces that need no editor: script selection and line-independent baseline keys."""
from __future__ import annotations

import contextlib
import io
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gdscript_warnings  # noqa: E402


class GdscriptWarningsTests(unittest.TestCase):
    def test_scripts_skip_captures_and_import_cache_and_honour_patterns(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            app = Path(folder)
            for relative in ("main.gd", "debug/bridge.gd", "captures/old.gd", ".godot/cache.gd", "debug/notes.txt"):
                (app / relative).parent.mkdir(parents=True, exist_ok=True)
                (app / relative).write_text("extends Node\n")
            self.assertEqual(gdscript_warnings.scripts(app, []), ["debug/bridge.gd", "main.gd"])
            self.assertEqual(gdscript_warnings.scripts(app, ["debug/*.gd"]), ["debug/bridge.gd"])

    def test_baseline_keys_ignore_line_numbers(self) -> None:
        moved = {"file": "main.gd", "code": "SHADOWED_VARIABLE", "line": 412,
                 "message": 'The local variable "home" is shadowing an already-declared variable at line 105 in the current class.'}
        edited = dict(moved, line=430, message=moved["message"].replace("line 105", "line 109"))
        other = dict(moved, code="UNUSED_VARIABLE")
        self.assertEqual(gdscript_warnings.key(moved), gdscript_warnings.key(edited))
        self.assertNotEqual(gdscript_warnings.key(moved), gdscript_warnings.key(other))

    def test_diagnostic_code_from_godot_4_8_field_or_4_7_prefix(self) -> None:
        span = {"start": {"line": 142, "character": 5}, "end": {"line": 142, "character": 10}}
        text = 'The local variable "point" is shadowing an already-declared function at line 407 in the current class.'
        current = gdscript_warnings.diagnostic_finding("physics/glow/flight.gd", {"code": "SHADOWED_VARIABLE", "message": text,
                                                                       "range": span, "severity": 2})
        legacy = gdscript_warnings.diagnostic_finding("physics/glow/flight.gd", {"message": "(SHADOWED_VARIABLE): " + text,
                                                                      "range": span, "severity": 2})
        error = gdscript_warnings.diagnostic_finding("main.gd", {"message": "Parse Error: Expected expression.", "range": span, "severity": 1})
        self.assertEqual(current, legacy)
        self.assertEqual((current["code"], current["line"], current["severity"], current["message"]),
                         ("SHADOWED_VARIABLE", 143, "warning", text))
        self.assertEqual((error["code"], error["severity"]), ("ERROR", "error"))

    def test_output_rejects_all_repository_scripts_and_source_aliases_before_collection(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            repo = Path(folder)
            app = repo / "app"
            app.mkdir()
            selected, unselected = app / "selected.gd", app / "unselected.gd"
            other = repo / "research" / "model.gd"
            other.parent.mkdir()
            own_source = repo / "tools" / "debug" / "gdscript_warnings.py"
            own_source.parent.mkdir(parents=True)
            project = app / "project.godot"
            for source in (selected, unselected, other, own_source, project):
                source.write_text("source contents\n", encoding="utf-8")
            targets = [selected, unselected, other, own_source, project, app / "new.gd"]
            symlink = repo / "alias.json"
            try:
                symlink.symlink_to(unselected)
                targets.append(symlink)
            except OSError:
                pass  # Windows may lack symlink creation permission.
            hardlink = repo / "hardlink.json"
            try:
                os.link(other, hardlink)
                targets.append(hardlink)
            except OSError:
                pass
            with patch.object(gdscript_warnings, "REPO", repo), \
                    patch.object(gdscript_warnings, "__file__", str(own_source)), \
                    patch.object(gdscript_warnings, "collect") as collect:
                for flag in ("--out", "--write-baseline"):
                    for target in targets:
                        with self.subTest(flag=flag, target=target):
                            err = io.StringIO()
                            with contextlib.redirect_stderr(err):
                                code = gdscript_warnings.main(["--in-place", "--files", "selected.gd", flag, str(target)])
                            self.assertEqual(code, 2)
                            self.assertIn("aliases", err.getvalue())
                            collect.assert_not_called()
            for source in (selected, unselected, other, own_source, project):
                self.assertEqual(source.read_text(encoding="utf-8"), "source contents\n")
            self.assertFalse((app / "new.gd").exists())

    def test_does_not_remove_another_runs_snapshot_on_preflight_or_name_collision(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            repo = Path(folder)
            app = repo / "app"
            app.mkdir()
            script = app / "selected.gd"
            script.write_text("extends Node\n")
            other_snapshot = repo / "tmp" / "gdscript-warnings" / "occupied" / "snapshot"
            other_snapshot.mkdir(parents=True)
            sentinel = other_snapshot / "sentinel"
            sentinel.write_text("another run is active")

            def create_snapshot(out):
                target = out / "snapshot" / "app"
                target.mkdir(parents=True)
                (target / "selected.gd").write_text("extends Node\n")
                return target

            with patch.object(gdscript_warnings, "REPO", repo), \
                    patch.object(gdscript_warnings.time, "strftime", return_value="occupied"), \
                    patch.object(gdscript_warnings, "collect") as collect:
                for args in (["--out", str(script)], ["--baseline", str(repo / "missing.json")], []):
                    with self.subTest(args=args), contextlib.redirect_stderr(io.StringIO()):
                        self.assertEqual(gdscript_warnings.main(args), 2)
                    self.assertEqual(sentinel.read_text(), "another run is active")
                    collect.assert_not_called()
            with patch.object(gdscript_warnings, "REPO", repo), \
                    patch.object(gdscript_warnings.time, "strftime", return_value="owned"), \
                    patch.object(gdscript_warnings, "snapshot", side_effect=create_snapshot), \
                    patch.object(gdscript_warnings, "collect", return_value=[]), \
                    contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(gdscript_warnings.main([]), 0)
            own = repo / "tmp" / "gdscript-warnings" / "owned"
            self.assertFalse((own / "snapshot").exists())
            self.assertTrue((own / "report.json").exists())
            self.assertEqual(sentinel.read_text(), "another run is active")

    def test_source_identities_are_checked_once_per_validation(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            repo = Path(folder)
            app = repo / "app"
            app.mkdir()
            scripts = [app / f"script-{index}.gd" for index in range(6)]
            outputs = [repo / f"report-{index}.json" for index in range(3)]
            for path in scripts + outputs:
                path.write_text("fixture")
            counts = {path: 0 for path in scripts}
            real_stat = Path.stat

            def count_stat(path, *args, **kwargs):
                if path in counts:
                    counts[path] += 1
                return real_stat(path, *args, **kwargs)

            with patch.object(gdscript_warnings, "REPO", repo), patch.object(Path, "stat", count_stat):
                gdscript_warnings.validate_outputs(outputs, None, None)
            self.assertEqual(list(counts.values()), [1] * len(scripts))

    def test_reports_refuse_baseline_aliases_before_collection(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            repo = Path(folder)
            (repo / "app").mkdir()
            (repo / "app" / "selected.gd").write_text("extends Node\n")
            baseline = repo / "baseline.json"
            original = json.dumps({"keys": []})
            baseline.write_text(original)
            aliases = [baseline]
            symlink = repo / "baseline-link.json"
            try:
                symlink.symlink_to(baseline)
                aliases.append(symlink)
            except OSError:
                pass
            hardlink = repo / "baseline-hard.json"
            try:
                os.link(baseline, hardlink)
                aliases.append(hardlink)
            except OSError:
                pass
            with patch.object(gdscript_warnings, "REPO", repo), patch.object(gdscript_warnings, "collect") as collect:
                for target in aliases:
                    with self.subTest(target=target), contextlib.redirect_stderr(io.StringIO()):
                        code = gdscript_warnings.main(["--in-place", "--baseline", str(baseline), "--out", str(target)])
                        self.assertEqual(code, 2)
                        collect.assert_not_called()
                target = repo / "new.json"
                with contextlib.redirect_stderr(io.StringIO()):
                    code = gdscript_warnings.main(["--in-place", "--out", str(target), "--write-baseline", str(target)])
                self.assertEqual(code, 2)
                collect.assert_not_called()
            self.assertEqual(baseline.read_text(), original)

    def test_refreshing_baseline_compares_the_preexisting_keys(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            repo = Path(folder)
            (repo / "app").mkdir()
            (repo / "app" / "selected.gd").write_text("extends Node\n")
            baseline = repo / "baseline.json"
            baseline.write_text(json.dumps({"keys": []}), encoding="utf-8")
            finding = {"file": "selected.gd", "line": 2, "severity": "warning",
                       "code": "UNUSED_VARIABLE", "message": "La variable niño no se usa."}
            with patch.object(gdscript_warnings, "REPO", repo), \
                    patch.object(gdscript_warnings, "collect", return_value=[finding]), \
                    patch.object(gdscript_warnings.time, "strftime", side_effect=["first", "second"]):
                output = io.StringIO()
                with contextlib.redirect_stdout(output):
                    status = gdscript_warnings.main(["--in-place", "--baseline", str(baseline),
                                                    "--write-baseline", str(baseline)])
                self.assertEqual(status, 1)
                self.assertIn("1 new warnings", output.getvalue())
                self.assertEqual(json.loads(baseline.read_text(encoding="utf-8"))["keys"],
                                 [gdscript_warnings.key(finding)])
                with contextlib.redirect_stdout(io.StringIO()):
                    self.assertEqual(gdscript_warnings.main(["--in-place", "--baseline", str(baseline)]), 0)

    def test_baseline_read_and_write_use_utf8_under_non_utf8_locale(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            repo = Path(folder)
            (repo / "app").mkdir()
            (repo / "app" / "selected.gd").write_text("extends Node\n")
            finding = {"file": "selected.gd", "line": 1, "severity": "warning",
                       "code": "UNUSED_VARIABLE", "message": "niño × ejemplo"}
            baseline = repo / "baseline.json"
            baseline.write_bytes(json.dumps({"keys": [gdscript_warnings.key(finding)]}, ensure_ascii=False).encode("utf-8"))
            real_path_open = Path.open
            def simulated_open(path, mode="r", buffering=-1, encoding=None, errors=None, newline=None):
                if "b" not in mode and encoding in (None, "locale"):
                    encoding = "cp1252"
                return real_path_open(path, mode=mode, buffering=buffering, encoding=encoding, errors=errors, newline=newline)
            with patch.object(gdscript_warnings, "REPO", repo), \
                    patch.object(gdscript_warnings, "collect", return_value=[finding]), \
                    patch.object(Path, "open", simulated_open), contextlib.redirect_stdout(io.StringIO()):
                status = gdscript_warnings.main(["--in-place", "--baseline", str(baseline), "--write-baseline", str(baseline)])
            self.assertEqual(status, 0)
            self.assertIn("niño × ejemplo", baseline.read_bytes().decode("utf-8"))

    def test_atomic_publication_preserves_outputs_on_failure_and_follows_symlinks(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            repo = Path(folder)
            (repo / "app").mkdir()
            (repo / "app" / "selected.gd").write_text("extends Node\n")
            artifacts = repo / "artifacts"
            artifacts.mkdir()
            destination = artifacts / "existing.json"
            old = '{"keys": []}\n'
            destination.write_text(old)
            before = set(artifacts.iterdir())
            real_replace = os.replace
            def fail_destination(source, target):
                if Path(target) == destination.resolve():
                    raise OSError("injected replacement failure")
                return real_replace(source, target)
            with patch.object(gdscript_warnings, "REPO", repo), \
                    patch.object(gdscript_warnings, "collect", return_value=[]), \
                    patch.object(gdscript_warnings.time, "strftime", side_effect=["report", "report-sync", "baseline", "baseline-sync", "symlink"]):
                for args in (["--out", str(destination)], ["--baseline", str(destination), "--write-baseline", str(destination)]):
                    for failure in ("replace", "fsync"):
                        injected = (patch.object(gdscript_warnings.os, "replace", side_effect=fail_destination)
                                    if failure == "replace" else
                                    patch.object(gdscript_warnings.os, "fsync", side_effect=[None, OSError("injected sync failure")]))
                        with self.subTest(args=args, failure=failure), injected, contextlib.redirect_stderr(io.StringIO()):
                            self.assertEqual(gdscript_warnings.main(["--in-place", *args]), 2)
                        self.assertEqual(destination.read_text(), old)
                        self.assertEqual(set(artifacts.iterdir()), before)
                link = artifacts / "report-link.json"
                try:
                    link.symlink_to(destination)
                except OSError:
                    return
                os.chmod(destination, 0o640)
                with contextlib.redirect_stdout(io.StringIO()):
                    self.assertEqual(gdscript_warnings.main(["--in-place", "--out", str(link)]), 0)
                self.assertTrue(link.is_symlink())
                self.assertEqual(json.loads(destination.read_text())["format"], "openrc-gdscript-diagnostics v1")
                if os.name != "nt":
                    self.assertEqual(destination.stat().st_mode & 0o777, 0o640)


if __name__ == "__main__":
    unittest.main()
