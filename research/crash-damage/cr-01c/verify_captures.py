#!/usr/bin/env python3
"""Check CR-01c image identity and the measured real-scene contact/camera contracts."""
import argparse
import hashlib
import json
from pathlib import Path
from PIL import Image


def verify(folder):
    doc = json.loads((folder/'captures.json').read_text())
    assert doc['format'] == 'openrc-cr01c-captures v1'
    rows = {row['name']: row for row in doc['records']}
    names = {'banked-crossing', 'banked-detected-reference', 'banked-pilot-crossing',
             'level-crossing', 'level-detected-reference'}
    assert set(rows) == names and len(doc['records']) == len(names)
    for name, row in rows.items():
        path = folder/(name+'.png')
        assert hashlib.sha256(path.read_bytes()).hexdigest() == row['image_sha256'], name
        with Image.open(path) as img:
            assert list(img.size) == row['size'] == [960, 540], name
            assert any(hi-lo > 100 for lo, hi in img.convert('RGB').getextrema()), name+' blank'
        if name.endswith('crossing'):
            assert abs(row['rendered_contact'][1]) < 2e-6, name
        else:
            assert row['rendered_contact'][1] < -.1, name+' reference does not penetrate'
    for fixture in ['banked', 'level']:
        crossing, detected = rows[fixture+'-crossing'], rows[fixture+'-detected-reference']
        for key in ['camera_position', 'camera_basis', 'camera_fov', 'detected_state']:
            assert crossing[key] == detected[key], (fixture, key)
        assert crossing['image_sha256'] != detected['image_sha256'], fixture
    print('Five identified nonblank images; plane residuals and paired camera/state controls pass.')


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('folder', type=Path)
    verify(p.parse_args().folder)
