"""Verify generated Stik JSON keeps its historical CRLF byte representation."""
from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_installations  # noqa: E402


def expected_crlf(value: dict) -> bytes:
    text = json.dumps(value, indent=2, ensure_ascii=False) + "\n"
    return text.replace("\n", "\r\n").encode("utf-8")


class InstallationLineEndingTests(unittest.TestCase):
    def test_generator_writes_identical_crlf_bytes_on_any_host(self) -> None:
        payload = {"engine": "fixture", "nested": [1, {"enabled": True}]}
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "generated.json"
            build_installations.write_generated_json(path, payload)
            first = path.read_bytes()
            build_installations.write_generated_json(path, payload)
            second = path.read_bytes()

        self.assertEqual(first, expected_crlf(payload))
        self.assertEqual(second, first)
        self.assertNotIn(b"\n", first.replace(b"\r\n", b""))

    def test_checked_in_installation_and_aircraft_outputs_are_crlf(self) -> None:
        generated = build_installations.outputs()
        self.assertEqual(len(generated), 8)
        for path, value in generated.items():
            with self.subTest(path=path.relative_to(ROOT)):
                self.assertEqual(path.read_bytes(), expected_crlf(value))


if __name__ == "__main__":
    unittest.main()
