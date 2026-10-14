# Ventage Jet turbine jet: plan

2026-10-14 · Revision 10 · **Status: AV-31 integrates the supplied Blender model and AV-09 now enables retracts, wheel contact, nose steering, main brakes and runway starts. AV-20 continuous turbine response remains integrated. The catalog aircraft remains experimental: calibrated planform/installation, flap aerodynamics, finite fuel and independent physical validation remain open.**

Step-ID prefix `AV-`. Owned paths: `assets/aircraft/avanti-s-a200/`, `app/aircraft/avanti_s_*`, `app/aircraft/verify_avanti.gd`, `app/physics/turbine.gd`, `app/data/aircraft/sebart_avanti_s_a200.json` (generated), `app/tests/test_turbine.gd`, `app/tests/test_avanti_handling.gd`, `research/avanti-s/`, `docs/research/avanti-s-*`.

Research: [family and choice](research/avanti-s-family-research.md) · [resources](research/avanti-s-resources.md) · [integration audit](research/avanti-s-integration-audit.md) · [turbine identity](research/avanti-s-turbine-research.md) · [controls and installation](research/avanti-s-controls-and-installation.md) · [AV-01 metrology](research/avanti-s-av01-metrology.md) · [physics requirements](research/avanti-s-av05-physics-requirements.md) · [turbine dynamics](research/avanti-s-av05-turbine-dynamics.md) · [airframe data](research/avanti-s-av06-airframe-data.md) · [aero references](research/avanti-s-av06-aero-references.md) · **[physics model and validation](research/avanti-s-av06-physics-model.md)**.

## 1. Identity and scope

The simulator displays this aircraft as **Ventage Jet**. Its catalog ID and source-aircraft provenance remain unchanged.

**SebArt Avanti S Jet 2.2m ARF (A200 original): 2.00 m span, 2.22 m length, 10.5 kg RTF dry with a JetCat P100-RX** (2017 catalog, non-BL, fixed thrust tube). Catalog ID `sebart-avanti-s-a200-p100rx`. Chosen for its documentation and turbine identity, not for sales rank. Other variants (XS, Mini, FC/Krill 2.1 m, current "2.3 m", Freewing EDF) are never mixed into its numbers. The P100-RX-BL is a different documented revision; do not mix its RPM or response data into the 2017 configuration. The 10.5 kg value is dry, not the in-flight mass with fuel. Sources: [manual](https://www.sebart.it/download/AVANTI%20S%20JET%202.2m-Manual%20Intro.pdf), [JetCat 2017 catalog](https://www.jetcat.de/jetcat/Kataloge/JetCat%20Lieferprogramm%202017_web.pdf).

Flight configuration (AV-07): in-air start at 29 m/s, turbine running, flaps up, gear up, half of the 3.2 l stock tank, CG 240 mm (the manual's beginner setting for a P100). AV-09 also offers a downlocked runway start, retract controls and main-wheel brakes. The [asset README](../assets/aircraft/avanti-s-a200/README.md) documents the generated geometry, seven hinge names, visual-only flap hook and build contract. The pilot camera, radio arming, pause, reset and recording rules are those of every aircraft.

## 2. Method

Same flow as the other aircraft: declarative geometry → generated data with `{value, unit, kind, source}` on every number → strict loader → float64 physics → tests through the real session loop. Physics data come from [derive_physics.py](../research/avanti-s/av06/derive_physics.py) and its sourced [inputs.json](../research/avanti-s/av06/inputs.json); never edit the generated JSON. Guessed values are labelled `estimated` and swept in [sensitivity.py](../research/avanti-s/av06/sensitivity.py). A disagreement with documented data is resolved in one visible place and reported, never spread over coefficients (see the neutral-point anchor in the [model report](research/avanti-s-av06-physics-model.md#3-stability-and-balance-what-the-blockout-could-not-explain)).

## 3. Steps

| ID | Step | Proof | Status / next evidence (checked 2026-10-14) |
| --- | --- | --- | --- |
| AV-00 | Choose the variant and archive evidence | sources, hashes, git exclusion | ✅ 2026-10-05 |
| AV-01 | Datum and minimum geometry | traceable dimensions; discrepancies shown | provisional: no calibrated planform exists; root LE station, root chord, stab and fuselage width still to measure (they decide the neutral point) |
| AV-02 | Visual model and app preview | historical blockout revisions 2–4; AV-31 imported Blender views | Visual blockout superseded by AV-31; AV-02 remains the estimated physical surrogate |
| AV-03 | Catalog and propeller-free adapter | common v2 `imported_glb` builder, model/Workshop manifests and catalog tests | Updated and qualified in AV-31; stable catalog ID and compatibility facade |
| AV-04 | Rig, manual throws and surface clearance | AV-31: 340 scene checks; seven measured rest transforms, signs, full travel and reset; 30° up/25° down aileron differential | Imported rig qualified; installed servo response and physical clearance under load remain unmeasured |
| AV-05a | Turbine propulsion branch: thrust, ram drag, throttle map, spool | `test_turbine.gd` (27): loader refusals, thrust and ram drag, ram recovery, inlet normal force, spool limits without overshoot, 240/480 Hz split, gyro sign; Stik goldens unchanged | ✅ 2026-10-06 |
| AV-05b | ECU states: start, stop, fuel cut, flameout ([roadmap research 05](research/roadmap-investigations/05-propulsion-engines-motors.md)) | state machine unit tests; residual energy and source-backed cooling | Detailed work/status in [turbine realism plan](plans/turbine-realism.md#13-incremental-implementation-sequence) (G2) |
| AV-06 | Mass, aero references, trim | `derive_physics.py --check` in `test.sh`; sensitivity table; trim from 20 to 73 m/s | ✅ 2026-10-06 (experimental) |
| AV-07 | First experimental flight | `test_avanti_handling.gd` (30): hands-off 30 s, spool times, roll vs prediction, Vmax, glide, idle energy, loop, stall, stall-rotation recovery; app `--trace` checked | ✅ 2026-10-06 (headless; pilot evaluation at Gate 2 pending) |
| AV-08 | Finish and turbine sound | AV-31 native/imported/exported captures; existing turbine whine/roar telemetry route | Blender finish and turbine presentation integrated; acoustic identification against this P100 installation remains open |
| AV-09 | Flaps and retracts | [Gear evidence](research/avanti-gear/AV-09/README.md): sampled Blender rig, actuator/contact/drag state, steering/brakes, runway and lifecycle tests | Gear implemented; flap aerodynamics and mixing remain open |
| AV-10 | Fuel burn | mass, CG and inertia move together for one fixed build; reproducible reset | Detailed AV-10a/b/c work/status in [turbine realism plan](plans/turbine-realism.md#13-incremental-implementation-sequence) (G4); historical CG endpoints are not a measured travel range |
| AV-11 | Independent contrast | comparable flight observations, sensitivity, envelope limits | pending: no Avanti telemetry exists publicly |
| AV-12 | Delivery | clean clone, export smoke per ID, full suite, renderer captures | pending |
| AV-13 | Extended ground/propulsion behavior | AV-09 covers point-contact gear and main brakes; vectoring and extended ECU remain separate | future extensions |
| AV-31 | Supplied Blender jet integration | reproducible source exporter, common model contract, 340 model checks, focused flight/crash/audio/Workshop tests, native Windows package and capture | Complete for the admitted gear-up/clean configuration; [evidence](research/avanti-blender/AV-31/README.md), [authoring guide](../assets/aircraft/avanti-s-a200/README.md) |

## 4. Known limits of the experimental model

The physical geometry remains the estimated AV-02 surrogate (wing 0.702 m², no published area); AV-31's Blender presentation supplies contact witnesses only. Its planform and turbine height differ and are not calibrated physical inputs. The neutral point is anchored on the manual's aft CG (260 mm at 3 % MAC); 0.345 kg of virtual tail weight balances the corrected estimated inventory (AV-15); spool constants are ±40 %; the P100 rotation sense is assumed. The [AV-14…17 report](research/avanti-realism/README.md), [AV-20 response evidence](research/turbine-realism/AV-20/README.md) and [AV-31 model evidence](research/avanti-blender/AV-31/README.md) distinguish implemented behavior from physical validation; the [AV-05…07 report](research/avanti-s-av06-physics-model.md) is historical.

## 5. Next actions

The [fuel-turbine realism plan](plans/turbine-realism.md) now owns detailed AV-05b/AV-10 and AV-18…30 work: stage-coupled response, ECU/thermal lifecycle, finite fuel and changing mass properties, installation/ambient effects, telemetry and physical acceptance. Its [AV-18 source review](research/turbine-realism/AV-18/README.md) is dated research, not an implemented-feature claim.

AV-20 now explicitly selects continuous turbine RPM in the generated experimental aircraft: stage-local governor/thrust/gyro, accepted RPM mirror, prescribed fuel mass and checkpoint v8. [Implementation evidence](research/turbine-realism/AV-20/README.md) records the numerical delta and remaining ECU, fuel and physical-validation gates. Historical sampled integration remains available when the optional selector is absent or `sampled`.

Keep AV-01 geometry provisional until calibrated A200 planform, tail and equipment locations are available. Coordinate AV-09's flap/gear input and aerodynamics with the physics and input owners; the current `set_flaps()` method only poses the visual hinges. AV-10 fuel burn, AV-05b ECU states, AV-08 acoustic identification, independent physical validation (AV-11), and fleet-wide release acceptance (AV-12) remain separate steps. AV-31 closes this model replacement and records its isolated Windows export proof.

## 6. AV-14…17 realism investigation and correction

Written before implementation. The user's focus is the Ventage Jet's complete RC flight behavior. Baseline `8b2020f4cc929bec62585deeea0d356b7c8af9df`, pinned Godot 4.7.2: 30 handling and 27 turbine checks pass. The app snapshot and sources are frozen independently of concurrent landscape/docs/validation work. Evidence lives in `docs/research/avanti-realism/AV-14/`; reproducible tools belong in `research/avanti-s/av14/`.

### Ownership and architecture

The lead owns integration, this plan, the evidence/tools, bounded AV-06 source/data corrections and Ventage Jet test changes. Three Luna/max audits cover airframe/primary sources, turbine/consumers, and controls/lifecycle/coverage, with separate report files. Contributions require lead review. Existing model/render, shared propulsion, input, crash and scenery owners retain their paths; no external owner acknowledgement is implied. Inspect shared-file status before edits. No production change starts until the audit findings and this plan are reviewed.

Retain the v2 contract, source generator, float64 session state and existing hinges. Correct demonstrated equations or provenance through the authored source; derive dependent quantities together. Keep uncertainty explicit instead of inventing measured Avanti behavior. The original A200/P100-RX identity excludes EDF, XS, Krill and BL data. No new aircraft-ID physics branch, guessed drag limiter, hidden stability assistance or partially active gear/flap module.

### Audit findings and decisions to verify

| Area | Evidence / decision |
| --- | --- |
| Tail mass placement | AV-06's exposed-tail area filter reuses `_` as the tuple's height while moments filter span; it includes the concealed center strip. Correct the domain consistently and independently integrate an analytic fixture. Current mass centroid is 0.8668 m aft; the consistent exposed-panel calculation gives 1.0146 m. Recompute virtual balance/inertia and disclose the resulting mass change. |
| Swept planform reference | MAC length correctly uses chord squared, but its leading-edge station also uses chord squared rather than area weighting. Review the geometric/constant-section-lift definition with independent trapezoid moments; distinguish it from a measured finite-wing aerodynamic center. Preserve the declared stability anchor, exposing its uncertainty. |
| Inventory | Paired aileron/flap/elevator servos span empty space as uniform boxes. Separate estimated hardware centers and local envelopes, retaining pair masses and longitudinal/vertical assumptions. Main gear is already separated. Unknown battery/electronics distribution remains an explicit approximation. |
| Propulsion and environment | Audit thrust/rpm tables, ECU demand, acceleration/deceleration, installed loss, ram drag/normal force, gyro signs, atmosphere and off-state consumers. Keep identified-vs-borrowed-vs-estimated evidence distinct. Add sensitivity evidence before any numerical retuning. |
| Controls and aero | Review differential throws, normalized servo time, trim saturation, damping, all-axis/both-sign response, high/normal rates, glide/climb, stalls/spins and inverted behavior. Manual radio expo is not a measured aerodynamic parameter or an instruction to apply expo twice. |
| Lifecycle / ground | Existing handling uses `Maneuvers.fly()` and skips session crash checks. Add Ventage Jet-specific full-session test/probe coverage, reset/fault/finite/trace completion guards, replay and deliberate hull impact. Gear/flaps are inactive; proper takeoff, landing and braking remain unimplemented. Probe approach energy and supported terrain/crash behavior without claiming gear-down landing acceptance. |
| Performance claims | Existing loop check integrates body pitch rate; that alone cannot prove a planar loop. Predicted level maximum exceeds the manual's 250 km/h tested-speed guidance; it is not a validated structural or operational envelope. No unsupported flutter/breakup model will be fabricated. |

### Phases and measurable acceptance

| ID | Work | Acceptance |
| --- | --- | --- |
| AV-14 | Trace source → loader → control/force/animation/lifecycle consumers; verify primary sources and baseline | Three reviewed audits, dated primary URLs and variant/loading limits, baseline hashes/logs. Identify every changed input's consumer and separate unsupported systems from valid zero states. |
| AV-15 | Correct confirmed geometry/inventory/provenance defects in generator/inputs | Analytic area/first-moment fixture independent of implementation; paired-mass/tensor oracle and physical principal moments; generator `--check`; strict v2 Godot validation. Document each intentional numerical delta and unchanged assumptions; never compensate with arbitrary coefficient tuning. |
| AV-16 | Full flight, propulsion and lifecycle probes | Same baseline/candidate matrix at 240/480 Hz: multiple trim speeds, normal/high all-axis both signs, turbine step/idle energy/go-around input, glide/approach, guided turns/slips, stall/commanded recovery, pitch-loop inputs, inverted trim, wind/density. Require expected rows, continuous finite state, no unintended crash/fault, exact checkpoint/restart. Use ≤1% selected steady and ≤5% selected smooth refinement bands; report nonlinear events and unmatched stochastic realizations individually. Define any geometric loop proof explicitly. |
| AV-17 | Integration and cost | Ventage Jet/turbine tests, all four model contracts, affected shared checks and `app/test.sh` in an isolated LF checkout; reproduce unrelated failures on baseline. Same-host alternating trim/stalled timing, investigate repeatable >5% regression. Final source/hash/link review; results and remaining physical gaps in the evidence entry point. |

### Risks and research basis

Pre-code review completed 2026-10-12: the lead reviewed all three audit findings. Adopt the consistent exposed-tail domain, area-weighted geometric MAC leading-edge station, and separated servo pairs at the existing estimated lateral centers (±0.75/0.35/0.125 m), with 0.03 m local envelopes. Preserve the stability anchor and all turbine numerical schedules. Qualify the 0.4 s governor provenance as a local small-signal equivalent; do not add a turbine spool reaction moment without an open-system angular-momentum balance. Correct the fuel sensitivity table so a fixed build changes fuel without secretly rebalancing hardware. The manual leaves CG fuel loading unspecified. Root owns handling-test/runner integration and comment-only turbine clarification; the airframe agent owns AV-06 generator/inputs and an independent geometry/inertia oracle; propulsion owns the sensitivity tool/oracle; coverage owns only the two AV-14 flight/lifecycle probes. Reviewed reports: [airframe](research/avanti-realism/AV-14/airframe-audit.md), [propulsion](research/avanti-realism/AV-14/propulsion-audit.md), [coverage](research/avanti-realism/AV-14/coverage-audit.md).

Changing estimated mass distribution and aerodynamic reference stations can alter nonlinear stall/rotation even when CG is held. The neutral-point anchor, airfoil/polar, 8% installed thrust loss, throttle law and spool schedules are not matched-build flight identification. Fuel loading at the manual CG is not specified; other Avanti variants do not resolve it. A scenario's controller can conceal stability problems, so include open-loop cases and record input clipping. Rendering, real-radio handling and low-end-machine acceptance require separate evidence.

Primary starting references: [SebArt original A200 manual](https://www.sebart.it/download/AVANTI%20S%20JET%202.2m-Manual%20Intro.pdf), [JetCat 2017 catalog](https://www.jetcat.de/jetcat/Kataloge/JetCat%20Lieferprogramm%202017_web.pdf), [P100 identification, Many et al.](https://www.dglr.de/publikationen/2022/550281.pdf), [NASA momentum thrust equation](https://www1.grc.nasa.gov/beginners-guide-to-aeronautics/thrust-force/), [NASA NDARC geometry, pp. 128–130](https://rotorcraft.arc.nasa.gov/Publications/files/Johnson_1085_TN21612_NASA%20TP-2009-215402-app7.pdf). The latter distinguishes geometric MAC from the lift-weighted aerodynamic center; the actual swept-wing loading remains modeled. Source-specific findings and proposed corrections are retained in the AV-14 audits before implementation.

### Recorded outcome, 2026-10-12

| Step | Result and remaining gate |
| --- | --- |
| AV-14 | Complete: three Luna/max audits reviewed, primary variant evidence checked, consumer paths and unsupported systems identified, baseline frozen before implementation. |
| AV-15 | Complete: exposed-tail integration, geometric MAC station and separated-servo inertia corrected through the generator; provenance and fixed-build sensitivity corrected. Twelve independent mathematical checks pass; generated data and strict Godot validation pass. |
| AV-16 | Software investigation complete: 34 cases × two revisions × two rates, all complete and finite; 84/84 selected refinement bands pass. Eight-input pitch sweep separates body rotation from path geometry. Five lifecycle cases pass on both revisions at both rates, including exact native checkpoint replay and crash reset, plus Linux replay. Physical aerobatic/stall/spin validation remains open. |
| AV-17 | Evidence recorded: 47 handling, 27 turbine and 86 corrected crash-pose checks; all four model contracts, actual app trim and FPS independence pass. Both full-suite attempts stop at the same baseline extreme-density reset failure; diagnostic continuation finds no remaining candidate-only failure after the test-only render-roundoff correction. Alternating host timing stays below the 5% regression trigger. A green uninterrupted suite, target-machine/render performance and pilot acceptance remain unclaimed. |

Integration review rejected an intermediate tail-centroid helper that ignored the authored chord-scale sweep, retained the consistent strip-domain fix, and verified the full inertia tensor independently. Lifecycle review replaced an unsupported JSON replay assumption with the production native-byte format and added a non-finite render-basis negative check. No turbine schedule, polar limit, arbitrary stability term, gear/flap behavior or structural limiter was retuned. [Final report, exact deltas, sources, plots and reproduction evidence](research/avanti-realism/README.md).
