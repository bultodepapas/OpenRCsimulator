from pathlib import Path
import hashlib
import json
import re
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
checks = HERE/'checks'/'python-final'
checks.mkdir(exist_ok=False)
process = subprocess.run([sys.executable, '-m', 'unittest', '-v', 'test_fixed_brake_trace_contract'],
    cwd=HERE/'payload/app/tests', stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
(checks/'output.log').write_text(process.stdout, encoding='utf-8')
match = re.search(r'Ran (\d+) tests', process.stdout)
(checks/'report.json').write_text(json.dumps(dict(complete=True, ok=process.returncode == 0,
    exit_code=process.returncode, tests=int(match[1]) if match else None), indent=2)+'\n')
assert process.returncode == 0, process.stdout

# Pin actual recursively preloaded scripts plus relevant runtime/source inputs.
pending = [HERE/'test_projection.gd', HERE/'test_baseline_tapes.gd']
scripts = {}
while pending:
    file = pending.pop().resolve()
    if str(file) in scripts: continue
    scripts[str(file)] = sha(file)
    for target in re.findall(r'(?:preload|extends)\s*\(?\s*["\']([^"\']+\.gd)["\']', file.read_text(encoding='utf-8')):
        next_file = ROOT/'app'/target[6:] if target.startswith('res://') else Path(target)
        if next_file.exists(): pending.append(next_file)
data = {str(p.relative_to(ROOT)).replace('\\','/'): sha(p) for p in (ROOT/'app/data/aircraft').glob('*.json')}
for name in ['app/data/ground/wheel_profiles.json', 'app/data/ground/surface_friction.json']:
    data[name] = sha(ROOT/name)
pins = dict(scripts=scripts, data=data)
(HERE/'loaded-source-pins.json').write_text(json.dumps(pins,indent=2)+'\n')

base = json.loads((HERE/'prehash.json').read_text())
for path, before in base.items():
    assert sha(ROOT/path) == before, path
    destination = HERE/'before'/path
    destination.parent.mkdir(parents=True,exist_ok=True)
    destination.write_bytes((ROOT/path).read_bytes())

reports = []
for cohort in ['projection-final', 'tapes-reviewed', 'review-fixes']:
    report_files = list((HERE/'checks'/cohort).glob('*/report.json'))
    for path in report_files:
        value = json.loads(path.read_text(encoding='utf-8'))
        assert value.get('ok') and value.get('complete'), str(path)
        reports.append(dict(path=str(path.relative_to(ROOT)).replace('\\','/'), sha256=sha(path)))
report = dict(scope='detached reviewed candidate only; not promoted; no stock data or force law changes',
    production_projection_checks=256, focused_python_tests=int(match[1]), baseline_tape_checks=30,
    baseline_tape_ticks=96, baseline_solver_changed=True,
    exact_legacy_exclusion='created_utc presentation timestamp only, normalized to a declared fixed sentinel',
    base_sources=base, review_patch_sha256=sha(HERE/'review.patch'),
    manifest_sha256=sha(HERE/'promotion-manifest.json'), loaded_sources_sha256=sha(HERE/'loaded-source-pins.json'),
    reports=reports, limitations=['physics-specific legacy CSV validators intentionally refuse v17',
    'synthetic fixture hardware only; no stock brake authoring', 'no airborne/differential brake qualification',
    'production receipts must follow guarded promotion; draft ORFL solver identity hashes installed sources, draft scripts separately pinned'])
(HERE/'review-receipt.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
