# CR-00 (docs/CRASH-DAMAGE-PLAN.md): effective mass and impact energy at each crash-hull point.
# Effective mass of a rigid airplane at a contact point along a direction n: m_eff = 1/(1/m + (r x n)^T I^-1 (r x n)).
# Run: python3 research/crash-damage/cr-00/effective_mass.py research/crash-damage/cr-00/models.json > research/crash-damage/cr-00/results.txt
# Inputs: models.json from dump_models.gd (the app loader). Rigid airplane, plastic impact at one point, no friction.
# Impact energy available at the point for a normal approach speed v_n: E = 1/2 m_eff v_n^2 (perfectly plastic, no friction).
import json, numpy as np, sys
d = json.load(open(sys.argv[1]))
labels = {
 "jensen_ugly_stik_60": ["L tip","R tip","spinner","tail end","L stab tip","R stab tip","fin top","belly"],
 "gp_extra_300s_60": ["L tip LE","R tip LE","L tip TE","R tip TE","spinner","L wheel","R wheel","tail wheel","tail end","L stab","R stab","fin top","canopy"],
 "p51d_mustang_120": ["L tip LE","R tip LE","L tip TE","R tip TE","spinner","prop low","prop L","prop R","tail end","L stab","R stab","fin top","canopy","scoop"],
 "sebart_avanti_s_a200": ["L tip LE","R tip LE","L tip TE","R tip TE","nose","tail cone","belly mid","belly fwd","belly aft","L stab","R stab","fin top","canopy"],
}
cases = {  # ground normal (pointing up, out of the ground) expressed in body FRD for an attitude
 "level (n=-z)": np.array([0,0,-1.0]),
 "nose-in vertical (n=-x)": np.array([-1.0,0,0]),
 "45deg dive (n)": np.array([-1,0,-1.0])/np.sqrt(2),
 "90deg bank L (n=+y)": np.array([0,1.0,0]),
}
for k, v in d.items():
    m = v["mass"]; J = v["inertia"]
    I = np.array([[J[0], -J[3], -J[4]],[-J[3], J[1], -J[5]],[-J[4], -J[5], J[2]]])
    Ii = np.linalg.inv(I)
    pts = np.array(v["hull"]).reshape(-1,3)
    print(f"\n== {k}: m={m:.2f} kg  KE at 10/15/25 m/s = {0.5*m*100:.0f}/{0.5*m*225:.0f}/{0.5*m*625:.0f} J")
    for i,r in enumerate(pts):
        lab = labels.get(k, [])[i] if i < len(labels.get(k, [])) else str(i)
        row = []
        for cn, n in cases.items():
            rn = np.cross(r, n)
            me = 1.0/(1.0/m + rn @ Ii @ rn)
            row.append(f"{me:6.2f}")
        print(f"  {lab:12s} r=({r[0]:+.2f},{r[1]:+.2f},{r[2]:+.2f})  m_eff[kg] level/nose-in/45dive/kn-edge: " + " ".join(row) + f"  ratio level {float(row[0])/m:.2f}")
