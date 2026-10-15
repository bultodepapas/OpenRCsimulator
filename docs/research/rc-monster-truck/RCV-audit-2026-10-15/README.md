# Bisonte MT8 behavior audit — 2026-10-15

Scope: the electric Bisonte's float64 dynamics, drivetrain/brakes, tire and hull contact, suspension/art articulation, airfield obstacles, water/mud, controls, pause/recovery, checkpoints/replay, damage and effects. The default remains the aircraft runway. Findings were reproduced before correction; estimated vehicle parameters and supplied geometry were retained.

## Findings corrected

| Finding | Consequence | Correction and proof |
| --- | --- | --- |
| Normal braking generated an unrestorable checkpoint | `braking_distance` has `start_tick`/`end_tick`; the old validator required `tick` on every event | Validate the emitted brake schema using its end tick; preserve integer tick semantics across JSON; restore and replay a real braking run |
| Unknown/reordered checkpoint events were accepted | Editable, rehashed history could disagree with deterministic replay | Validate exact emitted schemas, ranges and tick/time order; transactional rejection tests. This is consistency checking, not authentication |
| Native checkpoint identity omitted the GDScript integration implementation | Changing integration code could leave the same C++ identity | Bind the script or exported bytecode hash and artifact kind for both backends; reject missing or changed artifacts |
| Intermediate attitude was used as a unit quaternion for world velocity | RK stages can have nonunit quaternion length; position derivative and speed reporting used inconsistent mappings | Normalize spatial mappings, preserve the raw quaternion ODE, bump solver to v5; unit-start spinning-stage oracle and step refinement |
| Sound toggle did not reach splash playback | Silencing the engine left water audio enabled | Propagate the audio setting on every render update; verify an active splash voice stops and releases its stream |
| Repeated terrain sampling and unnecessary dry lake queries | Avoidable cost in each wet integration stage and on the runway | Exact per-evaluation coordinate cache plus content-keyed expanded bank bounds. No position quantization or reuse across RK stages; mutable-callback and 980-point terrain regressions |

Detailed evidence: [physics](physics/attitude-and-road-sampling.md), [session/input/damage](session/README.md), [parts/effects](visual/README.md), and [Windows/Linux native builds](native/README.md).

The rig checks found no hub, steering, spin, CG or damper alignment defect: eight runtime adapter checks and 46 author-rig checks passed, including 27 articulated poses. The generated rig remains byte-verified against its authorized source. Damage, grime, dust and wet particles retain private/bounded presentation state and pause/reset behavior. No tire, spring, brake or damage parameter was retuned on visual preference alone.

## Verification

The [integrated RC receipt](checks-final/verification.json) records 30 passing groups with unchanged source hashes during that run, including the new attitude regression and controller lifecycle test. Its native Session run passed 136 assertions. A [second complete 30-group run](checks-frozen-final/verification.json) passed on the frozen copy described below. The suite covers schema mutations, float64 guards, source freshness, obstacles, contact forces, braking/skids, suspension, replay, damage, menus, render lifecycle and dry/wet effects. Both native platforms separately passed 733 evaluator parity checks; lake sampling matched 2,676 scalar outputs over 669 coordinates exactly. These are software checks, not physical validation.

Parallel vehicle-catalog/nitro work changed shared files after the first green run. The first subsequent circuit attempt failed to parse incomplete dependencies; the next completed but changed source hashes during execution. Neither is accepted as a stable comparison. Final integrated runs use `.tools/rcv-audit-20261015-verified`, an isolated source copy with copied native binaries and source assets. Runtime art/imports and aircraft authoring assets are shared read-only through directory junctions; the RC source and accepted vehicle data are copied. The final receipts bind their exact sources. Early snapshot checks exposed missing authoring assets in the test copy; the final copy includes them and passes. No parallel implementation was reverted.

After those parallel edits, the [final live-tree checks](checks-live-final/verification.json) also passed vehicle data, Session, menu integration, active effects/audio and controller lifecycle with unchanged source hashes. This rechecks the shared seams; it does not claim to audit the separate nitro vehicle.

The frozen traces identify the exact audited integration source. Subsequent parallel changes to optional nitro preload/spawn behavior are outside the paired comparison; they must not be attributed to its v4/v5 numerical differences. A further [live physics regression](checks-live-physics-final/verification.json) passed airfield support/sampling, full vehicle dynamics, attitude/cache and Session checks after those edits, with unchanged source hashes throughout that run.

The [paired input experiment](same-tape-v4-v5/comparison.json) ran 5,392 steps through the v4 and v5 reference kernels using the same 9-decimal controls and the same first recorded state from the baseline circuit. The maximum position-axis difference was **0.0000009785 m**. Both trajectories remained finite and complete. This isolates the integration change from driver feedback; it is not byte-exact replay, does not run Session, and relies on the baseline circuit having zero damage. Its [receipt](same-tape-v4-v5/verification.json) binds the fixed reference commit, kernel hashes and CSV. The reference Git bytes differ from the baseline working-tree hash only by LF/CRLF encoding.

The intentionally corrected quaternion mapping does not eliminate RK truncation. In the coarse 12 rad/s free-flight test, maximum-axis error improves slightly while total Euclidean position error increases slightly; the stage-level normalized-rotation oracle is the evidence for the fix. Old solver-v4 checkpoints are intentionally incompatible with v5.

## Cost and behavior

The bounded [before](road-profile-before.log)/[after](road-profile-after.log) profile repeats the same four poses 40 times, with actual road callbacks:

| Pose | Mean kernel step, before → after | Road calls per step |
| --- | ---: | ---: |
| Runway | 2.533 → 1.828 ms | 41 → 41 |
| Mud | 10.044 → 8.188 ms | 152 → 120 |
| Shallow water | 10.793 → 7.972 ms | 152 → 120 |
| Deep water | 13.010 → 8.453 ms | 152 → 120 |

These measurements combine the road changes and corrected solver; they are local diagnostics, not isolated optimization attribution or a target-hardware benchmark. Wet computation remains slower than the 4.167 ms public-tick interval, and the plan's 500 µs complete-truck target remains open.

The complete closed-loop [circuit run](final-circuit.json) finished the same 5,393 ticks and 85.70 m route as the [baseline](baseline-circuit.json), with 100% sampled track coverage, no rollover and no damage. Peak speed remained 5.973850 m/s; this audit did not add power. It traversed the rollers, banked bend, step-up and tabletop. The driver stayed grounded on this route; jump/landing verification comes from the dedicated dynamics and activity tests. Session p95 was 5.602 → 5.320 ms (about 5% lower), a much smaller integrated gain than some isolated pose measurements.

The actual [lake entry](final-water/verification.json) completed 3,600 ticks through mud, shallow water and full body immersion. It reached 0.7725 m local depth and 25.4463 N buoyancy, with dissipative drag, no spurious damage, successful dry recovery and a byte-exact 48-tick continuation after a serialized submerged checkpoint. Session p95 was 17.495 → 16.774 ms (about 4% lower). Both final runs retained unchanged source hashes throughout; they are distinct closed-loop runs, whereas the paired kernel experiment above holds the input tape fixed.

Native-render captures show [mud](final-water-capture-ui/water-entry-mud.png), [shallow water](final-water-capture-ui/water-entry-shallow.png) and [immersion](final-water-capture-ui/water-entry-deep.png). Their [verification receipt](final-water-capture-ui/verification.json) passes with 3,600 ticks and unchanged sources; peak visible pools stayed within budget (22/32 water drops and 26/32 mud drops). The capture harness now starts through the real Drive action with explicit neutral/focused offscreen input, fixing a stale garage hint caused by its previous direct Session resume. This is a research-harness correction, not a change to player focus/arming policy.

## Reproduce

Run from the repository root, choosing new output directories:

```powershell
python -B research/rc-monster-truck/verify_runtime.py --godot .tools/Godot_v4.7.2-stable_win64.exe --out .tools/rc-audit-checks
python -B research/rc-monster-truck/audit-2026-10-15/compare_tape.py --godot .tools/Godot_v4.7.2-stable_win64.exe --reference-ref ed1720a87825646f02f5ba7e5035d367ebeb0362 --csv docs/research/rc-monster-truck/RCV-audit-2026-10-15/baseline-circuit.csv --out .tools/rc-audit-pair
python -B research/rc-monster-truck/driving/run_drive.py --godot .tools/Godot_v4.7.2-stable_win64.exe --scenario circuit --pace fast --output .tools/rc-audit-circuit.csv
python -B research/rc-monster-truck/water/run_water.py --godot .tools/Godot_v4.7.2-stable_win64.exe --out .tools/rc-audit-water --capture
```

The last command uses a real offscreen Compatibility renderer, ordinary Session controls and the existing lake. Capture timing includes a different rendering workload from headless timing.

## Remaining limits and references

Point-probed tires, estimated grip/damage/fluid parameters, parallel front steering, equal wheel drive torque and an open sinking chassis remain explicit model limits. This audit does not establish measured RC handling, deformable mud, breakable mechanical joints, electronics failure or a complete application release. The author rig generator is absent from the delivery; future generated-rig changes require that source pipeline. The full control tape grows with session length to retain exact replay; bounded recording remains separate.

The camera/interpolation review used Godot's [advanced physics interpolation guidance](https://docs.godotengine.org/en/stable/tutorials/physics/interpolation/advanced_physics_interpolation.html). Fixed-step timing was checked against the [Engine physics-step settings](https://docs.godotengine.org/en/stable/classes/class_engine.html#class-engine-property-max-physics-steps-per-frame). Physical assumptions and primary mechanics references remain in the [handling](../RCV-handling/README.md) and [water](../RCV-water/README.md) evidence.
