import bpy, bmesh, sys
from collections import Counter
ob = bpy.data.objects[sys.argv[sys.argv.index("--") + 1]]
bm = bmesh.new(); bm.from_mesh(ob.data)
bad = [f for f in bm.faces if f.calc_area() < 1e-10]
print("DEG", len(bad), "ngons", sum(1 for f in bm.faces if len(f.verts) > 4))
c = Counter()
for f in bad:
    p = f.calc_center_median() * 1000
    r = (p.x ** 2 + p.y ** 2) ** 0.5
    es = sorted(e.calc_length() * 1000 for e in f.edges)
    c[(len(f.verts), round(p.z, 1), round(r, 0))] += 1
for k, v in c.most_common(30): print("D", k, v)
for f in bad[:6]:
    print("EX", len(f.verts), [tuple(round(x * 1000, 4) for x in v.co) for v in f.verts])
