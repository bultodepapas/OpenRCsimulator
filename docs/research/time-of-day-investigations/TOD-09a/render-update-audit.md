# TOD-09a — Render-update audit

2026-10-10 · Status: code audit only; proposed prerequisite sequence, with no implementation or performance claim.

Parent: [time-of-day plan](../../../TIME-OF-DAY-PLAN.md) · Prior step: [TOD-08b](../TOD-08b/README.md)

## Why the clock comes first

TOD-09a should establish deterministic solar time before changing the renderer. Derive the instant from an integer simulation tick and an explicit civil anchor, fixed UTC offset and rate, as specified in the [plan](../../../TIME-OF-DAY-PLAN.md#open-steps-and-acceptance). Do not derive it from `_process(delta)`, operating-system time, or wrapped `sim_clock`. The current [visual timeline](../../../../app/environment/visual_timeline.gd) is fixed-time (`rate = 0`) with ordered edits; it cannot yet represent progression.

The production [Main loop](../../../../app/main.gd#L337) currently advances shader and cloud clocks from simulation time, but retains one `_lighting` snapshot for the Sun, environment, materials, and airplane shadow. Paused simulation time holds in the existing render loop ([pause handling](../../../../app/main.gd#L349)); restart and calendar rollover still need an explicit clock contract and evidence. TOD-09a is that state prerequisite, not a visible-lighting change.

## Cached render consumers for a later TOD-09b

The [atmosphere factory](../../../../app/render/atmosphere.gd#L109) creates a sky material with cached sun direction/intensity, haze, apparent disc direction, sky colors, and cloud silver strength. It also creates Environment fog/exposure values and the [DirectionalLight3D](../../../../app/render/atmosphere.gd#L200). The only existing in-place atmosphere updater changes cloud offsets.

The [field builder](../../../../app/render/field.gd#L19) creates a ground shader material. Mown/runway surfaces duplicate it ([ground.gd](../../../../app/render/ground.gd#L69)), while near grass copies its current shader parameters into a separate material ([near_grass.gd](../../../../app/render/near_grass.gd#L105)). These materials cache `sun_dir`, `sun_lin`, `sun_scatter`, and `haze_lin`; ground and near grass also use `sun_dir` to project cloud shadows. Updating only the original ground material would leave its copies stale. Treeline materials use Godot's live light input, so changing the DirectionalLight is sufficient for them. The airplane's projected shadow already updates in place, but reads the current snapshot in [Main._render_pose](../../../../app/main.gd#L711).

The optional scenery has the directional geometry blocker. [Scenery.build](../../../../app/scenery/scenery.gd#L113) uses the snapshot to set shared shadow-material opacity and to build projected shadows for nearby props. [GroundFeatures.contact_shadow](../../../../app/scenery/ground_features.gd#L101) turns the Sun direction into mesh vertices; [Scenery.build](../../../../app/scenery/scenery.gd#L203) then merges those vertices into per-cell shadow meshes. A live light update alone leaves these shadows aimed at the old Sun. The merged output does not retain per-placement shadow ownership. Other scenery geometry uses static vertex colors and normals with lit materials; that geometry is not sun-baked. [Flight-cue shadows](../../../../app/render/flight_cue_shadows.gd#L16) are local contact cues, not directional shadows, and need no solar-direction update.

The proposed TOD-09b seam is a scene-local binding of the existing Environment, sky material, Sun, and every ground/surface/near-grass shader material, updated in place from one lighting snapshot. Update the airplane shadow from that same snapshot. Give scenery shadows a separate bounded policy: retain enough placement data to replace only shadow batches at a measured cadence, or prototype a shader projection. Do not rebuild the complete field in the progression path. These are recommendations from the current code structure, not implemented behavior.

## Gate before visible 1× progression

TOD-09c should enable visible 1× progression only after 09a proves tick-to-instant determinism and lifecycle behavior, and 09b proves every cached consumer receives the same snapshot, scenic shadows remain coherent through low-Sun changes, and the chosen update cadence has an acceptable measured worst-frame cost. Include equal-tick results across frame rates, pause/focus/crash/restart, midnight/year rollover, horizon cases, and scenery on/off. No such in-place update or cadence measurement is claimed here.

The only cited cost is the existing TOD-08b paused-Apply measurement: 392–412 ms with scenery off and 478–512 ms with scenery on under llvmpipe. It measures full resource preparation/replacement, not a proposed 09b update path or target-GPU performance; see [TOD-08b verification](../TOD-08b/README.md#verification).
