#!/usr/bin/env python3
"""Verify the portable evidence, optionally unpack it into a fresh directory, and plot the same-tape comparison."""
from __future__ import annotations
import argparse
import csv
import gzip
import hashlib
import io
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent


def verified_files(evidence_dir: Path):
    try:
        manifest = json.loads((evidence_dir / 'manifest.json').read_text())
    except FileNotFoundError as error:
        raise SystemExit(
            f'Missing evidence manifest: {error.filename}. The full recording package is private; '
            'extract it and use --evidence-dir /path/to/extracted/evidence.'
        ) from error
    files = {}
    for row in manifest['files']:
        path = Path(row['path'])
        if not path.parts or path.parts[0] != 'evidence' or '..' in path.parts or len(path.parts) < 2:
            raise SystemExit(f'Invalid evidence path: {row["path"]}')
        relative = Path(*path.parts[1:])
        try:
            stored = (evidence_dir / relative).read_bytes()
        except FileNotFoundError as error:
            raise SystemExit(
                f'Missing evidence file: {error.filename}. The full recording package is private; '
                'extract it and use --evidence-dir /path/to/extracted/evidence.'
            ) from error
        if hashlib.sha256(stored).hexdigest() != row['stored_sha256']:
            raise SystemExit(f'Stored SHA-256 mismatch: {row["path"]}')
        data = gzip.decompress(stored) if row['path'].endswith('.gz') else stored
        if len(data) != row['bytes'] or hashlib.sha256(data).hexdigest() != row['sha256']:
            raise SystemExit(f'Original size or SHA-256 mismatch: {row["path"]}')
        files[relative.as_posix().removesuffix('.gz')] = data
    return files


def series(files, variant, soc):
    rows = list(csv.DictReader(io.StringIO(files[f'{variant}/soc-{soc:03d}.csv'].decode())))
    assert len(rows) == 1418 and [int(r['tick']) for r in rows] == list(range(1, 1419))
    return {key: [float(row[key]) for row in rows] for key in rows[0] if key != 'phase'}


def plot(files, output):
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    plt.rcParams.update({'font.size': 10, 'axes.spines.top': False, 'axes.spines.right': False})
    old = series(files, 'baseline', 100)
    new = series(files, 'candidate', 100)
    times = [t / 240 for t in new['tick']]
    fig, axes = plt.subplots(3, 1, figsize=(11.5, 9), sharex=True, layout='constrained')
    fig.suptitle('FPV battery and power: the same pilot tape', fontsize=18, weight='bold')
    for ax in axes:
        ax.grid(alpha=.18)
        for left, right in [(482 / 240, 578 / 240), (842 / 240, 938 / 240)]:
            ax.axvspan(left, right, color='#dfe9f2', alpha=.6)
    axes[0].plot(times, old['voltage_v'], color='#71717a', ls='--', lw=1.3, label='Baseline: instantaneous sag')
    axes[0].plot(times, new['voltage_v'], color='#1967b3', lw=1.6, label='Candidate: immediate + delayed sag')
    axes[0].set_ylabel('Pack terminal voltage (V)')
    axes[0].set_title('Full-charge start · shaded intervals are throttle punches', loc='left', fontsize=10)
    axes[0].legend(loc='lower right', frameon=False)
    axes[1].plot(times, old['current_a'], color='#71717a', ls='--', lw=1.3, label='Baseline')
    axes[1].plot(times, new['current_a'], color='#c46217', lw=1.5, label='Candidate')
    axes[1].axhline(0, color='#aa3d36', lw=.8)
    axes[1].set_ylabel('Pack current (A)')
    axes[1].set_title('Positive current discharges the pack; candidate braking never charges it', loc='left', fontsize=10)
    axes[1].legend(loc='upper right', frameon=False)
    for soc, color in [(100, '#1967b3'), (50, '#158577'), (20, '#8547a4')]:
        values = series(files, 'candidate', soc)
        axes[2].plot(times, values['polarization_v'], color=color, lw=1.6, label=f'{soc}% starting charge')
    axes[2].set_ylabel('Delayed voltage loss (V)')
    axes[2].set_xlabel('Simulation time (s)')
    axes[2].set_title('Polarization builds under load and relaxes after each burst', loc='left', fontsize=10)
    axes[2].legend(loc='upper right', frameon=False)
    axes[2].set_xlim(0, 1418 / 240)
    fig.supxlabel('Estimated 6S 1300 mAh pack · 1,418 identical pilot frames · software evidence, no hardware calibration', fontsize=9)
    fig.savefig(output, dpi=180, metadata={'Software': 'OpenRC FPV power comparison'})
    plt.close(fig)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--evidence-dir', type=Path, default=HERE / 'evidence',
                        help='directory containing manifest.json and the baseline/candidate evidence files')
    parser.add_argument('--unpack', type=Path, help='fresh directory for exact original .orfl/CSV/summary bytes')
    parser.add_argument('--plot', type=Path, help='write a comparison PNG (requires Matplotlib)')
    args = parser.parse_args()
    files = verified_files(args.evidence_dir)
    if args.unpack:
        targets = [(args.unpack / name, data) for name, data in files.items()]
        if any(path.exists() for path, _ in targets):
            raise SystemExit('Refusing to overwrite unpacked evidence; use a fresh directory.')
        for path, data in targets:
            path.parent.mkdir(parents=True, exist_ok=True)
            with path.open('xb') as stream:
                stream.write(data)
    if args.plot:
        plot(files, args.plot)
    print(f'Verified {len(files)} evidence files; all original and stored SHA-256 digests match.')


if __name__ == '__main__':
    main()
