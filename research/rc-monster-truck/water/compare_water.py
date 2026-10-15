"""Compare complete water-entry traces, excluding wall-clock cost."""
import argparse
import csv
import hashlib
import json
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('baseline', type=Path)
    parser.add_argument('candidate', type=Path)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    if args.out.exists():
        parser.error('output must be new')
    runs = []
    for directory in (args.baseline, args.candidate):
        stem = directory / 'water-entry'
        with stem.with_suffix('.csv').open(newline='', encoding='utf-8') as stream:
            rows = list(csv.DictReader(stream))
        receipt = json.loads(stem.with_suffix('.json').read_text())
        proof = json.loads((directory / 'verification.json').read_text())
        runs.append((stem, rows, receipt, proof))
    old, new = runs
    keys = [key for key in old[1][0] if key != 'tick_usec']
    differences = [(index + 1, key) for index, (a, b) in enumerate(zip(old[1], new[1]))
                   for key in keys if a[key] != b.get(key)]
    tape_equal = old[0].with_suffix('.controls.f64').read_bytes() == new[0].with_suffix('.controls.f64').read_bytes()
    state_equal = old[2]['final_state'] == new[2]['final_state']
    complete = all(len(run[1]) == run[2]['ticks'] == 3600 and run[3]['sources_unchanged'] for run in runs)
    report = {
        'ok': complete and new[3]['ok'] and not differences and tape_equal and state_equal,
        'scope': 'Exact CSV values, control bytes and final 31-state JSON values. Timing excluded. Baseline checkpoint defect is not waived for candidate acceptance.',
        'baseline': str(args.baseline), 'candidate': str(args.candidate),
        'baseline_complete_and_stable': complete, 'baseline_all_gates_passed': old[3]['ok'],
        'candidate_all_gates_passed': new[3]['ok'], 'rows': len(new[1]),
        'compared_columns': keys, 'different_cells': len(differences),
        'first_differences': differences[:10], 'control_tape_bytes_equal': tape_equal,
        'final_state_equal': state_equal,
        'tick_p95_us': [run[2]['tick_p95_us'] for run in runs],
        'tick_p50_us': [run[2]['tick_p50_us'] for run in runs],
        'csv_sha256': [hashlib.sha256(run[0].with_suffix('.csv').read_bytes()).hexdigest() for run in runs],
    }
    args.out.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report))
    return 0 if report['ok'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
