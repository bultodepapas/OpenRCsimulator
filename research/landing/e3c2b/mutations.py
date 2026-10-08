#!/usr/bin/env python3
"""Prove capture acceptance rejects corrupted copies of a valid rendered kit."""
import argparse
import copy
import json
from pathlib import Path
import shutil
import tempfile

from checks import check_records, check_images, check_kit
from prepare import sha256
from kit import parameters


def run(base):
    base = Path(base)
    check_kit(base/'manifest.json', base/'first', base/'second', *parameters())
    manifest = json.loads((base/'manifest.json').read_text())
    capture = json.loads((base/'first/captures.json').read_text())
    digest = sha256(base/'manifest.json')
    proofs = []

    def rejects(name, action):
        try:
            action()
        except ValueError as error:
            proofs.append(dict(case=name, rejected=True, reason=str(error)))
            return
        raise ValueError('accepted deliberate corruption: '+name)

    changes = [
        ('wrong manifest', lambda r: r.update(manifest_sha256='0'*64)),
        ('wrong tick', lambda r: r['frames'][0].update(tick=20)),
        ('wrong CG', lambda r: r['frames'][0].update(rendered_cg=[999,999,999])),
        ('wrong hinge', lambda r: r['frames'][0]['hinge_rotations'].update(elevator=[1,0,0])),
        ('wrong camera', lambda r: r['frames'][0].update(fov_deg=90)),
        ('hidden shadow', lambda r: r['frames'][0].update(background_shadow_visible=False)),
    ]
    for name, change in changes:
        changed = copy.deepcopy(capture)
        change(changed)
        rejects(name, lambda: check_records(manifest, changed, digest, *parameters()))
    record = copy.deepcopy(capture['frames'][0])
    record['png'] = record['background_png']
    rejects('airplane omitted', lambda: check_images(base/'first', [record], base/'second'))
    with tempfile.TemporaryDirectory() as temporary:
        record = capture['frames'][0]
        for key in ('png', 'background_png'):
            shutil.copyfile(base/'second'/record[key], Path(temporary)/record[key])
        with (Path(temporary)/record['png']).open('ab') as file:
            file.write(b'corruption')
        rejects('repeat image bytes changed', lambda: check_images(base/'first', [record], temporary))
    return dict(positive_control=True, checker_sha256=sha256(Path(__file__).with_name('checks.py')),
                mutation_script_sha256=sha256(__file__), mutations=proofs)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('kit', type=Path)
    args = parser.parse_args()
    print(json.dumps(run(args.kit), indent=2))
