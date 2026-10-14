# Avanti S realism investigation

2026-10-12 · AV-14…17 · Status: audit, bounded corrections and engine verification recorded; a reproduced baseline failure prevents a green full suite. Original SebArt A200, 2.00 m span, 2017 JetCat P100-RX non-BL. The aircraft remains experimental and has no matched-build flight validation.

2026-10-14 follow-up: [AV-17-R1 keyboard pitch and dive recovery](AV-17-R1/README.md) records the accelerated-stall reproduction, manufacturer/parameter audit, implemented input response and 240/480 Hz verification. The snapshot below predates [continuous turbine integration](../turbine-realism/AV-20/README.md) and [working landing gear](../avanti-gear/AV-09/README.md); its historical system limits are not current feature status.

The [pre-implementation plan](../../AVANTI-S-PLAN.md#6-av-1417-realism-investigation-and-correction) owns scope and acceptance. Three Luna/max audits were reviewed before source changes: [airframe and geometry](AV-14/airframe-audit.md), [turbine and force consumers](AV-14/propulsion-audit.md), [controls, animation and lifecycle](AV-14/coverage-audit.md). Reproduction tools: [AV-14 scripts](../../../research/avanti-s/av14/README.md).

## Corrections and their effects

- The exposed-tail mass centroid divided its first moments by an area selected using height instead of span. Both sums now use the same exposed span domain. The resulting component positions, virtual balance weight and inertia are regenerated together.
- The geometric MAC leading-edge station now uses area weighting, while MAC length retains chord-squared weighting. The finite-wing aerodynamic center remains modeled; the existing neutral-point anchor is retained explicitly.
- Aileron, flap and elevator servo pairs now occupy separate estimated left/right positions, retaining total masses and longitudinal/vertical stations. They previously contributed the inertia of uniform bars across empty space. Their dimensions and locations remain estimates.
- Fuel sensitivity now represents one fixed aircraft build: only fuel changes, while baseline hardware and ballast remain fixed. Mass, CG, static margin, stall speed, drag-polar equilibrium and climb-power estimate use the same loading case. Wing-area sweeps also update S/b consistently. These are static-polar estimates and omit CG-dependent trim drag; they do not implement fuel burn.
- The Avanti handling test now requires full, continuous, finite traces through the session callback with no crash, fault or unexpected pause. Its accumulated body-pitch rate and 1-g speed comparison are labeled as diagnostics, not proof of a loop or freedom from accelerated stall.

| Loaded quantity | Before | Corrected | Interpretation |
| --- | ---: | ---: | --- |
| Half-tank mass | 11.756299 kg | 11.705089 kg | Consistently regenerated balance weight; not a new measured empty mass |
| Roll inertia Ixx | 0.620508 kg·m² | 0.686737 kg·m² | +10.67%; the main response change |
| Pitch inertia Iyy | 2.440370 kg·m² | 2.464196 kg·m² | +0.98% |
| Yaw inertia Izz | 2.968171 kg·m² | 3.058242 kg·m² | +3.03% |
| CG aft of root leading edge | 240 mm | 240 mm | Selected loading scenario retained |
| Virtual tail balance mass | 0.396299 kg | 0.345089 kg | Still estimated hardware compensation |
| Geometric wing MAC leading edge | 102.368 mm | 118.267 mm | Corrected area weighting |

The [quantity delta record](AV-17/data-deltas.json) includes dependent aerodynamic derivatives and inventory changes. At 29 m/s the projected roll subsidence time changes from 0.04156 to 0.04602 s. Short-period prediction remains about 0.874 Hz with damping ratio 0.655. The projected spiral mode is slowly divergent (about −26.7 s); an unperturbed trim hold does not establish disturbance stability. These subsystem projections freeze controls/RPM and omit cross-axis coupling, so they are not the full gyro-coupled eigenvalues.

No turbine numerical schedule, maximum lift coefficient, drag coefficient, stability anchor, control throw, flap/gear behavior or speed limiter was tuned. The 0.4 s governor provenance now identifies the local small-signal throttle-to-thrust experiment and assumed mapping to RPM. Fuel-flow data are reserved for AV-10, with no flight-state consumer. Comments distinguish omitted mounting torque from a proven torque cancellation.

## Physical evidence and unresolved behavior

The [original SebArt manual](https://www.sebart.it/download/AVANTI%20S%20JET%202.2m-Manual%20Intro.pdf) establishes the variant, nominal dry mass, CG choices and control throws. It does not state the fuel condition for CG. The simulator's 240 mm CG at half tank is a selected build scenario. The [2017 JetCat catalog](https://www.jetcat.de/jetcat/Kataloge/JetCat%20Lieferprogramm%202017_web.pdf) establishes the selected engine's nominal endpoints; current BL, P160/P220 and EDF data are not interchangeable with this installation.

The predicted maximum level speed is about 264 km/h. The manual's tested-speed guidance is 250 km/h. A force-equilibrium prediction does not establish structural safety, and the simulator has no calibrated flutter/breakup model. The drag coefficient remains an estimate: the current build-up includes different geometry and explicit intake/canopy drag areas compared with the earlier preliminary table. Its fixed Mach 0.34 form-factor surrogate, assumed transition fractions and excrescence multiplier are now exposed in the [generated derivation](../../../research/avanti-s/av06/derivation.md). This explains the arithmetic difference without making either estimate a measurement.

The current aircraft is locked gear-up, flaps inactive and airborne-only. Proper taxi, takeoff, flap approach, landing, braking and retract transitions remain AV-09/13. ECU start/shutdown/flameout/relight, fuel burn with changing CG/inertia, turbine-specific sound, calibrated planform/polars and observed installed-engine transients remain open. Turbine rotor inertia/sense and transient mounting torque are unverified. NASA's [thrust equation](https://www1.grc.nasa.gov/beginners-guide-to-aeronautics/thrust-force/) supports the force bookkeeping; it does not identify this installation's ram correction or torque. [P100 ground identification](https://www.dglr.de/publikationen/2022/550281.pdf) provides local response evidence, not an Avanti flight envelope.

Needed physical evidence is a matched A200/P100 build record: measured planform and incidences, component positions and CG at known fuel loads, inertia, installed thrust/RPM transients, then calm-air trim, glide, control-response and stall observations. A pilot evaluation and real-radio/GPU presentation checks are separate from headless engine verification.

The baseline “loop” at +0.25 pitch command accumulates 437.6° of body q but its flight-path angle only ranges −52.7…+35.9°. The corrected aircraft also does not complete a loop under that input. The [eight-input follow-up](AV-16/pitch-sweep.md) distinguishes body rotation, vertical-plane path turning and departure from that plane. At +0.10 the corrected path turns about 350° in eight seconds; +0.25 instead enters a very different nonlinear response. This supports replacing the old test claim, not arbitrary tuning of the elevator or stall coefficients. The input is sustained and open-loop, with full-throttle demand; estimated static post-stall wing/tail laws, unknown actual polars and installed thrust remain physical validation gaps.

## Verification record

Baseline commit: `8b2020f4cc929bec62585deeea0d356b7c8af9df`; pinned Godot 4.7.2 (`ed1daf0bf`). [Baseline app hashes](AV-14/baseline-manifest.json), [30 original handling checks](AV-14/baseline-handling.log), [27 turbine checks](AV-14/baseline-turbine.log). The [strengthened test on unchanged aircraft data](AV-14/candidate-handling-initial.log) passed 47 checks before the source correction was regenerated; it is not the final candidate flight result.

Concurrent landscape/document work is preserved. A concurrent commit (`9d9ba1d`) captured intermediate Avanti files alongside landscape work; it is not used as the acceptance baseline. Final comparisons use the frozen baseline plus an explicit reviewed Avanti file overlay, with recorded hashes. No other developer's changes are reverted or claimed as this task's work.

- [Independent geometry/inventory checks](AV-17/geometry-inventory.log): 6 pass, including analytic geometry, separated-pair inertia, principal moments and generator freshness. [Sensitivity checks](AV-17/sensitivity-tests.log): 6 pass; [corrected loading/uncertainty table](AV-17/sensitivity.md).
- [Flight matrix comparison](AV-16/comparison.md): all 34 cases completed at both 240 and 480 Hz on both versions (136 runs), with finite continuous traces and no unexpected fault/crash. All 84 selected refinement comparisons meet the predeclared 1% steady / 5% smooth-response bands. High-alpha rotation and unmatched turbulent realizations remain descriptive.
- The final corrected-data handling test passes 47 checks. The turbine test passes 27. These are consistency/regression checks, not measurements of the real aircraft.
- [Lifecycle verification](AV-17/README.md): all five cases pass on both versions at both rates. Nonzero-input native checkpoint replay and the 1.5-second crash/restart boundary are exact. Actual servo-to-hinge movement, differential travel and neutral return agree; absent gear/flap functions remain inactive. JSON is explicitly diagnostic, with measured precision/type loss, and is not used for exact replay.
- The corrected geometry exposed a pre-existing exact render-basis comparison assumption in `test_crash_pose.gd`: quaternion normalization leaves a 2.22 × 10⁻¹⁶ difference near zero. Only ordinary-pose basis comparisons now allow 10⁻¹² roundoff; position, restored current/previous simulation state and held crash pose remain exact. A 10⁻⁶ rad change must fail. [Baseline](AV-17/crash-pose-baseline-final.log) and [candidate](AV-17/crash-pose-candidate-final.log) each pass all 86 checks; no render or simulation behavior was changed.
- [Whole-app comparison and timing](AV-17/README.md): all four model contracts, actual trimmed traces, schema/float64 checks and frame-rate checks pass. Both uninterrupted suites fail the same pre-existing extreme-density reset test. All continuation checks pass after the narrow crash-pose test correction; this is not an uninterrupted green suite. Alternating timing shows no repeatable >5% increase, with host/background-load and benchmark-scope limits recorded.
