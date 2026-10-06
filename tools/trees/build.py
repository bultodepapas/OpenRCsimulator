"""Reproducible L6a offline tree assets; no writes to the runtime tree.

npm ci --prefix tools/trees
$(app/tests/visual-env.sh) tools/trees/build.py --out /tmp/trees-bake
Copy verified artifacts only after reviewing reports. --out must be empty.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
TOOLS = Path(__file__).resolve().parent
IDS = ('CommonTree_1', 'CommonTree_3', 'Pine_1')


def run(command, log, env=None, timeout=180):
    with Path(log).open('w') as stream:
        child = subprocess.Popen([str(x) for x in command], stdout=stream, stderr=subprocess.STDOUT,
                                 env=env, start_new_session=True)
        try:
            status = child.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            os.killpg(child.pid, signal.SIGKILL)
            child.wait()
            raise RuntimeError(f'timed out: {command[0]}; see {log}')
    text = Path(log).read_text(errors='replace')
    if status or re.search(r'(?m)^\s*(?:(?:SCRIPT|SHADER) )?ERROR:', text):
        raise RuntimeError(f'failed: {command}; see {log}\n{text[-2000:]}')


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def inspect_mips(folder):
    """Check actual Godot mips, including silhouette loss at distant sizes."""
    import numpy as np
    from PIL import Image
    rows = []
    for level in range(11):
        image = Image.open(folder / f'mip-{level:02d}.png').convert('RGBA')
        if image.size != (1024 >> level, 1024 >> level):
            raise RuntimeError(f'bad mip size at level {level}')
        pixels = np.asarray(image)
        size = 512 >> level
        tiles = []
        if size:
            for x, y in ((0, 0), (size, 0), (0, size)):
                alpha = pixels[y:y+size, x:x+size, 3]
                count = int((alpha >= 128).sum())
                if level <= 4 and not count:
                    raise RuntimeError(f'empty silhouette at mip {level}')
                tiles.append(count)
            if level <= 4 and np.any(pixels[size:, size:, 3]):
                raise RuntimeError(f'alpha leaked into reserved slot at mip {level}')
        rows.append({'level': level, 'atlas_size_px': image.width,
                     'tile_opaque_pixels_at_cutoff_0_5': tiles})
    (folder / 'mip-analysis.json').write_text(json.dumps(rows, indent=2)+'\n')


def main():
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument('--out', required=True, type=Path)
    parser.add_argument('--godot', type=Path, default=ROOT / '.tools/Godot_v4.7.2-stable_linux.x86_64')
    args = parser.parse_args()
    out = args.out.resolve()
    if out.exists() and any(out.iterdir()):
        raise RuntimeError('--out must be new or empty; never reuse stale evidence')
    out.mkdir(parents=True, exist_ok=True)
    godot = args.godot.resolve()
    version = subprocess.check_output([str(godot), '--version'], text=True).strip()
    if not version.startswith('4.7.2.stable.'):
        raise RuntimeError(f'expected pinned Godot 4.7.2, got {version}')
    run(['node', TOOLS / 'adapt.mjs', '--out', out / 'derived'], out / 'adapt.log')
    with tempfile.TemporaryDirectory(prefix='openrc-tree-bake-') as scratch:
        project = Path(scratch)
        (project / 'project.godot').write_text('config_version=5\n[application]\nconfig/name="L6a Bake"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\nrenderer/rendering_method.mobile="gl_compatibility"\nenvironment/defaults/default_clear_color=Color(0,0,0,0)\n')
        (project / 'trees').mkdir()
        for name in IDS:
            for suffix in ('', '-reference'):
                shutil.copy2(out / 'derived' / (name + suffix + '.glb'), project / 'trees')
        raw = out / 'raw'
        raw.mkdir()
        env = {**os.environ, 'LP_NUM_THREADS': '1'}
        run(['xvfb-run', '-a', godot, '--path', project, '--rendering-driver', 'opengl3',
             '--audio-driver', 'Dummy', '--script', TOOLS / 'bake.gd', '--', '--out=' + str(raw)],
            out / 'bake.log', env=env)
        import sys
        run([sys.executable, TOOLS / 'process_atlas.py', '--bake', raw, '--out', out / 'atlas'], out / 'process.log')
        run([godot, '--headless', '--path', project, '--script', TOOLS / 'fix_atlas.gd', '--', out / 'atlas'], out / 'mips.log')
        inspect_mips(out / 'atlas')
    # Keep input hashes with the bake, so reproducing an image never relies on a script filename alone.
    inputs = list(TOOLS.glob('*.gd')) + list(TOOLS.glob('*.py')) + list(TOOLS.glob('*.mjs')) + [TOOLS/'package-lock.json']
    inputs += list((ROOT/'assets/landscape/trees/source').glob('*'))
    report = {'format':'openrc-tree-bake v1', 'godot':version,
              'inputs_sha256':{str(p.relative_to(ROOT)):sha(p) for p in sorted(inputs) if p.is_file()},
              'outputs_sha256':{str(p.relative_to(out)):sha(p) for folder in ('derived','atlas')
                                for p in sorted((out/folder).glob('*')) if p.is_file()},
              'bake':json.loads((raw/'bake.json').read_text())}
    (out/'manifest.json').write_text(json.dumps(report, indent=2, sort_keys=True)+'\n')
    print(f'Bake complete: {out}')


if __name__ == '__main__':
    main()
