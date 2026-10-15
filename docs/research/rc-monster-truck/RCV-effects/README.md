# RCV-25/33: dust, lights, grime and damage

Date: 2026-10-14. The Bisonte remains a selectable ground activity on the aircraft airfield. This revision connects render effects and estimated damage to the existing float64 truck Session. It preserves the accepted motor, brake, tire/contact and passive suspension parameters. [Operating guide and controls](../../../../research/rc-monster-truck/README.md#drive-and-experiment).

## Implemented behavior

- Tire dust depends on contact, surface, speed and slip, with four emitters capped at 96 particles total. It reuses the bundled smoke texture. Cosmetic grime accumulates on private body/tire overlays. Neither changes ground friction or physical state.
- Two projected headlights respond to Home's lighting; **L** and the garage button toggle them. Brake and reverse lamps follow controls independently. Darkness and off-state lens appearance are checked in native renders.
- The supplied suspension articulates with accepted wheel travel. The lab reports travel in millimetres alongside load and slip. [Drop and articulation evidence](damper-drop.md) supports retaining the current passive damper coefficients; no better measured hardware model was available.
- Contact episodes can dent the private body shell, shift bumpers inward and reduce propulsion. The HUD exposes condition and drive authority. **R** recovers, repairs and cleans, and marks the run assisted. Reset starts a new valid run. [Damage law, visual copy and checks](damage-01.md).
- Checkpoint and recording **v3** retain the 19-float64 damage sidecar, including active contact episodes, as well as requested and actually applied controls. Old v2 checkpoints are refused. Loading restores damage and stays paused; cosmetic grime/particles clear on load.

The damage law is an estimated gameplay proxy based on contact-associated energy loss and severe bottoming. It has a two-joule episode deadband and a motion threshold so resting contact does not continuously damage the truck. Other dissipation can contribute to the energy estimate. Only propulsion is derated: damage does not inject steering/braking, change the spring law, deform collision geometry, detach wheels or simulate material fracture. Physical damage calibration remains open.

## Measured integration

The final controlled fast lap completed **85.699 m in 22.471 s**, peaking at **5.974 m/s**, with maximum path error **1.117 m** and no airborne, hull-contact, wall-contact or rollover ticks. Body/suspension damage stayed zero and propulsion stayed at 100% for all **5,393 samples**. All 31 exported state channels and the ordinary driver commands match the accepted handling baseline exactly; timing is excluded from that comparison.

- [Final drive receipt](drive-final.json), [compressed full trace](drive-final.csv.gz), [comparison receipt](drive-final-comparison.json), [compression identities](retained-csv.json).
- [Comparison tool](../../../../research/rc-monster-truck/effects_runtime/compare_drive.py) checks exported values; the separate drive receipts establish completion and input/source identities.
- A separate 8 m/s supported wall-impact fixture produced body damage 0.6300 and drive authority 0.6023. Command replay and an active-contact checkpoint continuation matched physical and damage bytes exactly. [Session regression log](checks-final/test_rcv_damage_session.log).
- The integrated effects test compares every physical/damage byte with effects enabled and disabled over 360 actual circuit ticks. It also covers dirt accumulation, pause, lamps, Spanish labels, repair and damaged checkpoint restoration. [Activity regression log](checks-final/test_rcv_effects_activity.log).

The final headless lap measured Session tick P95 **5.299 ms** while other verification processes ran. This is not a clean performance qualification and exceeds the 4.167 ms budget at 240 Hz. The earlier run measured 4.135 ms; neither justifies claiming sustained 240 Hz rendering. Particle/overlay bounds and mesh-update caching limit presentation work, but a full rendering performance budget remains unqualified.

## Native visual review

The [integrated capture driver](../../../../research/rc-monster-truck/effects_runtime/capture_activity.gd) constructs the production activity and shared field, selects an existing spawn, then sends ordinary controls for 720 ticks. It advances particles between rendered frames and never injects physical state after spawn. The close camera is an observer. JSON receipts beside each PNG retain controls, state, renderer and source identities.

- [Garage on the aircraft runway](runtime-garage.png): Spanish layout and default location.
- [Daytime circuit drive](runtime-dust-reviewed.png): four contacting tires, a light trail and readable body.
- [Night circuit drive](runtime-night-reviewed.png): projected beams reach the ground and unlit dust no longer glows. The observer camera faces the truck; the night environment itself stays dark.
- [Small collision with a slalom wall](runtime-impact.png): body damage 0.1925, propulsion 88.43%, condition HUD and slight front deformation.

The separate [effects fixture report](effects-01.md) supplies maximum-dust and lamp close-ups with staged telemetry; it is not driving evidence. Grime remains cosmetic and is deliberately more apparent after prolonged off-road use. A three-second drive does not establish the saturated-grime appearance. The small wall hit does not qualify severe-impact appearance or physical strength.

Some immediate daytime capture shutdowns report four outstanding audio stream/playback objects from shared scenery. The verbose [day capture log](runtime-dust.log) identifies MP3/WAV audio types, not particle/mesh objects; no shader or script error occurred. These short-process captures do not establish a leak-free long-running activity lifecycle.

## Verification and reproduction

The [full focused runtime receipt](checks-final/verification.json) passed all **22 groups** with stable source hashes during the run: generated assets/data, float64 guard, course/contact/handling, input, Session, menu, damage and effects. After the final particle-color/night-lens correction, the [five relevant effect/activity/presentation/menu groups](checks-render-final/verification.json) passed again with stable source hashes. The final effects suite has 91 checks; damage has 162; damage Session has 16; integrated effects/activity has 17. The earlier [first pass](checks-accepted/verification.json) exposed a bare `sqrt` in the damage observer; routing it through the repository math wrapper fixed the guard without changing the numerical law.

The [whole-app parse receipt](parse-all.json) passed 852 scripts. The [follow-up](parse-followup.json) passed 11 changed/new scripts, bringing covered paths to 856; the [final effects parse](parse-effects-final.json) passed both subsequently edited effect files. Independent aircraft/helicopter work continued changing other files afterward. These receipts identify the exact tested bytes; they are not a claim that unrelated parallel edits are frozen.

Native review caught a material binding that headless state assertions missed: Godot requires `vertex_color_use_as_albedo` for the particle color to affect a StandardMaterial3D. Enabling it made opacity/tint effective; the final artist response keeps low-level daytime dust visible and dims it at night. The focused check now covers that binding, plus both emission and albedo for switched lamps. [Primary API reference](https://docs.godotengine.org/en/4.7/classes/class_cpuparticles3d.html#class-cpuparticles3d-property-color).

```powershell
python -B research/rc-monster-truck/verify_runtime.py --godot .tools/Godot_v4.7.2-stable_win64.exe --out tmp/rcv-effects-checks
python -B research/rc-monster-truck/driving/run_drive.py --scenario circuit --pace fast --output tmp/rcv-effects-drive.csv
python -B research/rc-monster-truck/effects_runtime/compare_drive.py docs/research/rc-monster-truck/RCV-handling/drive-final-cg065-fast-circuit.csv.gz tmp/rcv-effects-drive.csv --out tmp/rcv-effects-comparison.json
```

Create the output parent directory first and choose fresh output paths. Native captures require the actual renderer, not `--headless`; use the capture script with `--output=<absolute-fresh.png>`, optionally `--night` or `--impact`. Verification is software evidence, not measured RC tire, damper, collision or durability validation.
