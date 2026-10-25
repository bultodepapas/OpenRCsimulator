"""Pure-python prop geometry: APC PE0 tables, UIUC tables / silhouettes, Clark-Y sections (inches / mm)."""
import math
import os
import re
import sys

sys.path.insert(0, "/home/claude/props/ref")
import planform_uiuc as PU  # noqa: E402

IN = 25.4
PE0_DIR = "/home/claude/props/ext/apc_props/geometry"
REF = "/home/claude/props/ref"

# Clark Y (NACA TR / Abbott & von Doenhoff ordinates, % chord): x, upper, lower (flat bottom from 30 %)
CLARKY = [(0, 3.50, 3.50), (1.25, 5.45, 1.93), (2.5, 6.50, 1.47), (5, 7.90, 0.93), (7.5, 8.85, 0.63),
          (10, 9.60, 0.42), (15, 10.68, 0.15), (20, 11.36, 0.03), (30, 11.70, 0.0), (40, 11.40, 0.0),
          (50, 10.52, 0.0), (60, 9.15, 0.0), (70, 7.35, 0.0), (80, 5.22, 0.0), (90, 2.80, 0.0),
          (95, 1.49, 0.0), (100, 0.12, 0.0)]
CLARKY_TC = 0.117


def spline(xs, ys):
    """Natural cubic spline -> callable."""
    n = len(xs)
    h = [xs[i + 1] - xs[i] for i in range(n - 1)]
    al = [0.0] + [3 / h[i] * (ys[i + 1] - ys[i]) - 3 / h[i - 1] * (ys[i] - ys[i - 1]) for i in range(1, n - 1)]
    l, mu, z = [1.0] + [0.0] * (n - 1), [0.0] * n, [0.0] * n
    for i in range(1, n - 1):
        l[i] = 2 * (xs[i + 1] - xs[i - 1]) - h[i - 1] * mu[i - 1]
        mu[i] = h[i] / l[i]
        z[i] = (al[i] - h[i - 1] * z[i - 1]) / l[i]
    l[-1] = 1.0
    c, b, d = [0.0] * n, [0.0] * (n - 1), [0.0] * (n - 1)
    for j in range(n - 2, -1, -1):
        c[j] = z[j] - mu[j] * c[j + 1]
        b[j] = (ys[j + 1] - ys[j]) / h[j] - h[j] * (c[j + 1] + 2 * c[j]) / 3
        d[j] = (c[j + 1] - c[j]) / (3 * h[j])

    def f(x):
        x = min(max(x, xs[0]), xs[-1])
        i = max(0, min(n - 2, next((k for k in range(n - 1) if x <= xs[k + 1]), n - 2)))
        t = x - xs[i]
        return ys[i] + b[i] * t + c[i] * t * t + d[i] * t ** 3
    return f


# upper / lower as functions of sqrt(x): smooth through the round leading edge
_t = [math.sqrt(p[0] / 100) for p in CLARKY]
_YU = spline(_t, [p[1] / 100 for p in CLARKY])
_lo = [p for p in CLARKY if p[0] <= 30]
_YL = spline([math.sqrt(p[0] / 100) for p in _lo], [p[2] / 100 for p in _lo])


def clarky(x):
    """(upper, lower) ordinates of the 11.7 % Clark Y at chord fraction x."""
    t = math.sqrt(max(0.0, min(1.0, x)))
    return _YU(t), (max(0.0, _YL(t)) if x < 0.3 else 0.0)


def section_loop(n=22, tc=CLARKY_TC, te=0.004, camber=1.0, flat=True):
    """Closed loop (x, y) in chord units: TE -> upper -> LE -> lower -> TE (TE point shared once).
    tc = thickness ratio (Clark Y ordinates scaled), te = trailing edge thickness / chord,
    camber < 1 thins the lower bulge (flatter bottom)."""
    k = tc / CLARKY_TC
    xs = [(1 - math.cos(math.pi * i / n)) / 2 for i in range(n + 1)]   # LE (0) .. TE (1)
    up = [(x, clarky(x)[0] * k + te * x) for x in xs]
    lo = [(x, clarky(x)[1] * k * camber) for x in xs]
    return up[::-1] + lo[1:-1]            # TE(up) .. LE .. lower .. (TE lower at index omitted -> TE edge)


def section_props(loop):
    """Area, centroid of a closed polygon (x, y)."""
    a = cx = cy = 0.0
    for (x0, y0), (x1, y1) in zip(loop, loop[1:] + loop[:1]):
        cr = x0 * y1 - x1 * y0
        a += cr
        cx += (x0 + x1) * cr
        cy += (y0 + y1) * cr
    a /= 2
    return abs(a), cx / (6 * a), cy / (6 * a)


def read_pe0(name):
    """APC PE0 geometry table -> dict(stations=[...], radius, hubtra, blades, weight_g, airfoil)."""
    txt = open(os.path.join(PE0_DIR, f"{name}-PERF.PE0"), encoding="latin1").read()
    rows = []
    for line in txt.splitlines():
        p = line.split()
        if len(p) == 13 and all(re.match(r"^-?\d+\.\d+$", v) for v in p):
            v = list(map(float, p))
            rows.append(dict(r=v[0], c=v[1], p_q=v[2], p_lete=v[3], p_prather=v[4], sweep=v[5], tc=v[6],
                             twist=v[7], tmax=v[8], area=v[9], zhigh=v[10], cgy=v[11], cgz=v[12]))
    g = lambda k: float(re.search(k.replace(" ", r"\s*") + r"\s*[:=]?\s*(-?[\d.]+)", txt).group(1))
    return dict(rows=rows, R=g("RADIUS"), hubtra=g("HUBTRA"), blades=int(g("BLADES")),
                weight_g=g(r"TOTAL WEIGHT \(Kg\) =") * 1000, volume_in3=g(r"TOTAL VOLUME \(IN\*\*3\) ="),
                sg=g(r"DENSITY \(SPECIFIC GRAVITY, INPUT FILE\) ="), af=re.findall(r"AIRFOIL\d: [^\r\n]*", txt))


def read_uiuc(name):
    rows = []
    for line in open(os.path.join(REF, f"{name}_geom.txt")):
        p = line.split()
        if len(p) == 3 and re.match(r"^[\d.]+$", p[0]):
            rows.append(tuple(map(float, p)))
    return rows


def interp(xs, ys, x):
    if x <= xs[0]:
        return ys[0]
    for i in range(len(xs) - 1):
        if x <= xs[i + 1]:
            t = (x - xs[i]) / (xs[i + 1] - xs[i])
            return ys[i] + t * (ys[i + 1] - ys[i])
    return ys[-1]


if __name__ == "__main__":
    for nm in ("11x7", "12x6"):
        d = read_pe0(nm)
        print(nm, d["R"], d["hubtra"], d["weight_g"], d["volume_in3"], d["sg"], d["af"])
        r0 = d["rows"][0]
        loop = section_loop(tc=r0["tc"])
        A, cx, cy = section_props(loop)
        b = math.atan(r0["p_q"] / (2 * math.pi * r0["r"]))
        c = r0["c"]
        # axial (forward) coordinate of loop points with O at 0: w = -x c sin b + y c cos b; in-plane u = x c cos..
        ws = [-x * c * math.sin(b) + y * c * math.cos(b) for x, y in loop]
        wc = -cx * c * math.sin(b) + cy * c * math.cos(b)
        off = r0["cgz"] - wc
        print(" root beta %.1f  axial span %.3f .. %.3f in (zhigh data %.3f)  A=%.4f in2 (data %.4f)" % (
            math.degrees(b), min(ws) + off, max(ws) + off, r0["zhigh"], A * c * c, r0["area"]))
        for r_ in d["rows"][::8]:
            loop = section_loop(tc=r_["tc"])
            A, cx, cy = section_props(loop)
            b = math.atan(r_["p_q"] / (2 * math.pi * r_["r"]))
            c = r_["c"]
            ws = [-x * c * math.sin(b) + y * c * math.cos(b) for x, y in loop]
            us = [(1 - x) * c * math.cos(b) + y * c * math.sin(b) for x, y in loop]   # LE at u = c cos b ... see below
            wc = -cx * c * math.sin(b) + cy * c * math.cos(b)
            uc = (1 - cx) * c * math.cos(b) + cy * c * math.sin(b)
            du = r_["sweep"] - max(us)
            print("  r %.2f  zhigh model %.3f data %.3f | cgy model %.3f data %.3f | A %.4f/%.4f" % (
                r_["r"], max(ws) + r_["cgz"] - wc, r_["zhigh"], uc + du, r_["cgy"], A * c * c, r_["area"]))


# ============================================================================ blade definitions (mm)
def naca4_loop(n=22, tc=0.09, m=0.03, p=0.4, te=0.004):
    """NACA 4-digit cambered section (thin, curved: Master Airscrew style), chord line y = 0, LE at x = 0."""
    xs = [(1 - math.cos(math.pi * i / n)) / 2 for i in range(n + 1)]

    def yc(x):
        return m / p ** 2 * (2 * p * x - x * x) if x < p else m / (1 - p) ** 2 * ((1 - 2 * p) + 2 * p * x - x * x)

    def yt(x):
        return 5 * tc * (0.2969 * math.sqrt(x) - 0.1260 * x - 0.3516 * x ** 2 + 0.2843 * x ** 3 - 0.1036 * x ** 4) \
            + te * x / 2
    up = [(x, yc(x) + yt(x)) for x in xs]
    lo = [(x, yc(x) - yt(x)) for x in xs]
    return up[::-1] + lo[1:-1]


def stadium_loop(n=22, tc=0.24):
    """Rounded-end rectangle (flat bottom y = 0, top y = tc), same x stations as the airfoils."""
    xs = [(1 - math.cos(math.pi * i / n)) / 2 for i in range(n + 1)]
    h = tc / 2

    def ends(x):
        d = min(x, 1 - x)
        if d >= h:
            return 0.0
        return h - math.sqrt(max(0.0, h * h - (h - d) ** 2))
    up = [(x, tc - ends(x)) for x in xs]
    lo = [(x, ends(x)) for x in xs]
    return up[::-1] + lo[1:-1]


def blend(a, b, q):
    return [((1 - q) * pa[0] + q * pb[0], (1 - q) * pa[1] + q * pb[1]) for pa, pb in zip(a, b)]


def place(loop, c, beta, r):
    """Section loop (chord units) -> (r, u, a) in mm: u = rotation direction, a = forward (thrust)."""
    cb, sb = math.cos(beta), math.sin(beta)
    return [(r, -x * c * cb - y * c * sb, -x * c * sb + y * c * cb) for x, y in loop]


def smooth(t):
    t = min(1.0, max(0.0, t))
    return t * t * (3 - 2 * t)


NSEC = 22


T_MIN, TE_MIN = 0.42, 0.32       # mm: moulded props keep a real trailing edge and a rounded tip


def section_shape(kind, tc, q, camber=0.03, c=None):
    te = 0.004
    if c:
        tc = min(0.9, max(tc, T_MIN / c))
        te = min(0.5 * tc, max(te, TE_MIN / c))
    base = section_loop(NSEC, tc=tc, te=te) if kind == "clarky" else naca4_loop(NSEC, tc=tc, m=camber, te=te)
    return blend(base, stadium_loop(NSEC, tc=tc), q) if q > 0 else base


def extents(pts):
    us = [p[1] for p in pts]
    as_ = [p[2] for p in pts]
    return min(us), max(us), min(as_), max(as_)


def apc_rows(pe0, P_hub):
    """APC PE0 stations -> list of dict(r, c, beta, tc, q, cu, ca, mode) in mm (mode 'centroid')."""
    d = read_pe0(pe0)
    rows = []
    src = d["rows"]
    # elliptical tip: chord^2 linear over the last stations (PE0 ends at c = 0 on R)
    for i, s_ in enumerate(src):
        r = s_["r"] * IN
        c = max(s_["c"] * IN, 0.35)
        beta = math.atan(s_["p_q"] / (2 * math.pi * s_["r"]))
        tc = s_["tc"]
        cy = section_shape("clarky", tc, 0.0)
        A_cy = section_props(cy)[0] * c * c
        st = stadium_loop(NSEC, tc)
        A_st = section_props(st)[0] * c * c
        A_dat = s_["area"] * IN * IN
        q = 0.0 if A_dat <= 0 or A_st - A_cy < 1e-9 else min(1.0, max(0.0, (A_dat - A_cy) / (A_st - A_cy)))
        rows.append(dict(r=r, c=c, beta=beta, tc=tc, q=q, cu=s_["cgy"] * IN, ca=s_["cgz"] * IN, kind="clarky",
                         mode="centroid", src=s_))
    rows = tip_closure(rows, d["R"] * IN)
    return rows, d


def tip_closure(rows, R, c_min=6.0, n=9):
    """Rounded tip: from the last station with chord >= c_min, a quarter ellipse in the front view
    (r = r0 + (R - r0) sin t, c = c0 cos t), the other quantities interpolated toward the tip station."""
    i0 = max(i for i, e in enumerate(rows) if e["c"] >= c_min and e["r"] < R - 0.5)
    e0, e1 = rows[i0], rows[-1]
    out = rows[:i0 + 1]
    for k in range(1, n + 1):
        t = math.pi / 2 * k / n
        r = e0["r"] + (R - e0["r"]) * math.sin(t)
        f = (r - e0["r"]) / max(1e-9, e1["r"] - e0["r"])
        e = dict(e0)
        for kk in ("beta", "tc", "q", "cu", "ca"):
            if e0.get(kk) is not None and e1.get(kk) is not None:
                e[kk] = e0[kk] + f * (e1[kk] - e0[kk])
        e["r"] = r
        e["c"] = max(0.35, e0["c"] * math.cos(t))
        e.pop("src", None)
        out.append(e)
    return out


def silhouette(key, s):
    pts = PU.PLAN[key]
    ss = [p[0] for p in pts]
    return interp(ss, [p[1] for p in pts], s), interp(ss, [p[2] for p in pts], s)


TC_BASE = None


def tc_base(s):
    """APC 11x7 thickness ratio distribution vs r/R (shape reused for the Master Airscrew blades)."""
    global TC_BASE
    if TC_BASE is None:
        d = read_pe0("11x7")
        TC_BASE = ([x["r"] / d["R"] for x in d["rows"]], [x["tc"] for x in d["rows"]])
    return interp(TC_BASE[0], TC_BASE[1], s)


def ma_rows(spec, tc_scale):
    """Master Airscrew blades from UIUC c/R + beta tables and front / side silhouettes (mm, mode 'extent')."""
    R = spec["D"] * IN / 2
    geo = read_uiuc(spec["uiuc"])
    gs, gb = [g[0] for g in geo], [math.radians(g[2]) for g in geo]
    k_p = (spec["P"] / spec["D"]) / (spec.get("P_ref", spec["P"]) / spec.get("D_ref", spec["D"]))
    rows = []
    s_end = spec.get("s_end", 0.975)
    ss = [0.15 + i * 0.025 for i in range(int(round((s_end - 0.15) / 0.025)) + 1)]
    for s in ss:
        beta = math.atan(math.tan(interp(gs, gb, s)) * k_p)
        if spec.get("planform") == "MA3":
            pts = PU.MA3
            up = -interp([p[0] for p in pts], [p[1] for p in pts], s)
            dn = interp([p[0] for p in pts], [p[2] for p in pts], s)
        else:
            up, dn = silhouette(spec["front"], s)
        su, sd = silhouette(spec["side"], s)
        tc = tc_base(s) * tc_scale
        w = (up + dn) * R
        c = w / (math.cos(beta) + tc * math.sin(beta))
        rows.append(dict(r=s * R, c=c, beta=beta, tc=tc, q=0.0, cu=(up - dn) / 2 * R, ca=(su - sd) / 2 * R,
                         kind="naca", camber=spec.get("camber", 0.03), mode="extent"))
    end = dict(rows[-1])
    end["r"] = R
    return tip_closure(rows + [end], R, c_min=3.0)


def hub_transition(rows, hub_r, hub_t, kind, camber=0.03, n=7):
    """Neck rows from inside the hub to the first table station: a flatter rounded-end section that fits in
    the hub thickness (APC / MA roots), blended (shape, chord, angle, position) into the blade."""
    r0 = rows[0]
    c_n = 0.90 * r0["c"]
    t_n = 1.05 * r0["c"] * r0["tc"]
    tc_n = t_n / c_n
    ax_max = hub_t - 1.6
    beta_n = r0["beta"]
    for k in range(200):        # flatten until the neck fits axially between the hub faces
        pts = place(stadium_loop(NSEC, tc_n), c_n, beta_n, 0.0)
        u0, u1, a0, a1 = extents(pts)
        if a1 - a0 <= ax_max:
            break
        beta_n -= math.radians(0.25)
    rho = 2.2                      # root fillet: the neck flares (chord, a little thickness) into the hub
    room = max(0.0, (ax_max + 1.6 - 0.5 - (a1 - a0)) / 2)
    r_n = hub_r + rho + 0.2
    neck = dict(r=r_n, c=c_n, beta=beta_n, tc=tc_n, q=1.0, cu=None, ca=0.0, kind=kind, camber=camber,
                mode="extent_neck")
    out = []

    def flared(rr):
        d = rho - math.sqrt(max(0.0, rho * rho - max(0.0, hub_r + rho - rr) ** 2)) if rr < hub_r + rho else 0.0
        d = min(d, rho)
        e = dict(neck)
        e["r"] = rr
        e["a_lim"] = hub_t / 2 - 0.3
        e["c"] = c_n + 2 * d
        e["tc"] = (t_n + 2 * min(d, room) * 0.8) / e["c"]
        return e
    for rr in (0.55 * hub_r, hub_r - 1.0):
        out.append(flared(hub_r))
        out[-1]["r"] = rr
    for k in range(6):
        out.append(flared(hub_r - 0.2 + k * (rho + 0.2) / 6))
    for k in range(n):
        t = smooth(k / n)
        e = dict(r=r_n + (k / n) * (r0["r"] - r_n))
        for kk in ("c", "beta", "tc", "q"):
            e[kk] = neck[kk] + t * (r0[kk] - neck[kk])
        e["t_blend"] = t
        e.update(kind=kind, camber=camber, mode="blend")
        out.append(e)
    return out + rows


def loops_3d(rows, root_center):
    """Place every station; returns list of loops [(r, u, a)] in mm."""
    out = []
    ref = None
    for e in rows:
        shape = section_shape(e["kind"], e["tc"], e["q"], e.get("camber", 0.03), e["c"])
        pts = place(shape, e["c"], e["beta"], e["r"])
        u0, u1, a0, a1 = extents(pts)
        if e.get("mode", "centroid") == "centroid":
            A, cx, cy = section_props(shape)
            cb, sb = math.cos(e["beta"]), math.sin(e["beta"])
            uc = -cx * e["c"] * cb - cy * e["c"] * sb
            ac = -cx * e["c"] * sb + cy * e["c"] * cb
            du, da = e["cu"] - uc, e["ca"] - ac
        elif e.get("mode") == "extent":
            du, da = e["cu"] - (u0 + u1) / 2, e["ca"] - (a0 + a1) / 2
        else:
            du = da = None
        out.append([pts, du, da, (u0, u1, a0, a1)])
    # neck / blend rows: neck centred in-plane on the first table section's extent midpoint, axially on the hub
    first = next(i for i, e in enumerate(rows) if e.get("mode") not in ("extent_neck", "blend"))
    fu0, fu1, fa0, fa1 = out[first][3]
    f_mid_u = (fu0 + fu1) / 2 + out[first][1]
    f_mid_a = (fa0 + fa1) / 2 + out[first][2]
    for i, e in enumerate(rows[:first]):
        u0, u1, a0, a1 = out[i][3]
        t = e.get("t_blend", 0.0)
        mu = root_center[0] + t * (f_mid_u - root_center[0])
        ma = root_center[1] + t * (f_mid_a - root_center[1])
        out[i][1], out[i][2] = mu - (u0 + u1) / 2, ma - (a0 + a1) / 2
    res = []
    for (pts, du, da, _), e in zip(out, rows):
        L = [(p[0], p[1] + du, p[2] + da) for p in pts]
        lim = e.get("a_lim")
        if lim:       # flared root inside / at the hub: keep it between the hub faces (squash axially)
            amax = max(abs(p[2]) for p in L)
            if amax > lim:
                L = [(p[0], p[1], p[2] * lim / amax) for p in L]
        res.append(L)
    return res, first


def blade_volume(loops):
    """Volume of one lofted blade (mm^3) from station areas (trapezoids in r)."""
    def area(L):
        a = 0.0
        for (r0, u0, a0), (r1, u1, a1) in zip(L, L[1:] + L[:1]):
            a += u0 * a1 - u1 * a0
        return abs(a) / 2
    rs = [L[0][0] for L in loops]
    As = [area(L) for L in loops]
    return sum((rs[i + 1] - rs[i]) * (As[i] + As[i + 1]) / 2 for i in range(len(rs) - 1)), rs, As


# ============================================================================ the library
PROPS = [
    dict(key="APC_11x7", label="APC Sport 11x7", kind="apc", pe0="11x7", D=11, P=7, blades=2, hub_d=25.4,
         hub_t=0.53 * IN, mat="apc", mass_spec=40.0, sg=1.7, note="hub 1.00 x 0.53 in, 1.41 oz"),
    dict(key="APC_11x8", label="APC Sport 11x8", kind="apc", pe0="11x8", D=11, P=8, blades=2, hub_d=25.4,
         hub_t=0.55 * IN, mat="apc", mass_spec=41.1, sg=1.7, note="hub 1.00 x 0.55 in, 1.45 oz"),
    dict(key="APC_12x6", label="APC Sport 12x6", kind="apc", pe0="12x6", D=12, P=6, blades=2, hub_d=25.4,
         hub_t=0.48 * IN, mat="apc", mass_spec=45.9, sg=1.7, note="hub 1.00 x 0.48 in, 1.62 oz"),
    dict(key="APC_12x7", label="APC Sport 12x7", kind="apc", pe0="12x7", D=12, P=7, blades=2, hub_d=25.4,
         hub_t=0.52 * IN, mat="apc", mass_spec=None, sg=1.7, note="hub 0.52 in estimado (12x6 0.48 / 12x8 0.56)"),
    dict(key="APC_12.5x6", label="APC Sport 12.5x6", kind="apc", pe0="125x6", D=12.5, P=6, blades=2, hub_d=25.4,
         hub_t=0.50 * IN, mat="apc", mass_spec=None, sg=1.7, note="hub 0.50 in estimado"),
    dict(key="MA_GF_11x7", label="Master Airscrew G/F 11x7", kind="ma", uiuc="ma_11x7", front="ma_11x7_front",
         side="ma_11x7_side", D=11, P=7, blades=2, hub_d=25.0, hub_t=14.3, camber=0.035, mat="ma",
         mass_spec=26.1, sg=1.48, note="hub 14.3 mm, 26.1 g"),
    dict(key="MA_Scimitar_11x7", label="Master Airscrew Scimitar 11x7", kind="ma", uiuc="mas_11x7",
         front="mas_11x7_front", side="mas_11x7_side", D=11, P=7, blades=2, hub_d=25.0, hub_t=13.5, camber=0.03,
         mat="ma", mass_spec=28.6, sg=1.48, note="hub 13.5 mm, 28.6 g"),
    dict(key="MA_3B_11x7", label="Master Airscrew 3-Blade 11x7", kind="ma", uiuc="ma_11x7", planform="MA3",
         side="ma_11x7_side", D=11, P=7, blades=3, hub_d=29.0, hub_t=14.3, camber=0.035, mat="ma",
         mass_spec=34.9, sg=1.48, s_end=0.975, note="hub 14.3 mm, 34.9 g"),
    dict(key="MA_3B_12x6", label="Master Airscrew 3-Blade 12x6", kind="ma", uiuc="ma_11x7", planform="MA3",
         side="ma_11x7_side", D=12, P=6, P_ref=7, D_ref=11, blades=3, hub_d=29.0, hub_t=14.3, camber=0.035,
         mat="ma", mass_spec=47.9, sg=1.48, s_end=0.975, note="hub 14.3 mm, 47.9 g"),
]
BORE_D = 5 / 16 * IN + 0.02        # reamed to 5/16 in for the 61SF crankshaft


def prop_volume(spec, loops):
    hub_r, hub_t = spec["hub_d"] / 2, spec["hub_t"]
    V, rs, As = blade_volume(loops)
    Vo = sum((rs[i + 1] - rs[i]) * (As[i] + As[i + 1]) / 2 for i in range(len(rs) - 1) if rs[i] >= hub_r)
    return spec["blades"] * Vo + math.pi * (hub_r ** 2 - (BORE_D / 2) ** 2) * hub_t


def build_loops(spec, tc_scale=None):
    hub_r, hub_t = spec["hub_d"] / 2, spec["hub_t"]
    if spec["kind"] == "apc":
        rows, d = apc_rows(spec["pe0"], None)
        rows = hub_transition(rows, hub_r, hub_t, "clarky")
        L, first = loops_3d(rows, (1.0, 0.0))
        return L, rows, dict(pe0=d)
    if tc_scale is None:      # thickness scaled so the prop weighs what the maker lists (kept 0.9 .. 1.3)
        lo, hi = 0.9, 1.3
        for _ in range(40):
            mid = (lo + hi) / 2
            L, rows, _x = build_loops(spec, mid)
            m = prop_volume(spec, L) / 1000 * spec["sg"]
            lo, hi = (mid, hi) if m < spec["mass_spec"] else (lo, mid)
        tc_scale = (lo + hi) / 2
    rows = ma_rows(spec, tc_scale)
    rows = hub_transition(rows, hub_r, hub_t, "naca", spec.get("camber", 0.03))
    L, first = loops_3d(rows, (0.5, 0.0))
    return L, rows, dict(tc_scale=tc_scale)
