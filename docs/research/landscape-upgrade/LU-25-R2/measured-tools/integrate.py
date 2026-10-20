from pathlib import Path
import subprocess
r = Path.cwd()
w = r / 'tmp/perf-pass3-20261019'
engine = r / '.tools/Godot_v4.7.2-stable_win64.exe'
def run(script, project):
    p = subprocess.run([str(engine), '--headless', '--path', str(project), '--audio-driver', 'Dummy', '--script', str(script)], capture_output=True, text=True, timeout=60)
    (w / 'draft-oracle.log').write_text(p.stdout + p.stderr, encoding='utf-8')
    assert p.returncode == 0 and 'FAIL' not in p.stdout and 'ERROR:' not in p.stderr, (p.returncode, p.stdout[-300:], p.stderr)
    print(p.stdout[-800:])
run(w / 'test_lake_covered_sampling.gd', w / 'base/app')
for name in ['lake_surface', 'ground_terrain', 'hull_contact']:
    dest = r / 'app/physics' / (name + '.gd')
    assert dest.read_text(encoding='utf-8') == (w / 'base/app/physics' / dest.name).read_text(encoding='utf-8'), 'Concurrent change: ' + str(dest)
for name in ['lake_covered_reference', 'ground_terrain_covered_reference', 'hull_contact_covered_reference']:
    source = w / (name + '.gd')
    target = r / 'app/tests/fixtures' / source.name
    assert not target.exists()
    target.write_bytes(source.read_bytes())
for name in ['lake_surface', 'ground_terrain', 'hull_contact']:
    dest = r / 'app/physics' / (name + '.gd')
    dest.write_bytes((w / 'intended/physics' / dest.name).read_bytes())
test = (w / 'test_lake_covered_sampling.gd').read_text(encoding='utf-8')
test = '## LU-25-R2: covered-only lake query parity against original method oracles.\n' + test[test.index('extends SceneTree'):]
for const, oracle in [('BaseLake', 'lake_covered_reference'), ('BaseTerrain', 'ground_terrain_covered_reference'), ('BaseHull', 'hull_contact_covered_reference')]:
    import re
    test = re.sub(r'const ' + const + r' := preload\("[^"]+"\)', 'const ' + const + ' := preload("res://tests/fixtures/' + oracle + '.gd")', test)
test = test.replace('C:/DEVELOPMENT/OpenRCsimulator/tmp/perf-pass3-20261019/candidate/physics/', 'res://physics/')
(r / 'app/tests/test_lake_covered_sampling.gd').write_text(test, encoding='utf-8')
print('Integrated three measured production files and four regression files.')
