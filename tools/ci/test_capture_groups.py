#!/usr/bin/env python3
"""Exercise capture scheduling with disposable command stubs; no Godot is run."""
from collections import Counter
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
GROUPS = ("core", "ui", "quality", "terrain-atmosphere", "ground", "vegetation", "scenario")
EXPECTED_IMAGES = [f"capture{suffix}.png" for suffix in
                   ("", "-inspect", "-inspect-deflected", "-physics", "-physics-inspect", "-physics-nozoom",
                    "-physics-low-inspect", "-physics-low-inspect-noplane", "-physics-inspect-noplane")]
EXPECTED_IMAGES += [f"capture-land-az{az}-el{el}.png" for az in (0, 90, 180, 270) for el in (0, 10)]
EXPECTED_IMAGES += ["capture-land-az90-el10-t11.png"]
EXPECTED_IMAGES += [f"capture-land-az{az}-el0-100m.png" for az in (0, 90, 180, 225, 270)]
EXPECTED_IMAGES += [f"capture-land-{name}.png" for name in ("30m", "low3m", "sun", "30m-noplane", "low3m-noplane", "top")]
EXPECTED_IMAGES += [f"field/capture-land-az{az}-el{el}.png" for az in (0, 90, 180, 270) for el in (0, 10)]
EXPECTED_IMAGES += ["field/capture-land-top.png"]
EXPECTED_IMAGES += [f"ui-{screen}-{lang}.png" for lang in ("en", "es") for screen in ("home", "pause", "help", "hint")]
EXPECTED_CHECKERS = ["test_capture_runner.py", "check_landscape_captures.py", "compare_captures.py",
                     "check_trimmed_flight.py", "test_visual_quality_cases.py", "visual_quality_cases.py",
                     "test_field_failures.py", "check_review.py", "check_horizon.py", "check_phase6.py",
                     "check_cloud_probe.py", "check_surfaces.py", "test_stripes.py", "check_stripes.py",
                     "check_windsock.py", "check_windsock.py", "check_windsock.py", "check_windsock.py",
                     "check_grass.py", "check_grass_seam.py", "check_wind.py", "test_treeline_readability.py",
                     "treeline_readability.py", "scenario.sh"]

# Both Python entry points and Godot log their exact invocations after paths are
# normalized. Stub output is only sufficient to exercise the shell's sequencing
# and final manifest writer; it does not pretend to be rendered evidence.
STUB = r'''#!/usr/bin/python3
import hashlib, json, os, pathlib, sys
from pathlib import Path
args = sys.argv[1:]
env = os.environ
root, app, out = env['FAKE_ROOT'], env['FAKE_APP'], env['FAKE_OUT']
def normalize(value):
    return value.replace(out, 'OUT').replace(app, 'APP').replace(root, 'ROOT')
name = Path(sys.argv[0]).name
entry = [name] + args
with open(env['FAKE_LOG'], 'a') as stream:
    stream.write(json.dumps([normalize(x) for x in entry]) + '\n')
if env.get('FAKE_FAIL') and any(env['FAKE_FAIL'] in a for a in args):
    sys.exit(12)
def write(path, data='{}'):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(data)
def opt(key):
    return args[args.index(key) + 1] if key in args else ''
if name == 'godot':
    for arg in args:
        if arg.startswith('--trace='):
            write(arg.split('=', 1)[1], 'trace')
    target = next((a.split('=', 1)[1] for a in args if a.startswith('--out=')), '')
    if target and 'capture_aircraft_lights.gd' in ' '.join(args):
        write(Path(target) / 'summary.json')
    if target and 'capture_landscape_upgrade.gd' in ' '.join(args):
        write(Path(target) / 'report.json')
elif args and args[0] == '-':
    # Execute the real inline manifest code, against synthetic files.
    sys.argv = ['-'] + args[1:]
    exec(sys.stdin.read(), {'__name__': '__main__'})
elif args:
    script = Path(args[0]).name
    target = opt('--out')
    if script == 'capture_runner.py':
        path = Path(target)
        write(path, 'synthetic image')
        write(path.with_suffix('.json'), json.dumps({'image': path.name, 'capture_scene': opt('--scene'),
              'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}))
        write(path.with_suffix('.log'), f'saved {path} (error 0) draw_calls=1 primitives=1\n')
    else:
        summaries = {'visual_quality_cases.py': 'visual-quality-run-manifest.json',
          'check_review.py': 'repeat-1/review.json', 'check_horizon.py': 'capture-summary.json',
          'check_phase6.py': 'capture-summary.json', 'check_cloud_probe.py': 'summary.json',
          'check_surfaces.py': 'summary.json', 'check_stripes.py': 'summary.json',
          'check_windsock.py': 'summary.json', 'check_grass.py': 'capture-summary.json',
          'check_wind.py': 'capture-summary.json', 'treeline_readability.py': 'l6c-run-manifest.json'}
        if target and script in summaries:
            write(Path(target) / summaries[script])
        if target and script == 'check_grass_seam.py':
            write(target)
'''


@unittest.skipIf(os.name == 'nt', 'requires Linux or WSL shell utilities')
class CaptureGroupsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.app = self.root / "app"
        (self.app / "tests").mkdir(parents=True)
        (self.root / "tools/scenery").mkdir(parents=True)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        for name in ("godot", "python3"):
            path = self.bin / name
            path.write_text(STUB)
            path.chmod(0o755)
        self.executable(self.bin / "xvfb-run", '#!/bin/bash\nshift\nif [[ "$1" == -s ]]; then shift 2; fi\nexec "$@"\n')
        self.executable(self.app / "get-godot.sh", '#!/bin/bash\nprintf "%s\\n" "$FAKE_ROOT/bin/godot"\n')
        self.executable(self.app / "tests/visual-env.sh", '#!/bin/bash\nprintf "%s\\n" "$FAKE_ROOT/bin/python3"\n')
        self.executable(self.root / "tools/scenery/scenario.sh", '#!/bin/bash\nexec "$FAKE_ROOT/bin/python3" scenario.sh "$@"\n')
        self.log = self.root / "commands.jsonl"
        self.env = dict(os.environ, PATH=f"{self.bin}:{os.environ['PATH']}", FAKE_ROOT=str(self.root),
                        FAKE_APP=str(self.app), FAKE_LOG=str(self.log))
        self.current = (ROOT / "app/capture.sh").read_text(encoding="utf-8")

    def tearDown(self):
        self.temp.cleanup()

    @staticmethod
    def executable(path, content):
        path.write_text(content, encoding="utf-8")
        path.chmod(0o755)

    def run_capture(self, content, group=None, failure=None):
        self.executable(self.app / "capture.sh", content)
        if (self.app / "captures").exists():
            shutil.rmtree(self.app / "captures")
        self.log.unlink(missing_ok=True)
        output = self.root / f"out-{group}" if group else self.app / "captures"
        if output.exists():
            shutil.rmtree(output)
        env = dict(self.env, FAKE_OUT=str(output))
        if failure:
            env["FAKE_FAIL"] = failure
        command = ["bash", str(self.app / "capture.sh")]
        if group:
            command += ["--group", group, "--out", str(output)]
        result = subprocess.run(command, env=env, capture_output=True, text=True)
        calls = [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []
        return result, output, calls

    def test_default_runs_fixed_roster_and_emits_complete_manifest(self):
        new, new_out, new_calls = self.run_capture(self.current)
        self.assertEqual(new.returncode, 0, new.stderr + new.stdout)
        manifest = json.loads((new_out / "run-manifest.json").read_text())
        self.assertEqual(manifest['format'], 'openrc-capture-set v1')
        self.assertIs(manifest['complete'], True)
        self.assertEqual([entry['image'] for entry in manifest['captures']], EXPECTED_IMAGES)
        checkers = [Path(call[1]).name for call in new_calls if call[0] == 'python3'
                    and Path(call[1]).name not in ('capture_runner.py', '-')]
        self.assertEqual(checkers, EXPECTED_CHECKERS)
        self.assertEqual(sum(call[0] == 'python3' and Path(call[1]).name == 'capture_runner.py'
                             for call in new_calls), len(EXPECTED_IMAGES))
        self.assertEqual((new_out / 'timings.tsv').read_text().splitlines()[-1].split('\t')[0], 'scenario')

    def test_groups_cover_original_commands_once_without_complete_manifest(self):
        full, _, full_calls = self.run_capture(self.current)
        self.assertEqual(full.returncode, 0, full.stderr + full.stdout)
        partial_calls = []
        for group in GROUPS:
            result, output, calls = self.run_capture(self.current, group)
            self.assertEqual(result.returncode, 0, f'{group}: {result.stderr}{result.stdout}')
            self.assertFalse((output / "run-manifest.json").exists())
            self.assertIn("partial capture group", result.stdout)
            self.assertTrue((output / "timings.tsv").is_file())
            # Setup is common to each isolated run; the manifest is full-only.
            partial_calls.extend(c for c in calls if 'test_capture_runner.py' not in ' '.join(c)
                                 and '--import' not in c)
        full_calls = [c for c in full_calls if 'test_capture_runner.py' not in ' '.join(c)
                      and '--import' not in c and c[1:2] != ['-']]
        self.assertEqual(Counter(map(tuple, full_calls)), Counter(map(tuple, partial_calls)))

    def test_failing_checker_retains_timing_and_never_publishes_complete_marker(self):
        result, output, _ = self.run_capture(self.current, 'ground', 'check_stripes.py')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((output / 'run-manifest.json').exists())
        self.assertIn('ground\t', (output / 'timings.tsv').read_text())
        self.assertIn('fail (12)', (output / 'timings.tsv').read_text())

    def test_failed_full_setup_clears_old_complete_marker(self):
        self.executable(self.app / 'capture.sh', self.current)
        output = self.app / 'captures'
        output.mkdir()
        (output / 'run-manifest.json').write_text('{"complete": true}')
        env = dict(self.env, FAKE_OUT=str(output), FAKE_FAIL='--import')
        result = subprocess.run(['bash', str(self.app / 'capture.sh')], env=env, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((output / 'run-manifest.json').exists())
        self.assertIn('setup\t', (output / 'timings.tsv').read_text())

    def test_invalid_or_stale_output_fails_before_running_a_checker(self):
        self.executable(self.app / 'capture.sh', self.current)
        output = self.root / 'already-exists'
        output.mkdir()
        for args in (['--group', 'unknown', '--out', str(self.root / 'new')],
                     ['--group', 'core', '--out', 'relative'],
                     ['--group', 'core', '--out', str(output)],
                     ['--group', 'core', '--out', str(self.app / 'new')],
                     ['--out', str(self.root / 'new')]):
            result = subprocess.run(['bash', str(self.app / 'capture.sh'), *args], env=self.env, capture_output=True)
            self.assertNotEqual(result.returncode, 0, args)
        self.assertFalse(self.log.exists())


if __name__ == '__main__':
    unittest.main()
