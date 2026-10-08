"""D1-R4: reproduce envelope refusal, exact fleet loading and isolated solver faults."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
LOADER = ROOT/'app/physics/aircraft_data.gd'
TEST = ROOT/'app/tests/test_envelope_integrity.gd'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inputs():
    paths = [p for p in (ROOT/'app').rglob('*') if p.is_file() and '.godot' not in p.parts
             and p.suffix in ('.gd', '.json', '.tscn', '.godot')]
    paths += [p for p in HERE.iterdir() if p.suffix in ('.py', '.gd', '.txt')]
    paths += [ROOT/'research/aircraft-data/data2/bench.gd']
    return {str(p.relative_to(ROOT)): sha(p) for p in sorted(paths)}


def envelope_span(source):
    start = source.index('static func _envelope(')
    return start, source.index('\n\n## Stall start', start)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--godot', type=Path)
    args = parser.parse_args()
    out = args.output.resolve(); out.mkdir(parents=True, exist_ok=True)
    if any(out.iterdir()):
        raise ValueError('use an empty evidence directory')
    godot = str(args.godot.resolve()) if args.godot else subprocess.check_output([str(ROOT/'app/get-godot.sh')], text=True).strip()
    before = inputs()
    with tempfile.TemporaryDirectory(prefix='openrc-d1r4-proof-') as temp:
        work = Path(temp)
        env = dict(os.environ, XDG_DATA_HOME=str(work/'data'), XDG_CONFIG_HOME=str(work/'config'))

        def run(script, name, *, expect=0, extra=None):
            result = subprocess.run([godot, '--headless', '--path', str(ROOT/'app'), '--script', str(script)],
                                    cwd=ROOT, env=dict(env, **(extra or {})), capture_output=True, text=True, timeout=120)
            log = result.stdout + result.stderr
            (out/name).write_text(log)
            if result.returncode != expect or 'SCRIPT ERROR:' in log or '\nERROR:' in log:
                raise RuntimeError(f'unexpected result; see {out/name}')
            return log

        focused = run(TEST, 'focused.log')
        if 'checks, 0 failed' not in focused:
            raise RuntimeError('focused test did not complete')
        run(HERE/'probe.gd', 'after-probe.log')
        source = LOADER.read_text()
        a, b = envelope_span(source)
        baseline = work/'baseline.gd'
        baseline.write_text(source[:a]+(HERE/'reference_envelope.txt').read_text().rstrip()+source[b:])
        old_probe = work/'old_probe.gd'
        old_probe.write_text((HERE/'probe.gd').read_text().replace('res://physics/aircraft_data.gd', str(baseline)))
        run(old_probe, 'before-probe.log')
        timings = run(ROOT/'research/aircraft-data/data2/bench.gd', 'load-pairs.log',
                      extra={'OPENRC_DATA2_BASELINE': str(baseline)})
        pairs = [json.loads(line) for line in timings.splitlines() if line.startswith('{')]
        assert len(pairs) == 4 and all(p['exact_load_result'] and len(p['baseline_ms']) == 12 for p in pairs)
        # The old acceptance boundary must fail the focused integrity regressions.
        old_test = work/'old_test.gd'
        old_test.write_text(TEST.read_text().replace('res://physics/aircraft_data.gd', str(baseline)))
        old_log = run(old_test, 'original-rejection.log', expect=1, extra={'OPENRC_ENVELOPE_SKIP_SESSION': '1'})
        assert 'FAIL unreachable finite lift slope' in old_log
        # Deliberately remove the physical-domain check on a copy.
        no_cap = work/'no_cap.gd'
        envelope = source[a:b]
        assert envelope.count(' or end > PI / 2.0') == 1
        no_cap.write_text(source[:a]+envelope.replace(' or end > PI / 2.0', '')+source[b:])
        bad_test = work/'bad_test.gd'
        bad_test.write_text(TEST.read_text().replace('res://physics/aircraft_data.gd', str(no_cap)))
        cap_log = run(bad_test, 'mutation-no-domain-cap.log', expect=1, extra={'OPENRC_ENVELOPE_SKIP_SESSION': '1'})
        assert 'FAIL reachable linear bound but blend ends beyond 90' in cap_log
        solver_start = source.index('static func _solve_stall_start(')
        solver_end = source.index('\n\n## DATA-2a', solver_start)
        solver = source[solver_start:solver_end]
        needle = 'return 0.5 * (lo + hi)'
        assert solver.count(needle) == 1
        faults = {}
        for name, value in [('nan-root', 'NAN'), ('infinite-root', 'INF'), ('wrong-root', '0.4')]:
            faulty = work/(name+'.gd')
            faulty.write_text(source[:solver_start]+solver.replace(needle, 'return '+value)+source[solver_end:])
            log = run(HERE/'fault_probe.gd', name+'.log', extra={'OPENRC_ENVELOPE_LOADER': str(faulty)})
            assert '4 checks, 0 failed' in log
            faults[name] = 4
        # A NaN peak needs explicit finiteness: abs(NaN) > tolerance is false.
        peak_line = 'var peak: float = _blend_extreme(aero, cd90, w, start, side)'
        assert source.count(peak_line) == 1
        nan_peak = source.replace(peak_line, 'var peak: float = NAN')
        faulty = work/'nan_peak.gd'; faulty.write_text(nan_peak)
        log = run(HERE/'fault_probe.gd', 'nan-peak.log', extra={'OPENRC_ENVELOPE_LOADER': str(faulty)})
        assert '4 checks, 0 failed' in log
        faults['nan-peak'] = 4
        faulty.write_text(nan_peak.replace('not is_finite(peak) or ', ''))
        log = run(HERE/'fault_probe.gd', 'mutation-nan-residual-guard.log', expect=1,
                  extra={'OPENRC_ENVELOPE_LOADER': str(faulty)})
        assert '4 checks, 4 failed' in log
    assert inputs() == before, 'verification inputs changed during run'
    summary = {'step': 'D1-R4', 'source_sha256': before, 'focused_summary': next(line for line in focused.splitlines() if line.startswith('D1-R4:')),
               'exact_fleet_load_pairs': 48, 'timings': pairs, 'solver_fault_refusals': faults,
               'negative_controls': ['original boundary', 'removed domain cap', 'removed NaN residual guard'],
               'evidence_sha256': {p.name: sha(p) for p in sorted(out.iterdir()) if p.is_file()}}
    (out/'verification.json').write_text(json.dumps(summary, indent=2)+'\n')
    print(json.dumps({k:v for k,v in summary.items() if k not in ('source_sha256','evidence_sha256','timings')}, indent=2))


if __name__ == '__main__':
    main()
