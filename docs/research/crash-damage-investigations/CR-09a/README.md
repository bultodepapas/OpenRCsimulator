# CR-09a — Pooled visual wrecks

2026-10-11 · **Status: implemented; all focused assertions pass.** Evidence and limitations are below.

## Behavior

[Wreck](../../../../app/render/crash/wreck.gd) duplicates the airplane before a crash and groups existing procedural subtrees into recognizable sections. It keeps the source aircraft hierarchy and hinges untouched. The Ugly Stik retains left/right wing panels, horizontal and vertical tail, engine assembly, and propeller groups. The Extra 300S, P-51D, and Avanti use their available wing, tail, gear, engine, and propeller nodes. A C0–C2 event moves the whole copy as one body; C3 and C4 release structural groups in stages.

The controller preallocates 24 `RigidBody3D`s with CCD and 24 soft contact shadows. A local `WorldBoundaryShape3D` collides only on wreck layer 20; the flight model and field ground do not receive debris contacts. Sections inherit the aircraft CG velocity and angular velocity at their model-space center. Optional `cg_model` in the severity dictionary defines the aircraft-CG offset from the model root.

For C3 only, accepted secondary contacts involving the core also accumulate a separate, capped contact-exposure index. Once a provisional cumulative threshold is crossed, one still-attached group can release per qualifying core contact, ordered propeller (4 J), gear (12 J), canopy (25 J), then engine (50 J). The index sums the per-contact relative-kinetic-energy proxy, capped at 250 J per event and 1,000 J cumulatively; it is distinct from `secondary_impact`'s per-event joule strength. The thresholds are provisional ordinal values selected for staged cosmetic timing, with no measured failure data or material-limit basis. Release is deferred out of the physics callback, transfers the group's estimated mass share from the core, inherits its current point velocity, and applies no additional scatter energy. This post-crash visual breakup does not alter flight-state aerodynamics. C0–C2 and the initial C4 breakup path are unchanged.

Separation energy is an estimate. The controller uses a supplied `dissipated_normal_energy_j`, `normal_impact_energy_j`, or `normal_energy_j`; otherwise it estimates `0.5 × mass × normal_speed²`, with normal speed from `normal_speed_mps` or the CG velocity projected onto `contact_normal` (up by default). Scatter receives at most 12% of that estimate and 600 J total, divided across detached groups; the core receives no separation impulse. Group mass shares and the 14 m/s scatter-speed limit are presentation estimates, not aircraft data. `stats()` reports the estimate, energy source, applied scatter energy, and mass in SI units.

`secondary_impact(position, strength)` reports relative kinetic energy in joules (capped at 250 J with an 80 ms event lockout); this is a collision-strength proxy, not measured dissipated energy. Sleeping bodies remain visible until `reset()`. `set_paused()` freezes bodies and delayed-release timers. Each shadow stays on the local y=0.012 m plane, shrinking and fading as its body rises.

## Verification

`app/tests/test_crash_wreck.gd` runs the actual four catalog aircraft and checks mesh-backed groups, the Ugly Stik section names, C2 cohesion, C4 staged release, visible core meshes, bounded body and shadow pools, wreck-layer isolation, CCD, model-space-CG velocity, the delayed total-energy bound, emitted secondary-impact joules, inherited-state finiteness, box clearance above ground for eight seconds, sleep persistence, pause/resume, and reset without changing source hierarchy or visibility. Its focused C3 callback regression checks sub-threshold accumulation, deferred one-group-at-a-time release, separate per-event joules versus cumulative exposure, zero added scatter, transferred-mass conservation, point-velocity inheritance, and reset.

Reproduce on Windows from the repository root:

```powershell
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --check-only --script "$PWD/app/tests/test_crash_wreck.gd"
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --script res://tests/test_crash_wreck.gd
```

The pinned Godot 4.7.2 headless run reports **135 checks, 0 failures in 35.78 seconds**, with a clean exit across all four aircraft. The harness builds models through the render adapter directly, so it isolates wreck behavior from the flight director and audio route. It checks sleeping-piece stability across pause/resume. Drafts and the verbose run log are kept under ignored `.tools/crash-wreck-draft/`. This test does not establish a visual-quality, target-GPU, friction, or flight-physics acceptance result. Contact-shadow shader first-use cost is not measured.
