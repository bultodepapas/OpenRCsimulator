# HELI-33: helicopter impacts and aftermath

Date: 2026-10-14. Scope: the playable X-Cell research trainer with the existing HX-700 visual. Current operating behavior belongs to [HELICOPTER](../../../HELICOPTER.md). This record distinguishes software evidence from physical validation.

## Baseline

The old session checked an instantaneous main/tail disc envelope and 40 mm skid travel. It saved only a reason and tick, then froze the intact model. It did not preserve contact kinematics, check the fuselage against scenery, or run the existing crash renderer.

Before changes, `healthy_tape.gd` recorded every accepted body, continuous state, auxiliary state, input and shaft phase for 720 ticks each of stopped ground support, hover and small cyclic/yaw commands. `baseline.json` stores per-tick SHA-256 identities. Helicopters use their native accepted-state/CSV workflow; the fixed-wing `.orfl` replay tool does not support them.

The existing deterministic ground-cycle pilot also completed 84.920833 simulated seconds: startup, liftoff, hover, landing, hold and shutdown. Baseline peak altitude was 1.193706 m, peak horizontal displacement 1.498511 m, touchdown downward speed 0.017077 m/s, and final shaft speed zero. `baseline-cycle.json` retains its controls and accepted samples.

## Design and evidence limits

- Continuous flight forces, skid coefficients, rotor equations and source geometry are unchanged. The terminal detector reads float64 accepted states. Godot rigid bodies and particles are disposable aftermath presentation.
- Contact proxies derived from the supplied HX-700 visual are estimates for the surrogate. They are not measured X-Cell hull geometry or strength limits. The legacy 40 mm skid terminal threshold is retained.
- Rigid-body point effective mass is distinct from rotor spin energy. Presentation severity and part-release choices are provisional; they do not identify real material failure thresholds.
- Existing named mesh parts, crash textures and sound samples are reused. No generated aircraft geometry or authored physics JSON is edited.
- The playable physics reference is a glow-powered X-Cell. The HX visual's battery mesh does not establish a LiPo energy inventory. Impact dust and chips must not be represented as a proven battery fire.

## Implemented behavior

The session produces one terminal report with aircraft component and obstacle identity, time fraction, world/body contact point, normal, point and CG velocities, effective mass, normal energy and rotor speeds. It cuts drive, latches hold and freezes accepted flight state. Invalid detector inputs produce a diagnostic stop, not wreckage. Checkpoint v4 binds obstacle identity and refuses older contact-boundary versions.

Terrain checks distinguish four skids, the canopy/fuselage bounds, sampled tail boom, fin and both rotors. At |shaft speed| ≥20 rad/s, scenery checks cover the disc with 32 diameter segments. Their explicit inflation is `R*sin(pi/64) + blade_chord/2 + 0.025 m`; the current main rotor totals 0.092027 m. This can report contact early. Slow/stopped blades use a finite diameter/chord at tick-end phase, not a full circle. Exact within-tick shaft-phase windows, elastic blades and measured structural failure remain open.

The HX wreck adapter separates two articulated main blades, two tail blades, canopy, skids, boom and fin. Legacy duplicate GLB blade branches are hidden and excluded from collision bounds. A rotating blade contact can cause local C2 damage without turning the whole airframe into a high-severity wreck. Blade launch uses signed tangential velocity, with a per-blade shaft-energy budget; nonrotor parts receive no rotor spin velocity. Core/group boxes and their masses remain presentation estimates.

Existing effects are scaled to an RC model: short translucent surface dust, a brief nonthermal grey fracture puff, small chips, impact sounds and surface marks. Blade-envelope contact does not establish metal sparks. Enabled stationary night optics follow their corresponding wreck parts; rotor LED arcs and the armed beacon stop. No thermal fire or battery vent is inferred.

Native repeated captures exposed a pooled-body synchronization bug: the Node had the new impact pose while PhysicsServer retained the previous crash pose. The adapter now flushes transform/velocity state at relaunch and resets interpolation. The dedicated repeated main/nose/fence test checks both Node and PhysicsServer transforms, including a 24 m lateral relocation and pause/reset.

## Verification

- The 2,160 accepted-state hashes in `baseline.json` and `candidate.json` match exactly, including the candidate's production obstacle inventory.
- `baseline-cycle.json` and `candidate-cycle.json` retain identical 84 accepted samples and cycle reports across the 84.920833 s startup/flight/landing/shutdown exercise. Checkpoint hashes differ intentionally because v4 binds the obstacle world.
- All 12 final focused suites pass with stable runtime source hashes: detector (26 checks), wreck adapter (33), presentation (44), relaunch (66), session, ground lifecycle, state, renderer, controls, night kit, night rotor and controller actions. [Final manifest](checks/final/verification.json) retains logs' source identities; [regression comparison](checks/final/regression.json) verifies the final healthy tapes and complete cycle.
- The native parse pass covered 844 scripts without errors. The [final follow-up](checks/final/parse.json) covers nine integrated scripts and tests after the detector optimization. This is not a claim that every release/platform test in `app/test.sh` ran.

The initial combined regression run caught a transient dependency parse error while the adapter was being edited; the final isolated night-kit recheck passed. The runner rejects script/shader errors even when Godot exits with status zero.

The shared scenery aftermath layer caps contacts at the nearest 160 proxies and warns when that budget is reached. This does not limit authoritative first-impact detection, but distant debris/obstacle contacts are presentation-limited. Continuous in-flight damage, fuel-system failures and calibrated material breakage are not implemented by this slice.

## Native visual review

The actual helicopter route was captured with Godot 4.7.2, Compatibility/OpenGL 3.3 and an RTX 3090: six fixtures at noon and midnight, each at 0.04, 0.24, 0.8 and 2 seconds after impact. The [48-frame manifest](captures/captures.json) records contact reports and wreck/effect statistics; [verification](captures/verification.json) binds runtime/harness hashes and checks engine errors, pause/resume, source visibility, accepted-state immutability and reset.

| Fixture | Outcome exercised | Review frame |
| --- | --- | --- |
| Main rotor on ground | Local C2 blade release | [Day](captures/12-main-0240.png), [night](captures/00-main-0240.png) |
| Tail rotor on ground | Local C2 tail-blade release | [Day](captures/12-tail-0240.png), [night](captures/00-tail-0240.png) |
| Hard skid landing | C2 undercarriage impact | [Day](captures/12-hard-0240.png), [night](captures/00-hard-0240.png) |
| Nose on ground | C2 detached canopy exposes the frame | [Day](captures/12-nose-0800.png), [night](captures/00-nose-0800.png) |
| Production field fence | C3 rotor/obstacle contact at the correct location | [Day](captures/12-fence-0240.png), [night](captures/00-fence-0240.png) |
| Severe nose impact | C4 release of eight section groups; rotor stopped | [Day](captures/12-severe-0240.png), [night](captures/00-severe-0240.png) |

The severe fixture injects 32 m/s downward velocity and near-vertical nose-down attitude; it is deliberately outside normal trainer operation. It tests the bounded complete-breakup branch, not a measured crash threshold. Native debris trajectories can differ slightly with render scheduling; only accepted flight state is required to remain exact.

The bright line in the severe frame is the source `Servo_Cola_y_Varilla` pushrod, whose tail-axis bounds span about 0.844 m. It is a static, unskinned mesh retained with the core; it does not stretch between debris bodies. Pushrod bending and joint failure are outside this rigid-section presentation.

## Performance

The detector now rejects clear terrain points before allocating transformed vectors, bounds the complete rotor's vertical extent, and shares one spatial-bin query between hull and rotor scenery checks. The prepared hull reach is revalidated before using it to exclude obstacles.

The retained native microprofile uses 100 warm-up ticks and 500 samples per case. With the production obstacle world, direct detector p50/p95 changed from 1918/2460 to 897/991 microseconds on the ground and from 1532/2644 to 410/465 microseconds airborne. The empty-world airborne case regressed from 134/194 to 313/350 microseconds. These single-run CPU measurements do not establish a frame-rate or release budget. [Performance evidence](checks/performance/RESULTS.md) retains all cases, source copies, raw timings, hashes and limitations.

## References

[Horizon Hobby's Blade 230 S Smart manual](https://assets.horizonhobby.com/on/demandware.static/-/Sites-horizon-master/default/dwf32cafe6/Manuals/BLH1200-Manual-EN.pdf), maintenance section, separately identifies blades, tail rotor/boom, frame and landing gear for inspection. It supports component distinctions, not numerical damage thresholds or X-Cell calibration.

[Godot 4.7 CPUParticles3D documentation](https://docs.godotengine.org/en/4.7/classes/class_cpuparticles3d.html) defines `restart()` for emitter reuse and `speed_scale = 0` for pause. [Godot RigidBody3D](https://docs.godotengine.org/en/4.7/classes/class_rigidbody3d.html) documents the presentation body's velocity, freeze and contact interface.

## Reproduction

From the repository root, using the pinned native Godot 4.7.2 build:

```powershell
python research/helicopter/crashes/verify.py
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --script ../research/helicopter/crashes/healthy_tape.gd -- --out=C:/temporary/candidate.json
& .tools/Godot_v4.7.2-stable_win64_console.exe --path app --resolution 1280x720 --script ../research/helicopter/crashes/capture.gd -- --out-dir=C:/temporary/heli-crashes
```

The capture harness injects deliberate impact fixtures into the actual flight route. It is not a piloted maneuver or physical validation. Logs must be checked for script/shader errors as well as exit status.
