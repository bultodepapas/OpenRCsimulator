"""TQ-07-A6: ``serve`` remembers its slot counts; a restart without flags keeps them."""
from __future__ import annotations

import json
from pathlib import Path
import tempfile
import unittest

from tools.testqueue.testctl import parser, serve_capacity


class ServeCapacityTests(unittest.TestCase):
    def test_flags_are_remembered_and_reused_by_a_bare_restart(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.assertEqual(serve_capacity(root), (1, 1))  # nothing remembered: the conservative default
            self.assertFalse((root / "capacity.json").exists())
            self.assertEqual(serve_capacity(root, 2, None), (2, 1))
            self.assertEqual(serve_capacity(root), (2, 1))  # the watchdog's restart passes no flags
            self.assertEqual(serve_capacity(root, None, 3), (2, 3))
            self.assertEqual(json.loads((root / "capacity.json").read_text())["capture_slots"], 3)
            for bad in ((0, None), (9, None), (None, 5)):
                with self.subTest(bad=bad), self.assertRaises(ValueError):
                    serve_capacity(root, *bad)
            self.assertEqual(serve_capacity(root), (2, 3))  # a refused value is never remembered
            (root / "capacity.json").write_text("{ broken")
            with self.assertRaisesRegex(ValueError, "unreadable"):
                serve_capacity(root)

    def test_parser_leaves_slots_unset_without_flags(self):
        args = parser().parse_args(["serve", "--engine", "godot.exe"])
        self.assertIsNone(args.headless_slots)
        self.assertIsNone(args.capture_slots)


if __name__ == "__main__":
    unittest.main()
