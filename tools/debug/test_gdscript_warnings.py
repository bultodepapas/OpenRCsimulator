"""PT1h-R8: gdscript_warnings.py pieces that need no editor: script selection and line-independent baseline keys."""
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

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
        current = gdscript_warnings.finding("physics/glow/flight.gd", {"code": "SHADOWED_VARIABLE", "message": text,
                                                                       "range": span, "severity": 2})
        legacy = gdscript_warnings.finding("physics/glow/flight.gd", {"message": "(SHADOWED_VARIABLE): " + text,
                                                                      "range": span, "severity": 2})
        error = gdscript_warnings.finding("main.gd", {"message": "Parse Error: Expected expression.", "range": span, "severity": 1})
        self.assertEqual(current, legacy)
        self.assertEqual((current["code"], current["line"], current["severity"], current["message"]),
                         ("SHADOWED_VARIABLE", 143, "warning", text))
        self.assertEqual((error["code"], error["severity"]), ("ERROR", "error"))


if __name__ == "__main__":
    unittest.main()
