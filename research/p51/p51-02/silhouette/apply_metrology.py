#!/usr/bin/env python3
"""Write the AN 01-60-3 silhouette metrology into assets/aircraft/p51d-mustang-120/source.json (full-size block).

Rules are explicit and reproducible; every group written here is tagged "measured" in the source evidence. Values the
drawing cannot give (section exponents, hinge gaps, propeller, pilot widths) keep their estimates.

    python3 research/p51/p51-02/silhouette/apply_metrology.py
"""
import json
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
SOURCE = ROOT / "assets/aircraft/p51d-mustang-120/source.json"
IN = 0.0254
m = json.loads((HERE / "metrology.json").read_text())
src = json.loads(SOURCE.read_text())
fs = src["full_size"]
prof = m["profile_2in"]
z = np.array([p["z"] for p in prof])
top = np.array([p["top"] for p in prof])
bot = np.array([p["bottom"] for p in prof])
hw = np.array([np.nan if p["half_width"] is None else p["half_width"] for p in prof])
tip_z = m["spinner"]["tip_z"]
length = m["length_m"]
tail_z = tip_z + length

def at(arr, zq):
    ok = ~np.isnan(arr)
    return float(np.interp(zq, z[ok], arr[ok]))

# --- Artefacts in the side profile: the radio mast (top > 0.9 m between z 3.9 and 4.6) and the tail-wheel/doors bump
# (bottom below -0.5 m between z 4.7 and 5.4); the canopy is kept separately (top between the windscreen and z 3.1).
mast = (z > 3.9) & (z < 4.6) & (top > 0.9)
top_f = top.copy(); top_f[mast] = np.nan
# The extended tail wheel and its doors hang below the tail cone between z 4.7 and 6.0: the cone's bottom is the
# straight line between its ends. The fin and rudder rise above the deck aft of z 5.6: the cone's top is interpolated
# from the deck at 5.6 to the tail post (0.25 m above the FRL at the rudder's bottom hinge).
bump = (z > 4.7) & (z < 6.1)
bot_f = bot.copy(); bot_f[bump] = np.nan
fin_zone = z > 5.6
top_f[fin_zone] = np.nan
# Tail post anchors: top 0.25 m, bottom -0.03 m above the FRL at the rudder bottom hinge (read from the drawing's rudder
# bottom corner); the interpolation below uses them as the last valid samples.
post_z = tail_z - 0.5
deck_anchor_i = int(np.argmin(np.abs(z - post_z)))
top_f[deck_anchor_i] = 0.25
bot_f[deck_anchor_i] = -0.03
# Canopy: the top contour from the windscreen base to where it meets the deck again.
canopy_zone = (z > 0.6) & (z < 3.1)
# Fuselage top under the canopy = sill: the deck line interpolated between z 0.6 (0.57 m) and z 3.1.
sill_front, sill_back = at(top_f, 0.6), at(top_f, 3.1)
deck = top_f.copy()
deck[canopy_zone] = np.interp(z[canopy_zone], [0.6, 3.1], [sill_front, sill_back])
# Scoop: where the bottom contour dips below the fuselage line interpolated from z 1.0 (ahead of the lip) to z 4.2.
fus_bottom = bot_f.copy()
scoop_zone = (z > 1.1) & (z < 4.1) & (bot_f < np.interp(z, [1.0, 4.2], [at(bot_f, 1.0), at(bot_f, 4.2)]) - 0.03)
fus_bottom[scoop_zone] = np.interp(z[scoop_zone], [1.0, 4.2], [at(bot_f, 1.0), at(bot_f, 4.2)])
# Half-width under the wing (merged with the wing in plan) and at the stab: interpolate across.
hw_f = hw.copy()
hw_f[(z > -0.15) & (z < 2.95)] = np.nan  # wing and its root fillet merge with the fuselage in plan
hw_f[(z > 4.9) & (z < 6.45)] = np.nan   # stab and fin
hw_f[hw_f > 0.6] = np.nan               # any remaining merged run
hw_f[z < tip_z + 0.45] = np.nan  # spinner region: a cone, handled by the spinner itself

# Fuselage stations every ~0.25 m from the spinner back to the tail post, plus key stations.
spinner_back = tip_z + m["calibration"]["side"].get("spinner_length_m", 0.68)
stations_z = sorted(set([round(x, 3) for x in np.arange(spinner_back, post_z, 0.25)] + [round(spinner_back, 3), 0.0, round(post_z, 3)]))
rows = []
for zz in stations_z:
    t, b, w = at(deck, zz), at(fus_bottom, zz), at(hw_f, zz)
    rows.append([round(zz, 3), round(w, 3), round(t, 3), round(b, 3), 2.4 if zz < 2.8 else 2.1, 2.0])
# The spinner back ring must match the spinner radius (rounded nose): force half-width = radius there.
sp_r = m["calibration"]["side"]["spinner_radius_at_prop_plane_in"] * IN
rows[0][1] = round(sp_r, 3); rows[0][2] = round(m["spinner"]["axis_y"] + sp_r, 3); rows[0][3] = round(m["spinner"]["axis_y"] - sp_r, 3)
fs["fuselage_stations"] = rows
fs["spinner"] = {"tip_z": round(tip_z, 3), "back_z": round(spinner_back, 3), "radius": round(sp_r, 3), "axis_y": round(m["spinner"]["axis_y"], 3)}
# The builder places the exhaust row from the nose band to firewall_z - 0.45 m (full size): the drawing shows the
# stacks between z -1.52 and -0.54 m, so the model's "firewall" (cowl/fuselage split) is at -0.1 and the cowl panels end
# at the windscreen base.
fs["firewall_z"] = -0.1
fs["cowl_rear_z"] = 0.6
# Scoop stations [z, half_width, bottom]: the dip, with widths estimated from the front view silhouette (not separable
# from the wing there): 0.30 m half-width at the lip tapering to 0.16 at the exit (unchanged estimate).
sz = z[scoop_zone]
lip, exit_ = float(sz.min()) - 0.1, float(sz.max()) + 0.1
scoop = []
for zz in np.linspace(lip, exit_, 7):
    frac = (zz - lip) / (exit_ - lip)
    width = 0.30 if frac < 0.5 else 0.30 - 0.14 * (frac - 0.5) / 0.5
    scoop.append([round(float(zz), 3), round(width, 3), round(at(bot_f, zz) - 0.01, 3)])
fs["scoop_stations"] = scoop
# Canopy top line from the measured contour; the frame (windscreen/bubble joint) at the crown's start.
cz = z[canopy_zone]
canopy_pts = [[round(float(zz), 3), round(at(top, zz), 3)] for zz in np.arange(0.7, 3.05, 0.2)]
fs["canopy"] = {"top": canopy_pts, "frame_z": round(float(cz[np.argmax(top[canopy_zone])]) - 0.25, 3), "halfwidth_fraction": 0.95}
# Carburettor intake: part of the measured top line already; keep a shallow blend.
# The carburettor intake is already inside the measured top line: keep only a shallow blend so it does not protrude.
fs["carb_intake"] = {"z0": round(spinner_back + 0.15, 3), "z1": round(spinner_back + 1.1, 3), "half_width": 0.15, "height": 0.01}
# Wing from the plan metrology.
w = m["wing"]
fs["root_chord_centreline"] = w["root_chord"]; fs["tip_chord"] = w["tip_chord"]
fs["quarter_chord_sweep_deg"] = round(float(np.degrees(np.arctan((w["le_z_tip"] + 0.25 * (w["tip_chord"] - w["root_chord"])) / w["semi_span"]))), 2)
fs["chord_plane_y_root"] = round(-26.5 * IN, 3)  # printed wing reference line
fs["span"] = round(2 * w["semi_span"], 3)
fs["length"] = round(length, 3)
fs["aileron"] = {"inner": 3.25, "outer": 5.50, "chord_fraction": 0.21}
fs["flap"] = {"inner": 0.50, "outer": 3.20, "chord_fraction": 0.21}
# Tail.
st = m["stab"]
stab_y = 0.35
fs["tail"].update({"stab_y": stab_y, "stab_root_le_z": st["root_le_z"], "stab_tip_le_z": st["tip_le_z"], "stab_half_span": st["half_span"],
                   "stab_root_chord": st["root_chord"], "stab_tip_chord": st["tip_chord"],
                   "fin_root_le_z": 5.7, "dorsal_start_z": 4.6, "fin_top_y": m["fin"]["top_y"], "fin_top_le_z": 6.15, "fin_top_chord": 0.6,
                   "rudder_hinge_z": 6.64, "rudder_te_bottom": [round(tail_z, 3), 0.03]})
# Gear: wheel bottoms from the drawing (front view: 0.28 m higher than the first estimate), tail wheel at the bump.
# Main wheel bottom ~82 in below the FRL in the side view (and ~78 in below the spinner axis in the front view): axle at -1.70 m.
fs["gear"].update({"main_axle": [0.10, -1.70], "tail_axle": [5.13, -0.64]})
# Pilot under the canopy crown: a fixed template (full-size metres, from the first estimate) placed so the head centre
# sits 0.15 m behind the crown and the helmet top 0.05 m under it. Absolute, so re-running this script is idempotent.
crown_z = float(z[canopy_zone][np.argmax(top[canopy_zone])])
crown_y = float(top[canopy_zone].max())
template = {"cap_top": [2.72, 0.93], "cap_brim_front": [2.56, 0.84], "nose_front": [2.58, 0.76], "head_back": [2.84, 0.80],
            "chin": [2.62, 0.68], "shoulder_front": [2.55, 0.60], "shoulder_back": [2.95, 0.58]}
dz = (crown_z + 0.15) - (template["nose_front"][0] + template["head_back"][0]) / 2
dy = (crown_y - 0.05) - template["cap_top"][1]
for key, v in template.items():
    fs["pilot"][key] = [round(v[0] + dz, 3), round(v[1] + dy, 3)]
src["evidence"]["full_size.profile"] = {"kind": "measured", "source": "research/p51/p51-02/silhouette/metrology.json: filled silhouettes of the AN 01-60-3 three-view (public domain), each axis calibrated with a printed dimension; applied by apply_metrology.py",
                                        "method": "fuselage top/bottom from the side view, half-widths from the plan (interpolated under the wing and stab), canopy top line, scoop dip, spinner, wing/stab planforms (reserved checks: stab span +0.5 %, wing area +0.6 %, MAC +0.7 %)",
                                        "limits": "the drawing's side view is ~3 % anisotropic (heights vs length); scoop and canopy widths are estimates; the wing root LE extension of the D is not modelled; fin and rudder lines are read from the top contour"}
src["evidence"]["full_size.overall"]["kind"] = "measured"
src["evidence"]["full_size.wing"]["kind"] = "measured"
src["evidence"]["full_size.wing"]["source"] = "plan-view silhouette fit: root chord 105.0 in (extrapolated to the centreline), tip 48.3 in, LE sweep 14.5 in at the tip; dihedral 5 deg and wing reference line 26.5 in below the FRL printed on the drawing"
SOURCE.write_text(json.dumps(src, ensure_ascii=False, indent=2) + "\n")
print(f"stations {len(rows)}, scoop lip {lip:.2f}..{exit_:.2f}, canopy crown z {crown_z:.2f} y {top[canopy_zone].max():.3f}, spinner back {spinner_back:.3f}, tail {tail_z:.3f}")
