import hashlib
import json
import math
import re
import subprocess
from pathlib import Path

base = Path(__file__).resolve().parent
comparison_path = Path('C:/DEVELOPMENT/OpenRCsimulator/docs/research/physics-audit-2026-10-14/remediation/R11/damping-lag-diagnostic/d11g-repair/yaw_r02_vs_kj_comparison-v4.json')
inputs = json.loads(comparison_path.read_text())['model_inputs']
incidences = inputs['camber_equivalent_alpha0_rad']
assert max(incidences) - min(incidences) < 1e-14
angle = math.degrees(math.atan(incidences[0]))
summary = {'scope': 'Model comparison only; equivalent incidence is not measured camber.',
           'source_comparison_sha256': hashlib.sha256(comparison_path.read_bytes()).hexdigest(),
           'incidence_deg': angle, 'rows': []}
for panels, profile in [(6, .0434), (6, 0.0), (20, .0434), (80, .0434)]:
    name = f'matched-{panels}-' + ('profile' if profile else 'inviscid')
    work = base / name
    work.mkdir()  # refuse to overwrite any previous experiment
    geometry = (base / f'wing-{panels}.avl').read_text()
    geometry = geometry.replace('zero-camber', 'equivalent-incidence')
    geometry = geometry.replace(f'{6.0818/(2*math.pi):.16g}', f'{inputs["strip_slope_per_rad"]/(2*math.pi):.16g}')
    geometry = geometry.replace('0.0434', str(profile)).replace('0.4645152', str(inputs['area_m2']))
    geometry = geometry.replace('0.3048 0.0\nCLAF', f'0.3048 {angle:.16g}\nCLAF')
    (work / 'wing.avl').write_text(geometry, encoding='ascii')
    commands = ['OPER']
    for alpha in [0, 4, 11]:
        commands += [f'A A {alpha}', 'X', 'SB', f'a{alpha}-body.txt', 'FT', f'a{alpha}-forces.txt']
    tape = '\n'.join(commands + ['', 'QUIT', ''])
    (work / 'commands.txt').write_text(tape, encoding='ascii')
    run = subprocess.run([str(base/'avl352.exe'), 'wing.avl'], cwd=work, input=tape,
                         capture_output=True, text=True, timeout=60, creationflags=subprocess.CREATE_NO_WINDOW)
    (work/'run.log').write_text(run.stdout+'\nSTDERR:\n'+run.stderr, encoding='utf-8')
    assert run.returncode == 0, run.returncode
    for alpha in [0, 4, 11]:
        text = (work/f'a{alpha}-body.txt').read_text()
        row = {'panels':panels, 'profile_CD0':profile, 'alpha_deg':alpha}
        for key in ['Cnr', 'CLtot', 'CDtot']:
            row[key] = float(re.search(r'\b'+key+r'\s*=\s*([-+0-9.Ee]+)', text)[1])
        summary['rows'].append(row)
(base/'matched-summary.json').write_text(json.dumps(summary,indent=2)+'\n',encoding='utf-8')
print(json.dumps(summary,indent=2))
