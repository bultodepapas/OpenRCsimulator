#!/usr/bin/env python3
"""Independent TT-00-R1 GLB/metadata audit. Does not execute supplier scripts.

Supports the uncompressed, nonsparse accessors used by this delivery; not a
general glTF conformance validator. Requires NumPy; records its version.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import numpy as np


def rotation(q):
    x, y, z, w = np.array(q, dtype=float) / np.linalg.norm(q)
    return np.array([[1-2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w)],
                     [2*(x*y+z*w), 1-2*(x*x+z*z), 2*(y*z-x*w)],
                     [2*(x*z-y*w), 2*(y*z+x*w), 1-2*(x*x+y*y)]])


class GLB:
    def __init__(self, path):
        raw = path.read_bytes()
        magic, version, length = struct.unpack_from('<III', raw)
        assert magic == 0x46546C67 and version == 2 and length == len(raw)
        chunks = {}; offset = 12
        while offset < len(raw):
            size, kind = struct.unpack_from('<II', raw, offset)
            assert offset + 8 + size <= len(raw)
            chunks[kind] = raw[offset+8:offset+8+size]; offset += 8+size
        self.j = json.loads(chunks[0x4E4F534A]); self.binary = chunks[0x004E4942]
        self.nodes = self.j['nodes']; self.by_name = {n['name']:i for i,n in enumerate(self.nodes)}
        assert len(self.by_name) == len(self.nodes)
        self.parent = {child:i for i,n in enumerate(self.nodes) for child in n.get('children', [])}
        self.world = {}; self.local = {}
        for i,n in enumerate(self.nodes):
            if 'matrix' in n:
                m = np.array(n['matrix']).reshape(4,4).T
            else:
                m = np.eye(4); m[:3,:3] = rotation(n.get('rotation',[0,0,0,1])) @ np.diag(n.get('scale',[1,1,1]))
                m[:3,3] = n.get('translation',[0,0,0])
            self.local[i] = m
        def world(i):
            if i not in self.world:
                self.world[i] = world(self.parent[i]) @ self.local[i] if i in self.parent else self.local[i]
            return self.world[i]
        for i in range(len(self.nodes)): world(i)

    def accessor(self, i):
        a = self.j['accessors'][i]; assert 'sparse' not in a and not a.get('normalized',False)
        bv = self.j['bufferViews'][a['bufferView']]; assert bv.get('buffer',0) == 0
        dtype = np.dtype({5126:'<f4',5125:'<u4',5123:'<u2',5121:'u1'}[a['componentType']])
        count = {'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']]
        start = bv.get('byteOffset',0)+a.get('byteOffset',0)
        stride = bv.get('byteStride',dtype.itemsize*count)
        assert a['count'] == 0 or a.get('byteOffset',0)+(a['count']-1)*stride+count*dtype.itemsize <= bv['byteLength']
        return np.ndarray((a['count'], count), dtype=dtype, buffer=self.binary,
                          offset=start, strides=(stride,dtype.itemsize)).copy()

    def vertices(self, node):
        i = self.by_name[node]; m = self.world[i]
        points = np.concatenate([self.accessor(p['attributes']['POSITION']) for p in self.j['meshes'][self.nodes[i]['mesh']]['primitives']])
        return points @ m[:3,:3].T + m[:3,3]

    def summary(self):
        rows=[]; points=[]
        for i,n in enumerate(self.nodes):
            if 'mesh' not in n: continue
            mesh=self.j['meshes'][n['mesh']]; triangles=0; zero=0; nonfinite=0
            for p in mesh['primitives']:
                assert p.get('mode',4)==4
                v=self.accessor(p['attributes']['POSITION']); ix=self.accessor(p['indices']).reshape(-1).astype(int)
                assert len(ix)%3==0 and ix.min()>=0 and ix.max()<len(v)
                t=v[ix.reshape(-1,3)].astype(float); triangles+=len(t)
                area2=np.linalg.norm(np.cross(t[:,1]-t[:,0],t[:,2]-t[:,0]),axis=1)
                zero+=int(np.count_nonzero(area2==0)); nonfinite+=int(np.count_nonzero(~np.isfinite(v)))
            world=self.vertices(n['name']);points.append(world)
            rows.append(dict(name=n['name'],triangles=triangles,surfaces=len(mesh['primitives']),
                             zero_area_triangles=zero,nonfinite_coordinates=nonfinite,
                             identity_local_transform=bool(np.allclose(self.local[i],np.eye(4),atol=1e-7)),
                             bounds_m=[world.min(0).tolist(),world.max(0).tolist()]))
        cloud=np.concatenate(points)
        animations=[]
        for a in self.j.get('animations',[]):
            animations.append(dict(name=a.get('name'),channels=len(a['channels']),
                targets=[self.nodes[c['target']['node']]['name'] for c in a['channels']],
                duration_s=max(float(self.accessor(s['input']).max()) for s in a['samplers'])))
        return dict(nodes=len(self.nodes),mesh_nodes=len(rows),triangles=sum(x['triangles'] for x in rows),
                    surfaces=sum(x['surfaces'] for x in rows),materials=len(self.j.get('materials',[])),
                    external_uris=[x['uri'] for k in ['buffers','images'] for x in self.j.get(k,[]) if 'uri' in x],
                    extensions_used=self.j.get('extensionsUsed',[]),extensions_required=self.j.get('extensionsRequired',[]),
                    bounds_m=[cloud.min(0).tolist(),cloud.max(0).tolist()],size_m=np.ptp(cloud,axis=0).tolist(),
                    roots=[dict(name=self.nodes[i]['name'],matrix=self.world[i].tolist()) for i in self.j['scenes'][self.j.get('scene',0)]['nodes']],
                    meshes=rows,animations=animations),cloud


def audit(package):
    metadata=json.loads((package/'metadata.json').read_text())
    glb=GLB(package/'export/aircraft.glb'); summary,cloud=glb.summary()
    demo=GLB(package/'export/aircraft_demo.glb');demo_summary,_=demo.summary()
    joints=[];signs=[]
    a=np.deg2rad(10);rx=np.array([[1,0,0],[0,np.cos(a),-np.sin(a)],[0,np.sin(a),np.cos(a)]])
    for name,info in metadata['articulations'].items():
        i=glb.by_name[name];w=glb.world[i];axis=w[:3,0]/np.linalg.norm(w[:3,0]); declared=np.array(info['axis_sim'])
        joints.append(dict(name=name,parent=glb.nodes[glb.parent[i]]['name'],
            parent_matches=glb.nodes[glb.parent[i]]['name']==info['parent_node'],
            pivot_error_m=float(np.linalg.norm(w[:3,3]-info['pivot_sim_m'])),
            axis_error=float(np.linalg.norm(axis-declared)),
            local_rest_rotation_error=float(np.linalg.norm(glb.local[i][:3,:3]-rotation(info['rest_local_rotation_gltf_xyzw'])))))
        point=None; component=None; expected=None
        if name.startswith(('aileron_','flap_','elevator_','rudder_')):
            verts=glb.vertices(info['mesh_node']);point=verts[np.argmax(verts[:,2])]
            component=0 if name.startswith('rudder') else 1;expected=1 if component==0 else -1
        elif name=='tailwheel_steer':
            point=glb.world[glb.by_name['tailwheel_axle']][:3,3];component=0;expected=1
        elif 'suspension' in name:
            point=glb.world[glb.by_name['wheel_left_axle' if 'left' in name else 'wheel_right_axle']][:3,3]
            component=0;expected=-1 if 'left' in name else 1
        elif 'axle' in name:
            point=w[:3,3]+np.array([0,.01,0]);component=2;expected=-1
        elif name=='propeller_spin':
            point=w[:3,3]+np.array([0,.1,0]);component=0;expected=1
        if point is not None:
            delta=w[:3,:3]@rx@np.linalg.solve(w[:3,:3],point-w[:3,3])+w[:3,3]-point
            signs.append(dict(name=name,displacement_at_plus10deg_m=delta.tolist(),
                              expected_component=component,expected_sign=expected,passed=bool(delta[component]*expected>1e-6)))
    landmarks=[]
    pivot_map={'left_main_wheel_center':'wheel_left_axle','right_main_wheel_center':'wheel_right_axle',
               'tailwheel_center':'tailwheel_axle','propeller_hub':'thrust_frame','datum_D0':'TurboTimberEvolution'}
    for name,info in metadata['landmarks'].items():
        pos=np.array(info['sim_m'])
        if name in pivot_map:
            error=np.linalg.norm(pos-glb.world[glb.by_name[pivot_map[name]]][:3,3]);method='pivot origin'
        else:
            error=np.linalg.norm(cloud-pos,axis=1).min();method='nearest exported vertex'
        landmarks.append(dict(name=name,error_m=float(error),method=method))
    comp=metadata['mass_properties']['components'];mass=sum(x['mass']['value'] for x in comp)
    return dict(format='openrc-timber-r1-independent-audit-v1',numpy_version=np.__version__,
        files=[dict(path=p.relative_to(package).as_posix(),bytes=p.stat().st_size,sha256=hashlib.sha256(p.read_bytes()).hexdigest())
               for p in sorted(package.rglob('*')) if p.is_file()],
        neutral=summary,demo=demo_summary,joints=joints,sign_checks=signs,landmarks=landmarks,
        mass_ledger=dict(sum_kg=mass,cg_x_cad_mm=sum(x['mass']['value']*x['x_cad_mm'] for x in comp)/mass),
        checks=dict(all_parents_match=all(x['parent_matches'] for x in joints),
                    pivots_within_0p01mm=all(x['pivot_error_m']<1e-5 for x in joints),
                    axes_within_1e_minus5=all(x['axis_error']<1e-5 for x in joints),
                    local_rest_rotations_match=all(x['local_rest_rotation_error']<1e-5 for x in joints),
                    root_identity=len(summary['roots'])==1 and bool(np.allclose(summary['roots'][0]['matrix'],np.eye(4),atol=1e-7)),
                    signs=all(x['passed'] for x in signs),landmarks_within_0p01mm=all(x['error_m']<1e-5 for x in landmarks),
                    no_zero_area=all(x['zero_area_triangles']==0 for x in summary['meshes']),
                    finite=all(x['nonfinite_coordinates']==0 for x in summary['meshes']),
                    no_external_uris=not summary['external_uris'],neutral_no_animations=not summary['animations']))


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('package',type=Path);p.add_argument('output',type=Path);args=p.parse_args()
    report=audit(args.package);args.output.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report['checks'],indent=2))
    raise SystemExit(0 if all(report['checks'].values()) else 1)
