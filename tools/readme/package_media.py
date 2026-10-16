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
        'turbo-lumber-evolution': 'turbo-lumber-evolution.png',
        'xcell-60-research': 'helicopter.png',
        'mt8-bisonte': 'bisonte-mt8.png',
        'monster-car-2': 'monster-car-2.png',
    }
    if {a['id'] for a in manifest['vehicles']} != set(names):
        raise ValueError('Expected eight tour vehicles')
    if [a['id'] for a in manifest['vehicles']][:4] != ['sebart-avanti-s-a200-p100rx', 'xcell-60-research', 'mt8-bisonte', 'monster-car-2']:
        raise ValueError('Expected jet, helicopter and both trucks first')
    expected_frames = sum(a['frames'] for a in manifest['vehicles'])
    frame_paths = sorted((args.source / 'frames').glob('*.png'))
    if expected_frames != 576 or len(frame_paths) != expected_frames or manifest['frame_count'] != expected_frames:
        raise ValueError('Expected 576 fresh rendered frames')
    frames = []
    for path in frame_paths:
        with Image.open(path) as image:
            if image.size != (800, 450):
                raise ValueError(f'Wrong frame size: {path}')
            frames.append(image.convert('RGB').quantize(colors=64, dither=Image.Dither.NONE))
    args.destination.mkdir(parents=True, exist_ok=True)
    gif = args.destination / 'aircraft-tour.gif'
    frames[0].save(gif, save_all=True, append_images=frames[1:], duration=60,
                  loop=0, optimize=True)
    with Image.open(gif) as image:
        if image.n_frames != expected_frames:
            raise ValueError('GIF dropped frames')
        duration_ms = 0
        for i in range(image.n_frames):
            image.seek(i)
            duration_ms += image.info['duration']
    if gif.stat().st_size > 12_000_000:
        raise ValueError('README animation exceeds 12 MB')
    for aircraft in manifest['vehicles']:
        with Image.open(args.source / aircraft['still']) as image:
            if image.size != (960, 540):
                raise ValueError('Wrong still size')
            image.load()
        target = names[aircraft['id']]
        shutil.copyfile(args.source / aircraft['still'], args.destination / target)
        aircraft['still'] = target
    shutil.copyfile(args.source / 'flight.png', args.destination / 'flight.png')
    shutil.copyfile(args.source / 'flight.json', args.destination / 'flight.json')
    manifest['capture_tools_sha256'] = {
        name: hashlib.sha256(Path(__file__).with_name(name).read_bytes()).hexdigest()
        for name in ('capture_aircraft.gd', 'package_media.py')
    }
    manifest['animation'] = {'file': gif.name, 'duration_ms': duration_ms,
                             'pillow': PIL.__version__, 'frame_duration_ms': 60}
    manifest['sha256'] = {
        p.name: hashlib.sha256(p.read_bytes()).hexdigest()
        for p in sorted(args.destination.iterdir())
        if p.suffix in ('.png', '.gif')
    }
    (args.destination / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(f"Packaged {len(manifest['vehicles'])} vehicles, flight screenshot, {len(frames)} GIF frames ({gif.stat().st_size:,} bytes)")


if __name__ == '__main__':
    main()
