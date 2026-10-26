# Aircraft lighting

FW-35c, 2026-10-19. Aircraft lights are presentation state, shared by the fixed-wing flight route, helicopter route and Home previews. They never change flight physics, battery consumption or recorded control inputs. [Verification](research/field-world/FW-35c/README.md).

## Pilot controls and defaults

Use **L** or the controller's **Cycle lights** action. Airplanes retain ALL → NAV → OFF; the first daytime press selects ALL. NAV includes navigation lights and strobes. The helicopter retains AUTO → ALL → NAV → OFF → AUTO. Keyboard repeat does not cycle. The flight HUD shows the current resolved mode and marks automatic operation.

Automatic lights turn fully ON at **17:30 local simulator time**, including flights loaded after that time. Time comes from the accepted fixed `time_of_day_config.local_seconds`, or the field world's civil clock. Flowing worlds use the exact simulation clock and configured time scale, independently of the sky's update cadence. The OS clock and timezone are never used. The legacy fixed-sun scene has no civil time and retains its daytime default.

The established solar rules continue before 17:30 and after midnight: airplanes light below 6° solar elevation; the helicopter retains its smooth fade from 3° to −4°. Dawn therefore keeps its existing lighting behavior. Manual ALL, NAV or OFF takes priority over every time/solar update, paused time edit and sky/moon change.

The override belongs to one flight. The existing session `resetting` boundary clears it: successful restart, aircraft-data reload or checkpoint restoration resumes automatic selection. Rejected edits/reloads do not clear it. Starting another flight or changing aircraft starts automatic selection independently; no override is saved in preferences or physical checkpoints. A helicopter `--heli-lights=all|nav|off` supplies an initial override; its next session reset resumes AUTO.

## Programmable RGB builds (FW-RGB)

The Workshop lighting extension provides programmable fitted strips, lamp colors, bounded show effects and saved per-build settings. Its [implementation record](research/night-flight-lighting/implementation.md) identifies the checked behavior and open visual/performance gates; the [masterplan](night-flight-lighting-masterplan.md) remains the specification for later authoring and quality work.

The data contract is `openrc-aircraft-lighting` v1 inside presentation envelope v3 (also retained by later envelopes). Historical v1/v2 presentations inherit the original kit. The six materialized presets are Classic RC, Night Radian, Neon RGB, Night Aerobatics, Festival / Fireworks and Custom. Custom starts with every semantic zone available for editing and its optional effects disabled. Profiles can also explicitly inherit the aircraft equipment or disable lighting.

Use Workshop → Lighting → preset, then expand zones or effects for advanced editing. Save a build to retain colors, brightness and patterns with that aircraft variant; Trial flight uses the accepted draft. The night preview is local to the Workshop and does not change flight weather or time. The existing L/controller light control still selects ALL/NAV/OFF; NAV suppresses decorative strips and show effects.

Library → **Review compatible settings** previews the applied and skipped presentation settings before copying. Lighting appears as **Lighting / RGB profile**. Copying retains the complete semantic profile, including sequences and effects, as one Undo edit. The target preview reports missing hardware; unavailable lighting choices remain saved for later aircraft/profile reuse. A copied lighting profile does not add equipment to the target airframe. Home's catalog preview uses stock appearance; saved lighting belongs to the selected Workshop build and its trial/variant launch.

The Lighting page counts the enabled zones and effects available on the preview aircraft. **View aircraft support** expands the full list. Unavailable zones remain selectable and editable, with a reason beside their controls; their choices are retained in the build. Availability describes fitted hardware for the applied settings, not current brightness or visibility. Daylight, gear position and playback may hide an available light or effect. Pending edits do not change the report until applied. Original comparison explicitly suspends the draft report; returning to Draft restores it. Inherited, disabled and unavailable previews have distinct messages.

For the existing moonlit world and night exposure, select **Night, full moon** on Home. The CLI equivalent is `--time_of_day=night`. The separate `--time-of-day=HH:MM` SDR snapshot path is not equivalent and remains outside this visual qualification.

Zone edits include palette, brightness, cycle duration and telemetry response. Optional effects expose spark, trail or burst, intensity and lifetime. Apply or cancel an advanced edit before saving or flying. Navigation lock protects the saved navigation colors and patterns from editing. Expand **Edit sequence** to add, duplicate, reorder or remove cues. Each cue has a duration, pattern cycle, palette, enabled zone targets and optional enabled effect anchors. Apply cue accepts the edit into the shared draft; Save creates the durable build revision. Use the existing preview playback control to play from the beginning. There is no timeline scrubbing.

Sequences contain at most 32 cues and last at most 60 seconds before looping. Navigation targets require unlocking navigation colors and patterns. Targeted zones switch to Sequence; removing their last cue returns them to steady lighting. Undo restores the prior accepted profile. Unfinished timing/color text blocks Save/Test fly and survives draft recovery without becoming accepted lighting.

Colored strip emission and lamp sprites make the emitters visible. Short-range, shadowless OmniLights provide actual decorative spill; the existing landing SpotLight(s) illuminate the approach surface. Emission alone does not illuminate nearby objects. The authored Ugly Stik covering supports bounded rib/spar-masked emission. Opaque imported skins are not made translucent: foam transmission requires a suitable authored asset and remains separate work.

`AircraftLightingRig3D` receives the aircraft root and a validated lighting dictionary. Its `configure`, `set_mode`, `advance`, `reset`, `dispose` and `budget_info` methods remain on the rendering side. `advance` consumes displayed simulation time plus detached telemetry; preview uses its own accepted clock. Materials and VFX resources belong to the instance. Imported assets and shared resources are never rewritten.

RGB shader bindings are limited to the existing nine lamp meshes and five strips. Each `advance` allows at most 84 changed shader parameters (six per material); `set_mode` has an independent allowance of 23 so an animation update cannot delay a light-mode brightness change. Cached unchanged values cost no writes. A cue's pattern identity is accepted only after all its pattern uniforms are written. `budget_info` reports the most recent advance and mode operation separately; these are operation bounds, not a measured total frame-time budget. Unrecognized kit meshes keep their original materials and produce a diagnostic.

`capability_report()` returns detached `state`, `zones`, `effects` and `warnings` data without creating equipment or effects. Each requested row contains `id`, `enabled`, `available` and `reason`; reasons are `unsupported_group`, `missing_fitting` or `missing_anchor`, empty when available. Zones use live configured materials/lights and supported groups, with paired landing fixtures represented once. Effects use their actual mapped tip anchor and usable render world; they do not require the navigation lamp to be enabled. The Workshop preview publishes reports on configuration changes, independently of edit history and persisted profiles.

Initial semantic zones are `nav_left`, `nav_right`, `nav_tail`, `strobe_left`, `strobe_right`, `strobe_dorsal`, `strobe_ventral`, `strip_left`, `strip_right`, `strip_top_left`, `strip_top_right`, `strip_belly`, and `landing_lamp`. Wingtip show anchors are `vfx_tip_left` and `vfx_tip_right`. Aircraft equipment declarations and geometry determine availability; choosing a preset does not manufacture an unsupported lamp or a valid internal volume.

The current Timber model deliberately declares factory navigation, strobe and landing equipment only. Its five fitted orientation-strip meshes remain unavailable in every RGB preset; the Workshop explains this limitation. X8 uses the ordinary fitted external strips. Neither aircraft receives inferred translucent skin. A creator-approved Timber retrofit requires an explicit authoring/capability change, not a player preset overriding the model declaration. Availability also requires membership in the kit's accepted group bindings: an authored-disabled lamp node does not count as usable hardware. The diagnostic `zones_resolved` counter counts material bindings and must not replace the capability report in UI.

## Global lighting preferences

Settings → **Lighting** applies to every aircraft and Workshop preview. **Low** retains LEDs and landing lights while hiding decorative spill and show effects. **Standard** emits half the High particle count and samples show trails at 15 Hz; **High** retains the bounded 32-particle tip pools and 30 Hz trail sampling. These are workload controls, not hardware frame-rate guarantees.

**Aircraft show effects** immediately clears visible show transients when disabled. Reenabling waits for a new cue or maneuver event. **Reduce aircraft flashes** makes aircraft strobes steady, replaces animated RGB/cue colors with their base color, preserves static segment palettes, suppresses reactive brightness and disables show effects. It does not rewrite saved aircraft profiles or alter unrelated field strobes. Turning it off resumes the displayed-pose pattern clock.

The existing reversible Settings Keep/Revert/Close flow persists optional schema-1 keys in `display.cfg [aircraft_lighting]`: `quality` (`low`, `standard`, `high`; default `standard`), `reduced_flashes` (default false), and `show_vfx` (default true). Old files receive defaults, invalid individual lighting values fall back independently with a diagnostic, and future-version files remain read-only. Previewing these preferences changes presentation only.

### Scene grants and projected effects

`LightingSceneBudget` shares one weakly registered coordinator per actual `World3D`. A Workshop viewport with its own world has its own coordinator. Low/Standard/High permit respectively **0/2/4 decorative OmniLights and 0/2/4 allocated VFX anchor buffers per world**, with at most two of either per owner. Existing landing spots use the field's separate spot reservation. Higher explicit priority wins, then shorter camera distance, then stable owner identity; the active player supplies priority 100. Grants persist during pause and are released on disposal/reset or loss of eligible residuals. Decreases are published before increases, so handoff does not temporarily exceed the grant count.

Denied and idle effects retain no per-instance MultiMesh buffer. Their bounded CPU particles/trail samples can age while denied; a newly granted buffer is filled on the next presentation update. This can delay its first rendered frame by one update. Live CPU state drives requests independently of allocated GPU buffers, so a denied effect can regain capacity while its residuals remain alive. `budget_info().vfx` reports live CPU records, allocated GPU anchors/capacities, current grants and scene totals separately. Mesh/material resources and CPU pools remain instance-owned; this is not a total scene RAM/VRAM guarantee.

New VFX births use the aircraft bounds projected through the owning viewport's current camera. Near (>180 px), medium (60–180 px), far (12–60 px) and tiny (<12 px) tiers multiply quality density by 1, 0.5, 0.25 and 0. Thresholds have 10% hysteresis. Camera changes reset tier history without resetting the show clock. Missing camera/bounds retain the near fallback. Offscreen aircraft stop new births; existing particles and ribbons keep aging and use finite bounds derived from their own live geometry, so leaving the aircraft's screen rectangle does not hide a still-visible trail. Physical distance fades remain in effect. Shared-world inset views still require separate native qualification; the birth policy samples the owning viewport camera, not an aggregate of all views.

## Shared selection interface

[`aircraft_light_state.gd`](../app/render/world/aircraft_light_state.gd) is a persistent, flight-owned `RefCounted`. It owns timing and precedence; adapters own luminous nodes and rendering.

| API/state | Contract |
| --- | --- |
| `configure_evening(seconds)` | Seconds since local midnight, 0–86399; default 63000 (17:30). Invalid values preserve the accepted setting. |
| `set_mode("auto"|"all"|"nav"|"off")` | AUTO clears the override; other choices establish it. Invalid modes preserve state. |
| `update(local_seconds, daytime_gain)` | Resolve the current state. Adapter supplies the existing solar policy as a 0–1 gain; return value reports output changes. NAN civil time disables only the evening rule. |
| `selection`, `active_mode`, `gain` | User selection, resolved ALL/NAV/OFF and resolved light intensity. Manual ON always uses gain 1. |
| `reset()` | Resume AUTO without changing configuration. Sample the reset clock immediately afterward. |
| `cycle_mode(include_auto=false)` | Existing airplane cycle; `true` includes the helicopter AUTO detent. |

`World.aircraft_local_seconds(config, clock_s)` and `World.aircraft_sun_elevation(snapshot)` adapt both time systems. Fixed TOD uses geometric solar elevation, rather than the clamped rendering Sun. `World.dress_aircraft(...)` is an automatic-only preview helper; a flight keeps its own persistent state so repeated updates preserve manual choices.

The airplane route exposes `set_aircraft_lights(mode)` for UI consumers. Its keyboard/controller routes share the same selection operation. It creates the kit lazily, after measuring model/shadow geometry, then changes visibility only when the resolved mode changes. Dynamic anchors still follow articulated parts; gear gates can suppress a landing beam even in ALL. UI state reflects mode changes even when diagnostics are hidden.

## Adopting the standard

Catalog airplanes already use the common route, including the Stik powerplant variants. No aircraft-ID branch or new scene script is required. Keep all existing geometry, materials, hinge names and generators.

The default kit derives its positions from the model. Existing optional root metadata `light_anchors` overrides `nav_left`, `nav_right`, `nav_tail` and `landing`. Each anchor can supply a model-local `position`, a root-relative `follow` NodePath, a `follow_offset`, and `gear_gated`. The P-51 uses these existing bindings. Preserve their authoring pipeline when changing anchors.

For different equipment, the model root can declare `light_groups`, an Array containing any supported subset of `navigation`, `strobe`, `landing`, `orientation`. Omitted metadata enables all four. Landing includes the beam and its lamp sprite; orientation includes the emissive wing/belly strips. Unsupported groups stay dark in every mode.

Authored luminous effects can use `AircraftLights.bind_groups(kit, bindings, supported_groups)`. `bindings` maps group names to Arrays of `Node3D` references or kit-relative NodePaths. Bind the emitted glow and corresponding light together; bind only luminous presentation nodes, leaving reflective lens geometry intact. Invalid or duplicate references are rejected before replacing accepted bindings. Successful binding starts OFF; apply the flight state's resolved mode afterward. Instances retain their own nodes/materials; binding never edits shared source materials.

Imported emissive lenses use `prepare_emission(root)` and `set_emission_mode(bindings, mode, gain)`. Preparation caches per-instance surface overrides; it never changes the GLB, mesh or shared source material. The existing `light_red` and `light_green` materials map to navigation; root metadata `light_material_groups` can replace that material-name → group map. Timber's two imported navigation materials follow AUTO/ALL/NAV/OFF while its reflective lens geometry remains present. Preparation also runs in daylight before a kit exists. Material properties are updated only when mode/gain changes.

A different aircraft adapter should own one shared light-state instance, sample its authoritative clock and existing solar gain, apply `active_mode`/`gain` to its supported effects, and reset at its session boundary. The helicopter adapter demonstrates this while retaining rotor phase, exposure caps, its armed beacon gate and body-optic fade. Keep animation updates separate from selection changes.

## Creator-authored layouts (FW-RGB-04)

The authoritative authoring source is `assets/aircraft/customization-bindings.json` v3. Each family supplies `lighting_layout`; `research/aircraft-standardization/build_customization.py` generates companion v4. Historical source v1/v2 and companion v1–v3 remain readable. The independent presentation source-proof version stays 3; its ordered inventory includes the lighting policy, scene budget and skin helpers. Never hand-edit `app/data/aircraft_customization.json`.

The layout is creator data, separate from player lighting choices:

```json
{
  "version": 1,
  "anchors": [
    {"id": "nav_left", "node_path": ".", "position_m": [-0.7, 0.04, 0.0], "gear_gated": false}
  ],
  "strips": [
    {"id": "strip_left", "node_path": ".", "points_m": [[-0.3, -0.04, 0.0], [-0.7, -0.04, 0.0]], "face": [0, -1, 0], "width_m": 0.012}
  ]
}
```

These coordinates illustrate the schema; measure the actual aircraft before using them. Shipped point/strip declarations retain empty arrays, preserving existing fits and builder-owned mounts. Ugly Stik additionally uses the v2 skin binding below. This does not claim a new manual placement art pass across the fleet.

Authored strip patterns follow cumulative centerline distance in the host's local frame, from the first point to the last. Unequal segments receive proportional pattern space; bends and paths returning along an axis do not restart or fold the animation. Pattern `reverse` reverses travel along that same path. Host transforms move the strip while preserving its LED station colors; nonuniform scale stretches their world spacing. Legacy automatically fitted strips retain their existing axis-based pattern placement.

Segmented RGB strips filter their linear-light palette over the current camera's pixel footprint. Nearby segment interiors keep their original color; unresolved segments blend in proportion to their coverage, including incomplete palette cycles. Footprints covering the whole path converge to its weighted mean. This applies to authored and fitted RGB strips without changing saved patterns or sequence time. It reduces spatial color aliasing; it does not establish temporal-upscaler stability, aircraft orientation readability, or scene-wide performance. [Native filtering evidence](research/night-flight-lighting/implementation.md#fw-rgb-13-segmented-strip-filtering).

| Field | Contract |
| --- | --- |
| `anchors` | At most nine unique IDs: `nav_left`, `nav_right`, `nav_tail`, `strobe_left`, `strobe_right`, `strobe_dorsal`, `strobe_ventral`, `landing`, `landing_right`. Every row has exactly the four example fields. |
| `node_path` | `.` means the aircraft root; otherwise a relative path of ASCII alphanumeric/underscore node names separated by `/`, at most 160 characters. No absolute/resource paths, `..`, subnames or scripts. Host must resolve to a descendant `Node3D`. |
| `position_m` / `points_m` | Three finite numbers per position, each component in [−5, 5], in the host's local model metres. Booleans are invalid. Ancestor transforms apply once; the aircraft root supplies the world transform. |
| `gear_gated` | Boolean; only `landing` / `landing_right` may be true. Existing gear-down-and-locked policy controls both lens and beam. Point mounts follow host translation, rotation and scale; beam aiming retains the existing forward/down policy. |
| `strips` | At most five unique IDs: `strip_left`, `strip_right`, `strip_top_left`, `strip_top_right`, `strip_belly`. Each row has exactly the five example fields. |
| `points_m` | Ordered centerline of 2–32 points. Adjacent points must be at least 0.00001 m apart; segment/face cross-product magnitude divided by segment length must be at least 0.01. No per-LED nodes. |
| `face` | Host-local unit direction, length tolerance 0.999–1.001. Controls which side emits and the ribbon's across direction; do not make it parallel to a segment. |
| `width_m` | Finite width in [0.001, 0.05] scene metres. Like fitted strips, the shader maintains its physical/distance width independently of model scaling; centerline coordinates follow the host transform. |

`Airplane.build` copies the validated companion layout to instance metadata. `AircraftLights.attach` resolves it per instance after the shared geometric measurements, merges missing point anchors into the existing `light_anchors` contract, and substitutes authored ribbons only for the selected canonical strips. A strip follows its host's full transform through the existing `update_dynamic` call. Cached Home geometry never retains another instance's paths or pose. Existing builder-owned anchors win a conflict with a diagnostic. Missing hosts or invalid runtime metadata retain automatic fitting; geometry without a usable span yields an empty diagnosed kit. Source-schema errors fail generation and companion admission instead of silently publishing bad data.

Diagnostics are available in `NightKit.get_meta("layout_warnings")` and the RGB rig's configure/budget result. Layouts are installed during aircraft construction; rebuild the aircraft after changing metadata. Repeated `attach` calls retain the same kit. Original GLBs, meshes and shared materials remain untouched. VFX still uses the established wingtip kit anchors; there is no separate arbitrary VFX path registry in this revision.

Creator checklist:

1. Use the model's stable node names and local coordinates; test rotated/scaled parents and every articulated pose.
2. Keep builder-owned P-51/Timber mounts in their existing pipelines; do not duplicate them in the companion.
3. Keep omitted zones empty for automatic fitting. Check `light_groups` before expecting a fixture to illuminate.
4. Regenerate through `build_customization.py`, run its `--check` and Python tests, then the pinned `test_lighting_layout.gd` and existing kit/mount tests.
5. Inspect 1080p day/night, upper/lower views, manual light modes and gear gates. Check warnings and confirm fresh builds and cached Home previews agree.

### Authored covering illumination

Nested `lighting_layout` v2 adds a `skins` array to the unchanged v1 anchor/strip fields. Each row binds one strip zone to stable `target_id` values declared in a paint slot; it cannot load a shader, texture path or script from a saved profile. For example, the Ugly Stik left wing binds its three existing surface-0 covering meshes:

```json
{
  "version": 2,
  "anchors": [],
  "strips": [],
  "skins": [{
    "zone_id": "strip_left",
    "paint_slot_id": "wing",
    "target_ids": ["wing_left_0_skin", "wing_left_1_skin", "wing_left_2_skin"],
    "mask_profile_id": "jensen_stik_film_bays_v1"
  }]
}
```

The closed contract permits at most five skin rows and twelve unique target surfaces. The registered mask is restricted to the Stik visual family and derives from its existing project-authored rib/spar and UV recipes. Model dependencies already pin those recipes; the presentation inventory pins the compositor. The separately sourced engine is not part of this treatment. This is a thin-film visual approximation, not measured optical transmission or foam illumination.

`Airplane.build` resolves the validated paint targets into instance-only `lighting_skin_bindings`. `LightingSkins` duplicates supported `StandardMaterial3D` surfaces and composes a 512×512 mipmapped emission map with the current albedo texture/color. Ribs, spars and painted dark areas retain contrast. An owned `rgb_skin.gdshader` additive next pass decodes color before applying scene-linear energy, then uses the existing renderer encoding helper. The base surface retains its opaque shading and depth; the emission pass tests depth without writing it and does not illuminate other geometry. A strip zone's palette, brightness and reaction drive its associated skin; there is no independent per-pixel LED simulation inside the covering.

Only ALL with an enabled strip zone emits. NAV/OFF, hidden or unsupported orientation equipment, zero gain and disabled profiles suppress emission. Energy is capped relative to the supplied exposure; Reduced flashes uses the same stable policy as other aircraft emitters. Unsupported materials, pre-existing authored emission, mesh-wide overrides, unsupported UV transforms and missing targets remain unchanged with diagnostics. Disposal restores only overrides still owned by the helper, preserving later edits by another renderer component.

The mask is immutable and shared; composed textures are instance-owned, reused within that instance and cleared on disposal. `budget_info().skins` distinguishes target count, active emission passes, composed texture bytes and material writes. Each active surface adds one pass per view: six on the shipped Stik, at most twelve by contract. NAV/OFF/zero gain detach those passes. Surfaces with an existing next pass, non-back-face culling or vertex-color albedo are also skipped rather than changing their rendering. These counters do not establish total VRAM or staging-time qualification. Validate creators' day/night and upper/lower views, preserved paint/markings, two-instance independence and restoration after preview rebuilds before accepting a new mask.

### Updating saved builds

The full companion hash still pins a saved appearance, including authored geometry and presentation source hashes. Loading never silently changes that identity. For a readable old profile on the **same visual family and physical model manifest**, Workshop offers **Review appearance update**. Acceptance creates an unsaved copy with current bindings; Save creates a separate build, preserving the original revision. Undo restores the old pins and its blocked state. Colors, markings, lighting, sequences and mechanical-audio settings must remain identical except for the binding pins.

This reviewed update cannot establish equivalence of old and new slot meanings without the original companion descriptors. Missing current references, changed physical identity, future profile schemas and **any saved smoke entries** are refused. Smoke needs its original descriptor/migration path; this action does not discard it or reinterpret its outlets. Rebinding does not repair stale physical dependencies or grant flight validation. Inspect the proposed appearance before saving or flying.

## Checks

Run the focused suite with the pinned engine:

```powershell
python tools/godot/run_checked.py --label aircraft-lights --timeout 180 -- .tools/Godot_v4.8-beta1_win64_console.exe --headless --path app --audio-driver Dummy --script res://tests/test_aircraft_light_control.gd
```

For native before/after images, omit `--headless` and append `-- --capture-aircraft-lights=<absolute-output-directory>`. Use an isolated APPDATA directory for native test runs. The suite covers every fixed-wing visual family and the helicopter, actual input handlers, exact threshold crossings, manual precedence, dawn/daylight policy, new flights, resets, data reloads, Home changes, bounded attachment and configurable group references. Existing `test_night_kit.gd`, `test_p51_lights.gd` and `test_heli_night_lights.gd` retain geometry, motion, gate and emissive checks.

For the six-preset night preview matrix, run the existing aircraft visual fixture on a native renderer:

```powershell
python tools/godot/run_checked.py --label lighting-fleet-night --warnings-as-errors --timeout 600 -- .tools/Godot_v4.8-beta1_win64_console.exe --path app --audio-driver Dummy --rendering-method gl_compatibility --script res://tests/test_lighting_aircraft_visuals.gd -- --capture-lighting-fleet=C:/DEVELOPMENT/OpenRCsimulator/tmp/lighting-fleet-night
```

Choose a new absolute output directory and isolated APPDATA profile for each run; run only one rendered application at a time. The fixture captures all six presets for one catalog representative per fixed-wing visual family at 1920×1080. Its manifest records capabilities, source identities, renderer, camera and budgets. The held Workshop clock/exposure is intentionally repeatable: it cannot establish moving trails, production-night exposure, pilot readability or real-time frame cost. Use the [existing flight capture route](../tools/trailer/README.md) for advancing flight and inset evidence. Substitute `forward_plus` or `mobile` only when qualifying those native paths separately.
