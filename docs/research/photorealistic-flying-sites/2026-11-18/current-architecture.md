# Current OpenRC architecture and integration gaps

Inspected baseline: `f7b348e40aa5a44c4cc091d540fbffb55016e583`, 2026-11-18.
This is source evidence, not a runtime or benchmark result. Paths below are
existing files; proposed additions are identified explicitly in the
[design](godot-design.md). The checkout is sparse, so tracked configuration/data
must also be inspected with `git show HEAD:<path>` when absent locally.

## Engine and simulation authority

[`app/get-godot.sh`](../../../../app/get-godot.sh) pins
`4.8.beta2.official.cafc17a19` and platform hashes.
[`app/project.godot`](../../../../app/project.godot) selects Compatibility by
default and Mobile for the arm64 path; the
[`renderer_guard.gd`](../../../../app/app_state/renderer_guard.gd) and existing
graphics profile decide the effective route. The opt-in Forward+ path has its
own qualification. Do not replace the engine pin while implementing a site.

The [stack contract](../../../STACK.md#boundaries-and-data-flow) and
[`VehicleModel`](../../../../app/sim/vehicle_model.gd) separate rendering from
float64 accepted simulation state. Flight uses the custom 240 Hz kernel rather
than Godot rigid bodies. A native evaluator can replace an admitted evaluation
boundary; it does not render the scene or replace the tick transaction.

[`Frames.ned_to_render`](../../../../app/render/frames.gd) maps local metres as
`(N, E, D) → (E, -D, -N)`. That existing boundary is where a surveyed site's
positions enter Godot coordinates. Keep geographic bearings, photo orientation
and local NED explicit; a visually plausible rotated image is not evidence that
wind, runway, sun and compass agree.

## Existing seams and what they do not yet provide

| Concern | Source observation | Implication for the plan |
| --- | --- | --- |
| Registered landscapes | [`catalog.gd`](../../../../app/landscapes/catalog.gd) explicitly lists Club field and Green paradise; exposes `entry`, `build`, optional `build_staged`, and `collision_world` | Add a registered adapter and matching contact inventory; no automatic folder/plugin discovery is needed |
| Field schema | [`FieldLoader`](../../../../app/data/field_loader.gd) checks a strict `openrc-field v1` key set and unit-tagged quantities | A `panorama`, arbitrary capabilities or image filename cannot simply be inserted into field JSON; validate a separate presentation descriptor |
| Surfaces | Field surfaces are N/E-aligned rectangles; [`GroundSurfaces`](../../../../app/physics/ground_surfaces.gd), [`GroundTerrain`](../../../../app/physics/ground_terrain.gd) and [`GroundSupport`](../../../../app/physics/ground_support.gd) implement existing material/analytic-relief behavior | A rendered heightmap, Terrain3D collider or scanned mesh does not automatically supply authoritative landing contact |
| Runway heading/start | [`GroundStart.threshold`](../../../../app/physics/ground_start.gd) selects the west/east end and heading ±π/2 | Arbitrary runway bearings need owned data/start/contact work; preserve true NED or define a complete conversion contract |
| Home runway choice | [`app_root.gd`](../../../../app/app_root.gd), `_install_home` and landscape-change logic, derive availability from field ID `default` | A new field's runway requires explicit validated capability admission; never reuse the legacy identity as a workaround |
| Physical obstacles | [`collision_world.gd`](../../../../app/scenery/collision_world.gd) sorts and hashes supported proxies and bins them into 32 m cells; [`scenery_collision.gd`](../../../../app/sim/scenery_collision.gd) queries them | Initial shapes are supported oriented boxes and vertical capsules. Render silhouettes and arbitrary scan triangles are separate representations |
| Scene quality | [SC-24-R1](../../../DECISIONS.md#presentation) preserves the physical inventory across visual presets | Photo resolution, shadows or foliage quality cannot remove contacts or create hidden collidable objects |
| Loader lifecycle | [`set_landscape`](../../../../app/app_root.gd) admits field data before saving selection; [`HomeScene`](../../../../app/ui/home_scene.gd) and [`main.gd`](../../../../app/main.gd) consume adapter builds | Add sidecar/resource prevalidation and explicit failure propagation before replacing the accepted Home or flight; a null node is not a complete rollback design |

The [landscape authoring guide](../../../LANDSCAPES.md) is the current adapter
contract. The simple Green paradise adapter is a useful minimal scene, but it
has no photographed object registration, capability policy or general terrain
sampling. The `rc_track` special path is Club-specific; do not repurpose it as a
generic photo-terrain interface.

Supported collision primitives are not an existing general-purpose obstacle
authoring API. FieldLoader allows at most one field object, a validated treeline;
CollisionWorld currently derives other shapes from known scenery/light/prefab
inputs. SC-PHOTO-04 must either use a genuinely representable existing inventory
or add an SC/GP-owned validated contact-inventory builder for surveyed dimensions,
transforms, response/damage IDs, deterministic bins/hash and resource limits.
The photo sidecar links to this physical definition; it must not become an
unvalidated route into internal solver dictionaries.

Runway material is another independent gap. Production `main.gd` calls
`session.set_field(field)` with the shared surface table. The tracked
[`surface_friction.json`](../../../../app/data/ground/surface_friction.json)
labels its runway as maintained turf; the ground terrain adds estimated 1 mm
runway relief. A photograph of asphalt/concrete does not change those laws.
Select a compatible turf pilot or explicitly add site-specific surface-table
wiring/identity and native/replay qualification under SC-PHOTO-04b.

## Cameras and activity routing

[`PilotCamera.create/aim`](../../../../app/render/pilot_camera.gd) keeps the
normal pilot at the field station minus eye height in the down coordinate. This
is a good match for a captured panorama. The camera can rotate, track and change
FOV while retaining that eye.

[`CameraRig`](../../../../app/render/camera/camera_rig.gd) currently accepts
`pilot`, `chase`, `flyby`, `orbit`, and `closeup`. Its setters/cycle/update and
the main/helicopter key paths are not landscape-capability gates. Review-height
controls such as `--look_alt` also translate the eye. Saved camera settings,
settings preview, debug/CLI requests and crash framing can reintroduce a moving
camera even if Home initially selects pilot.

[`Magnifier`](../../../../app/render/camera/magnifier.gd) owns a separate
`SubViewport` and aircraft-only layer. It can reposition its camera along the
pilot-to-aircraft line to frame a distant model. Ordinary field meshes are not
drawn in that layer. It therefore needs explicit photo-site behavior; the first
pilot should mark it unavailable until a correct fixed-eye/occlusion-aware
alternative is demonstrated. Preserve its saved global preference for 3D sites.

| Activity | Current construction route | Photo-site consequence |
| --- | --- | --- |
| Home / fixed-wing | Catalog and selected field path | Add transactional descriptor admission and a fixed-eye Home composition |
| Helicopter | [`helicopter_main.gd`](../../../../app/helicopter_main.gd) uses landscape construction but has its own camera/start paths | Separate activity qualification, including rotorcraft pad capability |
| Multirotor FPV | [`multirotor_scene.gd`](../../../../app/vehicles/multirotor/multirotor_scene.gd) directly uses field/scenery builders; [`multirotor_camera.gd`](../../../../app/vehicles/multirotor/multirotor_camera.gd) is a moving onboard camera | Refuse the photo-site pairing in the pilot; later 3D/FPV work must wire the correct adapter and physical world explicitly |
| Airship / ground vehicle | [`airship_scene.gd`](../../../../app/vehicles/airship/airship_scene.gd) and [`ground_scene.gd`](../../../../app/vehicles/ground/ground_scene.gd) have their own construction | Selected field paths are forwarded by Home, so containment is required even if these activities are outside the first release |

Natural Random, companions and rotorcraft pads have separate existing restrictions.
Do not infer their compatibility from a successful fixed-wing panorama capture.
For later FPV/airship support, inspect their recorder/replay reconstruction as
well: paths rebuilding with `CollisionSetup` will not automatically recreate a
landscape-specific proxy inventory.

## World, sky, exposure and shadow ownership

[`World.build/build_staged`](../../../../app/render/world/world.gd) constructs
the environment, selected field, sky/lights and airfield stages. Subsequent
`refresh_presentation`, `update`, `adapt`, `flow_to` and `flow_frame` can modify
sky material, light, haze, clouds and exposure. `refresh_presentation` also
expects its current sky to be a `ShaderMaterial` and validates field metadata.
Installing `PanoramaSkyMaterial` inside an adapter without addressing that
contract would be incomplete.

Detached candidate nodes are not enough for rollback. World construction also
mutates shared owner, flow and Atmosphere state; Home sets shared appearance,
and cloud transport has additional saved state. SC-PHOTO-08 must avoid publishing
candidate globals or restore an explicitly complete validated snapshot on
failure/cancellation/stale builds. Verify the retained scene still updates and
refreshes correctly, not only that its node remains present.

[`FieldBuilder`](../../../../app/render/field.gd) and atmosphere writers use
`lighting_materials` and `lighting_snapshot` metadata. Ground-material updates
assume ground shader uniforms. A photo shader must not be handed to that writer
merely because it is a `ShaderMaterial`. Resolve the presentation policy with
World/Conditions and route compatible material updates deliberately.

Existing shadow components include
[`projected_shadow.gd`](../../../../app/render/projected_shadow.gd),
[`aircraft_shadow_proxy.gd`](../../../../app/render/aircraft_shadow_proxy.gd),
[`shadow_settings.gd`](../../../../app/render/shadow_settings.gd),
[`shadow_field_policy.gd`](../../../../app/render/shadow_field_policy.gd), and
[`vehicle_shadow_cue.gd`](../../../../app/render/vehicle_shadow_cue.gd).
Reuse their aircraft/proxy/settings ownership where applicable; their existence
does not prove that they composite correctly over a panorama. Photo-ground
projection, receiver position, alpha/depth ordering and captured sun matching
need the proposed renderer experiment.

## Native domain and replay

[`NativeMacosDomain.screen_session`](../../../../app/sim/native_macos_domain.gd)
compares the accepted stock aircraft/start, field, lake, surfaces, scenery and
collision inventory against its screened domain. New photo fields are outside
that domain. Keep the established reference/fallback behavior and record the
reason; do not update a stock fingerprint simply to admit the new scene.
Other platforms/backends require their own current admission check.

The flight log/checkpoint contract already binds physical field/world/backend
identity. A visual texture-resolution change should not change physical identity.
A current [flight-log replay](../../../FLIGHT-LOGGING.md) is a numerical research
workflow, not a player-facing 3D video replay. The pilot requires existing live
pause/reset, technical restore and offline numerical identity checks; adding a
visual replay player is outside its scope.
A geometry/contact revision should. If reproducible *visual* playback is desired,
add a separately versioned photo/presentation identity without claiming that
numerical replay currently records every rendering asset. A missing old
presentation asset must not silently substitute different physical contacts.

## Existing checks and their limits

The [validation document](validation-and-budgets.md) maps the proposed behavior
to existing focused tests. Most fixtures are Club-specific; the landscape test
currently expects two IDs. Adding a test filename to a plan does not establish
that it covers a photo site already.

Use [graphics tools](../../../tools/graphics.md), the
[landscape workflow](../../../../tools/landscape/README.md) and shared-host
[test admission](../../../../tools/testqueue/README.md). The landscape capture
is rendering-only, so it cannot qualify live-flight cost. The historical scenery
budget tool has its own engine/resolution assumptions and is not automatically
a current 4.8.beta2 pass. Export presets include landscape JSON patterns, but
all new resources/notices still require a clean-package check.

## Relationship to L16–L18

[LANDSCAPE-PLAN](../../../LANDSCAPE-PLAN.md) already lists optional photo sky,
the owner's field and Terrain3D directions as L16–L18. Those are not implemented
photo-site APIs. SC-PHOTO provides the detailed requested research and pending
delivery sequence, coordinated with L16–L18 rather than maintaining competing
status tables. Existing sky, shadow, camera and scene-budget plans retain their
interfaces and unrelated work.
