"""L5 route regression tests; all invalid field fixtures live in temporary directories."""

from __future__ import annotations

import json
import os
from pathlib import Path
import re
import signal
import shutil
import subprocess
import tempfile
import unittest


APP = Path(__file__).resolve().parents[1]
PROBE = "res://tests/probe_field_failure.gd"
FIELD_SOURCE = APP / "data" / "fields" / "default.json"
CASES = {
    "missing": (None, "cannot open field file"),
    "malformed JSON": ("{ not-json\n", "JSON error at line"),
    "bad unit": ("bad_unit", "pilot.north.unit: expected 'm'"),
    "colliding object": ("collision", "objects[0].collides=true is unsupported until L14"),
}


def godot_binary() -> str:
    configured = os.environ.get("OPENRC_TEST_GODOT") or os.environ.get("GODOT")
    if configured:
        return configured
    result = subprocess.run(
        [str(APP / "get-godot.sh")],
        cwd=APP,
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip().splitlines()[-1]


def invalid_payload(case: str) -> str | None:
    if case in {"missing", "malformed JSON"}:
        return None if case == "missing" else str(CASES[case][0])
    field = json.loads(FIELD_SOURCE.read_text(encoding="utf-8"))
    if case == "bad unit":
        field["pilot"]["north"]["unit"] = "ft"
    elif case == "colliding object":
        field["objects"] = [{"id": "tree", "collides": True}]
    else:
        raise AssertionError(f"unknown field failure case: {case}")
    return json.dumps(field, indent=2) + "\n"


class FieldFailureRoutes(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.godot = godot_binary()
        cls.xvfb = shutil.which("xvfb-run")

    def _command(self, headless: bool) -> list[str]:
        command = [self.godot, "--path", str(APP), "--audio-driver", "Dummy"]
        if headless:
            command.append("--headless")
        else:
            command.extend(["--rendering-driver", "opengl3"])
        command.extend(["--script", PROBE])
        return command

    def _run_probe(
        self,
        case: str,
        mode: str,
        *,
        headless: bool,
        language: str = "en",
        png_path: Path | None = None,
    ) -> subprocess.CompletedProcess[str]:
        with tempfile.TemporaryDirectory(prefix="openrc-field-failure-") as scratch:
            field_path = Path(scratch) / "field.json"
            payload = invalid_payload(case)
            if payload is not None:
                field_path.write_text(payload, encoding="utf-8")
            env = os.environ.copy()
            env.update(
                {
                    "OPENRC_TEST_FIELD_PATH": str(field_path),
                    "OPENRC_TEST_MODE": mode,
                    "OPENRC_TEST_LANGUAGE": language,
                    "OPENRC_TEST_EXPECTED_DIAGNOSTIC": CASES[case][1],
                }
            )
            if png_path is not None:
                png_path.parent.mkdir(parents=True, exist_ok=True)
                env["OPENRC_TEST_PNG_PATH"] = str(png_path)
            else:
                env.pop("OPENRC_TEST_PNG_PATH", None)
            command = self._command(headless)
            if not headless:
                if self.xvfb is None:
                    self.skipTest("xvfb-run is not installed; interactive error-panel checks need a display")
                command = [self.xvfb, "-a", "-s", "-screen 0 1280x720x24", *command]
            try:
                process = subprocess.Popen(
                    command,
                    cwd=APP,
                    env=env,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    start_new_session=True,
                )
                try:
                    stdout, stderr = process.communicate(timeout=30)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    stdout, stderr = process.communicate()
                    self.fail(f"probe timed out for {case} / {mode}:\n{stdout}{stderr}")
                return subprocess.CompletedProcess(command, process.returncode, stdout, stderr)
            except OSError as error:
                self.fail(f"could not launch probe for {case} / {mode}: {error}")

    def _assert_clean_diagnostic(self, result: subprocess.CompletedProcess[str], case: str) -> str:
        output = result.stdout + result.stderr
        expected = CASES[case][1]
        self.assertIn("FIELD DATA INVALID:", output, output)
        self.assertIn(expected, output, output)
        self.assertIsNone(re.search(r"(?m)^(?:SCRIPT )?ERROR:", output), output)
        self.assertNotIn("FAIL ", output, output)
        return output

    def test_headless_invalid_fields_fail_both_routes(self) -> None:
        for case in CASES:
            for mode in ("home", "flight"):
                with self.subTest(case=case, mode=mode):
                    result = self._run_probe(case, mode, headless=True)
                    self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                    self._assert_clean_diagnostic(result, case)

    def test_interactive_routes_show_a_focused_localized_error_panel(self) -> None:
        screenshot_env = os.environ.get("OPENRC_TEST_FIELD_FAILURE_PNG")
        screenshot = Path(screenshot_env).expanduser().resolve() if screenshot_env else None
        for mode in ("home", "flight"):
            with self.subTest(mode=mode):
                output_path = screenshot if mode == "home" else None
                language = "es" if mode == "home" else "en"
                result = self._run_probe(
                    "bad unit", mode, headless=False, language=language, png_path=output_path
                )
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                output = self._assert_clean_diagnostic(result, "bad unit")
                self.assertIn("error text follows the selected language", output)
                self.assertIn("keyboard focus starts on Quit", output)
                if output_path is not None:
                    png = output_path.read_bytes()
                    self.assertTrue(png.startswith(b"\x89PNG\r\n\x1a\n"), str(output_path))
                    self.assertGreater(len(png), 4096, str(output_path))


if __name__ == "__main__":
    unittest.main(verbosity=2)
