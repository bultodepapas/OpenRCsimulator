#!/usr/bin/env python3
"""L9e isolated filtering mutation. Never modifies the supplied project.

Run on Linux with a display (WSLg or xvfb-run) and LIBGL_ALWAYS_SOFTWARE=1 for a
GPU-independent Compatibility sampling check. GPU timings are measured separately.
The input project must already be imported. Output must not exist.
"""
import argparse
import os
from pathlib import Path
import shutil
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('godot', 'app', 'out'):
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    output = args.out.resolve()
    output.mkdir(parents=True, exist_ok=False)
    raw_app = output / 'raw-app'
    shutil.copytree(args.app.resolve(), raw_app)
    shader = raw_app / 'render/turf_detail.gdshaderinc'
    source = shader.read_text()
    for index in ('index', 'index + 1.0'):
        old = f'textureGrad(turf_detail, uv + hash22(vec2({index}, 71.0)), gx * 0.5, gy * 0.5)'
        new = f'textureLod(turf_detail, uv + hash22(vec2({index}, 71.0)), 0.0)'
        assert source.count(old) == 1
        source = source.replace(old, new)
    old = '(1.0 - smoothstep(0.015, 0.08, footprint))'
    assert source.count(old) == 1
    shader.write_text(source.replace(old, '1.0'))
    script = Path(__file__).with_name('turf_capture.gd').resolve()
    for name, app, scale in [('filtered', args.app.resolve(), 1), ('raw', raw_app, 1), ('reference', raw_app, 4)]:
        with (output / (name + '.log')).open('wb') as log:
            result = subprocess.run([str(args.godot.resolve()), '--path', str(app), '--audio-driver', 'Dummy',
                '--script', str(script), '--', '--mode=motion', '--filter-reference',
                '--scale=' + str(scale), '--out=' + str(output / name)],
                stdout=log, stderr=subprocess.STDOUT, timeout=180,
                **({'creationflags': subprocess.CREATE_NO_WINDOW} if os.name == 'nt' else {}))
        content = (output / (name + '.log')).read_text()
        assert result.returncode == 0 and 'ERROR:' not in content, content
        print(name, 'PASS', flush=True)


if __name__ == '__main__':
    main()
