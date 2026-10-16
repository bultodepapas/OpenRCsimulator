"""Independent AVL wing-only comparison; no simulator edits or flight-validation claim."""
import hashlib
import json
import math
import subprocess
from pathlib import Path

base = Path(__file__).resolve().parent
exe = base / 'avl352.exe'
assert hashlib.sha256(exe.read_bytes()).hexdigest() == '443520d255408491222a8df9060bd000f78da95a68845a2f6efdbc67e203f07a'
span, chord, slope = 1.524, 0.3048, 6.0818
for panels in (6, 20, 80):
    name = f'wing-{panels}'
    geometry = f'''D11f matched zero-camber rectangular wing, AVL 3.52, {panels} span panels
0.0
0 0 0.0
{span*chord:.12g} {chord} {span}
0.0 0.0 0.0
0.0
SURFACE
Wing
1 0.0 {panels} 0.0
CDCL
-2.0 0.0434 0.0 0.0434 2.0 0.0434
SECTION
{-chord/4} {-span/2} 0.0 {chord} 0.0
CLAF
{slope/(2*math.pi):.16g}
SECTION
{-chord/4} {span/2} 0.0 {chord} 0.0
CLAF
{slope/(2*math.pi):.16g}
'''
    (base / (name + '.avl')).write_text(geometry, encoding='ascii')
    commands = ['OPER']
    for alpha in (0, 4, 11):
        commands += [f'A A {alpha}', 'X', 'SB', f'{name}-a{alpha}-body.txt', 'FT', f'{name}-a{alpha}-forces.txt']
    commands += ['', 'QUIT', '']
    tape = '\n'.join(commands)
    (base / (name + '-commands.txt')).write_text(tape, encoding='ascii')
    output = subprocess.run([str(exe), name+'.avl'], cwd=base, input=tape, text=True,
                            capture_output=True, timeout=60, creationflags=subprocess.CREATE_NO_WINDOW)
    (base / (name + '-run.log')).write_text(output.stdout + '\nSTDERR:\n' + output.stderr, encoding='utf-8')
    print(name, output.returncode)
    if output.returncode:
        raise SystemExit(output.returncode)
    for alpha in (0, 4, 11):
        p = base / f'{name}-a{alpha}-body.txt'
        if not p.is_file():
            raise RuntimeError(f'Missing derivative output: {p}')
        print(alpha, [line.strip() for line in p.read_text().splitlines() if 'Cnr' in line or 'Cnr' in line.replace('_','')])
