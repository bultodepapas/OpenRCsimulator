"""Completion markers keep the same acceptance boundary on every pool entry."""
from pathlib import Path
import sys
import unittest

from tools.testqueue import pool_mcp, presets, remote_agent


class CompletionMarkerContracts(unittest.TestCase):
    def admissions(self, markers):
        options = {"script": "res://tests/test_fixture.gd", "require": markers, "timeout": 90}
        request = {"request_id": "markerfixture", "preset": "checked", "options": options,
                   "archive": {"path": str(Path(sys.executable).resolve().parent / "fixture.tar"),
                               "sha256": "a" * 64}, "engine_path": str(Path(sys.executable).resolve())}
        return {
            "local": lambda: presets.validate("checked", options)["require"],
            "mcp": lambda: pool_mcp._jobs([options])[0]["require"],
            "remote": lambda: remote_agent.validate_request(request)["options"]["require"],
        }

    def test_maximum_valid_markers_retain_the_same_literals(self):
        markers = [f"finished {index}: " + "x" * (4096 - len(f"finished {index}: ")) for index in range(128)]
        for name, admit in self.admissions(markers).items():
            with self.subTest(entry=name):
                self.assertEqual(admit(), markers)

    def test_over_limit_and_control_characters_are_rejected_before_placement(self):
        invalid = [["done"] * 129, ["x" * 4097], [""], ["line\nnext"],
                   ["line\rnext"], ["line\0next"], [1], "done", None]
        for markers in invalid:
            for name, admit in self.admissions(markers).items():
                with self.subTest(entry=name, markers=str(markers)[:32]):
                    with self.assertRaises((ValueError, remote_agent.Refused)):
                        admit()


if __name__ == "__main__":
    unittest.main()
