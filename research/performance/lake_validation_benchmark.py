#!/usr/bin/env python3
"""LU-25-R1: compare the unchanged guard with its cache in a disposable app.

Uses only Python's standard library. Run alone on the measured host. Asset/import
files are hard-linked read-only inputs; do not run an import in the snapshot.
The benchmark switch is inserted only into the new copy, never the working app.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', required=True, type=Path)
    parser.add_argument('--work', required=True, type=Path, help='New directory, on the repository volume')
    parser.add_argument('--aircraft', default='jensen-das-ugly-stik-60')
    parser.add_argument('--case', choices=['trim', 'maneuver', 'runway'], default='trim')
    parser.add_argument('--warmup', type=int, default=2400)
    parser.add_argument('--samples', type=int, default=14400)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    work = args.work.resolve()
    if work.exists() or work.is_relative_to(root / 'app'):
        parser.error('--work must be new and outside app/')
    if not 0 <= args.warmup <= 72000 or not 120 <= args.samples <= 72000 or args.samples % 120:
        parser.error('samples must be a multiple of 120; tick counts are bounded to 72000')
    godot = args.godot.resolve()
    if godot.name.endswith('_console.exe'):
        parser.error('Use the native .exe, not its Windows console launcher, so timeout owns the engine')
    if not godot.is_file():
        parser.error('Godot executable not found')
    work.mkdir(parents=True)
    app = work / 'app'

    def copy(source: str, target: str) -> str:
        relative = Path(source).relative_to(root / 'app')
        if relative.parts[0] in ('assets', '.godot'):
            os.link(source, target)
        else:
            shutil.copy2(source, target)
        return target

    shutil.copytree(root / 'app', app, copy_function=copy)
    hashes = {p.relative_to(app).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
              for p in app.rglob('*') if p.is_file() and '.godot' not in p.relative_to(app).parts
              and p.suffix in ('.gd', '.json', '.godot', '.tscn', '.tres')}
    leaf = app / 'physics/lake_surface.gd'
    source = leaf.read_text(encoding='utf-8')
    signature = 'static func is_valid_definition(lake: Dictionary) -> bool:'
    assert source.count(signature) == 1 and '_definition_is_valid_uncached' in source
    instrumented = source.replace(signature,
        'static var _benchmark_cache_enabled := false\n\n' + signature +
        '\n\tif not _benchmark_cache_enabled:\n\t\treturn _definition_is_valid_uncached(lake)')
    leaf.write_text(instrumented, encoding='utf-8')
    probe = Path(__file__).with_name('lake_validation_pair.gd')
    command = [str(godot), '--headless', '--path', str(app), '--audio-driver', 'Dummy',
               '--script', str(probe), '--', '--reference=res://sim/flight_session.gd',
               '--candidate=res://sim/flight_session.gd', '--output=' + str(work / 'paired.json'),
               '--aircraft=' + args.aircraft, '--case=' + args.case,
               '--warmup=' + str(args.warmup), '--samples=' + str(args.samples)]
    metadata = {'command': command, 'source_hashes': hashes,
                'benchmark_leaf_sha256': hashlib.sha256(leaf.read_bytes()).hexdigest(),
                'probe_sha256': hashlib.sha256(probe.read_bytes()).hexdigest()}
    (work / 'manifest.json').write_text(json.dumps(metadata, indent=2), encoding='utf-8')
    result = subprocess.run(command, capture_output=True, text=True, timeout=900)
    log = result.stdout + result.stderr
    (work / 'engine.log').write_text(log, encoding='utf-8')
    if result.returncode or 'ERROR:' in log:
        raise RuntimeError('Benchmark failed; inspect engine.log')
    report = json.loads((work / 'paired.json').read_text(encoding='utf-8'))
    assert report['complete'] and not report['failure']
    assert report['completed_batches'] == args.samples // 120
    assert len(report['baseline_tick_usec']) == len(report['candidate_tick_usec']) == args.samples
    assert len(report['baseline_batch_usec']) == len(report['candidate_batch_usec']) == args.samples // 120
    assert report['fingerprints'][0] == report['fingerprints'][1]
    print('PASS:', work / 'paired.json')


if __name__ == '__main__':
    main()
