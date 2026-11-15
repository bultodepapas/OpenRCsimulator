# Afterburner visual starter

This is an isolated engineering fixture, not an integrated OpenRC aircraft or qualified final artwork. It contains a two-mesh shader design intended to produce a continuous flame, an inner core and optional stationary shock-cell accents within a bounded nozzle-local extent. It consumes an externally supplied simulation clock and has no flight-physics authority. Its appearance and actual visibility have not been rendered or qualified.

## Run

From the prototype project directory, use the project's pinned Godot 4.8-beta2 executable:

```sh
godot --path . res://visual/visual_fixture.tscn
```

The scene exposes a manual output slider, a deterministic automatic sweep, three camera angles and pause/reset controls. The preview clock is local to this fixture. In production, supply the accepted/interpolated simulation clock instead.

## Minimal integration seam

```gdscript
var view = preload("res://visual/afterburner_visual.gd").new()
validated_nozzle_marker.add_child(view)
# Call only after a simulation snapshot is accepted and converted at the view boundary.
view.set_snapshot(snapshot.afterburner_actual, snapshot.sim_time_s)
```

The field names above are proposed adapter names. They are not claims about the production snapshot schema. The visual takes no control input, applies no force, consumes no fuel and changes no simulation state. `clear()` hides the effect and resets its presentation clock. Invalid numeric snapshots hide it. Normalized amounts are clamped to 0–1.

The nozzle origin is the exit plane. Local +Z points rearward. The source project's `app/render/frames.gd` confirms model −Z nose/+Z aft for the default model convention. Current Avanti Blender bindings expose `turbine.outlet_position`, `outlet_direction` and `outlet_node`; use that authored binding through the aircraft visual adapter, not this fixture's origin or a hard-coded production offset. The production adapter must rotate the component's +Z to the validated authored outlet direction, including any articulated parent transform. Do not assume every aircraft's nozzle points directly along model +Z. The source marks the installation as an estimate, not a measured P100-RX installation.

**Existing smoke transforms use the opposite local axis.** The `AircraftCustomization` smoke resolver in `app/render/aircraft_customization.gd` aligns local −Z to the exhaust direction, while this starter emits along local +Z. Reusing that resolved transform therefore requires a deliberate conversion: rotate the plume child by π radians around its local Y axis, or construct a dedicated transform that aligns the plume's +Z to the validated outlet direction. Keep any shared smoke marker unchanged. Skipping this conversion can point the flame into the aircraft.

Pass the timestamp associated with the interpolated presentation pose, rather than an unrelated latest physics tick. `phase_for_time()` reduces it before multiplication into four bounded phases; their integer cycle counts repeat continuously across the project's 1024-second shared-clock boundary. The shader receives bounded `animation_phase_rad`, not a growing float32 timestamp. Restoring a timestamp restores its phase; pausing preserves it. The fixture's own clock is for inspection only.

Set dimensions before adding the view to the tree. The prototype builds geometry once and fixes its finite culling bounds from those values. Recreate it if dimensions change; brightness/shock strength can be changed before subsequent snapshots. Each layer owns its own material, so instances do not overwrite one another. Shadow casting and GI participation are disabled. The shader has no built-in time dependency.

The caller owns graphics-quality admission. When afterburner effects are **Off**, do not instantiate this component or call `set_snapshot()`. If the setting changes to Off during a session, detach/free the component and stop its update calls; recreate it from the current accepted snapshot when enabled again. Merely setting output to zero hides the meshes but retains their allocated resources. Graphics quality must not alter the simulation's afterburner state or thrust.

## Reuse and provenance

The starter reuses Godot's native `CylinderMesh` and `ShaderMaterial`. `CylinderMesh` already creates cones when one radius is zero; a custom mesh generator would add no value here. The fixture nozzle uses built-in cylinder and torus primitives. The small original shader is glue for accepted-clock control and nozzle geometry, not a replacement for an available artwork library.

The official [Godot 3D Particles demo](https://github.com/godotengine/godot-demo-projects/tree/master/3d/particles) was evaluated as a future particle-learning/reference source. Its repository uses the [MIT license](https://github.com/godotengine/godot-demo-projects/blob/master/LICENSE.md). It is a general feature showcase rather than an accepted-clock afterburner drop-in. No demo code, texture, photograph or audio asset was copied into this starter. Any future imported asset needs its own pinned provenance/license receipt.

Primary API references:

- [CylinderMesh](https://docs.godotengine.org/en/latest/classes/class_cylindermesh.html)
- [Spatial shaders](https://docs.godotengine.org/en/latest/tutorials/shaders/shader_reference/spatial_shader.html)
- [GeometryInstance3D](https://docs.godotengine.org/en/latest/classes/class_geometryinstance3d.html)
- [Renderer features](https://docs.godotengine.org/en/latest/tutorials/rendering/renderers.html)
- [Screen-reading limits](https://docs.godotengine.org/en/latest/tutorials/shaders/screen-reading_shaders.html)

## Scope and qualification

The colors, length and cell spacing are illustrative art choices. They do not infer temperature, nozzle pressure ratio or thrust. The shader uses `ALBEDO`/`ALPHA` with the intention of supporting a baseline without bloom; actual visibility has not been observed. Default heat haze, particles, dynamic lights and environment overrides are deliberately outside the reusable component. The fixture itself has its own simple environment because it runs independently; do not transplant that environment into OpenRC's world/time-of-day owners.

Only headless software checks were completed. **Appearance, GPU shader compilation, performance and actual visibility remain unrendered and unqualified.** No image capture supports a claim of visual success. A future software-rendered Linux capture could check shader compilation and basic appearance, but would still not qualify target-GPU performance, native Apple Silicon, XR, exact cross-GPU imagery or actual JET placement.

Observed checks on 2026-11-14 used `4.8.beta2.official.cafc17a19`: project import completed, the fixture instantiated and ran headlessly without reported script errors, and `verify_visual.gd` passed 14 checks covering material isolation, pause/restoration, the 1024-second phase boundary, very large finite timestamps, invalid input, clamping/reset, bounds and shadow settings. These are software checks. A user-local Xvfb setup could not open a display because this execution environment disallows socket creation. No rendered image was obtained.

Run the focused software checks with:

```sh
godot --headless --path . --script res://visual/verify_visual.gd
```

To attempt a fixed-time rendered snapshot on a machine with a working display, supply an absolute output path; this capture path has not been verified here:

```sh
godot --path . --resolution 1920x1080 res://visual/visual_fixture.tscn -- \
  --capture=/absolute/scratch/flame.png --amount=0.85 --sim-time=4.25 --view=0
```

Capture images are inspection evidence, not distributable final art.
