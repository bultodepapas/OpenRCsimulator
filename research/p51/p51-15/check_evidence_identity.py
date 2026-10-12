"""Bridge frozen flight evidence to final provenance-only data edits."""
import argparse
import hashlib
import json
from pathlib import Path


def differences(left, right, path='$'):
    if type(left) is not type(right):
        return [(path, left, right)]
    if isinstance(left, dict):
        if left.keys() != right.keys():
            return [(path, sorted(left), sorted(right))]
        return [d for key in left for d in differences(left[key], right[key], path + '.' + key)]
    if isinstance(left, list):
        if len(left) != len(right):
            return [(path, len(left), len(right))]
        return [d for index, (a, b) in enumerate(zip(left, right))
                for d in differences(a, b, f'{path}[{index}]')]
    return [] if left == right else [(path, left, right)]


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--baseline', required=True, type=Path)
    p.add_argument('--candidate', required=True, type=Path)
    p.add_argument('--final', required=True, type=Path)
    p.add_argument('--out', required=True, type=Path)
    a = p.parse_args()
    files = {name: getattr(a, name) for name in ('baseline', 'candidate', 'final')}
    data = {name: json.loads(path.read_text(encoding='utf-8')) for name, path in files.items()}
    final_delta = differences(data['candidate'], data['final'])
    for path, before, after in final_delta:
        if not path.endswith('.source') or not isinstance(before, str) or not isinstance(after, str):
            raise SystemExit(f'Final data has an untested non-provenance change: {path}')
    for model in data.values():
        model.pop('inventory')
    baseline_delta = differences(data['baseline'], data['final'])
    if any(not isinstance(before, str) or not isinstance(after, str) for _, before, after in baseline_delta):
        raise SystemExit('Numeric/type/shape change outside the intended inventory')
    root = Path(__file__).resolve().parents[3]
    authored = [root / 'app/test.sh', root / 'app/tests/p51_envelope_base.gd',
                root / 'research/p51/p51-05/derive_physics.py', root / 'research/p51/p51-05/derivation.md']
    authored += sorted(Path(__file__).parent.glob('*.py')) + sorted(Path(__file__).parent.glob('*.gd'))
    report = {'sha256': {name: hashlib.sha256(path.read_bytes()).hexdigest() for name, path in files.items()},
              'final_source_hashes': {str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest()
                                      for path in authored},
              'frozen_to_final_source_edits': final_delta,
              'no_non_string_changes_outside_inventory': True,
              'frozen_to_final_only_source_text_changed': True}
    a.out.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(f'PASS: {len(final_delta)} provenance-only final edits; numeric/shape baseline changes confined to inventory')


if __name__ == '__main__':
    main()
