import bpy, bmesh, sys
from collections import Counter
ob = bpy.data.objects[sys.argv[sys.argv.index("--") + 1]]
bm = bmesh.new(); bm.from_mesh(ob.data)
nm = [e for e in bm.edges if len(e.link_faces) > 2]
print("NM", len(nm), "BOUNDARY", sum(1 for e in bm.edges if e.is_boundary))
for e in nm:
    c = (e.verts[0].co + e.verts[1].co) / 2 * 1000
    print("E", tuple(round(x, 3) for x in c), len(e.link_faces), round(e.calc_length() * 1000, 4), [len(f.verts) for f in e.link_faces], [round(f.calc_area()*1e6, 6) for f in e.link_faces])
directed = Counter((l.vert.index, l.link_loop_next.vert.index) for f in bm.faces for l in f.loops)
bad = [k for k, c in directed.items() if c > 1]
for a, b in bad[:8]:
    bm.verts.ensure_lookup_table()
    print("W", tuple(round(x * 1000, 3) for x in bm.verts[a].co))
