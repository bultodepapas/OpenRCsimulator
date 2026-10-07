"""D11d independent reference (pure Python 3, no dependencies). Run: python3 research/aero/d11d/lifting_line.py

Discrete Prandtl lifting line and Weissinger (one chordwise panel) for equal-span strips; prints the known answers
that app/tests/test_strip_induced.gd checks the GDScript map against, a refinement table for the AR 5 rectangular
Ugly Stik wing, and the Stik calibration (section slope a0 so the 3-per-side wing carries CLa minus the tail share).
Written independently of app/physics/aircraft_data.gd; it matches the knowledge base VLM
(docs/research/roadmap-investigations/02-aerodynamics-rc-scale.md, T2).
"""
import math


def solve(A, b):  # Gaussian elimination, partial pivot
    n = len(b); M = [row[:] + [b[i]] for i, row in enumerate(A)]
    for c in range(n):
        p = max(range(c, n), key=lambda r: abs(M[r][c])); M[c], M[p] = M[p], M[c]
        for r in range(c + 1, n):
            f = M[r][c] / M[c][c]
            for k in range(c, n + 1): M[r][k] -= f * M[c][k]
    x = [0.0] * n
    for r in range(n - 1, -1, -1):
        x[r] = (M[r][n] - sum(M[r][k] * x[k] for k in range(r + 1, n))) / M[r][r]
    return x

def strips(b, chord_at, n_side, equal_area=True):
    """Edges (a,b), centroid y, chord, width for 2*n_side strips (left tip -> right tip)."""
    half = b / 2
    # equal-span edges are fine for refinement; equal-area for a taper (rectangular: identical)
    edges = [half * k / n_side for k in range(n_side + 1)]
    right = [(edges[k], edges[k + 1]) for k in range(n_side)]
    out = []
    for (a, e) in reversed(right):
        out.append((-e, -a))
    out += right
    res = []
    for (a, e) in out:
        y = 0.5 * (a + e); c = chord_at(abs(y)); res.append(dict(a=a, b=e, y=y, c=c, w=e - a))
    return res

def K_matrix(st):
    n = len(st); K = [[0.0] * n for _ in range(n)]
    for i, si in enumerate(st):
        for j, sj in enumerate(st):
            # downwash/V at control point i from unit-Cl strip j: Gamma_j = 0.5 V c_j Cl_j; semi-infinite legs
            K[i][j] = sj['c'] / (8 * math.pi) * (1 / (si['y'] - sj['a']) - 1 / (si['y'] - sj['b']))
    return K

def responses(st, a0, S, b):
    n = len(st); K = K_matrix(st)
    A = [[(1.0 if i == j else 0.0) + a0 * K[i][j] for j in range(n)] for i in range(n)]
    # symmetric unit alpha
    cl = [a0 * x for x in solve(A, [1.0] * n)]
    CLa = sum(s['c'] * s['w'] * c for s, c in zip(st, cl)) / S
    # antisymmetric: alpha_i = 2 y_i/b per unit p_hat
    cl2 = [a0 * x for x in solve(A, [2 * s['y'] / b for s in st])]
    Clp = -sum(s['c'] * s['w'] * c * s['y'] for s, c in zip(st, cl2)) / (S * b)
    return CLa, Clp, K

b = 1.524; c = 0.3048; S = b * c; AR = b * b / S
print("AR %.3f" % AR)
# Sign check: uniform lift must induce positive (downward) induced angle everywhere.
st = strips(b, lambda y: c, 3); K = K_matrix(st)
print("sign check alpha_ind per unit Cl (all > 0):", [round(sum(row), 4) for row in K])
# Elliptic known answer (chord ~ sqrt(1-(2y/b)^2)) with many strips.
ce = lambda y: (4 * S / (math.pi * b)) * math.sqrt(max(1e-12, 1 - (2 * y / b) ** 2))
st = strips(b, ce, 200); CLa_e, _, _ = responses(st, 2 * math.pi, sum(s['c'] * s['w'] for s in st), b)
print("elliptic, 400 strips: CLa %.4f vs theory %.4f" % (CLa_e, 2 * math.pi / (1 + 2 / AR)))
print("AR 5 rectangular, a0 = 2pi, refinement (per side): n  CLa  Clp   [strip theory Clp = -a0/6 * (1-1/(4n^2))... ]")
for n in [3, 5, 10, 20, 40, 80]:
    st = strips(b, lambda y: c, n); CLa, Clp, _ = responses(st, 2 * math.pi, S, b)
    print("  %3d  %.4f  %.4f" % (n, CLa, Clp))

# --- Weissinger (one chordwise panel): bound vortex at c/4, control point at 3c/4, planar, unswept ---
def seg(p, p1, p2):
    """z-velocity at planar point p from a unit vortex segment p1->p2 (all z = 0)."""
    r1 = (p[0] - p1[0], p[1] - p1[1]); r2 = (p[0] - p2[0], p[1] - p2[1]); r0 = (p2[0] - p1[0], p2[1] - p1[1])
    cz = r1[0] * r2[1] - r1[1] * r2[0]
    if abs(cz) < 1e-14: return 0.0
    n1 = math.hypot(*r1); n2 = math.hypot(*r2)
    dot = r0[0] * (r1[0] / n1 - r2[0] / n2) + r0[1] * (r1[1] / n1 - r2[1] / n2)
    return dot / (4 * math.pi) * (1.0 / cz)  # (r1 x r2)_z / |r1 x r2|^2 * dot

def K_weissinger(st, far=1e5):
    n = len(st); K = [[0.0] * n for _ in range(n)]
    for i, si in enumerate(st):
        p = (si['c'] / 2.0, si['y'])  # x aft from the c/4 line: control point at 3c/4
        for j, sj in enumerate(st):
            A = (0.0, sj['a']); B = (0.0, sj['b'])
            w = seg(p, (far, sj['a']), A) + seg(p, A, B) + seg(p, B, (far, sj['b']))  # unit Gamma
            # per unit Cl_j: Gamma = 0.5 V c Cl; induced angle = -w/V (sign fixed below by the uniform-lift check)
            K[i][j] = -w * 0.5 * sj['c']
        K[i][i] -= 1.0 / (2.0 * math.pi)  # remove the 2-D self term: a0 carries it
    return K

def responses_w(st, a0, S, b):
    n = len(st); K = K_weissinger(st)
    A = [[(1.0 if i == j else 0.0) + a0 * K[i][j] for j in range(n)] for i in range(n)]
    cl = [a0 * x for x in solve(A, [1.0] * n)]
    CLa = sum(s['c'] * s['w'] * c for s, c in zip(st, cl)) / S
    cl2 = [a0 * x for x in solve(A, [2 * s['y'] / b for s in st])]
    Clp = -sum(s['c'] * s['w'] * c * s['y'] for s, c in zip(st, cl2)) / (S * b)
    return CLa, Clp

st = strips(b, lambda y: c, 3)
print("Weissinger sign check (row sums of K + self term, all > 0):", [round(sum(r) + 1 / (2 * math.pi), 4) for r in K_weissinger(st)])
print("AR 5 rectangular Weissinger, a0 = 2pi: n  CLa  Clp   (knowledge base VLM: 6/10/16 strips 4.32/4.17/4.08, -0.481/-0.449/-0.427 -> -0.40)")
for n in [3, 5, 8, 10, 20, 40, 80]:
    CLa, Clp = responses_w(strips(b, lambda y: c, n), 2 * math.pi, S, b)
    print("  %3d  %.4f  %.4f" % (n, CLa, Clp))

# Stik calibration cross-check: a0 so the 3-per-side Weissinger wing gives CLa - tail share.
target = 4.58 - 0.0956 / 0.4645148 * 1.75
st = strips(b, lambda y: c, 3)
lo, hi = 0.1, 50.0
for _ in range(80):
    a0 = 0.5 * (lo + hi)
    if responses_w(st, a0, S, b)[0] < target: lo = a0
    else: hi = a0
a0 = 0.5 * (lo + hi)
CLa, Clp = responses_w(st, a0, S, b)
n = len(st); K = K_weissinger(st)
A = [[(1.0 if i == j else 0.0) + a0 * K[i][j] for j in range(n)] for i in range(n)]
E0 = solve(A, [1.0 if i == 0 else 0.0 for i in range(n)])  # first column of E
print("python Stik: a0 %.6f wing CLa %.4f wing Clp %.4f  E[:,0] %s" % (a0, CLa, Clp, [round(x, 6) for x in E0]))

print("Elliptic wing, a0 = 2pi, 200 strips/side: AR  Weissinger  Prandtl  Helmbold")
for AR_e in [5, 10, 20, 50]:
    b_e = 1.0; S_e = b_e * b_e / AR_e
    ce2 = lambda y, S_e=S_e, b_e=b_e: (4 * S_e / (math.pi * b_e)) * math.sqrt(max(1e-12, 1 - (2 * y / b_e) ** 2))
    st = strips(b_e, ce2, 200); S_num = sum(s['c'] * s['w'] for s in st)
    CLw, _ = responses_w(st, 2 * math.pi, S_num, b_e)
    print("  %3d  %.4f  %.4f  %.4f" % (AR_e, CLw, 2 * math.pi / (1 + 2 / AR_e), 2 * math.pi * AR_e / (2 + math.sqrt(AR_e ** 2 + 4))))
