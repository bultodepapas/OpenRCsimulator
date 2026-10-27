"""NITRO-06-R3: carburettor root, the former Newton/bisection solve (replica) and the closed form against a 50-digit mpmath reference. Run: python3 closed_form.py"""
import math, mpmath
GAMMA = 1.4
CRITICAL_RATIO = 0.5282817877171742
PSI_CHOKED = 0.6847314563772704
ROOT_ITERATIONS, ROOT_TOLERANCE = 64, 1.0e-15
K = (GAMMA - 1.0) / GAMMA
C = 2.0 * GAMMA / (GAMMA - 1.0)

def g(r):
    if not math.isfinite(r) or r <= CRITICAL_RATIO: return 1.0
    if r >= 1.0: return 0.0
    return math.pow(r, 1.0 / GAMMA) * math.sqrt(max(C * (1.0 - math.pow(r, K)), 0.0)) / PSI_CHOKED

def dg(r):
    s = math.sqrt(max(C * (1.0 - math.pow(r, K)), 0.0))
    if s <= 0.0: return -math.inf
    return (math.pow(r, 1.0 / GAMMA - 1.0) * s / GAMMA - math.pow(r, 1.0 / GAMMA) * C * K * math.pow(r, K - 1.0) / (2.0 * s)) / PSI_CHOKED

def iterative(y):
    lo, hi = CRITICAL_RATIO, 1.0
    r = 0.5 * (lo + hi); n = 0
    for _ in range(ROOT_ITERATIONS):
        n += 1
        h = r - y * g(r)
        if h > 0.0: hi = r
        else: lo = r
        if abs(h) <= ROOT_TOLERANCE or hi - lo <= ROOT_TOLERANCE: break
        slope = 1.0 - y * dg(r)
        nxt = r - h / slope if slope > 0.0 and math.isfinite(slope) else math.nan
        if not math.isfinite(nxt) or nxt <= lo or nxt >= hi: nxt = 0.5 * (lo + hi)
        r = nxt
    return r, n

def closed(y):
    a = y * math.sqrt(C) / PSI_CHOKED
    t = 2.0 / (1.0 + math.sqrt(1.0 + 4.0 / (a * a)))
    return math.pow(t, GAMMA / (GAMMA - 1.0))

mpmath.mp.dps = 50
def exact(y):
    a = mpmath.mpf(y) * mpmath.sqrt(mpmath.mpf(C)) / mpmath.mpf(PSI_CHOKED)
    t = 2 / (1 + mpmath.sqrt(1 + 4 / (a * a)))
    return t ** (mpmath.mpf(GAMMA) / (mpmath.mpf(GAMMA) - 1))

def ulps(a, ref):
    return float(abs(mpmath.mpf(a) - ref) / mpmath.mpf(math.ulp(a)))

worst_i = worst_c = 0.0; iters = []; residual_i = residual_c = 0.0; y = 0.5283; count = 0; boundary = []
while y < 1.0e4:
    ref = exact(y); ri, n = iterative(y); rc = closed(y)
    worst_i = max(worst_i, ulps(ri, ref)); worst_c = max(worst_c, ulps(rc, ref)); iters.append(n)
    residual_i = max(residual_i, abs(ri - y * g(ri))); residual_c = max(residual_c, abs(rc - y * g(rc)))
    y *= 1.0007; count += 1
for y in (math.nextafter(CRITICAL_RATIO, 2.0), CRITICAL_RATIO * (1 + 1e-12), CRITICAL_RATIO * 1.001):
    boundary.append((y, closed(y), iterative(y)[0], float(exact(y))))
print(f"y values {count}: iterative worst {worst_i:.2f} ulp (iterations mean {sum(iters)/len(iters):.1f}, max {max(iters)}); closed form worst {worst_c:.2f} ulp")
print(f"max |r - y g(r)| iterative {residual_i:.2e}, closed {residual_c:.2e}")
for b in boundary: print("boundary y=%r closed=%r iterative=%r exact=%r" % b)

# Admission = r(a/x)/r(1/x) over an opening × demand grid, both methods against the exact ratio.
def admission(solve, opening, x):
    def ratio(y): return y if y <= CRITICAL_RATIO else solve(y)
    return min(ratio(opening / x) / ratio(1.0 / x), 1.0)
def exact_root(y):
    return mpmath.mpf(y) if y <= CRITICAL_RATIO else exact(y)
worst = {"iterative": 0.0, "closed": 0.0}; n = 0
for oi in range(101):
    opening = 0.02 + 0.98 * oi / 100
    for xi in range(1, 301):
        x = 0.01 * xi
        ref = min(exact_root(opening / x) / exact_root(1.0 / x), mpmath.mpf(1))
        for name, solve in (("iterative", lambda y: iterative(y)[0]), ("closed", closed)):
            worst[name] = max(worst[name], ulps(admission(solve, opening, x), ref))
        n += 1
print(f"admission over {n} cases, worst ulp vs exact: iterative {worst['iterative']:.1f}, closed {worst['closed']:.1f}")
