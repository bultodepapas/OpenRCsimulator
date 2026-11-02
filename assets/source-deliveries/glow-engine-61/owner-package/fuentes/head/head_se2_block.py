HEAD_SE2 = dict(  # SE heat-sink head, v2: shapes from the owner's photos E / Ac / D and a removed FSR head (eBay)
    fin_wb=2.10, fin_wc=0.92,          # fin width at the root / at the crest: tapered, full-round crest
    fin_end_ang=76.0, fin_end_in=0.15,  # steep end faces, ending just inside the rim round (slots run out on it)
    end_round=0.9, root_r=0.32,        # rounded top corner of the end faces, fillet at the fin roots
    rim_round=0.95,                    # convex round on the band's top outer edge: the slots run out through it
    cres_ri=17.0, cres_ang=57.0, cres_drop=0.85, cres_out_r=1.7, cres_in_ang=74.0, cres_end_ang=72.0,
    well_r=6.75, boss_pad=0.55,        # glow-plug well (flat floor), plateaus under the well and the screw pockets
    pocket_r=3.25, nx=440, ny=231,     # screw pockets (6.5 mm), heightfield resolution
)


def _smin(a, b, k):
    import numpy as np
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return b + (a - b) * h - k * h * (1.0 - h)


def _smax(a, b, k):
    return -_smin(-a, -b, k)


def head_se_height(xg, yg, P, Q, z0, zb, zt):
    """Top surface of the SE head as a height field z = F(x, y) (numpy arrays, mm): band top with its rounded rim,
    tapered round-crested fins with steep rounded ends, the two solid crescents on +-X with a rounded outer edge,
    and flat plateaus under the plug well and the six screw pockets (cut afterwards)."""
    import numpy as np
    R = P["r"]
    H = zt - zb
    r = np.hypot(xg, yg)
    re = Q["rim_round"]
    floor = np.where(r <= R - re, zb, zb - re + np.sqrt(np.clip(re * re - (r - (R - re)) ** 2, 0.0, None)))
    # fins
    rho = Q["fin_wc"] / 2
    hb = Q["fin_wb"] / 2
    tan_e = math.tan(math.radians(Q["fin_end_ang"]))
    fins = np.full(xg.shape, -5.0)
    for k in range(-P["n_half"], P["n_half"]):
        xk = (k + 0.5) * P["pitch"]
        d = np.abs(xg - xk)
        cap = (H - rho) + np.sqrt(np.clip(rho * rho - d * d, 0.0, None))
        flank = (H - rho) * (hb - d) / (hb - rho)
        hc = np.where(d <= rho, cap, flank)
        y_end = math.sqrt(max((R - re - Q["fin_end_in"]) ** 2 - xk * xk, 1.0))
        e = (y_end - np.abs(yg)) * tan_e
        fins = np.maximum(fins, _smin(hc, e, Q["end_round"]))
    # crescents: the band wall carried up on +-X, rounded outer edge, steep inner wall, steep rounded ends
    Hc = H - Q["cres_drop"]
    ro = Q["cres_out_r"]
    top = np.where(r > R - ro, Hc - ro + np.sqrt(np.clip(ro * ro - (r - (R - ro)) ** 2, 0.0, None)), Hc)
    inner = (r - Q["cres_ri"]) * math.tan(math.radians(Q["cres_in_ang"]))
    cres = np.full(xg.shape, -5.0)
    for s in (1.0, -1.0):
        phi = np.abs(np.arctan2(yg, s * xg))
        ends = (math.radians(Q["cres_ang"]) - phi) * r * math.tan(math.radians(Q["cres_end_ang"]))
        cres = np.maximum(cres, _smin(_smin(top, inner, 0.9), ends, 1.1))
    h = _smax(fins, cres, 0.35)
    F = _smax(floor, zb + h, Q["root_r"])
    # plateaus: plug-well floor and screw-pocket floors (flat, solid under the gaps)
    wf = P["well_floor"]
    rw = Q["well_r"] + Q["boss_pad"]
    F = _smax(F, np.clip(wf - (r - rw) * 3.0, zb - 3.0, wf), 0.25)
    for a in P["allen_angles"]:
        cx, cy = P["allen_r"] * math.cos(math.radians(a)), P["allen_r"] * math.sin(math.radians(a))
        dp = np.hypot(xg - cx, yg - cy)
        F = _smax(F, np.clip(P["allen_seat"] - (dp - Q["pocket_r"] - Q["boss_pad"]) * 3.0, zb - 3.0, P["allen_seat"]),
                  0.25)
    return F


def heightfield_solid(F, R, z0, nx, ny, chamfer=0.45):
    """Closed solid of revolution-sized disk: top = height field over the disk of radius R (columns in x,
    rows y = t * sqrt(R^2 - x^2)), vertical band wall, chamfered bottom edge, flat bottom at z0."""
    import numpy as np
    xs = np.linspace(-R + 0.015, R - 0.015, nx)
    ts = np.linspace(-1.0, 1.0, ny)
    Y = np.sqrt(np.clip(R * R - xs * xs, 0.0, None))
    xg = np.repeat(xs[:, None], ny, axis=1)
    yg = ts[None, :] * Y[:, None]
    zg = F(xg, yg)
    bm = bmesh.new()
    V = [[bm.verts.new((float(xg[i, j]), float(yg[i, j]), float(zg[i, j]))) for j in range(ny)] for i in range(nx)]
    for i in range(nx - 1):
        for j in range(ny - 1):
            bm.faces.new((V[i][j], V[i + 1][j], V[i + 1][j + 1], V[i][j + 1]))
    loop = [V[i][0] for i in range(nx)] + [V[nx - 1][j] for j in range(1, ny)] + \
           [V[i][ny - 1] for i in range(nx - 2, -1, -1)] + [V[0][j] for j in range(ny - 2, 0, -1)]
    ring1, ring2 = [], []
    for v in loop:
        x, y = v.co.x, v.co.y
        rr = math.hypot(x, y)
        ring1.append(bm.verts.new((x, y, z0 + chamfer)))
        f = (rr - chamfer) / rr
        ring2.append(bm.verts.new((x * f, y * f, z0)))
    n = len(loop)
    for k in range(n):
        k2 = (k + 1) % n
        bm.faces.new((loop[k2], loop[k], ring1[k], ring1[k2]))
        bm.faces.new((ring1[k2], ring1[k], ring2[k], ring2[k2]))
    bot = bm.faces.new(ring2)
    bmesh.ops.triangulate(bm, faces=[bot], quad_method="BEAUTY", ngon_method="EAR_CLIP")
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return bm


def glow_plug_os8(col, M, wf):
    """O.S. No.8 short-body plug: copper washer, 8 mm hex body (double-chamfered), dark insulator collar, centre
    terminal with a grooved knob and a rounded tip (photos E / Ac; AMain / O.S. product photos)."""
    out = [make_obj("ENG_GlowPlug_Washer", bm_revolve([(3.25, wf), (4.3, wf), (4.4, wf + 0.1), (4.4, wf + 0.5),
                                                       (4.3, wf + 0.6), (3.25, wf + 0.6)], 48, "Z", closed=True),
                    col, [M["copper"]])]
    h0, h1 = wf + 0.6, wf + 4.0
    hexb = make_obj("ENG_GlowPlug_Body", bm_cyl(8.0 / math.sqrt(3.0), (0, 0, h0), (0, 0, h1), 6), col, [M["black"]])
    boolean(hexb, [tmp_obj(bm_revolve([(0, h0 - 0.1), (3.75, h0 - 0.1), (4.75, h0 + 0.55), (4.75, h1 - 0.55),
                                       (3.75, h1 + 0.1), (0, h1 + 0.1)], 64, "Z"))], "INTERSECT")
    boolean(hexb, [tmp_obj(bm_revolve([(0, h1 - 0.2), (2.95, h1 - 0.2), (3.05, h1 - 0.05), (3.05, h1 + 0.75),
                                       (2.8, h1 + 1.05), (0.9, h1 + 1.15), (0, h1 + 1.15)], 48, "Z"))], "UNION")
    out.append(hexb)
    z = h1 + 1.1
    prof = [(0, z - 0.4), (0.78, z - 0.4), (0.78, z + 2.6), (1.02, z + 2.75), (1.05, z + 3.05), (0.86, z + 3.2),
            (1.06, z + 3.38), (1.06, z + 3.7), (0.86, z + 3.85), (1.04, z + 4.02), (1.0, z + 4.35),
            (0.75, z + 4.75), (0.4, z + 4.95), (0, z + 5.0)]
    out.append(make_obj("ENG_GlowPlug_Pin", bm_revolve(prof, 32, "Z"), col, [M["nickel"]]))
    return out


def knurled_screw_mesh(M, length):
    """Socket head cap screw with the knurled head of the O.S. head screws (photo E): 36 shallow grooves."""
    key = ("knurl", round(float(length), 2))
    me = SCREW_MESHES.get(key)
    if me is not None and me.name in bpy.data.meshes:
        return me
    s = make_obj("ENG_Screw_M3K", bm_screw(length), bpy.context.scene.collection, [M["black"]])
    cuts = [tmp_obj(bm_cyl(1.443, (0, 0, 1.4), (0, 0, 3.6), 6))]
    for i in range(36):
        a = 2 * math.pi * i / 36
        g = bm_box((-0.19, -0.085, 0.3), (0.19, 0.085, 2.55))
        bmesh.ops.translate(g, verts=g.verts[:], vec=(2.81, 0, 0))
        bmesh.ops.rotate(g, verts=g.verts[:], cent=(0, 0, 0), matrix=Rot("Z", math.degrees(a)).to_3x3())
        cuts.append(tmp_obj(g))
    boolean(s, cuts, "DIFFERENCE")
    for c in list(s.users_collection):
        c.objects.unlink(s)
    me = s.data
    bpy.data.objects.remove(s)
    me.name = f"ME_Screw_M3x{length:g}_knurl"
    SCREW_MESHES[key] = me
    return me


def build_head_se(col, M, V):
    """Heat-sink head of the SE engine (v2): one height-field top (tapered fins with round crests and steep rounded
    ends, slots running out through the rounded rim, solid crescents on +-X, flat plateaus) on the band, then the
    plug well, six screw pockets and clearance holes cut, combustion side from head_internals; knurled M3 socket
    screws and an O.S. No.8 plug."""
    import numpy as np  # noqa: F401
    P = dict(HEAD_SE_P0, **FIT.get("head_se", {}))
    Q = dict(HEAD_SE2, **FIT.get("head_se2", {}))
    r, z0 = P["r"], fin_top(V) + 0.6
    zt = z0 + V["head_h"]
    zb = z0 + P["band_h"]
    mat = M["gold"] if V["head"] == "gold" else M["silver"]
    bm = heightfield_solid(lambda xg, yg: head_se_height(xg, yg, P, Q, z0, zb, zt), r, z0, Q["nx"], Q["ny"])
    bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(0.6), verts=bm.verts[:], edges=bm.edges[:])
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4], quad_method="BEAUTY",
                          ngon_method="EAR_CLIP")
    head = make_obj("ENG_Head", bm, col, [mat])
    wf = P["well_floor"]
    cuts = [tmp_obj(bm_cyl(Q["well_r"], (0, 0, wf), (0, 0, zt + 3), 96))]
    for a in P["allen_angles"]:
        th = math.radians(a)
        c = (P["allen_r"] * math.cos(th), P["allen_r"] * math.sin(th))
        cuts.append(tmp_obj(bm_cyl(Q["pocket_r"], (c[0], c[1], P["allen_seat"]), (c[0], c[1], zt + 3), 48)))
    boolean(head, cuts, "DIFFERENCE")
    K = mech()
    out = [head] + head_internals(head, col, M, V, K, plug_top=wf, seat=P["allen_seat"])
    me = knurled_screw_mesh(M, K["head_screw_len"])
    for i, a in enumerate(P["allen_angles"]):
        th = math.radians(a)
        ob = bpy.data.objects.new(f"ENG_Head_Screw_{i + 1}", me)
        ob.matrix_world = T(P["allen_r"] * math.cos(th) * MM, P["allen_r"] * math.sin(th) * MM,
                            P["allen_seat"] * MM) @ Rot("Z", 17 * i)
        col.objects.link(ob)
        out.append(ob)
    out += glow_plug_os8(col, M, wf)
    head.data.set_sharp_from_angle(angle=math.radians(40))
    return out


