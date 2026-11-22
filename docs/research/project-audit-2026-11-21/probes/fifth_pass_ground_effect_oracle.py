#!/usr/bin/env python3
"""Check one emitted Stik component case by independent attached-strip algebra.
Usage: python3 fifth_pass_ground_effect_oracle.py /absolute/path/to/engine.log
No source modification or simulator flight is performed.
"""
import ast, math, re, sys
from pathlib import Path
text = Path(sys.argv[1]).read_text()
def take(pattern):
    match = re.search(pattern, text, re.MULTILINE)
    if not match:
        raise SystemExit("missing evidence: " + pattern)
    return match
if "ADMISSION true errors []" not in text or "PROBE_COMPLETE" not in text:
    raise SystemExit("missing admitted/completed probe")
meta = take(r"DATA span=([^ ]+) area=([^ ]+) effect=([^ ]+)")
S, tau = float(meta.group(2)), float(meta.group(3))
stations = take(r"STATION (\[[^\]]+\]) rows (\[[^\]]+\]) slope ([^\n]+)")
y = ast.literal_eval(stations.group(1)); slope = float(stations.group(3))
E = ast.literal_eval(take(r"MAP (\[[^\]]+\])").group(1))
sigma = ast.literal_eval(take(r"CASE alpha=0.0 factors=(\[[^\]]+\])").group(1))[:len(y)]
case = take(r"  d=2.0 blend=([^,]+),([^ ]+) GF=([^ ]+) GG=([^ ]+) LF=([^ ]+) LG=([^ ]+) PF=([^ ]+) PG=([^\n]+)")
blend_free, blend_near, gf, gg, lf, lg, pf, pg = map(float,case.groups())
neutral = take(r"  d=0.0 blend=([^,]+),([^ ]+) GF=([^ ]+) GG=([^ ]+) LF=([^ ]+) LG=([^ ]+) PF=([^ ]+) PG=([^\n]+)")
reverse = take(r"  d=-2.0 blend=([^,]+),([^ ]+) GF=([^ ]+) GG=([^ ]+) LF=([^ ]+) LG=([^ ]+) PF=([^ ]+) PG=([^\n]+)")
neutral_values = tuple(map(float,neutral.groups()))
reverse_values = tuple(map(float,reverse.groups()))
# At alpha=0, level symmetric controls and zero rates, d(alpha_i)/d(delta)=tau*sign(y_i).
# Attached source weights are all one. E maps source incidence to effective incidence.
# Additional GE lift on strip i is q*S/n*(1-sigma_i)*a0*tau*delta*(sign_i - sum_j E_ij*sign_j).
# Body z is down, so dMx from each lift is -y_i*dL_i.
n = len(y)
signs = [1 if yi > 0 else -1 for yi in y]
qbar = 0.5*1.225*15.0**2
delta = math.radians(2.0)
predicted = -qbar*S/n*slope*tau*delta*sum(y[i]*(1-sigma[i])*(signs[i]-sum(E[n*i+j]*signs[j] for j in range(n))) for i in range(n))
observed = lg-lf
assert blend_free == 0 and blend_near == 0
assert all(abs(x) < 1e-13 for x in neutral_values)
assert reverse_values[:2] == (0.0, 0.0)
assert all(abs(x+y)<1e-13 for x,y in zip(reverse_values[2:], (gf,gg,lf,lg,pf,pg)))
assert abs(pf-gf)<1e-13 and abs(pg-gg)<1e-13 and abs(gg-gf)<1e-13
assert abs(lf-gf)<1e-13 and lg < lf < 0
assert abs(lg-pg)>1e-4 and abs(observed)>1e-4
assert abs(predicted-observed)<2e-11, (predicted, observed)
print("independent strip ΔMx %.14f N m; component ΔMx %.14f N m; residual %.3g N m" % (predicted, observed, predicted-observed))
print("local-relative change %.9f%%; public change %.12g N m" % (100*observed/lf, pg-pf))
print("neutral=0; reversed ailerons reverse each Mx; both public paths select the attached oracle")
print("GE_ROLL_CHECK_OK")
