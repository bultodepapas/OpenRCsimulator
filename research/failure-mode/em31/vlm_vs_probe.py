"""Compare the masked-strip local law (strip_probe.log) with a lifting-line model of the same damaged planform."""
import math, sys, numpy as np
sys.path.insert(0, '.')
import importlib.util
spec = importlib.util.spec_from_file_location('wl', 'wingloss.py'); wl = importlib.util.module_from_spec(spec); spec.loader.exec_module(wl)
cases = {  # span b, root/tip chord, fuselage half-width
 'stik': (1.524, 0.3048, 0.3048, 0.05), 'extra': (1.6256, 0.3885, 0.2034, 0.076),
 'p51': (2.82, 0.6664, 0.307, 0.13), 'timber': (1.555, 0.2103, 0.2103, 0.06)}
def edges(b, cr, ct, n=3):
    h = b/2
    if abs(cr-ct) < 1e-9: return [h*(k+1)/n for k in range(n)]
    slope = (ct-cr)/h; tot = cr*h + slope*h*h/2
    return [h if k == n-1 else (-cr + math.sqrt(cr*cr + 2*slope*tot*(k+1)/n))/slope for k in range(n)]
for k, (b, cr, ct, root) in cases.items():
    h = b/2; e = edges(b, cr, ct)
    chord = lambda y: cr + (ct-cr)*min(abs(y), h)/h
    intact = wl.Wing([(-h, h)], chord)
    gi = intact.solve(np.ones(len(intact.ym))); Li = intact.lift_q(gi)
    out = []
    for name, cut in (('outer 1/3 area', -e[1]), ('outer 2/3 area', -e[0])):
        w = wl.Wing([(cut, h)], chord); g = w.solve(np.ones(len(w.ym)))
        out.append('%s (f=%.2f): L %.2f of intact, y_c %.3f m' % (name, 1 + cut/h, w.lift_q(g)/Li, w.roll_q(g, 0)/w.lift_q(g)))
    for var, wall in (('panel wall', root), ('panel free', None)):
        w = wl.Wing([(root, h)], chord, wall=wall); g = w.solve(np.ones(len(w.ym)))
        out.append('%s: L %.2f of intact, y_c %.3f m' % (var, w.lift_q(g)/Li, w.roll_q(g, 0)/w.lift_q(g)))
    print(k, '| strip edges (m):', ['%.3f' % x for x in e]); print('   ' + '\n   '.join(out))
