#!/usr/bin/env python3
"""Read-only TT-00 binary STL/sidecar inventory; Python standard library only."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import struct


def audit(root):
    files = []
    for path in sorted(root.rglob('*')):
        if not path.is_file():
            continue
        raw = path.read_bytes()
        row = dict(path=path.relative_to(root).as_posix(), bytes=len(raw),
                   sha256=hashlib.sha256(raw).hexdigest())
        if path.suffix == '.stl':
            count = struct.unpack_from('<I', raw, 80)[0]
            if len(raw) != 84 + 50 * count:
                raise ValueError(f'Not an exact binary STL: {path}')
            lo, hi = [math.inf] * 3, [-math.inf] * 3
            degenerate = 0
            for face in struct.iter_unpack('<12fH', raw[84:]):
                vertices = [face[3:6], face[6:9], face[9:12]]
                for v in vertices:
                    if not all(math.isfinite(x) for x in v):
                        raise ValueError(f'Non-finite vertex: {path}')
                    for i in range(3):
                        lo[i], hi[i] = min(lo[i], v[i]), max(hi[i], v[i])
                u = [vertices[1][i] - vertices[0][i] for i in range(3)]
                v = [vertices[2][i] - vertices[0][i] for i in range(3)]
                cross = [u[1]*v[2]-u[2]*v[1], u[2]*v[0]-u[0]*v[2], u[0]*v[1]-u[1]*v[0]]
                degenerate += sum(x*x for x in cross) == 0.0
            row.update(triangles=count, bounds_source_units=[lo, hi],
                       zero_area_triangles=degenerate)
        files.append(row)
    scene = json.loads((root/'piezas_stl_v12/escena.json').read_text())
    stls = [r for r in files if 'triangles' in r]
    names = {Path(r['path']).stem for r in stls}
    materials = scene['materiales']
    return dict(format='openrc-timber-source-audit-v1', source_directory=root.as_posix(),
                file_count=len(files), bytes=sum(r['bytes'] for r in files),
                stl_count=len(stls), triangles=sum(r['triangles'] for r in stls),
                bounds_source_units=[
                    [min(r['bounds_source_units'][0][i] for r in stls) for i in range(3)],
                    [max(r['bounds_source_units'][1][i] for r in stls) for i in range(3)]],
                material_labels=sorted(set(materials.values())),
                stls_without_material=sorted(names-set(materials)),
                materials_without_stl=sorted(set(materials)-names),
                missing_hinge_members=sorted({n for h in scene['bisagras'].values()
                                              for n in h['miembros']} - names),
                scene_metadata=scene, files=files)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    args.output.write_text(json.dumps(audit(args.source), indent=2) + '\n')
