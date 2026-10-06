"""Package untouched Godot stills and assemble the README's model-tour GIF.

Use the repository's pinned visual Python environment (app/tests/visual-env.sh).
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil

import PIL
from PIL import Image


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('destination', type=Path)
    args = parser.parse_args()
    manifest = json.loads((args.source / 'manifest.json').read_text())
    names = {
        'jensen-das-ugly-stik-60': 'ugly-stik.png',
        'gp-extra-300s-60': 'extra-300s.png',
        'p51d-mustang-120': 'p51d-mustang.png',
        'sebart-avanti-s-a200-p100rx': 'avanti-s.png',
    }
    if {a['id'] for a in manifest['aircraft']} != set(names):
        raise ValueError('Expected the four catalog aircraft')
    frame_paths = sorted((args.source / 'frames').glob('*.png'))
    if len(frame_paths) != 96 or manifest['frame_count'] != 96:
        raise ValueError('Expected 96 fresh rendered frames')
    frames = []
    for path in frame_paths:
        with Image.open(path) as image:
            if image.size != (640, 360):
                raise ValueError(f'Wrong frame size: {path}')
            frames.append(image.convert('RGB'))
    args.destination.mkdir(parents=True, exist_ok=True)
    gif = args.destination / 'aircraft-tour.gif'
    frames[0].save(gif, save_all=True, append_images=frames[1:], duration=110,
                  loop=0, optimize=True)
    with Image.open(gif) as image:
        if image.n_frames != 96:
            raise ValueError('GIF dropped frames')
        duration_ms = 0
        for i in range(image.n_frames):
            image.seek(i)
            duration_ms += image.info['duration']
    if gif.stat().st_size > 2_000_000:
        raise ValueError('README animation exceeds 2 MB')
    for aircraft in manifest['aircraft']:
        with Image.open(args.source / aircraft['still']) as image:
            if image.size != (960, 540):
                raise ValueError('Wrong still size')
            image.load()
        target = names[aircraft['id']]
        shutil.copyfile(args.source / aircraft['still'], args.destination / target)
        aircraft['still'] = target
    shutil.copyfile(args.source / 'flight.png', args.destination / 'flight.png')
    shutil.copyfile(args.source / 'flight.json', args.destination / 'flight.json')
    manifest['animation'] = {'file': gif.name, 'duration_ms': duration_ms,
                             'pillow': PIL.__version__, 'frame_duration_ms': 110}
    manifest['sha256'] = {
        p.name: hashlib.sha256(p.read_bytes()).hexdigest()
        for p in sorted(args.destination.iterdir())
        if p.suffix in ('.png', '.gif')
    }
    (args.destination / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(f'Packaged 4 aircraft, flight screenshot, {len(frames)} GIF frames ({gif.stat().st_size:,} bytes)')


if __name__ == '__main__':
    main()
