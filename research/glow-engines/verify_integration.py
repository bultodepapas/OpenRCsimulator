"""Reproduce installed glow software checks and preserve logs and source identity.

Does not infer physical accuracy from software tests. Run flight_bench.gd separately
at 240/480/960 Hz; only an isolated 240 Hz run is meaningful for timing.
"""
from pathlib import Path
import argparse
import concurrent.futures
import hashlib
import json
import re
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
REGRESSION = '''aircraft_catalog aircraft_data aircraft_contract aircraft_render_contract checkpoint checkpoint_integrity continuous_state
dynamics golden ground_start_integrity gyro modes propulsion propulsion_scalar replay_integrity
runway_checkpoint_metadata runway_start session_guards shaft_data shaft_equilibrium simulation
start_choice trace trace_metadata trim_integrity turbine ui_aircraft ui_home ui_runway'''.split()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', required=True, type=Path)
    parser.add_argument('--out', required=True, type=Path)
    parser.add_argument('--parse-all', action='store_true')
    args = parser.parse_args()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=False)
    godot = args.godot.resolve()
    # The Windows console launcher starts a child GUI binary. Run that binary
    # directly so a timeout terminates the process that owns the test and pipes.
    if sys.platform == 'win32' and godot.name.endswith('_console.exe'):
        executable = godot.with_name(godot.name.replace('_console.exe', '.exe'))
        if executable.is_file():
            godot = executable
    results = []
    source_paths = sorted({p for p in (ROOT/'app').rglob('*.gd') if '.godot' not in p.parts} |
                          set((ROOT/'app/data/glow').glob('*.json')) |
                          set((ROOT/'research/glow-engines').glob('*.py')) |
                          set((ROOT/'app/data/aircraft').glob('stik_glow*.json')))
    def fingerprints():
        return {p.relative_to(ROOT).as_posix():
                hashlib.sha256(p.read_bytes()).hexdigest() if p.is_file() else 'missing'
                for p in source_paths}
    sources_before = fingerprints()

    def run(label, command, timeout=180):
        started = time.monotonic()
        try:
            result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=timeout)
            text = result.stdout + result.stderr
            passed = result.returncode == 0 and not re.search(r'^(?:SCRIPT |SHADER )?ERROR:|^FAIL', text, re.M)
            entry = dict(check=label, exit_code=result.returncode, passed=bool(passed))
        except subprocess.TimeoutExpired as exc:
            def decoded(value):
                return value.decode('utf-8', errors='replace') if isinstance(value, bytes) else value or ''
            text = decoded(exc.stdout) + decoded(exc.stderr) + '\n' + str(exc) + '\n'
            entry = dict(check=label, passed=False, timeout=timeout)
        entry['wall_time_s'] = time.monotonic() - started
        (out/(label+'.log')).write_text(text, encoding='utf-8')
        results.append(entry)
        if not label.startswith('parse-') or not entry['passed']:
            print(label + ': ' + ('PASS' if entry['passed'] else 'FAIL'), flush=True)
        return entry

    for script, extra in [
        ('research/glow-engines/build_profiles.py',['--check']),
        ('research/glow-engines/build_installations.py',['--check']),
        ('research/glow-engines/test_profiles.py',[]),
        ('research/glow-engines/installation_schema.py',['--check']),
        ('research/glow-engines/test_installation_schema.py',[]),
        ('research/glow-engines/test_installation_line_endings.py',[]),
        ('research/glow-engines/test_refinement_report.py',[]),
        ('research/glow-engines/test_pilot_review.py',[]),
        ('research/glow-engines/reference/test_reference.py',[]),
        ('research/aircraft-standardization/build_schema.py',['--check']),
        ('app/tests/check_transcendentals.py',[]),
    ]:
        run(Path(script).stem,[sys.executable,script,*extra])
    scripts = sorted((ROOT/'app').rglob('*.gd')) if args.parse_all else sorted((ROOT/'app/physics/glow').glob('*.gd'))
    scripts = [p for p in scripts if '.godot' not in p.parts]
    base = [str(godot),'--headless','--path',str(ROOT/'app'),'--audio-driver','Dummy']
    def parse(p):
        relative = p.relative_to(ROOT/'app').as_posix()
        return run('parse-'+relative.replace('/','_'),base+['--check-only','--script','res://'+relative])
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        list(pool.map(parse,scripts))
    tests = set((ROOT/'app/tests').glob('test_glow_*.gd'))
    tests.update(ROOT/'app/tests'/('test_'+name+'.gd') for name in REGRESSION)
    # Dynamic electric and turbine integration live in later track-specific files.
    tests.update((ROOT/'app/tests').glob('test_electric_*.gd'))
    tests.update((ROOT/'app/tests').glob('test_turbine_*.gd'))
    for p in sorted(tests):
        # These fixtures rebuild several complete aircraft/scenery scenes. Their
        # wall-time ceiling is separate from the measured physics-tick budget.
        scene_fixture = p.stem in {'test_aircraft_catalog', 'test_ui_aircraft', 'test_ui_runway'}
        run(p.stem,base+['--script','res://tests/'+p.name], timeout=600 if scene_fixture else 180)
    run('glow-catalog-cli', [sys.executable, 'research/glow-engines/packaged_smoke.py',
        '--godot', str(godot), '--out', str(out/'cli')])
    sources_after = fingerprints()
    unchanged = sources_before == sources_after
    report = dict(format='openrc-glow-integration-proof v2',results=results,
                  ok=all(r['passed'] for r in results) and unchanged,
                  godot_executable=str(godot),
                  godot_executable_sha256=hashlib.sha256(godot.read_bytes()).hexdigest(),
                  source_sha256=sources_before, source_sha256_after=sources_after,
                  sources_unchanged=unchanged,
                  source_hash_scope='Declared app GDScripts and glow data/Python sources before and after verification; drift refuses a single-snapshot pass',
                  claim='Software verification of both candidate engine families; physical/pilot/release gates remain separate')
    (out/'verification.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print(f"{sum(r['passed'] for r in results)}/{len(results)} commands passed",flush=True)
    if not unchanged:
        print('Source changed during verification: ' + ', '.join(p for p in sources_before
              if sources_before[p] != sources_after[p]), flush=True)
    raise SystemExit(0 if report['ok'] else 1)

if __name__=='__main__': main()
