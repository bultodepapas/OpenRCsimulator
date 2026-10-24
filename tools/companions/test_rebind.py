#!/usr/bin/env python3
"""AFC-02-R3: offline checks of tools/companions/rebind.py (no Godot; behaviour parity is checked by the tool)."""
from __future__ import annotations

import json
import sys
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

            def fail_build(workspace, _revision, _directories):
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
