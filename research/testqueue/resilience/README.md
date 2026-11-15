# Queue resilience audit probes

These six scripts reproduce eleven observations in the 15 November 2026 baseline
`c048a4e6834646400070a488b293344dc1e1fd80`. They support the
[dated audit](../../../docs/research/testqueue/2026-11-15-resilience/README.md) and
[verification record](../../../docs/research/testqueue/2026-11-15-resilience/verification.md).
The [implementation plan](../../../docs/plans/mcp-queue-resilience.md) owns repairs.

**A successful probe means the audited behavior was reproduced.** These scripts
assert current defects/limitations; they are not new production regression gates.
As repairs land, convert the relevant cases into desired-behavior tests and retain
this dated evidence. Do not change production code to keep an old defect probe green.

They use private fixture roots, injected errors, fake processes and stubbed network
boundaries. No simulator, remote host or normal queue authority is required.
The recorded environment was Python 3.12.14 on Linux; cross-platform success is
not claimed. Run from the repository root using the bounded harness below:

```bash
python - <<'PY'
import os
from pathlib import Path
import subprocess
import sys
import tempfile

repo = Path.cwd()
scripts = sorted((repo / 'research/testqueue/resilience').glob('reproduce_*.py'))
assert len(scripts) == 6, 'Run from the repository root'
with tempfile.TemporaryDirectory(prefix='openrc-queue-audit-') as private:
    env = os.environ.copy()
    env.update(TMPDIR=private, TEMP=private, TMP=private,
               PYTHONDONTWRITEBYTECODE='1',
               PYTHONPATH=os.pathsep.join((str(repo), str(repo / 'tools/testqueue'))))
    for script in scripts:
        result = subprocess.run([sys.executable, str(script)], cwd=repo, env=env,
                                capture_output=True, text=True, timeout=40)
        print(script.name, 'exit', result.returncode)
        print(result.stdout, end='')
        print(result.stderr, end='', file=sys.stderr)
        result.check_returncode()
PY
```

The machine-readable [recorded output](../../../docs/research/testqueue/2026-11-15-resilience/reproduction-results.json)
keeps the source identity and the observed results. Small timing values illustrate
budget boundaries in fixtures; they are not performance estimates for the fleet.
