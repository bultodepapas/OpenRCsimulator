"""Verify fixed-FPS comparisons reject missing, malformed or unequal evidence."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "tools/ci/fixed_fps_digest.py"
DIGEST = "a" * 64


class FixedFpsDigestTests(unittest.TestCase):
    def extract(self, field, fps, output):
        return subprocess.run([sys.executable, str(HELPER), field, str(fps)], input=output,
                              capture_output=True, text=True)

    def test_extracts_one_complete_token_and_rejects_other_occurrences(self):
        for field in ("state_sha256", "flight_sha256"):
            valid = f"ticks=480 {field}={DIGEST}\n"
            result = self.extract(field, 30, valid)
            self.assertEqual((result.returncode, result.stdout), (0, DIGEST + "\n"))
            cases = ("ticks=480\n", f"{field}={'a' * 63}\n", f"{field}={'A' * 64}\n",
                     f"{field}={DIGEST}x\n", valid + valid,
                     valid + f"{field}=bad\n", f"{field}={DIGEST} {field}=bad\n")
            for output in cases:
                with self.subTest(field=field, output=output):
                    result = self.extract(field, 60, output)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn(f"60 fps: expected exactly one valid {field} digest", result.stderr)


@unittest.skipIf(os.name == "nt", "requires Bash")
class FixedFpsShellTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.outputs = Path(self.temp.name)
        script = (ROOT / "app/test.sh").read_text(encoding="utf-8")
        start = script.index('echo "== fixed step:')
        end = script.index('echo "== E0b5:', start)
        self.block = script[start:end]

    def write_outputs(self, changed=None):
        for kind, field in (("state", "state_sha256"), ("flight", "flight_sha256")):
            for fps in (30, 60, 144):
                value = DIGEST
                suffix = ""
                if changed and (kind, fps) == changed[:2]:
                    case = changed[2]
                    if case == "missing": value = None
                    elif case == "malformed": value = "a" * 63 + "g"
                    elif case == "duplicate": suffix = f"\n{field}={DIGEST}"
                    elif case == "unequal": value = "b" * 64
                token = f" {field}={value}" if value is not None else ""
                (self.outputs / f"{kind}-{fps}").write_text(f"ticks=480{token}{suffix}\n")

    def run_block(self):
        stub = r'''set -euo pipefail
run() {
  local fps="$2" kind=state
  if [[ " $* " == *" --aircraft=turbo-lumber-evolution "* ]]; then kind=flight; fi
  cat "$FPS_FIXTURES/$kind-$fps"
}
'''
        env = dict(os.environ, HERE=str(ROOT / "app"), FPS_FIXTURES=str(self.outputs))
        return subprocess.run(["bash", "-c", stub + self.block], env=env, capture_output=True, text=True)

    def test_all_three_fps_are_required_before_comparison(self):
        self.write_outputs()
        result = self.run_block()
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        for kind in ("state", "flight"):
            for fps in (30, 60, 144):
                for case in ("missing", "malformed", "duplicate", "unequal"):
                    with self.subTest(kind=kind, fps=fps, case=case):
                        self.write_outputs((kind, fps, case))
                        result = self.run_block()
                        self.assertNotEqual(result.returncode, 0, result.stderr + result.stdout)
                        if case == "unequal":
                            self.assertIn("depends on the rendering frame rate", result.stdout)
                        else:
                            self.assertIn(f"{fps} fps: expected exactly one valid", result.stderr)


if __name__ == "__main__":
    unittest.main()
