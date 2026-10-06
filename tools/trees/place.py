#!/usr/bin/env python3
"""L6b offline placement; estimates for visual composition, not surveyed field geometry."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import random

SEED = 610602
COUNT = 480
# Conservative whole-card radius at 25m height (1.125001 / 2 * 25 < 15).
CROWN_RADIUS = 15.0
GAPS = ((30.0, 8.0), (210.0, 10.0))  # center azimuth, half width in degrees


def generate(field):
    rng = random.Random(SEED)
    pilot = field['pilot']
    pn, pe = (pilot[k]['value'] for k in ('north', 'east'))
    strips = [s for s in field['surfaces'] if s['type'] in ('runway', 'mown')]
    points = []
    for _ in range(200000):
        n, e = rng.randrange(-2280, 2281) / 4, rng.randrange(-2280, 2281) / 4
        radius = math.hypot(n, e)
        if not 270 <= radius <= 570:
            continue
        angle = math.degrees(math.atan2(e, n)) % 360
        # Keep the entire crown outside the designed gaps, not just the trunk.
        margin = math.degrees(math.asin(CROWN_RADIUS / radius))
        if any(abs((angle - center + 180) % 360 - 180) <= half + margin for center, half in GAPS):
            continue
        if any(abs(n + pn - s['center_north']['value']) <= s['width_north_south']['value'] / 2 + 35 + CROWN_RADIUS for s in strips):
            continue
        # Broad irregular clusters rather than a wall or evenly spaced plantation.
        density = 0.25 + 0.75 * (0.5 + 0.5 * math.sin(math.radians(3 * angle) + math.sin(math.radians(5 * angle))))
        if rng.random() > density or any((n - p[0]) ** 2 + (e - p[1]) ** 2 < 9 ** 2 for p in points):
            continue
        points.append([n, e, 0])
        if len(points) == COUNT:
            break
    if len(points) != COUNT:
        raise ValueError('Placement exhausted its bounded candidate budget')
    points.sort()
    return {'id': 'treeline', 'type': 'treeline', 'collides': False, 'positions': {
        'value': points, 'unit': 'm', 'kind': 'derived',
        'source': 'L6b tools/trees/place.py, seed 610602. Estimated visual layout: 480 pilot-relative NED positions on a 0.25 m grid; 270-570 m radius; >=9 m spacing; crown-cleared gaps at 30+/-8 and 210+/-10 deg; runway/mown east-west corridor with 35 m margin plus 15 m crown radius. Flat visual vegetation, no collision or surveyed dimensions.'}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--field', type=Path, default=Path(__file__).resolve().parents[2] / 'app/data/fields/default.json')
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    field = json.loads(args.field.read_text())
    objects = [generate(field)]
    if args.check:
        if field['objects'] != objects:
            raise SystemExit('Committed placement differs from offline recipe')
    else:
        field['objects'] = objects
        args.field.write_text(json.dumps(field, indent=2) + '\n')
    digest = hashlib.sha256(json.dumps(objects[0]['positions']['value'], separators=(',', ':')).encode()).hexdigest()
    print(json.dumps({'count': COUNT, 'seed': SEED, 'positions_sha256': digest, 'gaps_deg': GAPS}, indent=2))


if __name__ == '__main__':
    main()
