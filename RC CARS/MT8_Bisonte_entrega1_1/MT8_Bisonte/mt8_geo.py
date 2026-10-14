"""Primitivas de malla (bmesh) construidas en el marco de Godot y convertidas a Blender.

Godot (x, y, z)  ->  Blender (x, -z, y)    [rotacion propia, sin espejo]
El exportador glTF con +Y arriba deshace exactamente este cambio, asi que en Godot
los vertices y transformaciones llegan tal y como se escriben aqui.
"""
import math
import bpy  # noqa: F401  (bmesh necesita bpy cargado)
import bmesh
from mathutils import Matrix, Vector

C = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
CI = C.inverted()


def g2b(v):
    return Vector((v[0], -v[2], v[1]))


def mat_g2b(mg):
    """Transformacion expresada en Godot -> la misma transformacion en coordenadas Blender."""
    return C @ mg @ CI


class Builder:
    """Acumula geometria en un bmesh, en coordenadas locales de Godot, con indice de material."""

    def __init__(self):
        self.bm = bmesh.new()
        self.mats = []

    def mat(self, name):
        if name not in self.mats:
            self.mats.append(name)
        return self.mats.index(name)

    # -- helpers
    def _merge(self, other_bm, matrix, mat):
        """Copia otro bmesh (coords Godot) aplicando matrix (Godot)."""
        mi = self.mat(mat)
        vmap = {}
        for v in other_bm.verts:
            nv = self.bm.verts.new(matrix @ v.co)
            vmap[v] = nv
        for f in other_bm.faces:
            try:
                nf = self.bm.faces.new([vmap[v] for v in f.verts])
                nf.material_index = mi
                nf.smooth = f.smooth
            except ValueError:
                pass
        for e in other_bm.edges:
            if not e.smooth:
                ne = self.bm.edges.get([vmap[e.verts[0]], vmap[e.verts[1]]])
                if ne:
                    ne.smooth = False

    def box(self, center, size, mat, bevel=0.0, segs=2, rot=None):
        b = bmesh.new()
        bmesh.ops.create_cube(b, size=1.0)
        bmesh.ops.scale(b, vec=Vector(size), verts=b.verts)
        if bevel > 0:
            bmesh.ops.bevel(b, geom=list(b.edges), offset=bevel, segments=segs, profile=0.5, affect='EDGES')
        m = Matrix.Translation(Vector(center))
        if rot is not None:
            m = m @ rot
        smooth_by_angle(b, 40)
        self._merge(b, m, mat)
        b.free()

    def cyl(self, p0, p1, r, mat, segs=16, r2=None, caps=True, bevel=0.0):
        p0, p1 = Vector(p0), Vector(p1)
        d = p1 - p0
        L = d.length
        b = bmesh.new()
        bmesh.ops.create_cone(b, cap_ends=caps, cap_tris=False, segments=segs,
                              radius1=r, radius2=(r if r2 is None else r2), depth=L)
        if bevel > 0 and caps:
            rim = [e for e in b.edges if len(e.link_faces) == 2 and
                   abs(e.link_faces[0].normal.dot(e.link_faces[1].normal)) < 0.5]
            bmesh.ops.bevel(b, geom=rim, offset=bevel, segments=2, profile=0.5, affect='EDGES')
        q = Vector((0, 0, 1)).rotation_difference(d.normalized())
        m = Matrix.Translation((p0 + p1) / 2) @ q.to_matrix().to_4x4()
        smooth_by_angle(b, 50)
        self._merge(b, m, mat)
        b.free()

    def sphere(self, c, r, mat, segs=12):
        b = bmesh.new()
        bmesh.ops.create_uvsphere(b, u_segments=segs, v_segments=max(6, segs // 2), radius=r)
        for f in b.faces:
            f.smooth = True
        self._merge(b, Matrix.Translation(Vector(c)), mat)
        b.free()

    def lathe_x(self, profile, mat, segs=48, x_sign=1.0, center=(0, 0, 0), angle=2 * math.pi, start=0.0,
                smooth_deg=40):
        """Revoluciona un perfil [(x_axial, r)] alrededor del eje X."""
        b = bmesh.new()
        vs = [b.verts.new((x_sign * x, 0.0, r)) for x, r in profile]
        es = [b.edges.new((vs[i], vs[i + 1])) for i in range(len(vs) - 1)]
        full = abs(angle - 2 * math.pi) < 1e-6
        if start:
            bmesh.ops.rotate(b, verts=vs, cent=(0, 0, 0), matrix=Matrix.Rotation(start, 3, 'X'))
        res = bmesh.ops.spin(b, geom=vs + es, cent=(0, 0, 0), axis=(1, 0, 0), angle=angle,
                             steps=segs, use_duplicate=False)
        bmesh.ops.remove_doubles(b, verts=b.verts, dist=1e-6)
        if x_sign < 0:
            bmesh.ops.reverse_faces(b, faces=b.faces)
        bmesh.ops.recalc_face_normals(b, faces=b.faces)
        smooth_by_angle(b, smooth_deg)
        self._merge(b, Matrix.Translation(Vector(center)), mat)
        b.free()

    def prism(self, poly_xz, y0, y1, mat, bevel=0.0, matrix=None):
        """Poligono en el plano XZ extruido entre y0 e y1."""
        b = bmesh.new()
        bot = [b.verts.new((x, y0, z)) for x, z in poly_xz]
        top = [b.verts.new((x, y1, z)) for x, z in poly_xz]
        n = len(poly_xz)
        b.faces.new(bot[::-1])
        b.faces.new(top)
        for i in range(n):
            j = (i + 1) % n
            b.faces.new((bot[i], bot[j], top[j], top[i]))
        bmesh.ops.recalc_face_normals(b, faces=b.faces)
        if bevel > 0:
            bmesh.ops.bevel(b, geom=list(b.edges), offset=bevel, segments=2, profile=0.5, affect='EDGES',
                            clamp_overlap=True)
        smooth_by_angle(b, 40)
        self._merge(b, matrix or Matrix.Identity(4), mat)
        b.free()

    def side_extrude(self, poly_zy, x0, x1, mat, bevel=0.0):
        """Poligono en el plano ZY (perfil lateral) extruido entre x0 y x1."""
        b = bmesh.new()
        a = [b.verts.new((x0, y, z)) for z, y in poly_zy]
        c = [b.verts.new((x1, y, z)) for z, y in poly_zy]
        n = len(poly_zy)
        b.faces.new(a)
        b.faces.new(c[::-1])
        for i in range(n):
            j = (i + 1) % n
            b.faces.new((a[i], c[i], c[j], a[j]))
        bmesh.ops.recalc_face_normals(b, faces=b.faces)
        if bevel > 0:
            bmesh.ops.bevel(b, geom=list(b.edges), offset=bevel, segments=3, profile=0.5, affect='EDGES',
                            clamp_overlap=True)
        smooth_by_angle(b, 35)
        self._merge(b, Matrix.Identity(4), mat)
        b.free()

    def helix(self, p_top, axis_dir, length, radius, wire, turns, mat, segs_per_turn=16, wire_segs=6):
        """Muelle helicoidal desde p_top a lo largo de axis_dir (unitario)."""
        b = bmesh.new()
        n = int(turns * segs_per_turn)
        rings = []
        for i in range(n + 1):
            t = i / n
            a = 2 * math.pi * turns * t
            c = Vector((radius * math.cos(a), -length * t, radius * math.sin(a)))
            tang = Vector((-radius * math.sin(a) * 2 * math.pi * turns, -length, radius * math.cos(a) * 2 * math.pi * turns)).normalized()
            nrm = Vector((math.cos(a), 0, math.sin(a)))
            bn = tang.cross(nrm).normalized()
            nrm = bn.cross(tang).normalized()
            ring = []
            for k in range(wire_segs):
                ph = 2 * math.pi * k / wire_segs
                ring.append(b.verts.new(c + wire * (math.cos(ph) * nrm + math.sin(ph) * bn)))
            rings.append(ring)
        for i in range(n):
            for k in range(wire_segs):
                k2 = (k + 1) % wire_segs
                f = b.faces.new((rings[i][k], rings[i][k2], rings[i + 1][k2], rings[i + 1][k]))
                f.smooth = True
        b.faces.new(rings[0][::-1])
        b.faces.new(rings[-1])
        bmesh.ops.recalc_face_normals(b, faces=b.faces)
        q = Vector((0, -1, 0)).rotation_difference(Vector(axis_dir).normalized())
        m = Matrix.Translation(Vector(p_top)) @ q.to_matrix().to_4x4()
        self._merge(b, m, mat)
        b.free()

    def add_bm(self, other, mat, matrix=None):
        self._merge(other, matrix or Matrix.Identity(4), mat)

    def to_mesh(self, name, materials, mirror_x=False):
        """Crea la malla Blender (aplica conversion Godot->Blender). mirror_x refleja los datos, no la escala."""
        import bpy
        bm = self.bm
        if mirror_x:
            bmesh.ops.scale(bm, vec=Vector((-1, 1, 1)), verts=bm.verts)
            bmesh.ops.reverse_faces(bm, faces=bm.faces)
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
        bmesh.ops.transform(bm, matrix=C, verts=bm.verts)
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        for mn in self.mats:
            me.materials.append(materials[mn])
        me.update()
        return me


def smooth_by_angle(b, deg):
    thr = math.radians(deg)
    b.normal_update()
    for f in b.faces:
        f.smooth = True
    for e in b.edges:
        if len(e.link_faces) == 2:
            if e.calc_face_angle(0.0) > thr:
                e.smooth = False
        else:
            e.smooth = False
