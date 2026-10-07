"""DATA-1 evidence: run actual CI freshness blocks in a fresh, disposable clone."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile
import textwrap

ROOT = Path(__file__).resolve().parents[4]
WORKFLOW = '.github/workflows/ci.yml'
STEP = 'Generated geometry and physics data match their sources'
P51 = 'assets/aircraft/p51d-mustang-120/'


def block(workflow):
    # Extract this literal run block, not a separately maintained list of commands.
    match = re.search(r'      - name: ' + re.escape(STEP) + r'\n        run: \|\n'
                      r'((?:          [^\n]*\n)+)', workflow)
    if not match:
        raise ValueError('Expected literal CI freshness step not found')
    return textwrap.dedent(match[1])


def run(script, clone):
    result = subprocess.run(['bash', '--noprofile', '--norc', '-eo', 'pipefail', '-c', script],
                            cwd=clone, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=120)
    return {'exit_code': result.returncode, 'output': result.stdout}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline-ref', default='baf5f86', help='pre-DATA-1 workflow revision')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    workflow = (ROOT / WORKFLOW).read_text()
    current = block(workflow)
    old = block(subprocess.check_output(['git', 'show', f'{args.baseline_ref}:{WORKFLOW}'],
                                       cwd=ROOT, text=True))
    checks = [f'python3 {P51}build_geometry.py --check',
              f'python3 {P51}compile_geometry.py --check',
              'python3 research/p51/p51-05/derive_physics.py --check']
    assert all(command in current.splitlines() and command not in old.splitlines() for command in checks)
    assert current.index(checks[0]) < current.index(checks[1]) < current.index(checks[2])
    results = []
    with tempfile.TemporaryDirectory(prefix='openrc-DATA-1-') as directory:
        clone = Path(directory) / 'repo'
        subprocess.run(['git', 'clone', '--quiet', '--no-hardlinks', str(ROOT), str(clone)], check=True)
        head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=clone, text=True).strip()
        (clone / WORKFLOW).write_text(workflow)
        clean_before, clean_after = run(old, clone), run(current, clone)
        assert clean_before['exit_code'] == clean_after['exit_code'] == 0, (clean_before, clean_after)
        results.append({'case': 'fresh checkout', 'before': clean_before, 'after': clean_after})
        # Whitespace/comments leave syntax valid: these are freshness failures,
        # not failures caused by feeding corrupt JSON/GDScript to another tool.
        cases = [
            ('stale geometry', P51 + 'geometry.json', b'\n', 'stale geometry.json'),
            ('stale runtime geometry', 'app/aircraft/p51d_geometry.gd', b'\n# DATA-1 stale copy\n', 'Stale model data'),
            ('stale physics', 'app/data/aircraft/p51d_mustang_120.json', b'\n', 'stale: app/data/aircraft/p51d_mustang_120.json'),
            ('stale derivation report', 'research/p51/p51-05/derivation.md', b'\n', 'stale: research/p51/p51-05/derivation.md'),
            ('changed source without regeneration', P51 + 'source.json', None, 'stale geometry.json'),
        ]
        for name, relative, suffix, diagnostic in cases:
            path = clone / relative
            original = path.read_bytes()
            if suffix is None:
                source = json.loads(original)
                source['kit']['span'] += .01
                mutated = (json.dumps(source, indent=2) + '\n').encode()
            else:
                mutated = original + suffix
            try:
                path.write_bytes(mutated)
                before, after = run(old, clone), run(current, clone)
                assert before['exit_code'] == 0, before
                assert after['exit_code'] != 0 and diagnostic in after['output'], after
                assert path.read_bytes() == mutated, 'check unexpectedly rewrote its input/output'
                results.append({'case': name, 'path': relative, 'before': before, 'after': after,
                                'check_left_mutation_untouched': True})
            finally:
                path.write_bytes(original)
        restored = run(current, clone)
        assert restored['exit_code'] == 0, restored
    evidence = {'baseline_workflow_ref': args.baseline_ref, 'clone_commit': head,
                'workflow_sha256': hashlib.sha256(workflow.encode()).hexdigest(),
                'commands': current.splitlines(), 'cases': results, 'restored_checkout': restored,
                'scope': 'Actual freshness step run locally with bash fail-fast; not a hosted GitHub Actions run.'}
    args.output.write_text(json.dumps(evidence, indent=2) + '\n')
    print(f'DATA-1: fresh checkout passes; {len(cases)} stale cases rejected without rewriting; restored checkout passes')


if __name__ == '__main__':
    main()
