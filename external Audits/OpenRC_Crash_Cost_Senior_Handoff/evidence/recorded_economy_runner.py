from pathlib import Path
import json
import os
import sys

BASE = Path('/workspace/scratch/bf9c4bc414d0/audit_work')
REPO = BASE / 'OpenRCsimulator'
HARNESS = BASE / 'economy_harness'
sys.path.insert(0, str(REPO / 'tools/godot'))
from run_checked import run_checked

os.environ['XDG_DATA_HOME'] = str(BASE / 'test_user_data')
manifest = json.loads((HARNESS / 'harness_manifest.json').read_text())
results = []
for test in manifest['tests']:
    name = Path(test).stem
    marker = '0 failures' if name in ['test_economy_package_optimizer', 'test_economy_replacement_quote'] else '0 failed'
    if name == 'test_economy_thermal_budget':
        marker = 'ThermalBudget tests passed:'
    report = run_checked([
        str(REPO / '.tools/Godot_v4.8-beta2_linux.x86_64'),
        '--headless', '--path', str(HARNESS), '--audio-driver', 'Dummy',
        '--script', 'res://' + test,
    ], out_dir=BASE / 'verification', timeout=45,
       required=[marker], label=name)
    results.append(report)
    log = Path(report['log']).read_text(errors='replace')
    summary = [line for line in log.splitlines() if 'checks' in line and any(s in line for s in ['failed', 'failures', 'passed'])]
    print(json.dumps({'test': name, 'ok': report.get('ok'), 'complete': report.get('complete'),
                      'summary': summary[-2:], 'report': report['report'],
                      'diagnostics': report.get('diagnostics', [])[:2]}), flush=True)
(BASE / 'verification/economy_suite_summary.json').write_text(json.dumps(results, indent=2))
print('ECONOMY_SUITE_COMPLETE', flush=True)
