#!/usr/bin/env python3
"""Resume app/test.sh at a test after an infrastructure timeout; keep its assertions unchanged."""
import argparse
from pathlib import Path
import shlex
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--project', type=Path, required=True)
parser.add_argument('--start', default='test_landing_maneuver.gd')
parser.add_argument('--timeout', type=int, default=180)
args = parser.parse_args()
project = args.project.resolve()
if not (project / 'tests' / args.start).is_file() or args.timeout <= 0:
    parser.error('start must name an existing test and timeout must be positive')
source = (project / 'test.sh').read_text()
header = source.split('# L6a imports', 1)[0]
header = header.replace('HERE="$(cd "$(dirname "$0")" && pwd)"', 'HERE=' + shlex.quote(str(project)))
header = header.replace('timeout 60 ', f'timeout {args.timeout} ')
marker = 'LOG="$(mktemp)";'
assert source.count(marker) == 1
remaining = marker + source.split(marker, 1)[1]
loop = 'for t in "$HERE"/tests/test_*.gd; do\n'
assert remaining.count(loop) == 1
remaining = remaining.replace(loop, loop + '  if [[ "$(basename "$t")" < ' + shlex.quote(args.start) + ' ]]; then continue; fi\n', 1)
print(f'Resuming {args.start} onward; per-process timeout {args.timeout}s; earlier sections must be verified separately.', flush=True)
with tempfile.NamedTemporaryFile(mode='w', suffix='.sh', prefix='openrc-resume-') as script:
    script.write(header + remaining)
    script.flush()
    raise SystemExit(subprocess.run(['bash', script.name]).returncode)
