"""Reproduce false acceptance without changing the app. Run from repository root.
Requires a genuine trace path, e.g. produced by --trace=/tmp/trim.csv --t=3.
"""
import csv
import io
from pathlib import Path
import subprocess
import sys
import tempfile

lines = Path(sys.argv[1]).read_text().splitlines()
meta = [line for line in lines if line.startswith('#')]
rows = list(csv.reader(line for line in lines if not line.startswith('#')))
mutations = {'initial sample only': rows[:2]}
nonfinite = [row.copy() for row in rows]
for name in ('speed_mps', 'pitch_deg', 'alt_m', 'engine_rpm'):
    nonfinite[-1][rows[0].index(name)] = 'nan'
mutations['nonfinite final sample'] = nonfinite
for label, values in mutations.items():
    stream = io.StringIO()
    stream.write('\n'.join(meta) + '\n')
    csv.writer(stream).writerows(values)
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / 'trace.csv'
        path.write_text(stream.getvalue())
        result = subprocess.run([sys.executable, 'app/tests/check_trimmed_flight.py', str(path)], capture_output=True, text=True)
    print(label, 'exit=', result.returncode, '\n', result.stdout, result.stderr)
