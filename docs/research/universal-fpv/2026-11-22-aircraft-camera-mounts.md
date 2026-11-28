# Aircraft FPV positions, cockpit structure and glass

**Date:** 2026-11-22. **Runtime baseline:** `7940a4081e10994f34c858c4acac3d7a1a271464`; the same runtime is present in planning parent `e8d0128d12d46656a7511301254f32c7f73c5f6c`. **Scope:** catalog, source builders, physical/model metadata, imported GLB JSON and existing Turbo Lumber exterior inspection images. No application run, new capture, Blender edit, numerical test or hardware measurement was performed. Source findings support the proposed positions; they do not establish exact lens placement or a usable inside picture.

The [execution plan](../../plans/universal-fpv.md#32-mounts-frames-and-optical-geometry) owns implementation and acceptance. This audit supplies the aircraft-specific evidence for CAM-FPV-00a/01a/02b/02e/04/06/07. The earlier [OSD review](2026-11-22-osd-deep-dive.md) and [20-repository survey](2026-11-22-github-code-survey.md) remain applicable: all positions use one shared OSD/telemetry pipeline and the achieved optical pose.

## 1. Requirement and census

The owner requests a clear forward/nose view, an inside-cockpit view with visible posts and clear or realistically reflective glass, and a forward-looking view near the top of the tail/rudder. Cockpit look uses two axes. Aircraft without a cabin get front only; the MoonRunner X99 flying wing is the explicit example. A cabin-equipped aircraft without a suitable conventional tail would receive front and cockpit only. No wing or winglet position is added to manufacture a uniform count.

The [catalog](../../../app/app_state/aircraft_catalog.gd), including `player_entries`, `airplane_flyable_entries`, `canonical_id` and `entry`, establishes:

- **8 player-selectable airplanes** across 8 visual families.
- **3 additional hidden airplane configurations**, the finite-glow Stiks; these remain in technical flyable coverage.
- **1 rotorcraft**, `xcell-60-research`, using the `hx-700` visual surrogate. It remains in universal FPV coverage but is outside this airplane-position count.
- `skywalker-x8` is a compatibility alias for MoonRunner physics, with its own retained legacy presentation path. It is not another catalog entry.

Raw data files are not the menu. Synthetic electric fixtures, alternate prop specimens and other unregistered data files are not counted as additional stock airplanes. User-imported Creator packages are variable installations and need a separate admission path; this audit does not claim to have inspected every installed user asset. The [aircraft contract](../../AIRCRAFT_CONTRACT.md#scope-and-authority) also distinguishes technical configurations from stock selection.

## 2. Complete airplane matrix

`front`, `cockpit` and `tail` below are proposed stable mount IDs. A requested position is a delivery target, not an implemented or visually qualified feature. Every `front` still needs exact placement and clearance; every cockpit needs an admitted eye/look envelope and glass/interior treatment. Turbo Lumber's cabin exterior is established, while its usable inside view remains additional asset work.

| Catalog ID | Stock selection | Required position target | Source finding and work |
| --- | --- | --- | --- |
| `jensen-das-ugly-stik-60` | Ugly Stick | `front` | Procedural fuselage has no cabin/canopy. Fin and rudder exist, but the cabinless exception deliberately excludes tail. Check the tractor prop installation. |
| `stik-electric-6s` | Ugly Stick Electric 6S | `front` | Reuses the Stik fuselage/wings/tail with an electric nose. No cabin. Check this motor/prop placement independently. |
| `gp-extra-300s-60` | Extra 300S | `front`, `cockpit`, `tail` | Authored canopy, rim, floor, fittings and pilot; fixed fin plus articulated rudder. Prepare the inside view and qualify tractor-prop clearance. |
| `p51d-mustang-120` | P-51D Mustang | `front`, `cockpit`, `tail` | Windscreen/hood frames, tub, fittings and pilot; fixed fin plus articulated rudder. Check coaming/armour/pilot and large tractor prop. |
| `f4u-corsair-250` | F4U-1D Corsair | `front`, `cockpit`, `tail` | Imported cockpit interior, separate frame/glass, fixed fin and rudder; moving canopy. Qualify interior, canopy states and all offered liveries. |
| `sebart-avanti-s-a200-p100rx` | Vantage Jet | `front`, `cockpit`, `tail` | Active imported V2 asset has cockpit, frame/glass and fixed vertical tail/rudder. Turbine; no physical propeller. Inspect dark glazing from inside. |
| `turbo-lumber-evolution` | Turbo Lumber Evolution | `front`, `cockpit`, `tail` | Existing inspection images show a windshield, side windows/dividers and conventional tail. An admitted cabin interior and inward glass/posts still require preparation. |
| `moonrunner-x99` | MoonRunner X99 | `front` | Tailless elevon wing with rear pusher. Opaque `canopy_hatch` is equipment cover, not a cockpit. No cockpit/tail/winglet position. |
| `stik-glow-61fx-2t` | Hidden technical configuration | `front` | Shared cabinless Stik visual; finite MAX-61FX installation and selected prop diameter require their own coverage. |
| `stik-glow-55ax-2t` | Hidden technical configuration | `front` | Shared cabinless Stik visual; finite MAX-55AX installation and selected prop diameter require their own coverage. |
| `stik-glow-fs64v-4t` | Hidden technical configuration | `front` | Shared cabinless Stik visual; finite FS-64V installation and selected prop diameter require their own coverage. |

The target is **18 selectable-airplane position/configuration pairs**, plus **3 hidden-configuration pairs**. This counts coverage cases, not simultaneously active cameras. An asset gap in a required stock cockpit is work to complete; do not quietly ship a reduced matrix and label the aircraft request finished. No exact camera coordinates or universal pan/tilt angle limits are supplied by this source audit.

### Source chain for each visual family

The catalog supplies physical data; [Airplane.build](../../../app/render/airplane.gd) resolves the visual family through the [model registry](../../../app/aircraft/model_registry.gd), validates the builder result and applies admitted paint/customization. Follow the manifest selected at runtime, rather than an older similarly named builder.

| Family / physical source | Active model source | Builder or imported visual |
| --- | --- | --- |
| [Stock Stik data](../../../app/data/aircraft/jensen_ugly_stik_60.json); hidden [61FX](../../../app/data/aircraft/stik_glow_61fx_2t.json), [55AX](../../../app/data/aircraft/stik_glow_55ax_2t.json), [FS64V](../../../app/data/aircraft/stik_glow_fs64v_4t.json) | [Stik manifest](../../../app/data/aircraft_models/jensen-das-ugly-stik-60.json) | [Procedural Stik](../../../app/aircraft/ugly_stik_model.gd) and equipment builder |
| [Electric Stik data](../../../app/data/aircraft/stik_electric_6s.json) | [Electric overlay manifest](../../../app/data/aircraft_model_overlays/stik-electric-6s.json) | [Electric builder](../../../app/aircraft/stik_electric_model.gd), sharing the Stik airframe geometry |
| [Extra data](../../../app/data/aircraft/gp_extra_300s_60.json) | [Extra manifest](../../../app/data/aircraft_models/gp-extra-300s-60.json) | [Extra builder](../../../app/aircraft/extra_300s_model.gd) |
| [P-51 data](../../../app/data/aircraft/p51d_mustang_120.json) | [P-51 manifest](../../../app/data/aircraft_models/p51d-mustang-120.json) | [P-51 builder](../../../app/aircraft/p51d_model.gd) |
| [Corsair data](../../../app/data/aircraft/f4u_corsair_250.json) | [Corsair manifest](../../../app/data/aircraft_models/f4u-corsair-250.json) | [Imported builder](../../../app/aircraft/imported_model.gd), [F4U GLB](../../../app/assets/aircraft/f4u-corsair-250/f4u_corsair.glb), [compiled geometry](../../../app/aircraft/f4u_corsair_geometry.gd) |
| [Vantage data](../../../app/data/aircraft/sebart_avanti_s_a200.json) | [Vantage/Avanti manifest](../../../app/data/aircraft_models/sebart-avanti-s-a200-p100rx.json) | Imported builder, [Avanti GLB](../../../app/assets/aircraft/avanti-s-a200/avanti_s.glb), [compiled Blender geometry](../../../app/aircraft/avanti_s_blender_geometry.gd) |
| [Turbo Lumber data](../../../app/data/aircraft/turbo_lumber_evolution.json) | [Lumber manifest](../../../app/data/aircraft_models/turbo-lumber-evolution.json) | Imported builder, [Timber GLB](../../../app/assets/aircraft/turbo-lumber-evolution/timber.glb), [compiled geometry](../../../app/aircraft/timber_geometry.gd) |
| [MoonRunner data](../../../app/data/aircraft/moonrunner_x99.json) | [MoonRunner overlay manifest](../../../app/data/aircraft_model_overlays/moonrunner-x99.json) | Imported builder, [MoonRunner GLB](../../../app/assets/aircraft/moonrunner-x99/moonrunner_x99.glb), [compiled geometry](../../../app/aircraft/moonrunner_x99_geometry.gd) |

## 3. What the actual models provide

### Ugly Stick and its propulsion variants

`UglyStik.build()` assembles `_fuselage`, `_wings`, `_tail` and equipment; it has no cabin/canopy construction. `_tail()` supplies `fin`, `rudder_hinge` and `rudder`. `StikElectric.build()` reuses that airframe and installs a different electric motor/prop presentation. Therefore the front-only outcome follows the explicit cabinless rule, not a mistaken claim that a Stik has no rudder.

The presentation adapter scales eligible propellers to the selected physical installation. A mount proven against one Stik engine or prop diameter does not automatically qualify the other four configurations. Place the optical point relative to fixed structure, ahead of the relevant swept geometry for the neutral clear picture; do not parent it to `propeller` or its spin node.

### Extra 300S

`_canopy()` builds `canopy`, `canopy_frame` and `cockpit_floor`. The frame is a painted perimeter, not proof of a complete set of interior posts. `_cockpit()` adds seat/instrument fittings, and `_pilot()` adds separate pilot geometry. `_tail()` includes `fin_frame`, `fin`, `rudder_hinge` and `rudder`.

`_glass()` reads appearance tint/alpha and deliberately falls back to opaque material when alpha is at least 1. The current [appearance](../../../app/aircraft/extra_300s_appearance.gd) uses alpha 0.28. The material cache and exterior-oriented faces need explicit treatment for an inside view; lowering alpha alone does not admit it. Define the eye above the useful interior surfaces, qualify pilot occlusion and supply any missing inside-facing surfaces. Preserve the authored canopy form rather than add generic posts that the aircraft does not have.

### P-51D Mustang

`_canopy()` separates `windscreen`, `windscreen_frame_1`, `windscreen_frame_2`, `windscreen_frame_front`, `canopy`, `canopy_frame`, hood rails, `cockpit_tub`, `gunsight` and `armour_plate`. The pilot is separately constructed. Its tail similarly separates fixed structure from `rudder_hinge`/`rudder`.

This is useful reuse, but the tub is a dark surface over the exterior deck, not a verified enclosed cockpit at a useful eye position. Check fuselage skin, pilot/head, armour and coaming against the full look envelope. The current alpha glass is cached and exterior-oriented; make the inside material/surface treatment intentional. The presentation adapter records the matched 26-inch visual/physical prop as a reason for installation-specific front clearance.

### F4U-1D Corsair

The active imported GLB names `cockpit_interior`, `canopy_frame`, `canopy_glass`, `windshield_glass`, `fin_fixed`, `rudder_hinge` and `rudder`. Metadata inspection of the 13 declared livery GLBs found the cabin nodes and double-sided alpha-blended glazing (alpha 0.12). This establishes source bindings/material intent, not visibility from an eye point or equivalent render results across all paints.

The compiled canopy mechanism moves `canopy_frame` and `canopy_glass`; [imported_model.gd](../../../app/aircraft/imported_model.gd) applies the mechanism. Keep the cockpit eye attached to body structure and check both open and closed canopy states. A camera parented to the sliding glass would move with an unrelated mechanism. Tail mounting likewise stays on fixed structure, not the rudder hinge. Check the physically scaled tractor prop and articulated travel separately from cabin admission.

### Vantage Jet

The catalog's Vantage uses the imported Avanti V2 scene. Its GLB contains `cockpit` with seat/tub/console/panel material roles, `canopy_frame`, `canopy_glass`, `vertical_tail_fixed`, `rudder_hinge` and `rudder`. Glass metadata is double-sided alpha blending with alpha 0.8; this comparatively dark value needs an inside-readability review rather than an assumed clear cockpit.

The manifest's `rotor.present = false` means the importer's `propeller` node is a compatibility wrapper, not evidence of a real front prop. The source geometry has `probe_fin_top`; it can help locate fixed structure but is not an authored FPV mount or a qualified lens coordinate. Inspect the active GLB/manifest, not a superseded procedural Avanti builder.

### Turbo Lumber Evolution

The active imported GLB includes `canopy_glass`, `fuselage_core`, `fin_fixed`, `rudder_hinge`, `rudder`, `propeller_spin` and `propeller_rotor`. None of its 36 nodes is named cockpit/interior. Its glazing is alpha blended and not double-sided. Those metadata facts alone do not establish a cabin. The committed TT-20 [nose close-up](../timber-integration/TT-20/inspection/inspection_nose_left.png) and [oblique exterior](../timber-integration/TT-20/inspection/inspection_oblique_front_left.png), inspected in this audit, do show a sloped windshield, side windows with visible dividers, the high-wing cabin shape and conventional fin/rudder. They establish exterior cabin eligibility, not a usable eye volume or inward glass/post rendering. The [TT-20 record](../timber-integration/TT-20/README.md) owns those older captures; they are not new FPV evidence.

Require all three positions, with explicit interior preparation before admission. Inspect the actual window/cabin boundaries, separate glass from opaque supports, create missing inside surfaces through the asset source and qualify the eye/look envelope. Do not advertise completion based on the word `canopy`. Do not classify the aircraft as cabinless solely because there is no node named `cockpit`. The remaining inside-view evidence belongs to 00c/02e.

### MoonRunner X99 and the legacy X8 route

The physical data declares a tailless, single-pusher elevon aircraft. `canopy_hatch` uses opaque foam/livery material; it is equipment cover, not a pilot cabin. Camera-door nodes are unbound static geometry and do not supply an admitted lens. This agrees with the owner's explicit **front only** requirement. The rear pusher still needs a safe look envelope if optional pan/tilt looks aft.

`canonical_id("skywalker-x8")` returns `moonrunner-x99`, but `entry("skywalker-x8")` intentionally retains both legacy ID and visual family in its compatibility result. It selects the [legacy manifest](../../../app/data/aircraft_models/skywalker-x8.json) and [legacy GLB](../../../app/assets/aircraft/skywalker-x8/skywalker_x8.glb) while using MoonRunner physics. Test that path in addition to the current overlay; blindly canonicalizing presentation would lose a supported asset route. Both original Skywalker and MoonRunner livery metadata retain opaque hatch treatment.

## 4. Shared implementation seams and source ownership

### Structural frames and placement

The inspected geometry uses model axes right +X, up +Y and nose −Z. [Frames.cg_in_model_frame](../../../app/render/frames.gd) maps the physical leading-edge datum into that model frame; `root_transform` places the structural root relative to the simulated CG. The Stik visual datums are `model_z_le = −0.115`, `model_y_thrust = −0.005`; Extra uses `−0.1088, 0`; the other listed stock manifests use `0, 0`. These are existing model datums, **not proposed lens coordinates**.

[main.gd](../../../app/main.gd) constructs the scaled model CG and reapplies Workshop root scale after each root transform. Resolve a local structural mount through the actual drawn root transform, apply imported source placement and uniform scale once, and remove scale from the optical rotation basis. A cached CG-to-camera offset would detach the lens from the mesh as CG changes. A second body interpolation would disagree with the drawn aircraft.

The existing [shadow bounds helper](../../../app/render/shadow.gd) provides a root-space extent, not proof of cabin location, a safe fin top or unobstructed line of sight. Bounds can support a labelled estimated front candidate; they cannot establish cockpit/tail semantics. Keep each family's existing camera owner and accepted/drawn-pose path.

### Materials, visibility and mechanisms

The [imported builder](../../../app/aircraft/imported_model.gd) resolves checked nodes and can duplicate active surface materials for particular bindings. [Airplane.build](../../../app/render/airplane.gd) applies vehicle paints, customization, lighting and custom skins, including retained surface overrides for Lumber. Procedural builders cache materials. Work with the accepted instance and exact surface identity, keep explicit originals and restore them on exit/replacement/refusal. A global cached-material edit would affect other instances and exterior views.

Recompose the view treatment when a new paint/model revision is accepted; restoring a snapshot from the previous paint would be incorrect. The existing [magnifier](../../../app/render/camera/magnifier.gd) tags aircraft meshes with `1 << 18` and uses a separate camera; crash debris uses `1 << 19`. Coordinate layer allocation and all auxiliary consumers. When glass and a post share a node, a node-wide hide is insufficient: use admitted surface bindings or split the source geometry. Preserve material overrides and source resources, not only node visibility.

Keep opaque structural frames independent from glass. A clear cockpit may omit only the glazing for that camera, while realistic glass needs a qualified inside-facing material/surface path. A layer mask selects mesh visibility, not a material variant. The chosen camera-specific strategy must preserve other cameras, shadows, paint and mechanism behavior; never hide physics colliders or the entire aircraft to make an eye position pass. Check the Corsair sliding canopy and rudder movement without moving their body-fixed lenses.

### Imported and generated assets

The [model binding source](../../../assets/aircraft/model-bindings.json) and per-overlay sources feed generated manifests. The [model manifest validator](../../../app/aircraft/model_manifest.gd) accepts a closed field set with no current camera/glass/interior semantics. Mount/visibility metadata therefore needs a compatible versioned presentation extension or identity-bound companion coordinated with CAM-13/AS; it is not an existing free-form field that can be pasted into the current manifest or strict physical JSON contract.

| Source family | Existing generation owner to extend when needed |
| --- | --- |
| Stik / electric Stik | [Stik geometry compiler](../../../assets/aircraft/ugly-stik-60/compile_geometry.py), procedural builders, and the [electric overlay bindings](../../../assets/aircraft/stik-electric-6s/model-bindings.json) |
| Extra | [Geometry compiler](../../../assets/aircraft/extra-300s-60/compile_geometry.py), authored geometry/appearance and procedural builder |
| P-51 | [Geometry source builder](../../../assets/aircraft/p51d-mustang-120/build_geometry.py) and [compiler](../../../assets/aircraft/p51d-mustang-120/compile_geometry.py), procedural builder |
| Vantage | Authored Blender delivery and [Blender geometry compiler](../../../assets/aircraft/avanti-s-a200/compile_blender.py) |
| Turbo Lumber | Authored model delivery, [geometry builder](../../../assets/aircraft/turbo-lumber-evolution/build_geometry.py) and [compiler](../../../assets/aircraft/turbo-lumber-evolution/compile_geometry.py) |
| Corsair | Authored model delivery and [F4U model compiler](../../../research/f4u-corsair/F4U-05/compile_model.py) |
| MoonRunner / legacy X8 | [MoonRunner geometry generator](../../../research/aircraft-standardization/build_moonrunner_geometry.py), [overlay bindings](../../../assets/aircraft/moonrunner-x99-overlay/model-bindings.json), and [legacy compiler](../../../research/skywalker-x8/X8-02/compile_model.py) |

Changing a compiled geometry file alone is not a durable fix. Preserve source/model/asset identity and regenerate dependent manifests/hashes using the owning pipeline. Interior work must not change physical geometry/laws merely to clear a camera.

Creator imports require a different admission adapter: [visual_builder.gd](../../../app/workshop/creator/visual_builder.gd) supplies its own package presentation and `model_transform()` rather than a normal stock manifest. [visual_paint.gd](../../../app/workshop/creator/visual_paint.gd) can replace every surface with an opaque Solid paint; original mode preserves imported materials. [ClearView conversion](../../../app/workshop/creator/clearview/converter.gd) may merge static parts and derive alpha blending from texture/material opacity. Neither transparency nor a guessed name safely identifies glazing. Bind source-specific glass/structure after the admitted transform, repair separability in the source/converter if required, or report a useful unsupported cockpit state for that imported package. An imported model's flight admission alone does not qualify inside views.

## 5. Renderer evidence and limits

Official sources accessed 2026-11-22:

| Primary reference | Constraint carried into the plan |
| --- | --- |
| [Godot 4.6 StandardMaterial3D](https://docs.godotengine.org/en/4.6/tutorials/3d/standard_material_3d.html) | Alpha blending has sorting/cost limits and does not receive screen-space reflections. Use restrained supported reflection/environment cues; do not require transparent SSR for realistic glass. A node override is separate from editing a shared mesh material. |
| [Godot 4.6 rendering limitations](https://docs.godotengine.org/en/4.6/tutorials/3d/3d_rendering_limitations.html) | Transparent objects sort by node position and can overlap incorrectly; depth prepass is not a universal fix. Splitting glass from opaque structure is useful. Near/far precision and clipping require actual view qualification. |
| [Godot 4.6 Camera3D](https://docs.godotengine.org/en/4.6/classes/class_camera3d.html) | `cull_mask` selects `VisualInstance3D.layers`; it does not define per-camera materials, and GI has separate layer behavior. |

These references guide design; they are not runtime proof for OpenRC's engine. [STACK](../../STACK.md) pins **Godot 4.8-beta2**, with Forward+, Mobile/native Metal and retained Compatibility paths as applicable. Qualify Clear and Realistic on the actual selected backend, from inside/outside, with bright/dark backgrounds, day/night, prop blur, smoke, canopy motion and paint variants. Keep realistic effects scalable and leave disabled effects without ongoing work. Realistic glass means useful visual cues within the measured renderer budget, not an unverified promise of physically exact optics.

## 6. Required evidence before calling the positions complete

The [plan packets](../../plans/universal-fpv.md#4-phases-and-subphases) retain their existing 9-phase/38-packet identities. 00a records this source census; 00c captures starting geometry; 01a defines mount/binding admission; 02b authors position sets/selection; 02e prepares cockpit/glass and optics; 04 provides two-axis cockpit look; 05e projects the shared OSD; 06 covers persistence/restore/replay; 07 qualifies the complete matrix.

| Case | Independent expected result |
| --- | --- |
| Every catalog configuration and alias | Exact matrix coverage; hidden fixtures stay hidden, X99 remains front only and its legacy visual path is checked. A missing required stock position blocks final release. |
| Neutral front view at all offered FOVs | Whole forward picture clears skin/spinner and installed prop swept geometry, including selected diameters and scale; no moving prop parent or camera collision push-out. |
| Cockpit yaw/pitch at limits, recenter and bank | Eye stays within admitted geometry; posts/coaming remain plausible; full joint composition is correct, with no invented independent roll cancellation. |
| Tail view and rudder input | Camera remains fixed to structure near the fin top and looks forward over the aircraft; rudder deflection does not steer it. |
| Canopy open/closed and pilot visibility | Body-fixed eye remains stable; own-pilot occlusion uses explicit view bindings; glass and opaque supports move according to their real mechanism. |
| Clear/Realistic, paint change and return to exterior | Inside glass is readable, posts stay opaque, materials/visibility restore exactly and a second aircraft instance is unchanged. |
| Fuel/CG, Workshop scale and imported transform | Lens follows structural geometry using the drawn pose; no doubled datum/scale or frozen CG offset; independent expected positions and axes agree. |
| Mount switch, invalid saved revision and refused load | Only supported positions offered; switch stages final pose/bindings and one cut, clears held rates and restores mount-specific settings. Refusal keeps the prior accepted view. |
| OSD while changing positions/glass | Same observation/alert/estimate/statistics owners persist; horizon/navigation use actual new optical pose and body attitude retains its meaning. |
| Runtime and hardware qualification | Source/asset identity, eye/limits/FOV, backend and captures recorded per mount. 1080p first, native output/internal pixels on Apple Silicon Retina; performance and pilot acceptance stated separately. |

Existing suites worth extending were **source-inspected, not run**: [aircraft render contract](../../../app/tests/test_aircraft_render_contract.gd) enumerates flyable configurations; [imported aircraft model](../../../app/tests/test_imported_aircraft_model.gd) checks isolated instance overrides/shared assets; [Creator visual](../../../app/tests/test_creator_visual.gd) covers transformed placement; [F4U verification](../../../app/aircraft/verify_f4u.gd) checks canopy frame/glass movement. The existing [frames](../../../app/tests/test_frames.gd), [camera settings](../../../app/tests/test_camera_settings.gd), [camera history](../../../app/tests/test_camera_history.gd) and route suites supply shared seams. Extend them with the independent geometry/ownership cases above; metadata tests alone cannot prove a usable cockpit image.

The integrated plan deliberately adopts fixed-fin attachment, body-fixed cockpit eyes, per-instance material/visibility restoration and two-axis capability limits. It rejects automatic cockpit admission from a canopy node, a generic tail point from bounds, global glass changes and counting the X99 alias as another airplane. Remaining geometry and runtime evidence is explicit implementation work.
