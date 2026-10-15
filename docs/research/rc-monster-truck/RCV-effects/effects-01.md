# RCV-25 effects 01: tire dust, grime and vehicle lights

**Date:** 2026-10-14. **Status:** render implementation, focused software checks, and native Compatibility fixture review complete. **Scope:** bounded tire dust, per-instance dirt overlays, and MT8 lighting presentation. This does not qualify physical soil interaction, damage, or vehicle realism.

## Implementation

`app/vehicles/ground/ground_effects.gd` prepares effects from the existing MT8 model bindings. It reads accepted telemetry and controls but never writes simulation state. Its render adapter samples the existing road callback once per tire using the render-to-NED mapping `north = -z`, `east = x`. Dust requires a loaded tire contact, a dirt/gravel/grass surface, and measurable road speed or tire slip. The source sits at the sampled ground height below the tire. Asphalt and airborne tires produce no dust.

Four `CPUParticles3D` emitters use the already-bundled `res://assets/crash/smoke.png` texture. Their fixed budget is 24 particles per tire (96 total), with world-space motion so emitted puffs remain behind as the truck moves. The puff quad is 0.20 m, and newly emitted puffs scale their translucent opacity with the continuous dust level. The unshaded particle material consumes vertex color as albedo, so that tint and opacity reach the renderer; night tint cools and dims newly emitted dust. Pausing stops emission and sets particle speed to zero. `reset()` restarts and clears each emitter.

Grime accrues from off-road contact and dust intensity using the caller's simulated elapsed time, capped at 0.1 s per render update and at 0.46 total. A private shader material overlay sits on the imported `Body` mesh and four `WheelMesh` bindings. The existing surface materials, material overrides, meshes, source model bytes and node names stay unchanged. The shader concentrates body grime below the shell midpoint and gives tire overlays a broad dirt tint.

The truck gets two warm forward SpotLight3D beams with shadows disabled and six small emissive lens fixtures. The public `headlights_enabled` flag controls headlight beams and lenses, including dark lens albedo when disabled; `night_weight` raises their brightness from a dim daytime level. Rear red and white lamp albedo/emission follow brake and reverse controls independently of the headlight toggle. `diagnostic_snapshot()` reports tire emission levels, particle caps, grime, light states, and pause state.

## Verification

Run the focused test with the pinned Godot 4.7.2 Windows binary:

```powershell
& .tools/Godot_v4.7.2-stable_win64.exe --headless --audio-driver Dummy --path app --script res://tests/test_rcv_ground_effects.gd
```

Result: `RCV ground effects: 91 checks, 0 failures`. The test uses the bundled MT8 source mesh and verifies tire binding, contact/surface/speed/slip gating, NED road sampling, ground-height emission, the 96-particle cap, particle vertex tint/opacity binding, continuous puff opacity, night dust tint/dimming, pause freezing, dirt reset, light albedo and emission controls, livery references, and unchanged SHA-256 values for the source GLB and smoke texture.

The native Compatibility capture uses a static `Model.build()` pose and staged maximum-dust telemetry; it is presentation evidence, not a driving result. At that maximum load the livery and chassis remain legible, with dust concentrated around and behind the tires. The final artist opacity response is proportional to the square root of activity, capped at 0.8 before material alpha and night dimming. Particle vertex color is explicitly bound to albedo. The night views show the lamp lenses and brake/reverse signals; projected ground light is subtle in this isolated fixture, so the [integrated driving captures](README.md#native-visual-review) are separate evidence. The capture receipt records the renderer, output dimensions, visual-fixture inputs, controls, and SHA-256 identities for the model, smoke texture, effect script, shader, and capture script: [`native-capture.json`](../../../../research/rc-monster-truck/effects/native-capture.json).

Captured views: [day dust](effects-day-dust.png), [night headlights](effects-night-headlights.png), and [night brake/reverse lamps](effects-night-rear-lamps.png). Recreate them with the command recorded in the receipt; the capture driver is [capture_ground_effects.gd](../../../../research/rc-monster-truck/effects/capture_ground_effects.gd).

## Primary API references

- [Godot 4.7 CPUParticles3D](https://docs.godotengine.org/en/4.7/classes/class_cpuparticles3d.html): fixed particle amount, global coordinates when `local_coords` is false, `speed_scale` pause, and `restart()` lifecycle.
- [Godot 4.7 GeometryInstance3D](https://docs.godotengine.org/en/4.7/classes/class_geometryinstance3d.html): the material overlay used to layer grime over existing model surfaces.
- [Godot 4.7 SpotLight3D](https://docs.godotengine.org/en/4.7/classes/class_spotlight3d.html): forward projected lights for the headlamps.
