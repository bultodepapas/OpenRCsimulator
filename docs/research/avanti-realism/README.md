# Avanti S realism investigation

2026-10-12 · AV-14…17 · Status: corrections reviewed; engine verification in progress. Original SebArt A200, 2.00 m span, 2017 JetCat P100-RX non-BL. The aircraft remains experimental and has no matched-build flight validation.

The [pre-implementation plan](../../AVANTI-S-PLAN.md#6-av-1417-realism-investigation-and-correction) owns scope and acceptance. Three Luna/max audits were reviewed before source changes: [airframe and geometry](AV-14/airframe-audit.md), [turbine and force consumers](AV-14/propulsion-audit.md), [controls, animation and lifecycle](AV-14/coverage-audit.md). Reproduction tools: [AV-14 scripts](../../../research/avanti-s/av14/README.md).

## Corrections and their effects

- The exposed-tail mass centroid divided its first moments by an area selected using height instead of span. Both sums now use the same exposed span domain. The resulting component positions, virtual balance weight and inertia are regenerated together.
- The geometric MAC leading-edge station now uses area weighting, while MAC length retains chord-squared weighting. The finite-wing aerodynamic center remains modeled; the existing neutral-point anchor is retained explicitly.
- Aileron, flap and elevator servo pairs now occupy separate estimated left/right positions, retaining total masses and longitudinal/vertical stations. They previously contributed the inertia of uniform bars across empty space. Their dimensions and locations remain estimates.
- Fuel sensitivity now represents one fixed aircraft build: only fuel changes, while baseline hardware and ballast remain fixed. Mass, CG, static margin, stall speed, drag-polar equilibrium and climb-power estimate use the same loading case. Wing-area sweeps also update S/b consistently. These are static-polar estimates and omit CG-dependent trim drag; they do not implement fuel burn.
- The Avanti handling test now requires full, continuous, finite traces through the session callback with no crash, fault or unexpected pause. Its accumulated body-pitch rate and 1-g speed comparison are labeled as diagnostics, not proof of a loop or freedom from accelerated stall.

No turbine numerical schedule, maximum lift coefficient, drag coefficient, stability anchor, control throw, flap/gear behavior or speed limiter was tuned. The 0.4 s governor provenance now identifies the local small-signal throttle-to-thrust experiment and assumed mapping to RPM. Fuel-flow data are reserved for AV-10, with no flight-state consumer. Comments distinguish omitted mounting torque from a proven torque cancellation.

## Physical evidence and unresolved behavior

The [original SebArt manual](https://www.sebart.it/download/AVANTI%20S%20JET%202.2m-Manual%20Intro.pdf) establishes the variant, nominal dry mass, CG choices and control throws. It does not state the fuel condition for CG. The simulator's 240 mm CG at half tank is a selected build scenario. The [2017 JetCat catalog](https://www.jetcat.de/jetcat/Kataloge/JetCat%20Lieferprogramm%202017_web.pdf) establishes the selected engine's nominal endpoints; current BL, P160/P220 and EDF data are not interchangeable with this installation.

The predicted maximum level speed is about 264 km/h. The manual's tested-speed guidance is 250 km/h. A force-equilibrium prediction does not establish structural safety, and the simulator has no calibrated flutter/breakup model. The drag coefficient remains an estimate: the current build-up includes different geometry and explicit intake/canopy drag areas compared with the earlier preliminary table. Its fixed Mach 0.34 form-factor surrogate, assumed transition fractions and excrescence multiplier are now exposed in the [generated derivation](../../../research/avanti-s/av06/derivation.md). This explains the arithmetic difference without making either estimate a measurement.

The current aircraft is locked gear-up, flaps inactive and airborne-only. Proper taxi, takeoff, flap approach, landing, braking and retract transitions remain AV-09/13. ECU start/shutdown/flameout/relight, fuel burn with changing CG/inertia, turbine-specific sound, calibrated planform/polars and observed installed-engine transients remain open. Turbine rotor inertia/sense and transient mounting torque are unverified. NASA's [thrust equation](https://www1.grc.nasa.gov/beginners-guide-to-aeronautics/thrust-force/) supports the force bookkeeping; it does not identify this installation's ram correction or torque. [P100 ground identification](https://www.dglr.de/publikationen/2022/550281.pdf) provides local response evidence, not an Avanti flight envelope.

Needed physical evidence is a matched A200/P100 build record: measured planform and incidences, component positions and CG at known fuel loads, inertia, installed thrust/RPM transients, then calm-air trim, glide, control-response and stall observations. A pilot evaluation and real-radio/GPU presentation checks are separate from headless engine verification.

## Verification record

Baseline commit: `8b2020f4cc929bec62585deeea0d356b7c8af9df`; pinned Godot 4.7.2 (`ed1daf0bf`). [Baseline app hashes](AV-14/baseline-manifest.json), [30 original handling checks](AV-14/baseline-handling.log), [27 turbine checks](AV-14/baseline-turbine.log). The [strengthened test on unchanged aircraft data](AV-14/candidate-handling-initial.log) passed 47 checks before the source correction was regenerated; it is not the final candidate flight result.

Concurrent landscape/document work is preserved. A concurrent commit (`9d9ba1d`) captured intermediate Avanti files alongside landscape work; it is not used as the acceptance baseline. Final comparisons use the frozen baseline plus an explicit reviewed Avanti file overlay, with recorded hashes. No other developer's changes are reverted or claimed as this task's work.
