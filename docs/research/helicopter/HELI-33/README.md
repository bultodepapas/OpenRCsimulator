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
