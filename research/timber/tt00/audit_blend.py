#!/usr/bin/env python3
"""Static .blend DNA audit using Blender's official external blendfile module.

Does not execute Blender, evaluate drivers, modify the source, or prove exportability.
See TT-00 README for pinned parser setup and dependency versions.
"""
import argparse
from collections import Counter
import hashlib
import importlib.util
import json
from pathlib import Path
import sys


def audit(source, module_path):
    sys.path.insert(0, str(module_path.parent))
    spec = importlib.util.spec_from_file_location('blendfile', module_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    def name(block):
        return block.get((b'id', b'name'))[2:] if block else None
    with module.open_blend(str(source)) as blend:
        objects = []
        for b in blend.find_blocks_from_code(b'OB'):
            adt = b.get_pointer(b'adt')
            objects.append(dict(name=name(b), type=b.get(b'type'),
                parent=name(b.get_pointer(b'parent')), data=name(b.get_pointer(b'data')),
                location=b.get(b'loc'), scale=b.get(b'size'), rotation_euler=b.get(b'rot'),
                rotation_mode=b.get(b'rotmode'),
                has_modifiers=bool(b.get((b'modifiers', b'first'))),
                has_constraints=bool(b.get((b'constraints', b'first'))),
                has_drivers=bool(adt.get((b'drivers', b'first'))) if adt else False))
        meshes = [dict(name=name(b), vertices=b.get(b'totvert'),
                       faces=b.get(b'totpoly'), corners=b.get(b'totloop'))
                  for b in blend.find_blocks_from_code(b'ME')]
        scenes = [dict(name=name(b), unit_system=b.get((b'unit', b'system')),
                       scale_length=b.get((b'unit', b'scale_length')))
                  for b in blend.find_blocks_from_code(b'SC')]
        return dict(format='openrc-timber-blend-static-audit-v1',
            source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
            parser_sha256=hashlib.sha256(module_path.read_bytes()).hexdigest(),
            header_parser_sha256=hashlib.sha256((module_path.parent/'_blendfile_header.py').read_bytes()).hexdigest(),
            block_counts={k.decode():v for k,v in Counter(b.code for b in blend.blocks).items()},
            scenes=scenes, objects=objects, meshes=meshes,
            materials=[name(b) for b in blend.find_blocks_from_code(b'MA')],
            images=[name(b) for b in blend.find_blocks_from_code(b'IM')],
            actions=[name(b) for b in blend.find_blocks_from_code(b'AC')])


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('parser_module', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    args.output.write_text(json.dumps(audit(args.source, args.parser_module), indent=2) + '\n')
