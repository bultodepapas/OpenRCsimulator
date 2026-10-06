# P-51D 1/4 flight realism: research, corrections and flown envelope

2026-10-06 · Revision 1 · **P51-06, P51-08, P51-09, P51-12 and P51-13 done:** the P-51D's physics is cross-checked against NACA flight data and RC-class data, the engine/propeller/ground effects it lacked are modelled, and the envelope is flown by 26 checks. Plan: [P51-PLAN](../P51-PLAN.md) · Derivation: [derivation.md](../../research/p51/p51-05/derivation.md) · Evidence: [research/p51/](../../research/p51/) (`p51-06` propeller/engine, `p51-08` envelope bands, `p51-13` section and stall).

## What was done

1. Three research passes: full-size P-51 aerodynamics (NACA wartime reports), giant-scale RC P-51 data (kits, plans, manuals, propeller datasheets, forum numbers), and modelling methods (engine/propeller torque balance, P-factor, slipstream, low-Re sections, spanwise stall).
2. Every important parameter compared with the evidence; mismatches corrected in `source.json` and `research/p51/p51-05/derive_physics.py` (regenerated data, no hand edits).
3. Five effects added to the physics as **per-aircraft opt-in** data blocks (absent = previous behaviour bit for bit; Stik goldens unchanged): shaft-balance rpm, thrust-line angles, propeller normal force and P-factor, tail slipstream with swirl, per-strip wing incidence. Plus a taildragger gear for the P-51 and a propeller-strike crash hull.
4. The envelope flown by closed-loop pilots in the real session loop: `app/tests/test_p51_envelope.gd` (15 checks) and `test_p51_ground.gd` (11), on top of `test_p51_handling.gd` (15).

## Sources

Evidence levels: **V** primary source read, **S** reputable secondary, **Sn** search snippet only, **C** computed here.

| ID | Source | Level | Used for |
| --- | --- | --- | --- |
| A | NACA, *Flying Qualities and Stalling Characteristics of North American XP-51* (1942), [ntrs 19930092575](https://ntrs.nasa.gov/citations/19930092575) | V | chords, incidences, stab +2°, tail areas, aileron geometry, neutral points (glide 34.2 % MAC), CLmax, stall behaviour |
| B | NACA ACR 4K02, P-51B drag (1945), [ntrs 19930092458](https://ntrs.nasa.gov/citations/19930092458) | V | washout (root +1°00', tip −0°53'), t/c, CD0 0.021-0.023 |
| C, D | NACA RM L6J25 and RM L5E05b (P-51D), [ntrs 20050019329](https://ntrs.nasa.gov/citations/20050019329), [ntrs 20150019958](https://ntrs.nasa.gov/citations/20150019958) | V | rudder ±30°, fin offset 1° left, CG 25.5 % MAC as tested |
| E | NACA MR L6F12, XP-51 drag in flight, [ntrs 19930093005](https://ntrs.nasa.gov/citations/19930093005) | V | airplane zero-lift angle −1.3° from the thrust line |
| F | Loftin & Smith, NACA TN 1945 (6-series sections at Re 0.7-9e6), [ntrs 19930082618](https://ntrs.nasa.gov/citations/19930082618) | V | section lift slope 0.86·2π, clmax(Re), rounded low-Re stall, Cm theory/measured ratio |
| G | Loftin, NASA SP-468, [ntrs 19850023776](https://ntrs.nasa.gov/citations/19850023776) | S | Oswald e 0.70-0.75 |
| H | UIUC/Lednicer P-51D root and tip ordinates, [m-selig.ae.illinois.edu](https://m-selig.ae.illinois.edu/ads/coord_database.html) | S | real camber lines → α0, Cm_ac (`research/p51/p51-13/`) |
| I | Mejzlik propeller datasheets 26x12 2B/3B, 28x10 2B, [mejzlik.eu/propeller-data](https://www.mejzlik.eu/propeller-data) | V (manufacturer-simulated data) | propeller model calibration, inertias, the engine's power anchor |
| J | Falcon/Mejzlik 28x10 on a DA-120: 6550 rpm static (FlyingGiants threads 200294, 53861) | Sn (three consistent reports) | installed engine power |
| K | Desert Aircraft DA-120 page, [desertaircraft.com](https://www.desertaircraft.com/products/da-120) | V | 11.7 hp rating, 1300-6900 rpm, propeller list |
| L | Hangar 9 Mustang 1.50 manual ([astramodel.cz](https://www.astramodel.cz/manualy/hangar9/hangar9_mustang_150.pdf)), Hangar 9 60cc, Top Flite Giant, Ziroli 98 in plans | V | throws (18/15/30°), CG, down/right thrust, washout practice |
| M | Built weights: Don Smith 112 in thread ([giantscalenews.com](https://www.giantscalenews.com/threads/don-smith-p-51-mustang.10787/)), Bates "50 lb+", Veich 18-27 kg | V | flight mass 21.5 kg |
| N | Selig, *Modeling Propeller Aerodynamics and Slipstream Effects on Small UAVs in Realtime*, AIAA 2010-7938 | V (PDF text) | slipstream wash factors 0.8/1.8, McCormick normal force and P-factor |
| O | Ribner, NACA TR 819 (propellers in yaw) | V | cross-check of the normal force (agrees within ~20 %) |
| P | JSBSim and YASim piston-engine models (source code) | S | throttle as admitted air flow, friction share |

Full source lists with URLs are kept in the step folders; downloaded PDFs and hashes are in the gitignored `references/p51-mustang/` (`propellers/`).

## Corrections (before → after)

| Quantity | Before | After | Kind | Why |
| --- | --- | --- | --- | --- |
| Root/tip chord | 104/50 in (unresolved vs 101.8/46.4) | 104/50 in, **resolved** | measured | A, B: 103.99 in at the centreline, 50 in at station 215; 101.8/46.4 came from student slides only |
| Washout | 0 | **1.88°** linear | measured | B: +1°00' root, −0°53' tip (NAA quotes 2°) |
| Stab incidence | 0 | **+2°** to the fuselage axis | measured | A, B (normal setting) |
| Aileron | 0.21 chord, 2.25 m span (full size) | **0.19** chord, 2.123 m | measured | A, F |
| Section lift slope | 0.95·2π | **0.86·2π** | measured (6-series at Re 0.7-1e6) | F |
| Section α0 / Cm_ac | −1.47° / −0.020 (parabolic camber) | **−1.37° / −0.029** | derived | real UIUC camber lines (aft-loaded), thin airfoil × 0.8 (F) |
| Airplane zero-lift angle | −2.1° | −1.6° | derived | A/E measure −1.3°: now within 0.3° |
| Neutral point (power off) | 38.5 % MAC | **34.2 % MAC** | calibrated | A: measured glide value; one lumped fuselage/scoop/propeller term (K_fus 0.033/deg) |
| Static margin at 27 % CG | 11.5 % | 7.2 % | derived | full size: ~5-9 % |
| CL_max | 1.15 (guess) | **1.02** | derived | F clmax at the model's chord Reynolds numbers, Schrenk loading, washout, finish −0.05 |
| Stall start | equal on all strips | mid-span strip first (+0.43°), root last | derived | lifting line (η 0.49 with 2° washout); A: glide stall broke first at mid-semispan |
| Oswald e | 0.80 | **0.75** | secondary | G |
| Flight mass | 18.2 kg (plan weight) | **21.5 kg** | estimated | M: 1/4-scale P-51s with retracts and 120 cc weigh 50-55 lb; CARF 2.54 m scaled gives 20.5-23 kg |
| Throws (high) | 16.3/15.8/32.0° (mm scaled) | **18/15/30°** | manual | L (degrees printed); full-size rudder ±30° (C) |
| Propeller model | generic BEM, 5751 rpm, 32.6 kgf static | **BEM calibrated on Mejzlik** (rms 6.5 %), **4951 rpm, 24.0 kgf** | derived | I, J: the old flat-torque curve gave 8.5 kW at 5751 rpm; a DA-120 delivers ~5.5 kW at that load (6.9 kW at 6550 rpm) |
| Engine | rpm = lag toward a throttle target | **shaft balance** J·dω/dt = Q_engine − Q_prop; installed power 6.9 kW at 6550 rpm (rating 11.7 hp is 24 % higher) | derived | J, K, P |
| Rotating inertia | 0.013 kg·m² | 0.0197 kg·m² | estimated | I (per-blade inertias) + crank |
| Thrust line | axial | **1.75° down, 1° right** | estimated | L (Top Flite, Ziroli); no full-size value published |
| P-factor, normal force | none | McCormick tables per J | derived | N, O |
| Tail slipstream | none | momentum theory, wash 0.8→1.8·w, free-vortex swirl × 0.6, decayed with the wash | borrowed/estimated | N |
| Landing gear | crash hull only | taildragger contacts, steerable tail wheel (−25°), grass surfaces | measured geometry, estimated springs | geometry.json, E1/E2 rules |
| Crash hull | wheels as crash points | propeller disc bottom added (prop strike) | derived | geometry.json |

## Flown envelope (2026-10-06)

| Item | Result | Expected (source) |
| --- | --- | --- |
| 1-g stall power off / on (30 %) | 14.6 / 13.1 m/s | Vs 15.7 from CL_max; power lowers it |
| Wing drop at the stall | left, −20° and growing; full up held → snap to −130° in 1 s | A: wing drop and snap; RC: left wing in power-on stalls |
| Takeoff run without rudder | −30° heading in 3 s | strong left swing (manuals: "be ready with right rudder") |
| Takeoff with rudder | 47 % right rudder, lift-off 39 m, 22.8 m/s, 4.1 s | roll 20-50 m (RC estimate) |
| Maximum level speed | 51.4 m/s (115 mph), 7082 rpm | Top Flite Giant owner: ~115 mph; propeller zero thrust at J 0.8 |
| Climb at 1.4 Vs, full throttle | 14 m/s (40°) | T/W 1.1 static |
| Idle glide at 1.4 Vs | L/D 7.1, propeller windmilling at 2570 rpm | clean airframe 8.7; big props brake |
| Roll rate, full high-rate aileron | 99 / 117 / 152 °/s at 20 / 25 / 35 m/s | grows with speed |
| Modes (20-40 m/s) | short period ζ 0.75-0.86; dutch roll ζ 0.19-0.22; spiral doubles in 8-29 s | MIL-F-8785C Level 1-2 |
| Wheel landing | touchdown 19.8 m/s, 1.0 m/s sink, one bounce, rollout 156 m without brakes | manuals: wheel landings, three-pointers bounce |

Pilot technique matters as on the real model: pulling to 16° at 17 m/s after touchdown drops a wingtip; a hard pull-out after a stall re-stalls it. Both were seen while tuning the test pilots.

## Findings

- **Pitch trim needs 6° of up elevator at 25 m/s** (41 % of the high-rate throw) with the measured full-size rigging (wing +1°, stab +2°) and the aft-loaded section's Cm_ac. RC designers rig with positive decalage (Ziroli: wing +2.5°, stab +1°); a builder would reduce the stab incidence. Kept full-size; revisit with a pilot (Gate 2).
- **Cruise needs little power:** 14 % throttle holds 25 m/s (drag ~30 N). The throttle maps linearly to admitted power; a real carburettor is more progressive.
- **Idle creeps** on the grass strip (19 N of idle thrust against 16 N of rolling resistance); no brakes are simulated.
- The **4-blade 26x12 is heavy for a 120 cc** (Biela rates it for 150-160 cc; the DA-120 list gives 3-blade 26x12 / 27x12). Kept for the scale look; changing the propeller is a data change (`source.json` → `fit_mejzlik.py` already covers 2- and 3-blade).

## Open uncertainties

- Thrust-line angles of the full-size airplane: not published (JSBSim and FlightGear values are uncited).
- Measured moments of inertia: none for the P-51D (JSBSim's are uncited); the model's come from the component inventory.
- The 4-blade propeller table is a calibrated prediction; Mejzlik's data are simulated, not measured. The windmilling branch is uncalibrated.
- Engine torque shape (no DA-120 dyno curve) and the static-rpm anchor (snippet-level reports).
- Slipstream: factors from one RC airplane (Selig); no wash lag; no wing wash.
- No real-model flight identification: the next proof is a pilot's verdict (Gate 2) and, ideally, logged flights of a real 1/4-scale P-51.

## Reproduce

```
python3 research/p51/p51-13/section_camber.py      # needs the UIUC .dat files (references/), writes section.json
python3 research/p51/p51-06/fit_mejzlik.py         # writes calibration.json (~20 s)
python3 research/p51/p51-05/derive_physics.py      # writes the data file and derivation.md (--check, --dry)
$(app/get-godot.sh) --headless --path app --script res://tests/test_p51_envelope.gd
$(app/get-godot.sh) --headless --path app --script res://tests/test_p51_ground.gd
```
