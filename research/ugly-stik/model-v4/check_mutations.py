#!/usr/bin/env python3
"""Prove winding and built-rod checks reject defects, only in temporary copies."""
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    root = next(p for p in Path(__file__).resolve().parents if (p / 'app/get-godot.sh').is_file())
    godot = subprocess.check_output([str(root / 'app/get-godot.sh')], text=True).strip()
    cases = [
        ('inverted_faces', 'ugly_stik_equipment.gd',
         'if (p1 - a).cross(p2 - a).dot(normal) > 0.0:',
         'if (p1 - a).cross(p2 - a).dot(normal) < 0.0:', 'clockwise faces agree with normals'),
        ('stretched_rod', 'ugly_stik_controls.gd',
         'var node := _cylinder_mesh(name, radius, length, color, profile, 8)',
         'var node := _cylinder_mesh(name, radius, length * 1.1, color, profile, 8)', 'built rod'),
    ]
    with tempfile.TemporaryDirectory(prefix='openrc-visual-mutations-') as directory:
        app = Path(directory) / 'app'
        shutil.copytree(root / 'app', app, ignore=shutil.ignore_patterns('.godot', 'captures', '__pycache__'))
        command = [godot, '--headless', '--path', str(app), '--script', 'res://aircraft/verify_model.gd']
        baseline = subprocess.run(command, capture_output=True, text=True, timeout=60)
        assert baseline.returncode == 0 and '0 failed' in baseline.stdout, baseline.stdout + baseline.stderr
        print('Unmodified temporary copy: PASS')
        for name, filename, old, new, expected in cases:
            path = app / 'aircraft' / filename
            source = path.read_text()
            assert source.count(old) == 1, f'Mutation anchor changed: {filename}'
            try:
                path.write_text(source.replace(old, new))
                result = subprocess.run(command, capture_output=True, text=True, timeout=60)
                output = result.stdout + result.stderr
                assert result.returncode != 0 and expected in output, output
                assert 'Parse Error' not in output, output
                print(f'{name}: rejected by {expected}; exit={result.returncode}')
            finally:
                path.write_text(source)


if __name__ == '__main__':
    main()
