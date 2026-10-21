from pathlib import Path
import subprocess, sys, json
root = Path(__file__).resolve().parent
repo = root.parents[1]
variant, number = sys.argv[1:]
assert variant in ('control', 'warmup')
assert number.isdecimal()
output = root / f'{variant}-{number}.json'
command = [sys.executable, str(repo / 'tools/godot/run_checked.py'), '--out-dir', str(root / 'native'), '--label', f'{variant}-{number}', '--timeout', '100', '--', str(repo / '.tools/Godot_v4.7.2-stable_win64.exe'), '--path', str(root / f'load-{variant}/app'), '--audio-driver', 'Dummy', '--windowed', '--resolution', '1280x720', '--screen', '0', '--position', '80,80', '--max-fps', '60', '--script', str(repo / 'research/performance/loading_probe.gd'), '--', f'--output={output}', '--cycles=2']
result = subprocess.run(command, cwd=repo, capture_output=True, text=True)
print(result.stdout[-2200:])
print(result.stderr[-1000:])
if result.returncode:
    raise SystemExit(result.returncode)
report = json.loads(output.read_text())
print(json.dumps(report, indent=2)[:4500])
