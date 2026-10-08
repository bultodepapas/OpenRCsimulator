#!/usr/bin/env python3
"""Run formula/contract negative controls only on disposable copies."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
MUTATIONS = {
    'inclusive-frame-count': ("n = end['frame'] - start['frame']", "n = end['frame'] - start['frame'] + 1", 'test_analytic_full_turns'),
    'lost-roll-direction': ('frequency = turns / duration', 'frequency = abs(turns) / duration', 'test_direction_changes_sign_not_duration_or_uncertainty'),
    'wrong-shared-event-sign': ("f'event:{end_id}': -factor*value/n*end['frame_u']", "f'event:{end_id}': factor*value/n*end['frame_u']", 'test_shared_middle_event_cancels_in_total_duration'),
    'omitted-clock-error': ("'capture_clock': factor*value*clock_u", "'capture_clock': 0.0", 'test_closed_form_uncertainty_and_signs'),
    'unchecked-clip-hash': ("require(video_hash == expected, 'video SHA-256 mismatch')", 'pass # deliberately bypass clip identity', 'test_verified_clip_required_and_mismatch_refused'),
}


def main():
    source = (HERE/'reduce.py').read_text()
    before = hashlib.sha256(source.encode()).hexdigest()
    results = []
    with tempfile.TemporaryDirectory(prefix='openrc-val8b-mutations-') as directory:
        work = Path(directory)
        for name in ['reduce.py', 'test_reduce.py', 'example.synthetic.json', 'example.synthetic.csv']:
            shutil.copy2(HERE/name, work/name)
        for name, mutation in [('control', None), *MUTATIONS.items()]:
            candidate = source
            if mutation:
                old, new, _ = mutation
                assert source.count(old) == 1, name
                candidate = source.replace(old, new)
            (work/'reduce.py').write_text(candidate)
            shutil.rmtree(work/'__pycache__', ignore_errors=True)
            run = subprocess.run([sys.executable, '-B', str(work/'test_reduce.py')], capture_output=True, text=True, timeout=30)
            log = run.stdout+run.stderr
            expected = 0 if mutation is None else 1
            assert run.returncode == expected, (name, log)
            if mutation:
                assert 'FAIL: '+mutation[2] in log and '\nERROR:' not in log, (name, log)
            results.append({'case': name, 'exit_code': run.returncode, 'intended_assertion': mutation[2] if mutation else None,
                            'log': log})
    assert hashlib.sha256((HERE/'reduce.py').read_bytes()).hexdigest() == before
    print(json.dumps({'source_sha256': before, 'results': results}, indent=2))


if __name__ == '__main__':
    main()
