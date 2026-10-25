"""O.S. 905 radial engine mount (code 71905200) for the 61SF, a 1/4" plywood firewall and a short fuselage nose
section, with the engine bolted on as it goes into an airplane. Runs on the finished engine .blend:

    blender -b engine_se.blend -P build_mount.py -- --save engine_se_bancada.blend [--no-fuselage]

Sources (Oct 2026):
  * O.S. 71905200 "Radial Motor Mount Set" for 60FP / 61SF / 61FX / 91FX: cast aluminium beam mount,
    drilled and tapped for the engine; set = 4 M3.5 x 16 engine screws, 4 lock washers, 4 blind nuts
    (Amazon / Horizon / eBay listings, O.S. 95AX manual parts page).
  * Model Airplane News test of the O.S. 61SF/RF (P. Chinn): crankcase width 42 mm, mounting hole
    spacing 52 x 25 mm.
  * Photos of the mount (Amazon product shot, two eBay listings with a cutting mat and side/back views):
    measured through a camera solved from the 52 x 25 hole rectangle on the beam tops (see /home/claude/mount).

Engine frame (mm): +Y = rear, -Y = prop; +Z = cylinder; crank axis at z -4.4; lug seat (beam tops) z -6.7.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, "/home/claude/engine")
import build_engine as be  # noqa: E402
from build_engine import (MM, bm_box, bm_cyl, bm_prism, bm_revolve, boolean, frame_basis, make_obj,  # noqa: E402
                          text_bm, tmp_obj, _principled)

A = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
SAVE = A[A.index("--save") + 1] if "--save" in A else None
FUSELAGE = "--no-fuselage" not in A

# ----------------------------------------------------------------------------- dimensions (mm)
SEAT = be.LUG_SEAT_Z                       # -6.7: beam tops = lug undersides
# proportions: first from the beam-top homography of the product photo, then refined by a joint fit of that
# photo's camera + beam depth / flange size / flange depth / tip length to its silhouette (IoU 0.88 -> 0.95,
# lug holes held within 0.8 px); flange width from the back-face photo rectified on its four bolt holes
BEAM_H = 13.8                              # beam depth below the seat (silhouette fit 13.8)
BEAM_X = (21.9, 29.8)                      # inner / outer faces (7.9 wide, beam-top homography); 43.8 between
TIP_Y = be.LUG_HOLE_Y[0] - 40.1            # beam tips 40.1 mm ahead of the rear holes
PLATE_Y = (be.LUG_HOLE_Y[0] + 30.0, be.LUG_HOLE_Y[0] + 37.1)   # 44.5 .. 51.6: front face 30 mm behind rear holes
PLATE_HW, PLATE_HH = 29.8, 29.35           # 59.6 x 58.7 flange (flush with the beam sides), R7 corners
PLATE_ZC = SEAT                            # flange centre on the seat plane; firewall holes 44.8 square
FW_HOLE = 22.4
CENTER_HOLE = (24.0, SEAT + 3.9)           # through hole, 3.9 above the flange centre (back-face photo)
FIN_T, FIN_L, FIN_H = 2.2, 18.0, 17.7      # two triangular fins per beam, legs along the beam and up the flange
RIB_Z = (-19.0, -15.2)                     # rib under the centre hole (hole bottom at -14.8)
FIREWALL_T = 6.4                           # 1/4" birch ply
FW_Y = (PLATE_Y[1], PLATE_Y[1] + FIREWALL_T)
FW_RECT = (-45.0, 45.0, -55.0, 35.0)       # x0, x1, z0, z1
FUS_END = 140.0
FW_R = 9.0                                 # firewall corners = inner radius of the nose shell
FUEL_HOLE = (38.0, 20.5)
PRESS_HOLE = (-38.0, 26.0)


def col(name, parent=None):
    c = bpy.data.collections.get(name) or bpy.data.collections.new(name)
    if c.name not in [x.name for x in (parent or bpy.context.scene.collection).children]:
        (parent or bpy.context.scene.collection).children.link(c)
    return c


def earclip(ob):
    """Triangulate n-gons (> 4 sides) by ear clipping: boolean caps are concave n-gons whose default
    triangulation in exporters / checkers can fold a triangle over (same-plane flipped faces)."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    ng = [f for f in bm.faces if len(f.verts) > 4]
    if ng:
        bmesh.ops.triangulate(bm, faces=ng, quad_method="BEAUTY", ngon_method="EAR_CLIP")
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        bm.to_mesh(ob.data)
    bm.free()


def sharp(ob, deg=32.0):
    """Smooth shading with crisp edges above `deg` (no pillow shading on flat faces)."""
    ob.data.set_sharp_from_angle(angle=math.radians(deg))


# ----------------------------------------------------------------------------- materials
def mat_wood(name, light, dark, rough=0.62, coat=0.0, ply=None, grain_scale=60.0, film=False):
    """Birch ply / balsa: soft grain (stretched noise along Z) + ply stripes on the edges (object Y)."""
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    nt = m.node_tree
    for n in [n for n in nt.nodes if n.type not in ("BSDF_PRINCIPLED", "OUTPUT_MATERIAL")]:
        nt.nodes.remove(n)
    b = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    m.diffuse_color, m.roughness, m.metallic = (*light, 1), rough, 0.0
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = 0.0
    if coat:
        b.inputs["Coat Weight"].default_value = coat
        b.inputs["Coat Roughness"].default_value = 0.12
    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (grain_scale, grain_scale, grain_scale * 0.06)   # long fibres along Z
    nt.links.new(tc.outputs["Object"], mp.inputs["Vector"])
    nz = nt.nodes.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = 6.0
    nz.inputs["Detail"].default_value = 8.0
    nz.inputs["Distortion"].default_value = 1.2
    nt.links.new(mp.outputs["Vector"], nz.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position, ramp.color_ramp.elements[0].color = 0.35, (*dark, 1)
    ramp.color_ramp.elements[1].position, ramp.color_ramp.elements[1].color = 0.68, (*light, 1)
    nt.links.new(nz.outputs["Fac"], ramp.inputs["Fac"])
    out = ramp.outputs["Color"]
    if ply:   # alternate the veneer tone through the thickness (object Y in metres)
        y0, t = ply
        sep = nt.nodes.new("ShaderNodeSeparateXYZ")
        nt.links.new(tc.outputs["Object"], sep.inputs["Vector"])
        mth = nt.nodes.new("ShaderNodeMath")
        mth.operation = "SUBTRACT"
        nt.links.new(sep.outputs["Y"], mth.inputs[0])
        mth.inputs[1].default_value = y0 * MM
        div = nt.nodes.new("ShaderNodeMath")
        div.operation = "DIVIDE"
        nt.links.new(mth.outputs[0], div.inputs[0])
        div.inputs[1].default_value = t * MM
        flo = nt.nodes.new("ShaderNodeMath")
        flo.operation = "FLOOR"
        nt.links.new(div.outputs[0], flo.inputs[0])
        mod = nt.nodes.new("ShaderNodeMath")
        mod.operation = "FLOORED_MODULO"
        nt.links.new(flo.outputs[0], mod.inputs[0])
        mod.inputs[1].default_value = 2.0
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        nt.links.new(mod.outputs[0], mix.inputs[0])
        nt.links.new(out, mix.inputs[6])
        mix.inputs[7].default_value = (0.86, 0.80, 0.72, 1)
        out = mix.outputs[2]
    nt.links.new(out, b.inputs["Base Color"])
    bp = nt.nodes.new("ShaderNodeBump")
    bp.inputs["Strength"].default_value = 0.08
    bp.inputs["Distance"].default_value = 0.0001
    nt.links.new(nz.outputs["Fac"], bp.inputs["Height"])
    nt.links.new(bp.outputs["Normal"], b.inputs["Normal"])
    return m


def mat_tube(name, color, alpha=0.55):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Roughness"].default_value = 0.32
    b.inputs["Transmission Weight"].default_value = alpha
    b.inputs["IOR"].default_value = 1.41
    b.inputs["Subsurface Weight"].default_value = 0.15
    m.diffuse_color, m.roughness, m.metallic = (*color, 1), 0.32, 0.0
    return m


def materials():
    M = {k: bpy.data.materials[v] for k, v in (("black", "M_Black_Oxide"), ("steel", "M_Steel"))}
    M["mount_cast"] = _principled("M_Alu_Mount_Cast", (0.74, 0.735, 0.72), 1.0, 0.36, rough_var=0.05,
                                  noise_scale=240.0, bump=0.10, bump_scale=1700.0)
    M["mount_mach"] = _principled("M_Alu_Mount_Machined", (0.86, 0.86, 0.855), 1.0, 0.24, rough_var=0.05,
                                  noise_scale=900.0, aniso=0.45)
    M["zinc"] = _principled("M_Zinc_Plated", (0.78, 0.79, 0.80), 1.0, 0.30, rough_var=0.06, noise_scale=500.0)
    M["rubber"] = _principled("M_Rubber_Black", (0.025, 0.025, 0.027), 0.0, 0.62, rough_var=0.05)
    M["ply"] = mat_wood("M_Plywood_Firewall", (0.80, 0.66, 0.46), (0.66, 0.50, 0.32), rough=0.38, coat=0.55,
                        ply=(FW_Y[0], FIREWALL_T / 5.0), grain_scale=55.0)   # epoxy fuel-proofed birch, 5 plies
    M["balsa"] = mat_wood("M_Liteply_Balsa", (0.85, 0.74, 0.56), (0.74, 0.61, 0.43), rough=0.7, grain_scale=40.0)
    M["film"] = _principled("M_Covering_Film_Red", (0.30, 0.016, 0.018), 0.0, 0.22, rough_var=0.03, coat=0.5)
    M["fuel"] = mat_tube("M_Silicone_Fuel", (0.62, 0.40, 0.62), 0.55)     # purple-tint silicone fuel line
    M["press"] = mat_tube("M_Silicone_Pressure", (0.55, 0.70, 0.45), 0.55)
    return M


def text_outline_bm(body, size, depth, font="DejaVuSerif-Bold.ttf", fit_w=None, res=4):
    """Raised letters without folded cap triangles: glyph outlines from the font curve, caps by scanfill
    (mathutils tessellate_polygon, even-odd holes), straight walls; centred, z 0..depth (mm)."""
    from mathutils.geometry import tessellate_polygon
    fpath = os.path.join(be.FONT_DIR, font)
    cu = bpy.data.curves.new("TMP_TextO", "FONT")
    cu.body = body
    if os.path.exists(fpath):
        cu.font = bpy.data.fonts.load(fpath, check_existing=True)
    cu.size, cu.align_x, cu.align_y = size, "CENTER", "CENTER"
    cu.fill_mode = "NONE"
    cu.resolution_u = res
    ob = bpy.data.objects.new("TMP_TextO", cu)
    bpy.context.scene.collection.objects.link(ob)
    bpy.context.view_layer.update()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    bpy.data.objects.remove(ob)
    bpy.data.curves.remove(cu)
    # edges -> closed loops
    adj = {}
    for e in me.edges:
        a_, b_ = e.vertices
        adj.setdefault(a_, []).append(b_)
        adj.setdefault(b_, []).append(a_)
    co = [Vector((v.co.x, v.co.y)) for v in me.vertices]
    bpy.data.meshes.remove(me)
    seen, loops = set(), []
    for v0 in adj:
        if v0 in seen:
            continue
        loop, prev, cur = [v0], None, v0
        seen.add(v0)
        while True:
            nxt = [w for w in adj[cur] if w != prev and (w not in seen or (w == v0 and len(loop) > 2))]
            if not nxt:
                break
            if nxt[0] == v0:
                break
            prev, cur = cur, nxt[0]
            seen.add(cur)
            loop.append(cur)
        if len(loop) >= 3:
            pts = [co[i] for i in loop]
            clean = [pts[0]]
            for p in pts[1:]:
                if (p - clean[-1]).length > 0.06:
                    clean.append(p)
            changed = True
            while changed and len(clean) > 3:    # drop near-collinear points: no sliver triangles in the caps
                changed = False
                for k in range(len(clean)):
                    p0, p1, p2 = clean[k - 1], clean[k], clean[(k + 1) % len(clean)]
                    u, w = p1 - p0, p2 - p1
                    if u.length < 1e-6 or w.length < 1e-6 or abs(u.angle_signed(w)) < math.radians(9.0):
                        del clean[k]
                        changed = True
                        break
            if len(clean) >= 3:
                loops.append(clean)
    xs = [p.x for L in loops for p in L]
    ys = [p.y for L in loops for p in L]
    cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    sx = fit_w / (max(xs) - min(xs)) if fit_w and max(xs) - min(xs) > fit_w else 1.0
    loops = [[Vector(((p.x - cx) * sx, p.y - cy)) for p in L] for L in loops]

    def area(L):
        return sum(L[i].x * L[(i + 1) % len(L)].y - L[(i + 1) % len(L)].x * L[i].y for i in range(len(L))) / 2

    def inside(pt, L):
        c = False
        for i in range(len(L)):
            a_, b_ = L[i], L[(i + 1) % len(L)]
            if (a_.y > pt.y) != (b_.y > pt.y) and pt.x < (b_.x - a_.x) * (pt.y - a_.y) / (b_.y - a_.y) + a_.x:
                c = not c
        return c
    # group each hole with the smallest outer loop that contains it (one glyph per group)
    order = sorted(range(len(loops)), key=lambda i: -abs(area(loops[i])))
    depth_of = {}
    parent = {}
    for i in order:
        par = None
        for j in order:
            if j == i or abs(area(loops[j])) <= abs(area(loops[i])):
                continue
            if inside(loops[i][0], loops[j]) and (par is None or abs(area(loops[j])) < abs(area(loops[par]))):
                par = j
        parent[i] = par
    def lvl(i):
        n = 0
        while parent[i] is not None:
            i = parent[i]
            n += 1
        return n
    groups = {}
    for i in range(len(loops)):
        root = i if lvl(i) % 2 == 0 else parent[i]
        groups.setdefault(root, []).append(i)
    bm = bmesh.new()
    for root, idx in groups.items():
        polys = [loops[i] for i in idx]
        flat = [p for L in polys for p in L]
        tris = tessellate_polygon([[Vector((p.x, p.y, 0.0)) for p in L] for L in polys])
        bot = [bm.verts.new((p.x, p.y, 0.0)) for p in flat]
        top = [bm.verts.new((p.x, p.y, depth)) for p in flat]
        for a_, b_, c_ in tris:
            try:
                bm.faces.new((top[a_], top[b_], top[c_]))
                bm.faces.new((bot[c_], bot[b_], bot[a_]))
            except ValueError:
                pass
        k = 0
        for L in polys:
            n = len(L)
            for i in range(n):
                j = (i + 1) % n
                try:
                    bm.faces.new((bot[k + i], bot[k + j], top[k + j], top[k + i]))
                except ValueError:
                    pass
            k += n
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return bm


# ----------------------------------------------------------------------------- mount
def prism_yz(pts, x0, x1):
    return bm_prism(pts, x0, x1, lambda u, v, w: (w, u, v))


def prism_xz(pts, y0, y1):
    return bm_prism(pts, y0, y1, lambda u, v, w: (u, w, v))


def build_mount(C, M):
    y0, y1 = PLATE_Y
    zt, zb = PLATE_ZC + PLATE_HH, PLATE_ZC - PLATE_HH
    mount = make_obj("BANC_Bancada_OS905", bm_box((-PLATE_HW, y0, zb), (PLATE_HW, y1, zt), r=7.0, axis=(0, 1, 0),
                                                  segs=8), C, [M["mount_cast"], M["mount_mach"]])
    ops = []
    bot = SEAT - BEAM_H
    for s in (-1, 1):
        xi, xo = s * BEAM_X[0], s * BEAM_X[1]
        lo, hi = min(xi, xo), max(xi, xo)
        b = bm_box((lo, TIP_Y, bot), (hi, y0 + 1.0, SEAT), r=0.5, segs=2)        # beam (edges broken 0.5)
        ops.append(tmp_obj(b))
        tri = [(y0 - FIN_L, SEAT - 0.8), (y0 + 1.0, SEAT - 0.8), (y0 + 1.0, SEAT + FIN_H), (y0, SEAT + FIN_H),
               (y0 - FIN_L, SEAT)]
        for f0 in (BEAM_X[0], BEAM_X[1] - FIN_T):                                # inner and outer fin
            a_, b_ = sorted((s * f0, s * (f0 + FIN_T)))
            ops.append(tmp_obj(prism_yz(tri, a_, b_)))
    # stiffening rib between the beams just under the centre hole, 45 deg fillets down to the beam sides
    rz0, rz1 = RIB_Z
    ops.append(tmp_obj(bm_box((-BEAM_X[0] - 0.6, y0 - 5.5, rz0), (BEAM_X[0] + 0.6, y0 + 1.0, rz1), r=0.6, segs=2)))
    for s in (-1, 1):
        pts = [(s * (BEAM_X[0] + 0.6), rz0), (s * (BEAM_X[0] - 1.2), rz0), (s * (BEAM_X[0] + 0.6), bot + 0.4)]
        ops.append(tmp_obj(prism_xz(pts, y0 - 5.5, y0 + 1.0)))
        # 45 deg corner gussets where the beams' inner faces meet the flange (seen from above in the photo)
        g = [(s * (BEAM_X[0] + 0.6), y0 + 1.0), (s * (BEAM_X[0] + 0.6), y0 - 6.5), (s * (BEAM_X[0] - 6.5), y0 + 1.0)]
        ops.append(tmp_obj(bm_prism(g, bot, SEAT, lambda u, v, w: (u, v, w))))
    boolean(mount, ops, "UNION")
    cut = []
    d, zc = CENTER_HOLE
    r = d / 2
    cut.append(tmp_obj(bm_revolve([(0, y0 - 0.5), (r + 0.6, y0 - 0.5), (r + 0.6, y0), (r, y0 + 0.6), (r, y1 - 0.6),
                                   (r + 0.6, y1), (r + 0.6, y1 + 0.5), (0, y1 + 0.5)], 96, "Y", center=(0.0, zc))))
    for sx in (-1, 1):
        for sz in (-1, 1):
            x, z = sx * FW_HOLE, PLATE_ZC + sz * FW_HOLE
            cut.append(tmp_obj(bm_cyl(2.15, (x, y0 - 2, z), (x, y1 + 2, z), 32)))       # M4 clearance
            cut.append(tmp_obj(bm_cyl(4.4, (x, y0 - 3, z), (x, y0 + 0.3, z), 48)))      # spot face 0.3 deep
    cut.append(tmp_obj(bm_box((-19.5, y1 - 1.8, PLATE_ZC - 19.5), (19.5, y1 + 1.0, PLATE_ZC + 19.5), r=5.0,
                              axis=(0, 1, 0), segs=6)))                                # back pocket 39 x 39
    for sx in (-1, 1):
        for y in be.LUG_HOLE_Y:
            x = sx * be.LUG_HOLE_X
            cut.append(tmp_obj(bm_cyl(1.45, (x, y, SEAT - 12.5), (x, y, SEAT + 1.0), 24)))   # M3.5 tap drill 2.9
            cut.append(tmp_obj(bm_cyl(1.45, (x, y, SEAT - 0.45), (x, y, SEAT + 0.01), 24, r2=1.95)))  # chamfer
    boolean(mount, cut, "DIFFERENCE")
    # machined faces: beam tops / bottoms / tips, flange back face, tapped holes
    me = mount.data
    for p in me.polygons:
        c, n = p.center / MM, p.normal
        on_beam = BEAM_X[0] - 0.01 <= abs(c.x) <= BEAM_X[1] + 0.01 and c.y < y0 - FIN_L + 0.5
        mach = (on_beam and abs(n.z) > 0.95) or (on_beam and n.y < -0.95 and c.y < TIP_Y + 0.3) \
            or (n.y > 0.95 and c.y > y1 - 0.01) \
            or (abs(abs(c.x) - be.LUG_HOLE_X) < 2.2 and c.z < SEAT + 0.05 and c.z > SEAT - 13 and abs(n.z) < 0.9
                and on_beam)
        p.material_index = 1 if mach else 0
    # cast lettering on the top edge, read from the front: "O.S. 905"
    t = text_outline_bm("O.S. 905", 5.2, 0.4, font="DejaVuSerif-Bold.ttf", fit_w=27.0)
    bmesh.ops.transform(t, matrix=frame_basis((1, 0, 0), (0, 1, 0), (0.0, (y0 + y1) / 2 + 0.2, zt - 0.05)),
                        verts=t.verts[:])
    letters = make_obj("BANC_Letras_OS905", t, C, [M["mount_cast"]], smooth=False)
    return mount, letters


# ----------------------------------------------------------------------------- hardware
def screw_me(name, length, d, pitch, head_r, head_h, hexr, hexd, mat):
    s = make_obj(name, be.bm_screw(length, d=d, pitch=pitch, depth=0.54 * pitch, head_r=head_r, head_h=head_h,
                                   chamfer=0.4), bpy.context.scene.collection, [mat])
    boolean(s, [tmp_obj(bm_cyl(hexr, (0, 0, head_h - hexd), (0, 0, head_h + 0.2), 6))], "DIFFERENCE")
    for c in list(s.users_collection):
        c.objects.unlink(s)
    me = s.data
    bpy.data.objects.remove(s)
    me.name = "ME_" + name
    return me


def ring_bm(ri, ro, z0, z1, segs=40, gap_deg=0.0, rise=0.0):
    """Washer along Z; with gap_deg > 0 a split (helical) lock washer."""
    bm = bmesh.new()
    if gap_deg <= 0:
        return bm_revolve([(ri, z0), (ro, z0), (ro, z1), (ri, z1)], segs, "Z", closed=True)
    n = segs
    a0, a1 = math.radians(gap_deg / 2), 2 * math.pi - math.radians(gap_deg / 2)
    rings = []
    for i in range(n + 1):
        a = a0 + (a1 - a0) * i / n
        dz = rise * (i / n - 0.5)
        ca, sa = math.cos(a), math.sin(a)
        rings.append([bm.verts.new((r * ca, r * sa, z + dz)) for r, z in ((ri, z0), (ro, z0), (ro, z1), (ri, z1))])
    for A_, B_ in zip(rings, rings[1:]):
        for k in range(4):
            bm.faces.new((A_[k], A_[(k + 1) % 4], B_[(k + 1) % 4], B_[k]))
    bm.faces.new(rings[0][::-1])
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return bm


def place(me, name, pos, direction, C, spin=0.0):
    return be.place_screw(me, name, pos, direction, C, spin=spin)


def mesh_from_bm(name, bm, mat):
    o = make_obj(name, bm, bpy.context.scene.collection, [mat])
    for c in list(o.users_collection):
        c.objects.unlink(o)
    me = o.data
    bpy.data.objects.remove(o)
    me.name = "ME_" + name
    return me


def tnut_bm():
    """M4 blind (T) nut: 16 mm flange, 5.6 mm barrel, four prongs that bite into the firewall."""
    bm = bm_revolve([(1.65, 0.0), (8.0, 0.0), (8.0, 1.0), (2.8, 1.0), (2.8, 6.1), (2.5, 6.4), (1.65, 6.4)], 48, "Z",
                    closed=True)   # barrel ends 1 mm short of the firewall's front face
    out = make_obj("TMP_tnut", bm, bpy.context.scene.collection, [])
    pr = []
    for k in range(4):
        a = math.radians(45 + 90 * k)
        ca, sa = math.cos(a), math.sin(a)
        # prong: thin tapered tab (0.8 thick) standing on the flange, pointing +Z (into the wood)
        pts = [(6.2, 0.3), (7.9, 0.3), (7.15, 3.8)]
        b = bm_prism(pts, -0.4, 0.4, lambda u, v, w: (u * ca - w * sa, u * sa + w * ca, v))
        pr.append(tmp_obj(b))
    boolean(out, pr, "UNION")
    bm = bmesh.new()
    bm.from_mesh(out.data)
    bmesh.ops.scale(bm, vec=(1 / MM, 1 / MM, 1 / MM), verts=bm.verts[:])
    d = out.data
    bpy.data.objects.remove(out)
    bpy.data.meshes.remove(d)
    return bm


def build_hardware(C, M):
    out = []
    me35 = screw_me("Screw_M3_5x16", 16.0, 3.5, 0.6, 3.0, 3.5, 1.732, 2.0, M["black"])
    me_lw = mesh_from_bm("LockWasher_M3_5", ring_bm(1.85, 3.15, 0.0, 0.9, 48, gap_deg=9, rise=0.25), M["black"])
    lug_top = 0.3
    for i, (sx, y) in enumerate([(sx, y) for y in be.LUG_HOLE_Y for sx in (-1, 1)]):
        x = sx * be.LUG_HOLE_X
        w = bpy.data.objects.new(f"BANC_Arandela_Presion_{i + 1}", me_lw)
        w.matrix_world = be.T(x * MM, y * MM, (lug_top + 0.13) * MM) @ be.Rot("Z", 37 * i + 20)
        C.objects.link(w)
        out.append(w)
        out.append(place(me35, f"BANC_Tornillo_Motor_M3_5x16_{i + 1}", (x, y, lug_top + 1.17), (0, 0, 1), C, spin=29 * i))
    me4 = screw_me("Screw_M4x20", 20.0, 4.0, 0.7, 3.5, 4.0, 1.732, 2.4, M["black"])
    me_fw = mesh_from_bm("Washer_M4", bm_revolve([(2.2, 0.0), (4.5, 0.0), (4.5, 0.8), (2.2, 0.8)], 48, "Z", closed=True),
                         M["zinc"])
    me_tn = mesh_from_bm("TNut_M4", tnut_bm(), M["zinc"])
    y0 = PLATE_Y[0]
    for i, (sx, sz) in enumerate([(-1, 1), (1, 1), (-1, -1), (1, -1)]):
        x, z = sx * FW_HOLE, PLATE_ZC + sz * FW_HOLE
        w = place(me_fw, f"BANC_Arandela_M4_{i + 1}", (x, y0, z), (0, -1, 0), C)
        out.append(w)
        out.append(place(me4, f"BANC_Perno_Parallamas_M4x20_{i + 1}", (x, y0 - 0.8, z), (0, -1, 0), C, spin=41 * i))
        # blind nut from behind: flange on the back face, barrel and prongs into the ply (+Z local = -Y world)
        out.append(place(me_tn, f"BANC_Tuerca_Ciega_M4_{i + 1}", (x, FW_Y[1] + 1.0, z), (0, -1, 0), C, spin=15 * i))
    return out


# ----------------------------------------------------------------------------- firewall, fuselage, lines
def build_firewall(C, M):
    x0, x1, z0, z1 = FW_RECT
    fw = make_obj("BANC_Parallamas_Contrachapado", bm_box((x0, FW_Y[0], z0), (x1, FW_Y[1], z1), r=FW_R, axis=(0, 1, 0),
                                                          segs=10), C, [M["ply"]])
    cut = []
    for sx in (-1, 1):
        for sz in (-1, 1):
            x, z = sx * FW_HOLE, PLATE_ZC + sz * FW_HOLE
            cut.append(tmp_obj(bm_cyl(2.9, (x, FW_Y[0] - 1, z), (x, FW_Y[1] + 1, z), 32)))
    for (x, z) in (FUEL_HOLE, PRESS_HOLE):
        cut.append(tmp_obj(bm_cyl(4.0, (x, FW_Y[0] - 1, z), (x, FW_Y[1] + 1, z), 40)))
    boolean(fw, cut, "DIFFERENCE")
    gr = []
    for i, (x, z) in enumerate((FUEL_HOLE, PRESS_HOLE)):
        prof = [(2.9, FW_Y[0] - 1.0), (5.2, FW_Y[0] - 1.0), (5.4, FW_Y[0] - 0.6), (5.2, FW_Y[0]), (4.0, FW_Y[0]),
                (4.0, FW_Y[1]), (5.2, FW_Y[1]), (5.4, FW_Y[1] + 0.4), (5.2, FW_Y[1] + 1.0), (2.9, FW_Y[1] + 1.0)]
        gr.append(make_obj(f"BANC_Pasamuros_Goma_{i + 1}", bm_revolve(prof, 40, "Y", center=(x, z), closed=True), C,
                           [M["rubber"]]))
    return [fw] + gr


def build_fuselage(C, M):
    """Nose section cut 87 mm behind the firewall: 3 mm lite-ply shell with R12 rounded corners (balsa corner
    blocks sanded round), red covering film outside and over the front edge, bare wood inside and at the cut."""
    x0, x1, z0, z1 = FW_RECT
    t = 3.0
    y0 = FW_Y[0]
    shell = make_obj("BANC_Fuselaje_Morro", bm_box((x0 - t, y0, z0 - t), (x1 + t, FUS_END, z1 + t), r=FW_R + t,
                                                   axis=(0, 1, 0), segs=10), C, [M["balsa"], M["film"]])
    boolean(shell, [tmp_obj(bm_box((x0, y0 - 5, z0), (x1, FUS_END + 5, z1), r=FW_R, axis=(0, 1, 0), segs=10))],
            "DIFFERENCE")
    zc = (z0 + z1) / 2
    for p in shell.data.polygons:
        c, n = p.center / MM, p.normal
        outward = n.x * c.x + n.z * (c.z - zc) > 0 and abs(n.y) < 0.9
        p.material_index = 1 if (outward or n.y < -0.9) else 0
    sharp(shell, 40)
    return [shell]


def catmull(pts, n=10):
    P = [Vector(p) for p in pts]
    P = [P[0] * 2 - P[1]] + P + [P[-1] * 2 - P[-2]]
    out = []
    for i in range(1, len(P) - 2):
        p0, p1, p2, p3 = P[i - 1], P[i], P[i + 1], P[i + 2]
        for k in range(n):
            t = k / n
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                              + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    out.append(P[-2])
    return out


def tube_bm(path, ro, ri, segs=24):
    """Hollow tube (silicone line) along a polyline: parallel-transport frames, annular end faces."""
    bm = bmesh.new()
    T_ = [(path[min(i + 1, len(path) - 1)] - path[max(i - 1, 0)]).normalized() for i in range(len(path))]
    t0 = T_[0]
    ref = Vector((0, 0, 1)) if abs(t0.z) < 0.9 else Vector((1, 0, 0))
    nrm = (ref - t0 * ref.dot(t0)).normalized()
    outer, inner = [], []
    for i, (p, t) in enumerate(zip(path, T_)):
        if i:
            nrm = (nrm - t * nrm.dot(t)).normalized()
        b2 = t.cross(nrm)
        ringo, ringi = [], []
        for k in range(segs):
            a = 2 * math.pi * k / segs
            dv = math.cos(a) * nrm + math.sin(a) * b2
            ringo.append(bm.verts.new(p + ro * dv))
            ringi.append(bm.verts.new(p + ri * dv))
        outer.append(ringo)
        inner.append(ringi)
    for R in (outer, inner):
        for A_, B_ in zip(R, R[1:]):
            for k in range(segs):
                bm.faces.new((A_[k], A_[(k + 1) % segs], B_[(k + 1) % segs], B_[k]))
    for i in (0, -1):
        for k in range(segs):
            k2 = (k + 1) % segs
            bm.faces.new((outer[i][k], outer[i][k2], inner[i][k2], inner[i][k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return bm


def nipple(name):
    ob = bpy.data.objects[name]
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    me = ev.to_mesh()
    P = [ev.matrix_world @ v.co / MM for v in me.vertices]
    ev.to_mesh_clear()
    c = sum(P, Vector()) / len(P)
    # principal axis by power iteration on the covariance
    cov = [[sum((p[i] - c[i]) * (p[j] - c[j]) for p in P) for j in range(3)] for i in range(3)]
    v = Vector((1, 1, 1))
    for _ in range(60):
        v = Vector([sum(cov[i][j] * v[j] for j in range(3)) for i in range(3)]).normalized()
    ts = [(p - c).dot(v) for p in P]
    return c, v, min(ts), max(ts)


LINE_BEND = {}


def min_bend(path):
    r = 1e9
    for a_, b_, c_ in zip(path, path[1:], path[2:]):
        u, v = b_ - a_, c_ - b_
        if u.length < 1e-6 or v.length < 1e-6:
            continue
        ang = u.angle(v)
        if ang > 1e-6:
            r = min(r, (u.length + v.length) / 2 / ang)
    return round(r, 1)


def build_lines(C, M):
    out = []
    # fuel: carb nipple (axis -Y, tip at the rear) -> firewall grommet on the needle side -> tank
    c, v, tmin, tmax = nipple("CARB_Fuel_Nipple")
    tip = c + v * tmin if (c + v * tmin).y > (c + v * tmax).y else c + v * tmax   # barb end points to the rear
    start = tip - Vector((0, 1, 0)) * 4.7
    fx, fz = FUEL_HOLE
    pts = [start, tip + Vector((0, 3.0, 0)), (23.6, -2.0, 27.8), (28.0, 12.0, 25.8), (33.2, 28.0, 23.0), (37.0, 41.0, 21.2),
           (fx, FW_Y[0] - 5.0, fz), (fx, FW_Y[0] - 2.5, fz), (fx, FW_Y[0], fz), (fx, FW_Y[1] + 2, fz), (fx, FW_Y[1] + 10, fz), (fx - 2, FW_Y[1] + 24, fz - 3)]
    path = catmull(pts, 12)
    LINE_BEND["fuel"] = min_bend(path)
    out.append(make_obj("BANC_Linea_Combustible", tube_bm(path, 2.5, 1.78), C, [M["fuel"]]))
    # pressure: muffler nipple (tip up and inboard) -> over to the firewall on the exhaust side
    c, v, tmin, tmax = nipple("MUF_Pressure_Nipple")
    e1, e2 = c + v * tmin, c + v * tmax
    tip, base = (e1, e2) if e1.z > e2.z else (e2, e1)
    d = (tip - base).normalized()
    px, pz = PRESS_HOLE
    # waypoints optimised for the largest bend radius (3.8 mm) inside a corridor clear of the can and the head
    pts = [tip - d * 2.6, tip + d * 2.5, (-47.4, 28.9, 71.1), (-45.9, 33.5, 70.1), (-42.4, 37.1, 63.3),
           (-40.3, 37.8, 33.5), (px, 43.3, pz + 1.0), (px, FW_Y[0] - 4.0, pz), (px, FW_Y[0] - 2.0, pz), (px, FW_Y[0], pz),
           (px, FW_Y[1] + 2, pz), (px, FW_Y[1] + 10, pz), (px + 2, FW_Y[1] + 24, pz - 3)]
    path = catmull(pts, 12)
    LINE_BEND["pressure"] = min_bend(path)
    out.append(make_obj("BANC_Linea_Presion", tube_bm(path, 2.5, 1.5), C, [M["press"]]))
    return out


# ----------------------------------------------------------------------------- main
def main():
    M = materials()
    root_c = col("BANCADA_Avion")
    cm, ch, cf, cl = (col(n, root_c) for n in ("BANC_Bancada", "BANC_Herrajes", "BANC_Parallamas", "BANC_Lineas"))
    mount, letters = build_mount(cm, M)
    hw = build_hardware(ch, M)
    fw = build_firewall(cf, M)
    lines = build_lines(cl, M)
    fus = []
    if FUSELAGE:
        cfu = col("BANC_Fuselaje", root_c)
        fus = build_fuselage(cfu, M)
    for o in hw + fw + fus:
        if o.data.users == 1 or not o.data.get("_clip"):
            earclip(o)
            o.data["_clip"] = True
    for o in [mount, letters] + hw + fw:
        if o.data.users == 1 or not o.data.get("_sharp"):
            sharp(o, 40 if "Tornillo" in o.name or "Perno" in o.name else 32)
            o.data["_sharp"] = True
    root = bpy.data.objects.new("Bancada_Avion", None)
    root_c.objects.link(root)
    for o in [mount, letters] + hw + fw + lines + fus:
        mw = o.matrix_world.copy()
        o.parent = root
        o.matrix_world = mw
    # show the propeller and spinner as installed; drop the studio floor under the fuselage
    pc = bpy.data.collections.get("E61_Prop")
    if pc:
        pc.hide_viewport = pc.hide_render = False
        for vl in bpy.context.scene.view_layers:
            def walk(lc):
                if lc.collection == pc:
                    lc.exclude, lc.hide_viewport = False, False
                for ch_ in lc.children:
                    walk(ch_)
            walk(vl.layer_collection)
    bd = bpy.data.objects.get("LD_Backdrop")
    if bd:
        low = (FW_RECT[2] - 3.0 - 0.6) * MM if FUSELAGE else (PLATE_ZC - PLATE_HH - 0.6) * MM
        bd.location.z = low
    piv = bpy.data.objects.get("PIVOT_Base_Montaje")
    if piv:
        piv.location.z = (FW_RECT[2] - 3.0) * MM if FUSELAGE else (PLATE_ZC - PLATE_HH) * MM
    rep = {"ok": True, "mount_objects": len([mount, letters] + hw), "line_min_bend_mm": LINE_BEND, "firewall": len(fw), "lines": len(lines),
           "fuselage": len(fus), "plate_y": PLATE_Y, "beam_tip_y": TIP_Y, "plate_z": (PLATE_ZC - PLATE_HH, PLATE_ZC + PLATE_HH)}
    if SAVE:
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(SAVE))
        rep["saved"] = SAVE
    return rep


if __name__ == "__main__":
    import json
    try:
        r = main()
    except Exception as e:  # noqa: BLE001
        import traceback
        traceback.print_exc()
        r = {"ok": False, "error": f"{type(e).__name__}: {e}"}
    print("@@JSON@@" + json.dumps(r, default=str), flush=True)
