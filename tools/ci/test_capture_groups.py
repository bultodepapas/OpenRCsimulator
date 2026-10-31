#!/usr/bin/env python3
"""Exercise capture scheduling with disposable command stubs; no Godot is run."""
from collections import Counter
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

import capture_groups as receipts

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
if env.get('FAKE_MUTATE') and any(env['FAKE_MUTATE'] in a for a in args):
    Path(app, 'tests/capture_runner.py').write_text('changed during run')
if name == 'python3' and args and Path(args[0]).name == 'capture_groups.py':
    os.execv('/usr/bin/python3', ['/usr/bin/python3', *args])
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
        write(Path(target) / 'summary.json', '{"ok": true}')
    if target and 'capture_landscape_upgrade.gd' in ' '.join(args):
        write(Path(target) / 'report.json')
        write(Path(target) / 'sun_alignment.png', 'synthetic alignment')
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
            if script in ('visual_quality_cases.py', 'treeline_readability.py'):
                ids = json.loads(env['FAKE_VQ_CASES'] if script == 'visual_quality_cases.py' else env['FAKE_TREE_CASES'])
                count = len(ids)
                captures = []
                for case in ids:
                    image, sidecar = Path(target) / f'{case}.png', Path(target) / f'{case}.json'
                    write(image, case)
                    sha = hashlib.sha256(image.read_bytes()).hexdigest()
                    scene = case.split('-')[1] if case.startswith('ui-') else 'field'
                    write(sidecar, json.dumps({'image': image.name, 'sha256': sha, 'capture_scene': scene}))
                    captures.append({'case_id': case, 'image': image.name,
                        'sha256': sha,
                        'capture_manifest': sidecar.name,
                        'capture_manifest_sha256': hashlib.sha256(sidecar.read_bytes()).hexdigest()})
                data = {'complete': True, 'inventory': {'expected_case_ids': ids, 'capture_count': count},
                        'captures': captures}
                write(Path(target) / summaries[script], json.dumps(data))
            else:
                write(Path(target) / summaries[script])
        if target and script == 'check_grass_seam.py':
            write(target)
        if script == 'scenario.sh':
            latest = Path(args[1]) / 'latest'
            write(latest / 'scenario.json')
            write(latest / 'sync.json', '[{"ok": true}]')
            write(latest / 'report.html', '<html>synthetic</html>')
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
        excluded = ('OPENRC_', 'GODOT_', 'MESA_', 'LIBGL_', 'GALLIUM_', 'LP_', 'VK_')
        self.env = {key: value for key, value in os.environ.items() if not key.startswith(excluded)}
        self.env.update(PATH=f"{self.bin}:{os.environ['PATH']}", FAKE_ROOT=str(self.root),
                        FAKE_APP=str(self.app), FAKE_LOG=str(self.log),
                        FAKE_VQ_CASES=json.dumps(receipts.VQ_CASES), FAKE_TREE_CASES=json.dumps(receipts.TREELINE_CASES))
        self.current = (ROOT / "app/capture.sh").read_text(encoding="utf-8")

    def tearDown(self):
        self.temp.cleanup()

    @staticmethod
    def executable(path, content):
        path.write_text(content, encoding="utf-8")
        path.chmod(0o755)

    def run_capture(self, content, group=None, failure=None, run_id=None, mutation=None):
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
        if mutation:
            env["FAKE_MUTATE"] = mutation
        command = ["bash", str(self.app / "capture.sh")]
        if group:
            command += ["--group", group, "--out", str(output)]
        if run_id is not None:
            command += ["--run-id", run_id]
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
                     ['--group', 'core', '--out', str(self.root / 'new'), '--run-id', ''],
                     ['--group', 'core', '--out', str(self.root / 'new'), '--run-id', '../bad'],
                     ['--out', str(self.root / 'new')]):
            result = subprocess.run(['bash', str(self.app / 'capture.sh'), *args], env=self.env, capture_output=True)
            self.assertNotEqual(result.returncode, 0, args)
        self.assertFalse(self.log.exists())

    def test_matrix_rosters_match_current_producers(self):
        code = '''
import sys, types
from pathlib import Path
root = Path(sys.argv[1])
sys.path[:0] = [str(root / "tools/ci"), str(root / "app/tests")]
runner = types.ModuleType("capture_runner")
runner.run_capture = lambda *args, **kwargs: None
sys.modules["capture_runner"] = runner
sys.modules["numpy"] = types.ModuleType("numpy")
compare = types.ModuleType("compare_captures")
compare.difference_mask = compare.load = compare.measure_pair = lambda *args: None
sys.modules["compare_captures"] = compare
import capture_groups, visual_quality_cases, treeline_readability
assert capture_groups.VQ_CASES == [case.case_id for case in visual_quality_cases.capture_cases()]
assert capture_groups.TREELINE_CASES == [case.case_id for case in treeline_readability.capture_cases()]
'''
        result = subprocess.run([sys.executable, '-c', code, str(ROOT)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def prepare_receipts(self):
        for name in receipts.DIRECT_SOURCES:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            if not path.exists():
                path.write_text('fixture source\n')
        shutil.copyfile(ROOT / 'tools/ci/capture_groups.py', self.root / 'tools/ci/capture_groups.py')
        self.executable(self.app / 'capture.sh', self.current)
        (self.root / '.gitignore').write_text('/out-*\n/bin/\n/commands.jsonl\n/app/captures/\n/results/\n')
        for command in (['git', 'init', '-q'], ['git', 'add', '.'],
                        ['git', '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid',
                         'commit', '-qm', 'fixture']):
            subprocess.run(command, cwd=self.root, check=True, capture_output=True)
        return subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=self.root, text=True).strip()

    def reduce(self, parts, commit, output, run_id='run-1', godot=None, visual_python=None):
        return subprocess.run([sys.executable, str(self.root / 'tools/ci/capture_groups.py'), 'reduce',
            '--repo', str(self.root), '--run-id', run_id, '--expect-commit', commit,
            '--godot', str(godot or self.bin / 'godot'),
            '--visual-python', str(visual_python or self.bin / 'python3'),
            '--out', str(output), '--parts', *map(str, parts)], capture_output=True, text=True)

    def test_receipts_reduce_and_reject_incomplete_stale_or_changed_evidence(self):
        commit = self.prepare_receipts()
        self.env['OPENRC_CODE_REVISION'] = 'forged-override'
        forged, forged_output, _ = self.run_capture(self.current, 'ui', run_id='run-1')
        self.assertNotEqual(forged.returncode, 0)
        self.assertFalse((forged_output / receipts.RECEIPT).exists())
        del self.env['OPENRC_CODE_REVISION']
        parts = []
        for group in GROUPS:
            result, output, _ = self.run_capture(self.current, group, run_id='run-1')
            self.assertEqual(result.returncode, 0, f'{group}: {result.stderr}{result.stdout}')
            self.assertFalse((output / 'run-manifest.json').exists())
            receipt = json.loads((output / receipts.RECEIPT).read_text())
            self.assertEqual(receipt['start']['source']['commit'], commit)
            parts.append(output)

        results = self.root / 'results'
        accepted = results / 'accepted.json'
        result = self.reduce(parts, commit, accepted)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(json.loads(accepted.read_text())['production_qualified'])
        self.assertFalse((results / 'run-manifest.json').exists())
        original_result = accepted.read_bytes()
        result = self.reduce(parts, commit, accepted)
        self.assertNotEqual(result.returncode, 0, 'an existing result must not be overwritten')
        self.assertEqual(accepted.read_bytes(), original_result)

        def reject(label, selected=None, expected_commit=commit, run_id='run-1', godot=None, visual_python=None,
                   error_contains=None):
            destination = results / f'{label}.json'
            result = self.reduce(parts if selected is None else selected, expected_commit, destination,
                                 run_id=run_id, godot=godot, visual_python=visual_python)
            self.assertNotEqual(result.returncode, 0, label)
            self.assertFalse(destination.exists(), label)
            if error_contains:
                self.assertIn(error_contains, result.stderr)

        reject('missing', parts[:-1])
        reject('duplicate', parts + [parts[0]])
        reject('stale-run', run_id='run-2')
        reject('wrong-commit', expected_commit='0' * 40)
        other_engine = self.bin / 'different-godot'
        other_engine.write_text('different engine')
        reject('wrong-engine', godot=other_engine)
        reject('wrong-interpreter', visual_python=other_engine)

        receipt_path = parts[1] / receipts.RECEIPT
        original_receipt = receipt_path.read_text()
        data = json.loads(original_receipt)
        data['start']['config']['environment']['LP_NUM_THREADS'] = '2'
        receipt_path.write_text(json.dumps(data))
        reject('wrong-config')
        data = json.loads(original_receipt)
        data['status'] = 'failed'
        receipt_path.write_text(json.dumps(data))
        reject('failed-group')
        receipt_path.unlink()
        reject('missing-receipt')
        receipt_path.write_text(original_receipt)
        receipt_path.write_text(original_receipt.replace('"status": "passed"',
                                                         '"status": "failed", "status": "passed"'))
        reject('duplicate-json-key', error_contains='duplicate JSON key')
        receipt_path.write_text(original_receipt)
        data = json.loads(original_receipt)
        data['start']['config']['historical_viewport'][0] = 1280.0
        receipt_path.write_text(json.dumps(data))
        reject('wrong-config-type')
        receipt_path.write_text(original_receipt)
        data = json.loads(original_receipt)
        data['outputs'] = []
        receipt_path.write_text(json.dumps(data))
        reject('wrong-receipt-type')
        receipt_path.write_text(original_receipt)
        data = json.loads(original_receipt)
        data['start']['group'] = 'unknown'
        receipt_path.write_text(json.dumps(data))
        reject('unexpected-group')
        receipt_path.write_text(original_receipt)

        image = parts[0] / receipts.CORE_IMAGES[0]
        original_image = image.read_bytes()
        image.write_bytes(b'corrupt')
        reject('corrupt-image')
        image.write_bytes(original_image)
        sidecar = image.with_suffix('.json')
        original_sidecar = sidecar.read_bytes()
        sidecar.unlink()
        reject('missing-sidecar')
        sidecar.write_bytes(original_sidecar)
        extra = parts[2] / 'unexpected.txt'
        extra.write_text('unexpected')
        reject('extra-output')
        extra.unlink()
        matrix_image = parts[2] / 'vq01b' / f'{receipts.VQ_CASES[0]}.png'
        original_matrix_image = matrix_image.read_bytes()
        matrix_image.write_bytes(b'changed')
        reject('corrupt-matrix-image')
        matrix_image.write_bytes(original_matrix_image)
        vq_root = parts[2] / 'vq01b'
        vq_manifest = vq_root / 'visual-quality-run-manifest.json'
        original_vq_manifest = vq_manifest.read_bytes()
        vq = json.loads(original_vq_manifest)
        vq['inventory']['capture_count'] = 66.0
        vq_manifest.write_text(json.dumps(vq))
        reject('wrong-matrix-count-type')
        vq_manifest.write_bytes(original_vq_manifest)

        # Change a case and its filenames/hashes coherently, including the
        # receipt's output list. The independent fixed case roster must reject it.
        vq_receipt = parts[2] / receipts.RECEIPT
        original_vq_receipt = vq_receipt.read_text()
        vq = json.loads(original_vq_manifest)
        entry = vq['captures'][0]
        old_image, old_sidecar = vq_root / entry['image'], vq_root / entry['capture_manifest']
        old_sidecar_bytes = old_sidecar.read_bytes()
        replacement = 'invented-case'
        new_image, new_sidecar = vq_root / f'{replacement}.png', vq_root / f'{replacement}.json'
        old_image.rename(new_image)
        metadata = json.loads(old_sidecar_bytes)
        metadata['image'] = new_image.name
        new_sidecar.write_text(json.dumps(metadata))
        old_sidecar.unlink()
        entry.update(case_id=replacement, image=new_image.name, capture_manifest=new_sidecar.name,
                     capture_manifest_sha256=receipts.digest(new_sidecar))
        vq['inventory']['expected_case_ids'][0] = replacement
        vq_manifest.write_text(json.dumps(vq))
        new_receipt = json.loads(original_vq_receipt)
        for name in (f'vq01b/{old_image.name}', f'vq01b/{old_sidecar.name}'):
            del new_receipt['outputs'][name]
        for path in (new_image, new_sidecar, vq_manifest):
            new_receipt['outputs'][path.relative_to(parts[2]).as_posix()] = receipts.digest(path)
        vq_receipt.write_text(json.dumps(new_receipt))
        reject('replacement-case', error_contains='incomplete or inconsistent fixed capture inventory')
        new_image.rename(old_image)
        new_sidecar.unlink()
        old_sidecar.write_bytes(old_sidecar_bytes)
        vq_manifest.write_bytes(original_vq_manifest)
        vq_receipt.write_text(original_vq_receipt)
        checks = parts[4] / receipts.CHECKS
        original_checks = checks.read_text()
        checks.write_text(original_checks + 'ground:surfaces\n')
        reject('duplicate-check')
        checks.write_text(original_checks)
        source = self.root / 'app/tests/compare_captures.py'
        original_source = source.read_text()
        source.write_text('changed source\n')
        reject('source-drift')
        source.write_text(original_source)
        ignored = self.app / 'native' / 'fixture.gdextension'
        ignored.parent.mkdir(parents=True, exist_ok=True)
        info_exclude = self.root / '.git/info/exclude'
        info_exclude.write_text(info_exclude.read_text() + '\n/app/native/\n')
        ignored.write_text('unrecorded native extension')
        reject('ignored-runtime-input')
        ignored.unlink()
        subprocess.run(['git', 'update-index', '--assume-unchanged', 'app/tests/compare_captures.py'],
                       cwd=self.root, check=True)
        reject('assume-unchanged')
        subprocess.run(['git', 'update-index', '--no-assume-unchanged', 'app/tests/compare_captures.py'],
                       cwd=self.root, check=True)
        nested = parts[0] / 'experimental-result.json'
        result = self.reduce(parts, commit, nested)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(nested.exists())
        reserved = results / 'run-manifest.json'
        result = self.reduce(parts, commit, reserved)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(reserved.exists())
        final = self.reduce(parts, commit, results / 'restored.json')
        self.assertEqual(final.returncode, 0, final.stderr)

    def test_failed_checker_or_source_drift_never_emits_receipt(self):
        self.prepare_receipts()
        for kwargs in ({'failure': 'check_stripes.py'}, {'mutation': 'check_stripes.py'}):
            result, output, _ = self.run_capture(self.current, 'ground', run_id='failure', **kwargs)
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertFalse((output / receipts.RECEIPT).exists())
            self.assertFalse((output / 'run-manifest.json').exists())


if __name__ == '__main__':
    unittest.main()
