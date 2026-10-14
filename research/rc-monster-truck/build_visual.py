"""Reproduce the authorized Bisonte art bundle; never edit generated rig/geometry."""
from pathlib import Path
import argparse
import hashlib
import json

ROOT = Path(__file__).resolve().parents[2]
DELIVERY = ROOT / 'RC CARS/MT8_Bisonte_entrega1_1/MT8_Bisonte'
FILES = {
    'out/MT8_Bisonte.glb': ('app/assets/vehicles/mt8-bisonte/MT8_Bisonte.glb', '7967bb46673ae5b4178a3d40ad8c3b8e1a9d0350b1cc73e2084f52ab496bb0a6'),
    'out/mt8_spec.json': ('app/assets/vehicles/mt8-bisonte/mt8_spec.json', '8d9a2ba3b41400fa934376ede5b110fcc046a05819b3f251076ea90e3fb2b5ef'),
    'godot/mt8_rig.gd': ('app/vehicles/ground/mt8_rig.gd', 'b120b5d202b78d537bb3c71a61339af95463209eb918966535e3c34f760e65a2'),
}


def outputs():
    result = {}
    records = []
    for source, (target, expected) in FILES.items():
        payload = (DELIVERY / source).read_bytes()
        assert hashlib.sha256(payload).hexdigest() == expected, f'Unreviewed source: {source}'
        result[target] = payload
        records.append(dict(source=source, target=target, sha256=expected, bytes=len(payload)))
    manifest = dict(format='openrc-visual-source', version=1, id='mt8-bisonte',
                    delivery=DELIVERY.relative_to(ROOT).as_posix(), files=records,
                    authorization={'date': '2026-10-13', 'by': 'project owner',
                                   'statement': 'Original model and scripts; inclusion and modification in OpenRC authorized.',
                                   'license_identifier': 'LicenseRef-OpenRC-Owner-Authorization'})
    result['assets/vehicles/mt8-bisonte/source-manifest.json'] = (json.dumps(manifest, indent=2) + '\n').encode()
    result['app/assets/vehicles/mt8-bisonte/SOURCE.txt'] = (
        'Bisonte MT8, original model and rig delivered by the project owner.\n'
        'On 2026-10-13 the owner confirmed original authorship and authorized inclusion\n'
        'and modification in OpenRC. No third-party brand affiliation is claimed.\n'
        'Source: RC CARS/MT8_Bisonte_entrega1_1/MT8_Bisonte in the source repository.\n'
        'Generated runtime copies: research/rc-monster-truck/build_visual.py.\n'
        'This authorization does not invent a separate general-purpose asset license.\n'
    ).encode()
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    for relative, payload in outputs().items():
        target = ROOT / relative
        if args.check:
            assert target.is_file() and target.read_bytes() == payload, f'Stale bundle: {relative}'
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(payload)
    print('Bisonte visual bundle: exact source bytes verified' if args.check else 'Bisonte visual bundle written')


if __name__ == '__main__':
    main()
