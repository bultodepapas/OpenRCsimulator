"""Compare complete drive traces while excluding wall-clock cost and new damage columns."""
import argparse
import csv
import gzip
import hashlib
import json
from pathlib import Path


def read(path):
    opener = gzip.open if path.suffix == '.gz' else open
    with opener(path, 'rt', encoding='utf-8', newline='') as stream:
        return list(csv.DictReader(stream))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('baseline', type=Path)
    parser.add_argument('candidate', type=Path)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    if args.out.exists():
        parser.error('output already exists')
    baseline, candidate = read(args.baseline), read(args.candidate)
    if not baseline or not candidate:
        parser.error('both traces must contain samples')
    keys = [key for key in baseline[0] if key != 'session_tick_us' and not key.startswith('damage_')]
    differences = [(i + 1, key) for i, (old, new) in enumerate(zip(baseline, candidate))
                   for key in keys if old[key] != new.get(key)]
    healthy = all(float(row['damage_body_damage']) == 0.0
                  and float(row['damage_suspension_damage']) == 0.0
                  and float(row['damage_drive_scale']) == 1.0 for row in candidate)
    report = {
        'baseline': args.baseline.as_posix(), 'candidate': args.candidate.as_posix(),
        'baseline_file_sha256': hashlib.sha256(args.baseline.read_bytes()).hexdigest(),
        'candidate_file_sha256': hashlib.sha256(args.candidate.read_bytes()).hexdigest(),
        'baseline_rows': len(baseline), 'candidate_rows': len(candidate),
        'compared_columns': keys, 'different_cells': len(differences),
        'first_differences': differences[:10], 'all_rows_healthy': healthy,
        'ok': len(baseline) == len(candidate) and not differences and healthy,
        'scope': 'Exact exported values including all 31 state channels and driver inputs; timing excluded. Completeness is established by the separate drive receipts.',
    }
    args.out.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({key: report[key] for key in ['ok', 'candidate_rows', 'different_cells', 'all_rows_healthy']}))
    return 0 if report['ok'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
