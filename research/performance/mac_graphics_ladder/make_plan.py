"""Write the DT-MAC-03b graphics ladder plan. Usage: make_plan.py <plan.json> <smoke-plan.json>

The ladder is cumulative: each step adds options to the previous one, so a step's delta is the marginal cost
on top of the earlier state, not an option's standalone cost. Five ladder passes alternate direction
(ascending, descending, ascending, descending, then ascending again after the soaks) so order and heat bias
cancel in the mean, and a reference run (REF = L09) is inserted every ten runs to expose drift.
"""
import json
import sys

steps = [
    ("L00", "Floor: every option at its minimum", {}),
    ("L01", "+ Scene detail Medium (Automatic's M1 choice)", {"scene_detail": "medium"}),
    ("L02", "+ MSAA 2x", {"msaa_3d": 1}),
    ("L03", "+ Projected shadows and planar aircraft cue", {"shadow_technique": "projected", "shadow_aircraft_cue": "auto"}),
    ("L04", "+ Native sun shadows (technique Automatic) with Automatic distance (300 m) and softness (PCF); "
            "atlas still Low (2048, filter 1)",
     {"shadow_technique": "auto", "shadow_distance": "auto", "shadow_softness": "auto"}),
    ("L05", "+ Shadow quality Current (Standard: 4096 atlas, 16-bit, 2 cascades, filter 2)", {"shadow_quality": "current"}),
    ("L06", "+ Cloud shadows on the ground", {"shadow_cloud": "on"}),
    ("L07", "+ Scenery life bundle: birds Normal, flags Automatic, runway meadow, RC track Automatic",
     {"birds": "normal", "flag_animation": "auto", "runway_meadow": "on", "rc_track": "auto"}),
    ("L08", "+ Lens/impact effects (Automatic, curtain, rain, grime) and aircraft lighting Standard+VFX "
            "(mostly crash/weather/night effects: expected near zero in the daytime orbit)",
     {"lens_effects": "auto", "impact_effects": "curtain", "lens_rain": "on", "lens_grime": "on",
      "aircraft_lighting_quality": "standard", "aircraft_lighting_show_vfx": True}),
    ("L09", "+ MSAA 4x (= product defaults with Scene detail Medium)", {"msaa_3d": 2}),
    ("L10", "+ Scene detail High (props, 3D field trees within 60 deg, LOD 1 px, worn-path turf)", {"scene_detail": "high"}),
    ("L11", "+ Shadows High (4096, 32-bit, 4 cascades, filter 3), Far 600 m, Soft",
     {"shadow_quality": "high", "shadow_distance": "far", "shadow_softness": "soft"}),
    ("L12", "+ Scene detail Extreme (every nearby field tree in 3D)", {"scene_detail": "extreme"}),
    ("L13", "+ Shadows Ultra (8192, filter 4), lens Ultra, aircraft lighting High, birds Many, flags Detailed, "
            "splatter", {"shadow_quality": "ultra", "lens_effects": "ultra", "aircraft_lighting_quality": "high",
                         "birds": "many", "flag_animation": "detailed", "impact_effects": "splatter"}),
    ("L14", "+ MSAA 8x", {"msaa_3d": 3}),
]
configs = {}
cumulative = {}
for name, label, delta in steps:
    cumulative = dict(cumulative, **delta)
    configs[name] = {"label": label, "display": dict(cumulative)}
configs["L15"] = {"label": "L14 on the High renderer (Forward+/Metal)", "display": dict(configs["L14"]["display"]),
                  "renderer": "forward_plus"}
ladder = [name for name, _l, _d in steps] + ["L15"]
L09 = configs["L09"]["display"]
L13 = configs["L13"]["display"]
configs["REF"] = {"label": "Reference: L09 repeated every ten runs (drift)", "display": dict(L09)}
product_defaults = {
    "msaa_3d": 2, "reconstruction": "auto", "scene_detail": "auto", "flag_animation": "auto", "birds": "normal",
    "runway_meadow": "on", "rc_track": "auto", "aircraft_lighting_quality": "standard", "aircraft_lighting_show_vfx": True,
    "shadow_quality": "current", "shadow_technique": "auto", "shadow_aircraft_cue": "auto", "shadow_distance": "auto",
    "shadow_softness": "auto", "shadow_cloud": "on", "lens_effects": "auto", "impact_effects": "curtain",
    "lens_rain": "on", "lens_grime": "on",
}
configs["AUTO"] = {"label": "Product defaults (every Automatic choice), borderless 1080p, VSync off",
                   "display": dict(product_defaults)}
configs["OOB"] = {"label": "Fresh-install display defaults: windowed Automatic size, VSync on (no first-run "
                           "defaults exist for the M1; calibration file removed)",
                  "display": dict(product_defaults, vsync_mode="enabled", window_mode="windowed",
                                  window_resolution="auto")}
configs["R720"] = {"label": "L09 windowed 1280x720", "display": dict(L09), "resolution": "1280x720", "windowed": True}
configs["R900"] = {"label": "L09 windowed 1600x900", "display": dict(L09), "resolution": "1600x900", "windowed": True}
configs["MFXS-Q"] = {"label": "L09 + MetalFX Spatial Quality", "display": dict(L09, reconstruction="metalfx_spatial_quality")}
configs["MFXS-85"] = {"label": "L09 + MetalFX Spatial 85%", "display": dict(L09, reconstruction="metalfx_spatial_85")}
configs["MFXT-Q"] = {"label": "L09 + MetalFX Temporal Quality (MSAA off: two variables change)",
                     "display": dict(L09, reconstruction="metalfx_temporal_quality", msaa_3d=0)}
configs["MFXT-N"] = {"label": "L09 + MetalFX Temporal Native AA (MSAA off: two variables change)",
                     "display": dict(L09, reconstruction="metalfx_temporal_native", msaa_3d=0)}
configs["L13-MFXS"] = {"label": "L13 + MetalFX Spatial Quality", "display": dict(L13, reconstruction="metalfx_spatial_quality")}
configs["X01"] = {"label": "L09 on the High renderer (Forward+/Metal)", "display": dict(L09), "renderer": "forward_plus"}
configs["V-L00"] = {"label": "L00 with VSync (60 Hz)", "display": dict(configs["L00"]["display"], vsync_mode="enabled")}
configs["V-L09"] = {"label": "L09 with VSync (60 Hz)", "display": dict(L09, vsync_mode="enabled")}
configs["V-L13"] = {"label": "L13 with VSync (60 Hz)", "display": dict(L13, vsync_mode="enabled")}
configs["G-L09"] = {"label": "L09 at Green Paradise", "display": dict(L09), "landscape": "green_paradise"}
configs["G-L13"] = {"label": "L13 at Green Paradise", "display": dict(L13), "landscape": "green_paradise"}
configs["N-L09"] = {"label": "L09 at night", "display": dict(L09), "time": "night"}
configs["N-L13"] = {"label": "L13 at night", "display": dict(L13), "time": "night"}
configs["S-L09"] = {"label": "L09 soak: 12 two-lap windows (about 14 minutes)", "display": dict(L09), "windows": 12}
configs["S-L13"] = {"label": "L13 soak: 12 two-lap windows (about 14 minutes)", "display": dict(L13), "windows": 12}

sweep = ["R720", "R900", "MFXS-Q", "MFXS-85", "MFXT-Q", "MFXT-N", "L13-MFXS", "X01"]
extras = ["V-L00", "V-L09", "V-L13", "G-L09", "G-L13", "N-L09", "N-L13"]
first = {"screenshots": True, "restart_timing": True}
body = [{"config": c, "pass": 1, "overrides": first} for c in ["AUTO", "OOB"] + ladder]
body += [{"config": c, "pass": 1, "overrides": first} for c in sweep + extras]
body += [{"config": c, "pass": 2} for c in list(reversed(ladder)) + list(reversed(sweep))]
body += [{"config": c, "pass": 3} for c in ladder]
body += [{"config": c, "pass": 4} for c in reversed(ladder)]
runs = []
for index, run in enumerate(body):
    if index % 10 == 0:
        runs.append({"config": "REF", "pass": index // 10 + 1})
    runs.append(run)
runs.append({"config": "REF", "pass": len(body) // 10 + 2})
runs += [{"config": "S-L09", "pass": 1, "overrides": {"screenshots": True}},
         {"config": "S-L13", "pass": 1, "overrides": {"screenshots": True}}]
# Pass 5, appended so earlier run indices never change, repeats every configuration ascending. Passes 2-5 then
# hold two ascending and two descending ladder runs without pass 1's screenshots and restart timing, and every
# single-pass configuration gets a second sample.
reference = len(body) // 10 + 2
for index, config in enumerate(["AUTO", "OOB"] + ladder + sweep + extras):
    if index % 10 == 0:
        reference += 1
        runs.append({"config": "REF", "pass": reference})
    runs.append({"config": config, "pass": 5})
runs.append({"config": "REF", "pass": reference + 1})
json.dump({"configs": configs, "runs": runs}, open(sys.argv[1], "w"), indent=1)
json.dump({"configs": configs, "runs": [{"config": "L00", "pass": 0, "overrides": first},
                                        {"config": "OOB", "pass": 0, "overrides": first}]},
          open(sys.argv[2], "w"), indent=1)
print(len(runs), "runs;", len(configs), "configs")
