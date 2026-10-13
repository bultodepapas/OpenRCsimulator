"""Fly both glow families from an exported PCK with no loose-project fallback.

The editor runtime checks compiled resources via --pack/--main-pack. --exported
runs a self-contained native export without path overrides. Neither check
qualifies target-machine timing or physical flight accuracy. Omit both options
to exercise the ordinary source-tree CLI (also used by app/test.sh).
"""
from pathlib import Path
import argparse
import csv
import hashlib
import io
import json
import math
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
CASES = [('stik-glow-55ax-2t', 'glow_2t'), ('stik-glow-fs64v-4t', 'glow_4t')]


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inspect_trace(path, aircraft, family):
    text = path.read_text(encoding='utf-8')
    meta = dict(line[2:].split(': ', 1) for line in text.splitlines()
                if line.startswith('# ') and ': ' in line)
    rows = list(csv.DictReader(io.StringIO('\n'.join(
        line for line in text.splitlines() if not line.startswith('#')))))
    assert len(rows) == 721, len(rows)
    assert abs(float(rows[-1]['t_s']) - 3.0) < 1e-9
    assert meta['glow_family'] == family, meta
    assert aircraft in text
    identity = json.loads(meta['glow_identity'])
    assert identity and meta['propulsion_model'] == 'glow-mean-cycle-finite-tank-fixed-datum-v1'
    assert all(math.isfinite(float(value)) for row in rows for value in row.values())
    assert all(float(row['engine_rpm']) > 0 and float(row['glow_running']) == 1 for row in rows)
    fuel = [float(row['glow_fuel_kg']) for row in rows]
    fires = [float(row['glow_fire_count']) for row in rows]
    assert fuel[-1] > 0 and fuel[-1] < fuel[0]
    assert all(b <= a for a, b in zip(fuel, fuel[1:]))
    assert fires[-1] > fires[0] and all(b >= a for a, b in zip(fires, fires[1:]))
    return dict(aircraft=aircraft, family=family, rows=len(rows), identity=identity,
                initial_rpm=float(rows[0]['engine_rpm']), final_rpm=float(rows[-1]['engine_rpm']),
                consumed_fuel_kg=fuel[0]-fuel[-1], successful_fires=fires[-1]-fires[0],
                trace_sha256=sha256(path))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', required=True, type=Path)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--pack', type=Path)
    mode.add_argument('--exported', action='store_true')
    parser.add_argument('--out', required=True, type=Path)
    args = parser.parse_args()
    runtime = args.godot.resolve()
    pack = args.pack.resolve() if args.pack else None
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=False)
    records = []
    with tempfile.TemporaryDirectory(prefix='openrc-glow-empty-project-') as temporary:
        for aircraft, family in CASES:
            trace = out/(family+'.csv')
            command = [str(runtime), '--headless', '--audio-driver', 'Dummy']
            if not args.exported:
                command += ['--path', temporary if pack else str(ROOT/'app')]
            if pack:
                command += ['--main-pack', str(pack)]
            command += ['--', '--aircraft='+aircraft, '--trace='+str(trace), '--t=3']
            result = subprocess.run(command, cwd=temporary, capture_output=True, text=True, timeout=120)
            log = result.stdout + result.stderr
            (out/(family+'.log')).write_text(log, encoding='utf-8')
            assert result.returncode == 0 and not re.search(r'^(?:SCRIPT |SHADER )?ERROR:', log, re.M), log
            records.append(inspect_trace(trace, aircraft, family))
            print(f'{family}: {len(records)} / 2 families passed, 721 accepted trace rows', flush=True)
    engine = runtime.with_name(runtime.name.replace('_console.exe', '.exe'))
    report = dict(format='openrc-glow-cli-proof v1', passed=True,
                  scope='native exported application in empty directory' if args.exported else
                        ('compiled PCK in empty project' if pack else 'source project CLI'),
                  runtime=str(runtime), runtime_sha256=sha256(runtime),
                  engine_binary_sha256=sha256(engine),
                  pack_sha256=sha256(pack) if pack else None,
                  checker_sha256=sha256(Path(__file__)), cases=records,
                  claim='Resource/CLI software smoke, not physical, acoustic or release-performance acceptance')
    (out/'report.json').write_text(json.dumps(report, indent=2)+'\n', encoding='utf-8')


if __name__ == '__main__':
    main()
