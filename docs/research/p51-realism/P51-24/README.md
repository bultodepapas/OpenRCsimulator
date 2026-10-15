# P51-24: lateral-directional audit against P-51 flight data; rudder area corrected

2026-10-15 · Revision 1 · **Status: rudder area corrected in the physics and verified. Directional stability remains about 2–3.5× too high relative to rudder power, and the remaining fix is a shared fuselage term. The visual rudder outline is still narrow.** The fuselage term followed in [P51-25](../P51-25/README.md). Prefix: P51-24. [Plan](../../../P51-REALISM-PLAN.md)

## Method

[`sideslip_probe.gd`](../../../../research/p51/p51-24/sideslip_probe.gd) solves steady straight sideslips on the runtime equations. The sideslip is imposed, and α, elevator, throttle (or flight path for a glide), bank, aileron and rudder are solved with all six accelerations zero. It reports rudder, aileron and bank per degree of sideslip at ±1° and ±2°. Full-size ratios are dimensionless and compared at equal CL:

- [NACA RM L6J25, Table I](sources/rm-l6j25-table1.png) ([NTRS 20050019329](https://ntrs.nasa.gov/citations/20050019329)): production P-51D, clean, climb power, ±1° sideslip. The report calls the values approximate.
- [NACA MR L-566, Figure 39](sources/mr-l566-fig39-sideslip.png): XP-51 cruise, CG 25.3 % MAC.

## Findings

| Per degree of sideslip | XP-51 cruise | P-51D, production tail | Model before | Model after |
| --- | --- | --- | --- | --- |
| Rudder | ≈0.85 ("nearly 1°") | 0.46 / 0.55 / 0.31 at 103 / 200 / 350 mph | 2.08 glide; 2.0–2.4 level | **1.75 glide; 1.7–2.0 level** |
| Aileron (dihedral effect) | ≈0.20–0.24 | — | 0.19 | 0.19 |
| Bank (side force), CL ≈ 0.31 | ≈1.0 | — | ≈0.84 | ≈0.84 |

The dihedral effect and side force agree within about 15–20 %. The rudder needed per degree of sideslip did not. RM L6J25 attributes its pilots' difficulty holding steady sideslips to "the low rudder-fixed directional stability of the airplane", while the model was about four times stiffer relative to its rudder.

### Cause 1, corrected: rudder area

Both NACA dimension tables give the production P-51D vertical tail as 20.02 ft², fin 9.61 ft², so the rudder is 10.41 ft² (including the 0.81 ft² tab), with ±30° travel. RM L6J25 Figure 5 [draws the rudder](sources/rm-l6j25-fig5-rudders.png): 26 in maximum chord behind the hinge and about 15–17 in near the top.

The P-51 geometry put the hinge at 6.64 m. That was an unmeasured constant in `apply_metrology.py`, and it leaves only 7.2 ft² of the measured silhouette aft of the hinge; the physics generator's exposed fraction was 0.253. Solving the hinge so the measured full-size silhouette aft of it has 10.41 ft² gives z = 6.488 m. This independently reproduces the published 26 in maximum chord (25.2 in) and 74 in span (77.4 in, including the rounded top).

[`derive_physics.py`](../../../../research/p51/p51-05/derive_physics.py) now computes this aerodynamic hinge from the silhouette and the NACA area. It uses the hinge only to split the existing side polygon, so Sv, its centroid, the inventory and every other coefficient are bit-identical. Exactly four values change:

| Value | Before | After |
| --- | ---: | ---: |
| rudder area fraction (exposed polygon) | 0.253 | 0.375 |
| `surfaces.vertical.control_effectiveness` | 0.449208 | 0.533637 |
| `Cndr` / `CYdr` / `Cldr` | −0.06266 / 0.12781 / 0.01657 | −0.07444 / 0.15183 / 0.01969 |

**The visual model is unchanged.** Moving the visual hinge to 6.488 m fails `verify_p51` ("tail cone ends ahead of the rudder hinge"). On the real airplane the lower rudder continues the fuselage outline aft of the sternpost, so the builder would have to split the tail cone. That is a visual rework for owner review, not part of this step. The narrow visual rudder is an open visual item.

### Cause 2, open: directional stability without a fuselage term

The model's Cnβ = 0.1397 is the fin alone. The shared surface-consistency rule (`AircraftData`, "inconsistent with vertical surface force/arm") requires Cnβ to equal the fin's contribution, so the generator's DATCOM fuselage estimate (−0.023/rad) is computed but omitted for every fixed-wing aircraft. To bring rudder per sideslip to 0.5–0.85 with the corrected rudder, total Cnβ must be about 0.04–0.06/rad, a reduction of about 0.08–0.10. The fuselage estimate supplies about a quarter of that. The rest comes from the bubble-canopy fuselage, the large spinner and the propeller in sideslip at climb power, which the full-size data include. A supported fuselage side-force and yaw element, applied consistently in the attached oracle and the local model, is a shared contract change for the aircraft-standardization and physics owners. It is proposed here, not implemented. **Follow-up:** implemented as the opt-in `aero.surfaces.body_cn_beta` in [P51-25](../P51-25/README.md), calibrated about the CG.

## Runtime evidence

Godot 4.7.2, native Windows. Baseline and candidate share the tree, with only the P-51 JSON and Workshop descriptor changed ([sideslip before](baseline-sideslip.txt), [after](candidate-sideslip.txt), [logs](tests/)).

- **Model contract:** `verify_p51` 248/248, `verify_p51_clearance` 12/12. The geometry is unchanged.
- **Other tests:** `test_runway_start`, `test_prop_strike`, `test_aircraft_data`, `test_aircraft_catalog` and `test_trim` pass. The P51-15 inventory oracle passes.
- **P-51 failures:** the three known ones (P51-19 stall recovery, P51-22 lift-off and loop), with the loop at 345° instead of 343°. `test_rudder_authority` uses the Ugly Stik, and its values are byte-identical.
- **Probes ([240 Hz](candidate-airborne-240.json), [480 Hz](candidate-airborne-480.json), ground [240](candidate-ground-240.json) and [480](candidate-ground-480.json) against [baseline](baseline-airborne-240.json)):** all 34 airborne and 5 ground cases complete. Rudder-pulse peak yaw rate and sideslip rise 16–19 %. The trim rudder command falls from 0.109 to 0.092. The heading-hold takeoff peak right rudder falls from 0.52 to 0.46 and its maximum heading error from 8.2° to 7.1°. 240/480 Hz agree within 0.2 %.

## Limits

The ratios compare dimensionless full-size data with a model whose Reynolds number and propeller differ. RM L6J25 values are approximate slopes over ±1°, and the XP-51 had a razorback fuselage without the D's dorsal fin. The aerodynamic-hinge solve assumes the measured silhouette outline is correct. The P-51D power effect on directional stability is not separated in the data.
