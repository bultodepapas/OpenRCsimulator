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
| No hand launch | Gearless aircraft fall back to a trimmed start at 30 m | **X8-07** hand-launch start for gearless aircraft |
| Elevon hinges are not a model role | Model manifest roles closed | **X8-02** roles `elevon_left`/`elevon_right`, exclusive of the conventional four |

## 3. Steps

| ID | State | Work / proof |
| --- | --- | --- |
| X8-00 | Done 2026-10-25 | Delivery r4 frozen in `assets/source-deliveries/skywalker-x8-r4/` without images (owner rule) or the demo GLB; zip kept local in `references/source-deliveries/`. [manifest.py](../research/skywalker-x8/X8-00/manifest.py) writes [source-manifest.json](../assets/aircraft/skywalker-x8/source-manifest.json): 50 of 147 author hashes match, 97 omitted by rule. Both GLBs pass the generic preflight (38,504 triangles, 9 materials, span 2.117 m). |
| X8-01 | In progress | Sources: NTNU X8 aero studies (already in the [flying-wing library](research/flight-dynamics/rc-validation-library-2026-10-18/flying-wings/README.md)), manufacturer data, propulsion, EPO crash behaviour. |
| X8-02 | In progress | Model family and elevon roles. |
| X8-03 | Planned | Elevon controls and rudderless trim. |
| X8-04 | Planned | Tailless local aero law. |
| X8-05 | Planned | Pusher layout. |
| X8-06 | Planned | Physics data generator: mass inventory, inertia, NTNU coefficients, winglets, electric drive and pack, crash hull. |
| X8-07 | Planned | Hand-launch start. |
| X8-08 | Planned | Foam crash tolerance. |
| X8-09 | Planned | Catalog registration: catalog, Spanish texts, Workshop descriptor, economy dossier, fleet lists. |
| X8-10 | Planned | Verification: loader/regime/trim suites, flight-test battery, conformance, golden flights unchanged. |
| X8-11 | Owner | Physical evidence: piloted `.orfl`, measured mass/CG/throws of a real X8. |

## 4. Owner decisions

| ID | Decision | State |
| --- | --- | --- |
| D1 | Display name: the delivery leaves it to the owner; "Skywalker" and "X8" are Skywalker Technology product names | Pending; working name "X8 Flying Wing" |
| D2 | Asset licence terms (`LICENSE.txt`: not set) | Pending; F4U-13's reasoning may apply, but only the owner can extend it |
| D3 | Configuration | Delivery UAV build, 6S pack (working choice) |
