"""Run scoped RCV-37 regressions and validate retained exact-parity evidence."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[4]
EVIDENCE = ROOT / 'docs/research/rc-monster-truck/RCV-37'
TESTS = {
    'nitro-audio': 'tests/test_rcv_nitro_audio.gd',
    'nitro-visual': 'tests/test_rcv_nitro_visual.gd',
    'nitro-activity': 'tests/test_rcv_nitro_activity.gd',
    'nitro-effects': 'tests/test_rcv36_effects.gd',
    'nitro-service': 'tests/test_rcv_nitro_service.gd',
    'bisonte-activity': 'tests/test_rcv_activity.gd',
}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', type=Path, required=True)
    args = parser.parse_args()
    checks = EVIDENCE / 'checks'
    results = []
    for name, script in TESTS.items():
        process = subprocess.run(
            [str(args.godot.resolve()), '--headless', '--path', str(ROOT / 'app'),
             '--script', 'res://' + script], capture_output=True, text=True,
            timeout=150, encoding='utf-8', errors='replace',
        )
        output = process.stdout + process.stderr
        log_path = checks / (name + '.log')
        log_path.write_text(output, encoding='utf-8')
        if process.returncode or re.search(r'^(?:(?:SCRIPT |SHADER )?ERROR:|FAIL[: ])', output, re.M):
            raise RuntimeError(f'{name} failed:\n{output}')
        if not re.search(r'0 fail|test passed|FAILURES=0', output):
            raise RuntimeError(f'{name} did not report a completed passing suite:\n{output}')
        results.append({'test': script, 'source_sha256': sha(ROOT / 'app' / script),
                        'log': log_path.name, 'log_sha256': sha(log_path), 'passed': True})
        print(f'{name}: passed', flush=True)
    audio = json.loads((checks / 'audio.json').read_text())
    assert audio['complete'] and audio['parity_passed'] and audio['parity_complete']
    assert audio['candidate_sha256'] == sha(ROOT / 'app/audio/nitro_voice.gd')
    session = json.loads((checks / 'session.json').read_text())
    assert session['exact_replay']
    report = {'complete': True, 'scope': 'RCV-37 source runtime; scoped regressions',
              'full_repository_suite': False, 'new_release_export': False,
              'tests': results, 'audio_sha256': sha(checks / 'audio.json'),
              'session_sha256': sha(checks / 'session.json'),
              'model_sha256': sha(ROOT / 'app/vehicles/ground/monster_car_2_model.gd'),
              'voice_sha256': sha(ROOT / 'app/audio/nitro_voice.gd')}
    (checks / 'verification.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    main()
