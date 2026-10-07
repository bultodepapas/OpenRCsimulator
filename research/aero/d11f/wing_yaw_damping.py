"""D11f independent reference (pure Python 3): wing yaw damping Cnr of a rectangular AR 5 wing with 3 equal strips per
side (the simulator's layout), Weissinger kernel as in research/aero/d11d/lifting_line.py, section slope a0 calibrated
like the Ugly Stik (6.0818/rad). Yaw rate r gives each strip an onset speed u_i = V - r*y_i (body x). Circulation from
flow tangency at the 3/4-chord points; forces by Kutta-Joukowski at each strip's bound vortex with the local onset and
the trailing-leg induced downwash there (induced drag = lift * induced angle), plus profile drag CD0 * q_i. Prints
Cnr (per r b / 2V) split into profile and lift-induced parts for several CL. Run: python3 research/aero/d11f/wing_yaw_damping.py
"""
import math

b = 1.524; c = 0.3048; S = b * c; n_side = 3; a0 = 6.0818; CD0 = 0.0434; V = 15.0
h = b / 2
edges = [-h + k * h / n_side for k in range(2 * n_side + 1)]
ys = [0.5 * (edges[i] + edges[i + 1]) for i in range(2 * n_side)]
n = len(ys)

def seg(px, py, x1, y1, x2, y2):
    r1x, r1y, r2x, r2y = px - x1, py - y1, px - x2, py - y2
    cz = r1x * r2y - r1y * r2x
    if abs(cz) < 1e-14: return 0.0
    n1 = math.hypot(r1x, r1y); n2 = math.hypot(r2x, r2y)
    return ((x2 - x1) * (r1x / n1 - r2x / n2) + (y2 - y1) * (r1y / n1 - r2y / n2)) / (4 * math.pi * cz)

def horseshoe_w(px, py, j, far=1e5):  # z-velocity (up) per unit circulation of horseshoe j
    a, e = edges[j], edges[j + 1]
    return seg(px, py, far, a, 0.0, a) + seg(px, py, 0.0, a, 0.0, e) + seg(px, py, 0.0, e, far, e)

def trailing_w(px, py, j, far=1e5):  # trailing legs only (at the bound line: the induced downwash of lifting-line theory)
    a, e = edges[j], edges[j + 1]
    return seg(px, py, far, a, 0.0, a) + seg(px, py, 0.0, e, far, e)

def solve(A, rhs):
    m = len(rhs); M = [A[i][:] + [rhs[i]] for i in range(m)]
    for col in range(m):
        p = max(range(col, m), key=lambda r: abs(M[r][col])); M[col], M[p] = M[p], M[col]
        for r in range(col + 1, m):
            f = M[r][col] / M[col][col]
            for k in range(col, m + 1): M[r][k] -= f * M[col][k]
    x = [0.0] * m
    for r in range(m - 1, -1, -1):
        x[r] = (M[r][m] - sum(M[r][k] * x[k] for k in range(r + 1, m))) / M[r][r]
    return x

# Frame: x downstream, y right, z up; the air meets strip i with onset (u_i, 0, W), W = V sin(alpha) the same everywhere.
# Generalised Weissinger with section slope a0 (as in D11d): tangency at the 3/4-chord point,
# Cl_i/a0 = W/u_i - (induced angle from all horseshoes except strip i's own 2-D term). Gamma_i = 0.5 u_i c Cl_i.
def loads(alpha, r):
    W = V * math.sin(alpha)
    u = [V * math.cos(alpha) - r * y for y in ys]
    A = [[0.0] * n for _ in range(n)]
    for i in range(n):
        for j in range(n):
            k = -horseshoe_w(c / 2, ys[i], j) * 0.5 * u[j] * c / u[i]
            if i == j: k -= 1.0 / (2 * math.pi)
            A[i][j] = (1.0 if i == j else 0.0) / a0 + k
    cl = solve(A, [W / u[i] for i in range(n)])
    gam = [0.5 * u[j] * c * cl[j] for j in range(n)]
    N = 0.0; L = 0.0
    for i in range(n):
        dy = edges[i + 1] - edges[i]
        w_down = -sum(trailing_w(0.0, ys[i], j) * gam[j] for j in range(n))  # trailing-leg downwash at the bound vortex
        # Kutta-Joukowski with the local air velocity (u_i, 0, W - w_down) across a bound vortex along +y:
        # F = Gamma (U x y_hat) dy = Gamma (-(W - w_down), 0, u_i) dy. Profile drag along the onset.
        fx = -gam[i] * (W - w_down) * dy + 0.5 * (u[i] ** 2 + W * W) * c * dy * CD0
        L += gam[i] * u[i] * dy
        N += ys[i] * fx                    # a downstream force on the right wing yaws the nose right (+)
    return L, N

qS = 0.5 * V * V * S
prof = -CD0 / 3 * (1 - 1 / (4 * n_side ** 2))  # strip-midpoint sum of y^2: 97.2 % of the continuum
print("Wing yaw damping, Weissinger reference (3 strips per side, a0 %.4f, CD0 %.4f):" % (a0, CD0))
print("  CL      Cnr      profile   lift-induced  lift-induced/CL^2")
for deg in [2, 4, 6, 8, 10]:
    a = math.radians(deg); dr = 0.05
    Lp, Np = loads(a, dr); Lm, Nm = loads(a, -dr)
    L0, _ = loads(a, 0.0)
    cl_ = L0 / qS
    cnr = (Np - Nm) / (2 * dr) / (qS * b * b / (2 * V))
    print("  %.3f   %.4f   %.4f    %.4f        %.4f" % (cl_, cnr, prof, cnr - prof, (cnr - prof) / cl_ ** 2))

# Induced drag factor of the same wing in symmetric flight, refined (the 3-strip layout is far too coarse for induced drag:
# it gives e > 1). Equal-span strips per side, a0 = 2*pi and the calibrated 6.0818, Kutta-Joukowski at the bound vortex.
def induced_factor(per_side, slope):
    global edges, ys, n
    saved = (edges, ys, n)
    edges = [-h + k * h / per_side for k in range(2 * per_side + 1)]
    ys = [0.5 * (edges[i] + edges[i + 1]) for i in range(2 * per_side)]
    n = len(ys)
    W = V * math.sin(math.radians(4)); u = V * math.cos(math.radians(4))
    A = [[(1.0 if i == j else 0.0) / slope - horseshoe_w(c / 2, ys[i], j) * 0.5 * c - (1.0 / (2 * math.pi) if i == j else 0.0)
          for j in range(n)] for i in range(n)]
    cl = solve(A, [W / u] * n)
    gam = [0.5 * u * c * x for x in cl]
    D = sum(gam[i] * (-sum(trailing_w(0.0, ys[i], j) * gam[j] for j in range(n))) * (edges[i + 1] - edges[i]) for i in range(n))
    L = sum(gam[i] * u * (edges[i + 1] - edges[i]) for i in range(n))
    edges, ys, n = saved
    return (D / qS) / (L / qS) ** 2

AR = b * b / S
print("Induced drag factor k_i = CD_i/CL^2 of the AR %.1f rectangular wing (Weissinger, KJ at the bound vortex):" % AR)
for per_side in [3, 10, 40]:
    for slope in [2 * math.pi, a0]:
        k = induced_factor(per_side, slope)
        print("  %2d strips/side, a0 %.3f: k_i %.4f (span efficiency e = %.3f)" % (per_side, slope, k, 1 / (math.pi * AR * k)))
print("Borrowed whole-airplane polar: k 0.0815 about CL_minD 0.23 (e 0.78 incl. tail, fuselage, profile drag rise)")
