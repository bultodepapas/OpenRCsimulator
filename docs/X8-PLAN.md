# X8 flying wing: integration plan

Checked 2026-10-25 · Aircraft/model owner · Prefix **X8-00…12**. The X8 is a 2.12 m EPO flying wing inspired by the Skywalker X8: two elevons, winglets without rudders, an electric pusher and no landing gear (hand launch, belly landing). The owner delivered its Blender game model r4 on 2026-10-25 and asked for a robust catalog integration that reuses the other aircraft's data and a more crash-tolerant foam airframe. This plan states what is done, what is open and how each step is proven. Implementation, passing software checks and physical validation remain separate claims.

## 1. Identity and scope

One configuration: the delivery's UAV build (mapping-camera bay, parachute pack, magnetic hatch, 6S pack), physics from the NTNU Skywalker X8 studies (wind tunnel, CFD and flight identification) and the shared electric, battery and contact laws. The visual model is the author's parametric r4 (`abisal` default skin, `bolido` second skin). Catalog ID and visual family: `skywalker-x8`.

## 2. Gaps found in the shared code

The X8 is the first catalog aircraft outside the conventional wing-tail/tractor/geared family. The [standardization plan](plans/aircraft-standardization.md#control-surfaces-and-actuators) rules that elevons, a flying-wing aero layout and a pusher each need an explicit capability, not a data trick. Each extension below is opt-in: existing aircraft keep byte-identical data, trims and golden flights.

| Gap | Evidence | Resolution |
| --- | --- | --- |
| No elevon mixing; four conventional surfaces required | `controls: conventional` only; `ControlSurfaces`, `_controls()`, model roles and identity surfaces fixed to aileron/elevator/rudder | **X8-03** `controls: elevon`: radio-style mix with pitch and roll shares and servo end-point saturation; physics receives the exact symmetric/antisymmetric decomposition; no rudder (zero throw, zero rudder derivatives, zero fin control effectiveness); trim replaces the rudder unknown with bank angle |
| The local aero law needs a horizontal tail | `aero.surfaces.horizontal` mandatory; every wing strip acts at the reference point | **X8-04** optional capability `airframe_layout: tailless`: no horizontal element; wing strips at their own swept quarter-chord stations; elevons act on their strips with a section camber couple; the loader solves effectiveness, station offset and section moment so the local wing reproduces the oracle's CLδe, Cmδe, Cmα and Cm0 |
| Pusher not representable | `single_tractor` forced for every propeller | **X8-05** `propulsion_layout: single_pusher`: propeller aft of the CG, axial thrust; no wake modules (electric has none) |
| No crash tolerance per airframe | Terminal hull energy and depth are global constants | **X8-08** `damage: tolerant_hull` with an evidence-bearing `crash_tolerance` block threaded into the contact policy, its law identity and the crash presentation |
| No hand launch | Gearless aircraft fall back to a trimmed start at 30 m | **X8-07** `hand_launch` start choice for airplanes without landing gear |
| Elevon hinges are not a model role | Model manifest roles closed | **X8-02** roles `elevon_left`/`elevon_right`, exclusive of the conventional four |

## 3. Steps

| ID | State | Work / proof |
| --- | --- | --- |
| X8-00 | Done 2026-10-25 | Delivery r4 frozen in `assets/source-deliveries/skywalker-x8-r4/` without images (owner rule) or the demo GLB; zip kept local in `references/source-deliveries/`. [manifest.py](../research/skywalker-x8/X8-00/manifest.py) writes [source-manifest.json](../assets/aircraft/skywalker-x8/source-manifest.json): 50 of 147 author hashes match, 97 omitted by rule. Both GLBs pass the generic preflight (38,504 triangles, 9 materials, span 2.117 m). |
| X8-01 | Done 2026-10-25 | [Sources](research/skywalker-x8/X8-01/README.md): NTNU wind tunnel, CFD and flight identification (2018–2026), measured part masses and inertia, retail specifications, UIUC propeller data, EPO material data; 36 records in [sources.json](research/skywalker-x8/X8-01/sources.json), local copies in `references/skywalker-x8/`. |
| X8-02 | Done 2026-10-25 | [Model family](research/skywalker-x8/X8-02/README.md): both skins in `app/assets/aircraft/skywalker-x8/`, `compile_model.py` geometry, elevon model roles exclusive of the conventional four (`model_manifest.gd`, `imported_model.gd`, `build_models.py`). Proof: `verify_skywalker_x8.gd` 36/36, `test_elevon_model_contract.gd` 25/25, `test_models.py` 19/19, F4U and livery suites unchanged. |
| X8-03 | Done 2026-10-25 | Elevon controls: radio mix with end-point clipping, no rudder, bank-angle trim ([X8-04 evidence](research/skywalker-x8/X8-04/README.md)). |
| X8-04 | Done 2026-10-25 | Tailless strip law with loader-derived elevon effectiveness, station shift, section moment and elevon couple ([evidence](research/skywalker-x8/X8-04/README.md)). Proof: golden flights 4/4 unchanged, `test_x8_flying_wing.gd` 37/37, contract 3587/0, schema–loader agreement 112/0. |
| X8-05 | Done 2026-10-25 | `single_pusher` for electric propellers, hub aft of the CG required. |
| X8-06 | Done 2026-10-25 | [Physics data](research/skywalker-x8/X8-06/README.md) from [derive_physics.py](../research/skywalker-x8/X8-06/derive_physics.py): 3.13 kg, CG 435 mm (4.4 % MAC margin), 28-point hull from the drawn model, ideal-bus and 6S-pack files. |
| X8-07 | Done 2026-10-26 | [Hand launch](research/skywalker-x8/X8-07/README.md): start choice `hand_launch` for airplanes without landing gear (session, Home, preferences, `--start`, Quick Flight, trace, Spanish). Released from the runway edge in front of the pilot, 1.9 m up, into the along-runway wind, wings level at +5°, 6.5 m/s over the ground (estimated), motor at full throttle; refusals fail closed. Proof: `test_hand_launch.gd` 136/0 (including a dead-motor control), Home and preference suites, golden flights unchanged, running app via the debug bridge. A measured throw belongs to X8-11. |
| X8-08 | Done 2026-10-25 | `tolerant_hull`: 12.5 J/kg and 0.12 m terminal thresholds, presentation durability 4 (estimates). A 3 m/s belly touchdown is survivable; under the shared balsa thresholds it is terminal. |
| X8-09 | Done 2026-10-25 | Catalog (experimental, after the Turbo Lumber), Spanish texts, Workshop descriptor, [economy dossier](research/skywalker-x8/X8-09/economy.md) (12 of 19 lines priced, the rest explicitly unpriced), parked bakes, fleet lists and counts. |
| X8-10 | Done 2026-10-25 | [Verification](research/skywalker-x8/X8-10/README.md): fleet suites, flight-test card v5 30/40 valid with no script errors. |
| X8-11 | Owner | Physical evidence: piloted `.orfl`, measured mass/CG/throws of a real X8. |
| X8-12 | Done 2026-10-26 | [Optimization round](research/skywalker-x8/X8-12/README.md): electric trim stops at its residual floor (X8 launch trim 5.9× faster, Timber 4.6×), generic trim reuses the steady rpm across surface probes (glow 1.6×, bit-identical), one cached data load answers both ground starts. Tick cost, data load and model asset measured and left unchanged. |

## 4. Owner decisions

| ID | Decision | State |
| --- | --- | --- |
| D1 | Display name: the delivery leaves it to the owner; "Skywalker" and "X8" are Skywalker Technology product names | Pending; working name "X8 Flying Wing" |
| D2 | Asset licence terms (`LICENSE.txt`: not set) | Pending; F4U-13's reasoning may apply, but only the owner can extend it |
| D3 | Configuration | Delivery UAV build, 6S pack (working choice) |
