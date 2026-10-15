"""Recheck RCV-36 script parsing and the retained scoped evidence."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[4]
EVIDENCE = ROOT / 'docs/research/rc-monster-truck/RCV-36'
SCRIPTS = [
    'audio/nitro_engine_audio.gd', 'audio/nitro_voice.gd',
    'physics/ground_vehicle/nitro_dynamics.gd', 'sim/ground_vehicle/session.gd',
    'vehicles/ground/ground_scene.gd', 'vehicles/ground/ground_dashboard.gd',
    'vehicles/ground/ground_effects.gd', 'vehicles/ground/nitro_exhaust.gd',
    'vehicles/ground/monster_car_2_model.gd', 'tests/test_nitro_dynamics.gd',
    'tests/test_rcv_nitro_activity.gd', 'tests/test_rcv_nitro_service.gd',
    'tests/test_rcv_nitro_audio.gd', 'tests/test_rcv36_effects.gd',
]
LOG_RESULTS = {
    'checks/nitro-service.log': '38 checks, 0 failed',
    'checks/nitro-session.log': '28 checks, 0 failed',
    'checks/nitro-activity.log': '99 checks, 0 failures',
    'checks/bisonte-session.log': '136 checks, 0 failed',
    'checks/bisonte-activity.log': '24 checks, 0 failures',
    'checks/menu.log': '27 checks, 0 failures',
    'checks/nitro-visual.log': 'Monster Car 2 visual test passed',
}

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', type=Path, required=True)
    args = parser.parse_args()
    results = []
    for relative in SCRIPTS:
        process = subprocess.run(
            [str(args.godot.resolve()), '--headless', '--path', str(ROOT / 'app'),
             '--check-only', '--script', 'res://' + relative],
            capture_output=True, text=True, timeout=60, encoding='utf-8', errors='replace',
        )
        output = process.stdout + process.stderr
        if process.returncode or re.search(r'^(?:SCRIPT |SHADER )?ERROR:', output, re.M):
            raise RuntimeError(f'Parse failed: {relative}\n{output}')
        results.append({'path': 'app/' + relative, 'sha256': sha(ROOT / 'app' / relative), 'parse': 'pass'})
    logs = []
    for relative, expected in LOG_RESULTS.items():
        path = EVIDENCE / relative
        content = path.read_text(encoding='utf-8-sig')
        assert expected in content, relative
        assert not re.search(r'^(?:(?:SCRIPT |SHADER )?ERROR:|FAIL:)', content, re.M), relative
        logs.append({'path': relative, 'sha256': sha(path), 'result': expected})
    capture = json.loads((EVIDENCE / 'captures/capture.json').read_text())
    assert capture['complete'] and capture['accepted_ticks'] == 960
    assert capture['observer_preserves_state'] and capture['max_dust_active_wheels'] == 4
    assert capture['dirty']['grime_amount'] > 0.0 and capture['clean']['grime_amount'] == 0.0
    assert capture['dirty']['grime_overlay_count'] == 70
    assert capture['exhaust']['particle_budget'] == 32 and capture['exhaust']['emitting']
    assert capture['nitro']['fuel_kg'] < 0.1
    render_log = (EVIDENCE / 'captures/render.log').read_text(encoding='utf-8-sig')
    assert not re.search(r'^(?:SCRIPT |SHADER )?ERROR:', render_log, re.M)
    printed = next(line for line in render_log.splitlines() if line.startswith('RCV-36 capture: '))
    printed_capture = json.loads(printed.removeprefix('RCV-36 capture: '))
    assert printed_capture['complete'] and printed_capture['accepted_ticks'] == 960
    audio = json.loads((EVIDENCE / 'audio/receipt.json').read_text())
    for item in audio['sources']:
        assert sha(ROOT / item['path']) == item['sha256'], item['path']
    assert sha(EVIDENCE / 'audio' / audio['preview']['path']) == audio['preview']['sha256']
    comparison = json.loads((EVIDENCE / 'physics/candidate/comparison.json').read_text())
    assert comparison['complete'] and comparison['solver_changed']
    report = {'complete': True, 'scope': 'RCV-36 scoped source-runtime verification',
              'full_repository_suite': False, 'new_release_export': False,
              'scripts': results, 'integration_logs': logs,
              'grime_shader_sha256': sha(ROOT / 'app/vehicles/ground/ground_grime_overlay.gdshader'),
              'capture_driver_sha256': sha(Path(__file__).with_name('capture_service_effects.gd')),
              'capture_images': {path.name: sha(path) for path in sorted((EVIDENCE / 'captures').glob('*.png'))},
              'capture_sha256': sha(EVIDENCE / 'captures/capture.json'),
              'audio_receipt_sha256': sha(EVIDENCE / 'audio/receipt.json'),
              'physics_comparison_sha256': sha(EVIDENCE / 'physics/candidate/comparison.json')}
    (EVIDENCE / 'checks/verification-receipt.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(f'RCV-36: {len(results)} script parses, {len(logs)} retained integration logs, capture/audio/physics receipts passed')

if __name__ == '__main__':
    main()
