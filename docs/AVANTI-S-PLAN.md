# Avanti S turbine jet: plan

2026-10-12 · Revision 6 · **Status: the Avanti S flies in the catalog as experimental. The visual blockout and commanded-surface rig are integrated; planform metrology, turbine presentation, flap/gear simulation, fuel burn, independent validation and delivery remain open.**

Step-ID prefix `AV-`. Owned paths: `assets/aircraft/avanti-s-a200/`, `app/aircraft/avanti_s_*`, `app/aircraft/verify_avanti.gd`, `app/physics/turbine.gd`, `app/data/aircraft/sebart_avanti_s_a200.json` (generated), `app/tests/test_turbine.gd`, `app/tests/test_avanti_handling.gd`, `research/avanti-s/`, `docs/research/avanti-s-*`.

Research: [family and choice](research/avanti-s-family-research.md) · [resources](research/avanti-s-resources.md) · [integration audit](research/avanti-s-integration-audit.md) · [turbine identity](research/avanti-s-turbine-research.md) · [controls and installation](research/avanti-s-controls-and-installation.md) · [AV-01 metrology](research/avanti-s-av01-metrology.md) · [physics requirements](research/avanti-s-av05-physics-requirements.md) · [turbine dynamics](research/avanti-s-av05-turbine-dynamics.md) · [airframe data](research/avanti-s-av06-airframe-data.md) · [aero references](research/avanti-s-av06-aero-references.md) · **[physics model and validation](research/avanti-s-av06-physics-model.md)**.

## 1. Identity and scope

**SebArt Avanti S Jet 2.2m ARF (A200 original): 2.00 m span, 2.22 m length, 10.5 kg RTF dry with a JetCat P100-RX** (2017 catalog, non-BL, fixed thrust tube). Catalog ID `sebart-avanti-s-a200-p100rx`. Chosen for its documentation and turbine identity, not for sales rank. Other variants (XS, Mini, FC/Krill 2.1 m, current "2.3 m", Freewing EDF) are never mixed into its numbers. The P100-RX-BL is a different documented revision; do not mix its RPM or response data into the 2017 configuration. The 10.5 kg value is dry, not the in-flight mass with fuel. Sources: [manual](https://www.sebart.it/download/AVANTI%20S%20JET%202.2m-Manual%20Intro.pdf), [JetCat 2017 catalog](https://www.jetcat.de/jetcat/Kataloge/JetCat%20Lieferprogramm%202017_web.pdf).

Flight configuration (AV-07): in-air start at 29 m/s, turbine running, flaps up, gear up, half of the 3.2 l stock tank, CG 240 mm (the manual's beginner setting for a P100). Ground contact is a crash until AV-09. The [asset README](../assets/aircraft/avanti-s-a200/README.md) documents the generated geometry, seven hinge names, visual-only flap hook and build contract. The pilot camera, radio arming, pause, reset and recording rules are those of every aircraft.

## 2. Method

Same flow as the other aircraft: declarative geometry → generated data with `{value, unit, kind, source}` on every number → strict loader → float64 physics → tests through the real session loop. Physics data come from [derive_physics.py](../research/avanti-s/av06/derive_physics.py) and its sourced [inputs.json](../research/avanti-s/av06/inputs.json); never edit the generated JSON. Guessed values are labelled `estimated` and swept in [sensitivity.py](../research/avanti-s/av06/sensitivity.py). A disagreement with documented data is resolved in one visible place and reported, never spread over coefficients (see the neutral-point anchor in the [model report](research/avanti-s-av06-physics-model.md#3-stability-and-balance-what-the-blockout-could-not-explain)).

## 3. Steps

| ID | Step | Proof | Status / next evidence (checked 2026-10-12) |
| --- | --- | --- | --- |
| AV-00 | Choose the variant and archive evidence | sources, hashes, git exclusion | ✅ 2026-10-05 |
| AV-01 | Datum and minimum geometry | traceable dimensions; discrepancies shown | provisional: no calibrated planform exists; root LE station, root chord, stab and fuselage width still to measure (they decide the neutral point) |
| AV-02 | Visual model and app preview | inspector views, scale, joints and contour comparisons (revisions 2–4) | Integrated as a blockout; planform and hidden geometry remain estimated |
| AV-03 | Catalog and propeller-free adapter | `verify_avanti.gd`, catalog and UI tests | ✅ 2026-10-06 |
| AV-04 | Rig, manual throws and surface clearance | `verify_avanti.gd` checks the seven surface pivots, signs, travel and reset; handling tests check 30° up/25° down aileron differential | Software implementation complete; installed servo response is unmeasured |
| AV-05a | Turbine propulsion branch: thrust, ram drag, throttle map, spool | `test_turbine.gd` (27): loader refusals, thrust and ram drag, ram recovery, inlet normal force, spool limits without overshoot, 240/480 Hz split, gyro sign; Stik goldens unchanged | ✅ 2026-10-06 |
| AV-05b | ECU states: start, stop, fuel cut, flameout ([roadmap research 05](research/roadmap-investigations/05-propulsion-engines-motors.md)) | state machine unit tests; residual thrust decays, never instant | pending (G2) |
| AV-06 | Mass, aero references, trim | `derive_physics.py --check` in `test.sh`; sensitivity table; trim from 20 to 73 m/s | ✅ 2026-10-06 (experimental) |
| AV-07 | First experimental flight | `test_avanti_handling.gd` (30): hands-off 30 s, spool times, roll vs prediction, Vmax, glide, idle energy, loop, stall, stall-rotation recovery; app `--trace` checked | ✅ 2026-10-06 (headless; pilot evaluation at Gate 2 pending) |
| AV-08 | Finish and turbine sound | comparable captures, stable pause, owner reading | Pending; current generic sound is not a P100 turbine model |
| AV-09 | Flaps and retracts | input channel and state, actuator limits, flap aero (ΔCLmax +0.18/+0.33, ΔCD +0.016/+0.070, elevator mix), gear drag and contacts per state | pending: shared input and aero change |
| AV-10 | Fuel burn | mass, CG and inertia move together (CG 221 → 263 mm full → empty); reproducible reset | pending (G4) |
| AV-11 | Independent contrast | comparable flight observations, sensitivity, envelope limits | pending: no Avanti telemetry exists publicly |
| AV-12 | Delivery | clean clone, export smoke per ID, full suite, renderer captures | pending |
| AV-13 | Contact, brakes, vectoring, extended ECU | own tests | future |

## 4. Known limits of the experimental model

The geometry is a photo blockout (wing 0.702 m², no published area); the neutral point is anchored on the manual's aft CG (260 mm at 3 % MAC); 0.40 kg of virtual tail weight balances the estimated inventory; spool constants are ±40 %; the P100 rotation sense is assumed. The full list, the shared changes it needs and what the tests do not prove are in the [model report](research/avanti-s-av06-physics-model.md).

## 5. Next actions

Keep AV-01 geometry provisional until calibrated A200 planform, tail and equipment locations are available. Coordinate AV-09's flap/gear input and aerodynamics with the physics and input owners; the current `set_flaps()` method only poses the visual hinges. AV-10 fuel burn, AV-05b ECU states, AV-08 sound/finish, independent physical validation (AV-11), and clean export acceptance (AV-12) remain separate steps.
