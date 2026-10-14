# Sky, clouds and storm scenarios

2026-10-13 · **Implementation plan** · Owner: Field world, coordinated with Landscape, UI, TOD, M5 wind, CAM, AUD and CR · Steps: **FW-76–90**.

Preserve the current beautiful fair-weather sky and add equally polished alternatives: cloudless blue, high wisps, broken cumulus, overcast, dark pre-storm, a distant thunderstorm and, finally, an interactive tornado scenario. The sky is a principal landscape in an RC flight simulator: judge it while tracking a small moving airplane, not only in a sky screenshot.

This is a planning delivery. No new presets, downloaded runtime dependencies, weather physics or menu controls are implemented by this document. The dated [FW-76 investigation](../research/field-world/FW-76/README.md) owns source evaluations and research limitations. The [world guide](../FIELD-WORLD-PLAN.md) owns existing behavior. Documentation is in English according to the repository convention; proposed player labels include Spanish.

## 1. Delivery decision

1. **Ship a Compatibility-first collection.** Extend the existing shader and composition pipeline, keeping the current sky as the default and exact regression reference. Download and evaluate suitable free resources before authoring replacement textures, meshes or effects.
2. **Make cloud movement an explicit choice.** New presets support Still, Follow wind and independent wind aloft. Preserve the old drift in the existing preset until the player chooses another motion mode.
3. **Keep appearance and physical conditions independently editable.** Selecting dark clouds does not silently increase wind, change humidity/density or wet the runway. A separately selected scenario can deliberately configure both and disclose those changes.
4. **Add a dramatic distant storm before interactive severe weather.** Large cloud structures, coherent lighting and rain curtains establish the landscape; a spatial wind field is a separate dependency.
5. **Finish with a bounded experimental tornado challenge.** The airplane responds through its existing aerodynamic equations. The funnel is a visual representation of a scenario, not the collision shape or force generator.
6. **Evaluate volumetric rendering as a conditional quality route.** Neither a renderer migration nor a new plugin is a prerequisite for useful sky choices. Select a volumetric dependency only after an isolated comparison on the pinned engine.

These are proposed implementation decisions. Record adopted backend and contract decisions in [DECISIONS](../../DECISIONS.md) when the comparison and interface review are complete.

## 2. Inspected baseline and concrete integration points

The planning audit inspected the working tree based on commit `69437cc4276735b13e8be51097d9719130b2f42a`. Other tracks are active; refresh source and status before implementation. Graph discovery was used first, but some indexed ranges were stale and wind symbols were missing; the current files were checked directly.

| Existing implementation | What it means for this work |
| --- | --- |
| [Engine pin](../../app/get-godot.sh), [project settings](../../app/project.godot): Godot 4.7.2-stable, Compatibility/OpenGL, 1280×720, 4× MSAA | Preserve this production target. An addon advertised for “Godot 4” still needs the exact renderer/export checks. |
| [Sky shader](../../app/render/sky.gdshader), [cloud density](../../app/render/cloud_field.gdshaderinc), [directional relief](../../app/render/cloud_relief.gdshaderinc) | Already has deterministic periodic noise, clustering, cirrus, silver lining and shaded cloud interiors. It is a direction-based projected layer, not a cloud volume that the aircraft can enter. |
| [Spec](../../app/spec.gd), [Atmosphere](../../app/render/atmosphere.gd) | Existing deck is 1,500 m, coverage control 0.35, scale 6, seed 1253 and shadow strength 0.22. Artistic configuration, not measured meteorology. Coverage is a noise threshold, not measured fraction of visible sky. |
| `Atmosphere.cloud_offset()` / `update_clouds()` | Fixed drift `(0.004, 0.0015)` cells/s, wrapped at 64 cells, updated once per simulation second. No physical-wind input. Faster presets need a measured update strategy. |
| [World.update / flow_to](../../app/render/world/world.gd), [conditions resolver](../../app/render/world/conditions.gd) | Wind reaches the shader clock, but cloud drift still uses the fixed Spec values. FW flowing time and explicit TOD snapshots are different existing routes and both must receive sky appearance. |
| `Atmosphere.update_sky_material`, `apply_state_to_sky`, `update_ground_material` | Multiple writers currently apply cloud/light uniforms. A preset can be overwritten by a later time update unless composition happens in one resolved snapshot. Ground copies and near grass must receive the same cloud configuration. |
| [Sky state](../../app/render/world/sky_state.gd) and [TOD](../../app/environment/) | Existing sun/moon, haze, exposure and visual history must remain authoritative. Compatibility has calibrated color conversion and an exposure workaround; replacing the WorldEnvironment wholesale would discard them. |
| [Home](../../app/ui/home.gd), [weather dialog](../../app/ui/weather_dialog.gd), [application root](../../app/app_root.gd) | Home has a Weather button next to Fly. Its dialog has Wind & Gusts, Turbulence, Atmosphere and Time of day. Reuse the same shell/widgets and add Sky & clouds. |
| [Pause menu](../../app/ui/pause_menu.gd) | Currently exposes Time of day, not a complete in-flight weather editor. A unified Flight conditions entry is planned in the [UI redesign](../MENU-REDESIGN-PLAN.md), not already implemented. |
| [Preferences](../../app/app_state/preferences.gd), [visual checkpoint](../../app/app_state/visual_checkpoint.gd) | Persist a separately validated sky selection. Keep direct technical launches independent of player preferences and extend visual replay without corrupting physics identity. |
| [WindField.sample(time_s)](../../app/physics/wind_field.gd), [FlightSession.wind_at](../../app/sim/flight_session.gd) | Physical wind is currently spatially uniform. Stateful OU turbulence belongs to the session transaction. A tornado cannot be implemented correctly by changing this one time-only vector. |
| [Wind plan](../WIND-PLAN.md) M5-W05/W07, [Natural Random](natural-random-flight.md) NR-07 | Spatial wind and distributed aircraft response already have an owner; cloud consumers and random sky choices must share this plan's appearance contract. Do not create competing cloud catalogs. |

The existing [L4c day](../research/visual-quality-implementation/L4c/app-after-day.png) and [cross-sun](../research/visual-quality-implementation/L4c/after-cross.png) images were inspected. Their soft bright edges and open blue gaps are the preservation reference. These are archived captures from that investigation, not new captures or a current performance measurement.

## 3. Preset collection and art direction

Time of day remains orthogonal: “Sunset” is not a second cloud type. Each supported cloud preset should work with fixed day, astronomical daylight, dusk and moonlit night, or declare a tested restriction. Never relabel a daytime photograph as a physically responsive night sky.

| Stable ID; English / Spanish label | Intended landscape | Technique and first delivery |
| --- | --- | --- |
| `classic`; Classic clouds / Nubes actuales | Preserve today's bright, airy cloudscape, spacing and directional relief | Exact existing branch; first release |
| `clear`; Clear blue / Azul despejado | Clean blue dome, atmospheric horizon, zero cloud fragments or cloud shadows | Existing atmosphere with every cloud layer and cloud shadow disabled; first release |
| `cirrus`; High wisps / Nubes altas | Fine high veils and generous blue gaps; subtle depth and light | Independent thin upper layer; must work when low-deck coverage is zero; first release |
| `fair_cumulus`; Fair-weather cumulus / Cúmulos de buen tiempo | Larger rounded masses, luminous shoulders and softer darker bases | Existing density/relief plus qualified shape parameters; first release |
| `broken`; Broken cloud cover / Parcialmente nublado | Broad groups at different apparent scales, blue corridors and an approaching bank | Layered coverage/morphology; first release |
| `overcast`; Overcast / Cubierto | Continuous soft ceiling, visible large-scale texture and diffuse ground light | Dedicated overcast shape/opacity treatment; first release |
| `prestorm`; Dark storm clouds / Nubes de tormenta | Dense dark bases, heavy rolling masses, brighter distant openings and reduced direct sun | Thick lower deck and coordinated light/haze; first release, visual only |
| `distant_storm`; Distant thunderstorm / Tormenta lejana | Anvil/towering silhouette, layered base, optional distant rain curtain | Downloaded masks/atlases or bounded cloud geometry after comparison; second release |
| `tropical_bands`; Tropical storm bands / Bandas de tormenta tropical | Broad rain/cloud bands crossing a distant horizon | Later authored scene; ground-level view, not a satellite-shaped hurricane pasted overhead |
| `tornado_challenge`; Tornado challenge / Desafío de tornado | Rotating storm base, connected funnel, near-ground dust and readable danger extent | Final experimental scenario, after spatial-wind and flight-response gates |

Overcast and pre-storm must differ in structure, light direction and depth, not just tint. The current horizon fade removes low-angle cloud density; simply setting coverage to 1 would leave an implausibly open horizon. Add an overcast horizon closure that still matches terrain haze. The current cirrus branch is nested inside the low-cloud condition; decouple it for the high-wisps option.

**Visual criteria:** broad readable masses first, intermediate billows second, fine detail last. Vary vertical shape and underside darkness; avoid repeated cotton balls, noisy wallpaper, sharp cutouts and uniformly black storm skies. Preserve contrast for small aircraft against both the bright rim and dark underside. Darkening the sky requires compatible sunlight, ambient fill, haze, reflections and ground shadows. No universal green tint or lightning is required to communicate a storm.

A hurricane and a tornado are distinct phenomena, and tornadoes can also occur over water. The desired dramatic funnel over this field is best represented as a tornado associated with a thunderstorm. A hurricane-inspired scene uses large rainbands; it does not shrink a whole tropical cyclone to the scale of the RC runway. [NOAA structure and NSSL references](../research/field-world/FW-76/README.md#meteorology-and-flight-physics)

## 4. Godot implementation options and reuse decision

The detailed source/license record is in [FW-76](../research/field-world/FW-76/README.md#godot-and-downloadable-candidates). Download candidates into an isolated research project; never enable their editor plugins in production during evaluation.

| Option | Strength | Cost / integration limit | Proposed role |
| --- | --- | --- | --- |
| Extend current 2D/2.5D sky | Already integrated, deterministic, inexpensive and calibrated | No real flight through cloud; distant shapes need more than threshold/tint | Production foundation |
| Free HDRI / panorama, e.g. Poly Haven | Strong real cloud shapes and fast static background | Baked sun/horizon, no intrinsic wind animation or volumetric traversal; storage and lighting mismatch | Reference collection, optional fixed-time photographic preset, or licensed mask source |
| Sky3D | Downloadable MIT sky/cloud/fog/time system; Compatibility support documented upstream | Duplicates ephemeris, fog and clocks; upstream `TIME` and IBL policies need adaptation | Isolated comparison; reuse bounded components only if materially better |
| POM Clouds | Downloadable MIT cloud-mesh approach; upstream lists all three renderers | Parallax is not proof of a traversable volume; intersections, transparency and multi-view behavior need tests | First reusable candidate for large nearby/distant formations |
| Godot Foundation Sky Shaders demo | Engine-maintained educational comparison and downloadable shader examples | Forward+ demo; performance and exact version constraints | Learning/prototype reference |
| Sunshine Clouds 2 | Volumetric authoring, masks and wind controls; MIT repository | Compute/compositor route does not fit Compatibility | First candidate for a separate high-quality renderer experiment |
| Clay John volumetric cloud demo v2 | Open MIT compute/raymarch implementation with explicit pipeline | Forward+/Mobile route; custom atmosphere overlaps current system | Technical reference and comparison, not production replacement |
| MMqd Nishita clouds / GDQuest stylized sky | Accessible source/tutorial material for noise, scattering and composition | Half-resolution assumptions, older target versions or stylized appearance | Focused learning; conditional reuse after source/license audit |
| Built-in FogVolume / volumetric fog | Local participating media with lighting | Forward+ only; finite range and temporal ghosting; not an automatic full sky-cloud solution | Conditional experiment for cloud immersion, never first-release dependency |
| Transparent meshes, cloud cards and particles | Works as a bounded distant storm/funnel representation when qualified | Overdraw, sorting, intersection artifacts and camera-facing shapes | Compatibility storm/tornado presentation |

Godot documents separate sky-background, cubemap and reduced-resolution work. Changing a uniform can refresh radiance; using `TIME` can do so every frame. Generic examples of half-resolution cloud passes do **not** establish Compatibility support: the repository's [pinned GLES3 source investigation](../research/landscape-investigations/01-sky-shaders.md) found that these subpasses are not rendered. Keep this restriction until an exact-version executable probe proves otherwise. [Godot sky shader reference](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/sky_shader.html)

Volumetric fog requires Forward+. Compute shaders and CompositorEffects are unavailable in Compatibility. This does not mean every form of raymarching is impossible in a fragment shader; it means addon backend requirements and full-resolution cost must be evaluated explicitly. [Renderer matrix](https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html), [volumetric fog](https://docs.godotengine.org/en/4.7/tutorials/3d/volumetric_fog.html)

### Resource intake

Before making a new cloud texture, sky photograph, funnel mesh or particle atlas, test the free downloadable candidates. For each adopted file retain URL, author, exact tag/commit, original filename, SHA-256, license text, transitive asset licenses, download date and any transformation recipe. An MIT plugin label does not automatically license every linked texture; a tutorial video does not grant rights to its project files.

Store source provenance under proposed `assets/sky/weather/`; approved minimal runtime resources under proposed `app/assets/sky/weather/`. Use existing import conventions, mipmaps, qualified compression, and an explicit memory budget. Keep originals/reproduction scripts outside `app/`. Do not bundle demo terrains, cameras, lights, clocks or unrelated assets. Lock exact dependency versions before adoption. Generated derivatives must be rebuilt from recorded sources; never hand-edit them.

Use actual runtime captures as selector thumbnails. Downloaded photographs can guide art review but must not advertise a result that the renderer does not produce.

### Shader work for the first collection

Keep the accepted classic code path intact and add new resolved layer inputs only for non-classic presets. The implementation sequence is:

1. Resolve macro coverage and layer identity separately from optical thickness. Coverage changes where clouds exist; thickness changes transmission and shading inside them. A single threshold must not drive both effects.
2. Shape low-deck masses at coarse scale, then add bounded billow/detail variation. Reuse the existing noise and relief until the downloaded comparison demonstrates a clear improvement. Filter/fade fine detail with projected size near the horizon and under zoom; MSAA does not remove procedural shader aliasing.
3. Evaluate cirrus as an independent thin layer, with its own scale/transport and weak opacity. Compose layers in a declared order; clear disables all of them explicitly.
4. Shade the visible mass using the existing light-direction relief, a bounded ambient term and an optical-depth transmission approximation. Parameters are artistic estimates. Keep lit shoulders distinct from an emissive outline; night clouds do not glow without a source.
5. Compose cloud opacity with the sky and sun/moon discs, then apply the established haze/color pipeline once. Overcast needs its own horizon treatment and diffuse light response; pre-storm needs a readable base-to-opening contrast. Do not globally darken the whole screen to simulate cloud depth.
6. Keep expensive visible detail out of the radiance branch where possible, while explicitly controlling any changed ambient/reflection approximation. Check all ground/grass shadow materials against the same accepted coverage/offset state.

For the advanced volume comparison, inspect weather-map shape, height profile, base/detail noise, density-to-extinction mapping, light sampling, empty-space skipping, reconstruction and depth-aware compositing. Require camera-inside-cloud and aircraft-edge cases. Those concerns explain the need for a downloadable implementation trial; they are not a request to build a new volumetric engine from scratch.

## 5. Player flow and discoverability

### Entry and layout

**Home → Weather / Condiciones de vuelo → Sky & clouds / Cielo y nubes.** Add the sky value to the compact Home summary, such as “Partly cloudy · Light wind · Evening”, within the existing layout. When UI-20–29 delivers its Conditions row, move the same component there without a second catalog or preferences format.

Use a two-column preset gallery at 720p, with a selected border, text name and one-line description. Show four to six cards per viewport with scrolling, not tiny previews across a crowded tab row. Include the current sky first. Place advanced controls below the gallery, collapsed initially. Keep the footer with Apply and Cancel visible. EN and ES, keyboard/controller focus, screen scaling and long labels are acceptance cases.

The page contains:

- **Sky appearance:** the supported preset cards, each with a real capture.
- **Cloud motion:** Follow wind, Still, or Wind aloft. Classic retains its legacy motion until explicitly changed. Follow wind is the recommended default for newly selected animated presets.
- **Advanced appearance:** only useful controls such as coverage, density and seed; edits set “Custom”, with Reset to preset. Keep shader jargon and sample counts out of the player flow.
- **Scenario:** Free flight by default. Later, an explicit Storm/Tornado challenge entry opens a briefing showing the physical wind/start changes before launch. Do not conceal it inside a color preset.

The current top-level weather preset picker edits wind. Relabel or scope it to **Wind preset** when adding sky presets; it must not ambiguously overwrite unrelated tabs. Selecting Clear changes neither current time nor wind. Changing wind updates the motion preview only when Follow wind is selected.

### Apply, cancel and pause

Home uses a detached draft. Apply validates all touched domains, saves once and rebuilds/updates its single still backdrop. Cancel restores focus and leaves preferences/world state unchanged. The still Home view can show an optional bounded motion preview inside the dialog; closing it must free its resources and restore shader globals.

In Pause, coordinate one **Flight conditions** entry with the UI owner, initially sharing the current Time of day route and this new sky page. Appearance can apply while the session is held. Physical wind/atmosphere changes remain **next restart** under the existing session contract; show that distinction next to Apply. A failed validation/preparation keeps the previous accepted scene and session.

Applying a paused sky change commits the complete new appearance atomically; it does not run a transition on wall-clock time. A transition that continues after resume must be a recorded simulation-time visual event. Keep a quiet static snapshot while paused. Selecting an interactive tornado requires a fresh scenario/reset boundary and must never unexpectedly activate forces in an ongoing ordinary flight.

The first delivery needs no new hotkey or HUD panel. The final challenge may use a small scenario status cue and optional wind-field debugging overlay, coordinated with HUD/CAM. Provide separate toggles for storm flashes and camera effects; their disabled state cannot change wind physics.

## 6. Configuration and composition contracts

### Separate three kinds of state

| Domain | Proposed contract | Owner and invariant |
| --- | --- | --- |
| Sky appearance | Versioned `openrc-sky-appearance v1`: stable preset ID, seed, supported layer parameters, motion mode, optional wind-aloft vector, visual quality | FW/TOD; may change pixels but never physical density, forces, trim or RNG |
| Physical weather | Existing `openrc-weather` variants; a separately versioned spatial extension when M5-W05 is ready | M5; SI/float64 values, fail-closed validation, complete replay identity |
| Scenario | Versioned authored recipe resolving sky, weather, lighting request, start and storm/vortex parameters | Scenario/UI coordination; expands once into explicit validated inputs; no hidden continuously mutating presets |

Do not add arbitrary dictionaries to the weather-v3 validator or silently reinterpret its existing wind limits. Treat the fields above as a proposed schema, finalized in FW-77; unsupported future modes must be rejected. Resolve missing sky input to an exact classic configuration for old saves/traces and technical launches. An unknown/corrupt user preference falls back to classic with a concise notice; an invalid explicit scenario or CLI sky input refuses that request.

Store selected IDs **and resolved versioned values** where reproducibility requires them. A later catalog retune must not change an old recorded flight. Include the resource/source fingerprint in visual evidence; do not insert visual quality settings into the physics fingerprint. The [aircraft contract](../../AIRCRAFT_CONTRACT.md) stays unchanged unless distributed load integration exposes an actual missing aircraft capability.

### One resolved scene snapshot

```text
Validated player draft / CLI / scenario recipe
          ├── physical weather → FlightSession → stage wind/air → existing flight dynamics
          ├── lighting selection → existing FW/TOD solar state
          └── sky appearance + cloud transport state
                        ↓
              resolved visual snapshot
                        ↓
       sky + sun/moon transmission + ambient/haze + ground/grass shadows
                        ↓
                scene-local render resources
```

Add proposed `app/environment/sky_appearance_config.gd` for validation/catalog resolution and `sky_appearance.gd` for composition with the existing lighting snapshot. Keep proposed `app/data/sky/weather_presets.json` authoritative for presets. `Atmosphere` consumes resolved values; neither it nor `World.flow_to()` invents a second preset policy.

Thread appearance through `app_root → HomeScene / main → World / Atmosphere`, including rebuild, reset, failed launch and Home return. Update both FW-flow and explicit-TOD paths. Retire the previous world flow before switching to a snapshot. Avoid mutable additions to `Spec.ATMOSPHERE`, uncontrolled static singletons or independent third-party sun/time controllers.

The existing global cloud drift uniform reaches ground materials. Either keep a strict single-active-world lifecycle with save/restore for previews or make the new uniforms scene-local. Choose and test one policy before adding a live preview. A preview must not move production shadows, change exposure or consume physics RNG.

For overcast/storm appearance, resolve direct-light attenuation, cloud ambient fill and shadow contrast from the same accepted appearance. Audit sunlight already attenuated by the cloud-shadow layer to avoid counting absorption twice. Preserve the current exact cubic color encoding and the night ambient/reflection workaround. New sky reflections must be explicitly qualified; do not re-enable sky IBL merely because an addon expects it.

## 7. Cloud transport and interaction with wind

### Motion semantics

| Mode | Required behavior |
| --- | --- |
| Classic legacy | Reproduces existing 1 s quantized drift and pixels; backward compatibility only |
| Still | Cloud translation, shape evolution and cloud-shadow advection stop. Wind can still affect the aircraft. Lighting follows its separately selected clock, so a moving sun can still change the shadow projection. |
| Follow wind | Transport follows a declared mean wind mapping. Zero mean with gust/turbulence disabled produces no translation or shape evolution. More mean wind moves the field faster in the correct direction. |
| Wind aloft | Explicit layer speed/direction; can differ from the windsock. Surface calm does not imply upper-air calm. Display a simple explanation. |

For the first Follow wind implementation, use the configured mean wind as an **authored proxy for wind aloft**, not instantaneous OU turbulence measured at the aircraft. The current field does not model altitude-dependent wind. Avoid an entire sky vibrating at the turbulence rate. Later M5 shear can provide actual layer-height samples. Formation/dissipation is a separate optional evolution parameter; the player's Still and fully calm choices keep it zero. [NWS wind-profile reference](../research/field-world/FW-76/README.md#meteorology-and-flight-physics)

### Coordinate and time requirements

The project uses NED; renderer axes are east/up/south. Wind input is meteorological **FROM**; `(W_N, W_E)` below is the validated transport vector after the existing FROM-to-toward conversion. For example, 0° FROM north must move clouds south, not north. For layer height `H` with scale `S` cells per deck unit, the existing planar projection implies:

```text
horizontal render velocity = (W_E, -W_N) m/s
noise offset rate = -(S / H) * (W_E, -W_N) cells/s
offset(t) = wrap(offset_at_anchor + integrated_offset_rate, 64)
```

The minus sign is required because the shader samples `position + offset`. This mapping assumes the existing flat projection, fixed reference height and no camera translation. If cloud geometry becomes world-relative, redefine the projection consistently and test it from pilot, chase and onboard cameras. Sky, shadow and cloud-bank placement must use one coordinate contract.

For fixed mean wind use an analytic offset from a time anchor; for changing wind, integrate in a deterministic fixed-tick visual transport state with checkpointed anchors. Do not accumulate render-frame `delta`, advance the physical RNG, or multiply cloud speed by the astronomical time-of-day acceleration. A 20× Evening clock does not imply 20× wind.

Keep float64 offsets/times on the CPU, wrap before GPU conversion, and sample accepted tick/interpolation state read-only. A wind change preserves the current phase and changes its derivative, rather than recomputing `new_speed × all_elapsed_time`. Reset, pause, rewind and restore must reproduce motion. Optimize uniform updates with an explicit frequency/quantization policy; faster wind may need a separate visual layer path if repeated sky-radiance updates are too expensive.

Cloud shadows use the same shape seed, coverage and transport. A changed noise octave/period requires revisiting the 64-cell periodicity tests. Support cirrus and low-deck speeds independently only when both shadows and display semantics are defined; high cirrus need not cast a detailed ground mask.

## 8. Distant storms and the later tornado

### Storm presentation before storm physics

Start with one dominant, world-anchored distant bank placed away from the normal takeoff/landing sightline. Use a downloaded/licensed mask, cloud mesh or atlas when suitable. Qualify it at the horizon, in a turn, at pilot zoom and from moving cameras; a camera-facing billboard that reveals itself during a circuit fails.

Add a bounded anvil/tower silhouette, layered dark base, depth-colored rain curtain and coherent reduction of sun/ambient contrast. Allow a dry foreground with rain in the distance. A tropical-band scene can reuse this composition with broader moving bands. Art review determines composition, not a random distribution of many effects.

Rain, thunder and lightning are a later optional presentation layer. Reuse the audio bus/listener architecture and spatial delay from event distance; author event timing in simulation time. Avoid white fullscreen flashes that erase the aircraft. Do not imply new tire friction, water accumulation, icing, engine ingestion, electrical damage or precipitation aerodynamics. Those require their owning physical models and evidence.

### Spatial wind prerequisites

M5-W05 must supply a pure position/time query, conceptually `sample_ned(position_f64, time_s, accepted_weather_state)`. Preserve the old uniform route exactly. Each RK stage samples at its own position/time; debug probes and rendering cannot mutate the field. Turbulence still advances only at the committed transaction boundary and rolls back on failure.

The broad storm field can combine independently bounded background flow, shear, inflow, updraft/downdraft and a smooth gust-front region. Start with separately verified analytic components, not CFD. Coordinate the scope under M5-W05/W08; a real thunderstorm circulation is far more complex than their sum. Label these authored experimental conditions.

Feed the resulting wind through the existing relative-air calculations. For a local component at offset `r`, use its ground-relative velocity including `omega × r`, subtract wind at that component's stage position, and reuse the accepted aerodynamic/propeller laws. Whole-aircraft center sampling is an intermediate test, not acceptance of tornado-induced wing/tail differential loads. Avoid an extra “tornado force”, position advection or invented `-dW/dt` acceleration.

Coordinate aero stations, tail, propeller inflow, downwash/wake and all active powerplants. Ambient wind must not duplicate induced flow. Ground contact remains ground-relative. Publish the new environment identity, recorded sample positions/times and checkpoint state through versioned trace readers before exposing the scenario.

### Bounded vortex prototype

Compare smooth finite-core analytical profiles using [Wood and White](https://ams.confex.com/ams/pdfpapers/141522.pdf) as a source, including its discussion of the ideal Rankine cusp and Burgers–Rott behavior. Select an equation only after checking the typeset formula and an independent numerical oracle. The downloadable paper is a model reference, not validation of our aircraft in a tornado.

Requirements for the chosen practice model:

- Tangential velocity is zero and finite at the center, peaks near a configured core radius, and decays outward; evaluate the Cartesian center limit without division by zero.
- Radial inflow and vertical velocity have documented units, sign and vertical boundary behavior. Near the ground there is no downward/upward flow through the surface boundary implied by the model. Independently added components do not constitute a mass-conserving atmospheric solution; disclose that limitation or derive a coupled field.
- Smooth radial, vertical and lifecycle envelopes limit the affected volume. Verify values **and derivatives** at the core, taper and start/stop joins. Prefer at least C2 joins for the candidate, then measure actual integration convergence rather than assuming smoothness is enough.
- Choose maximum speed, core size, gradients and traversal time from a numerically qualified aircraft envelope. Do not simply raise the current 15 m/s UI limit, use EF numbers as force settings, or silently clamp an invalid field after producing huge loads.
- Translation/tilt of the vortex center is explicit scenario state. A moving visual funnel alone cannot relocate the wind. Cosmetic detail can vary; center, orientation and influence envelope cannot drift apart.
- A bounded seeded perturbation is separate from the mean swirl. It must not reset/advance when a particle is spawned or a camera changes. Existing temporal OU turbulence must not be counted twice.

The NWS EF scale is a damage-based estimate; it is unsuitable as an unqualified “EF5 wind” knob. Use a plain challenge intensity with explicit internal SI parameters and an Experimental label. Cloud darkness, condensed funnel width and particle opacity are not measurements of wind strength. [NWS scale](https://www.weather.gov/oun/efscale)

### Tornado presentation and play

Reuse licensed VFX resources where possible: tapered moving funnel, layered rotating texture, cloud-base connection and a small ground dust/debris ring. Use bounded mesh/particle counts, depth fading and distance LOD. The [Godot tornado tutorial](../research/field-world/FW-76/README.md#tutorials-and-community-evidence) is a presentation study, not a physical solver. Debris is cosmetic initially; do not add hundreds of physical rigid bodies.

Stage the challenge as approach → outer circulation → optional penetration → recovery/landing. The airplane may enter the modeled region and experience changing local airspeed, roll/pitch/yaw disturbance and loss of control through the accepted model. A believable recovery is preferable to a hidden scripted spin. Reuse crash/reset behavior when the aircraft actually impacts terrain. Show a clear escape/restart action and an optional practice intensity.

Spawn outside the strong-gradient core and verify runway equilibrium/airborne trim for each enabled aircraft. A failed trim rejects the scenario without borrowing an old trim. Gate unsupported aircraft out with a capability reason; do not tune per-aircraft “wind strength multipliers” to make them survive. A full severe-weather realism claim requires separate physical validation and is outside this deliverable.

## 9. Implementation phases and acceptance

Each row is a small independently reviewable change. Runtime work remains pending. `FW-76` covers this research plus the remaining fresh baseline/intake checks. Existing M5/UI/TOD step status remains in its own plan; the rows here own their sky/scenario integration only.

| Phase / ID | Work | Required proof and status |
| --- | --- | --- |
| 0 · FW-76 | Research, source/license shortlist, baseline snapshots, exact renderer probes and acceptance budgets | **Research delivered.** Fresh baseline captures, isolated addon downloads/probes and minimum-hardware measurement pending. |
| 1 · FW-77 | Validated appearance catalog, resolver and immutable composition contract; identity/migration design with TOD/NR | Invalid/unknown inputs refused; old inputs resolve to exact classic; no Spec mutation; all proposed fields have units/ranges/ownership. **Pending.** |
| 1 · FW-78 | Sky gallery in existing conditions dialog, draft/apply/cancel, Home summary and EN/ES preferences | 720p keyboard/controller flows, cancel/no-write, focus return, save/reload, failed apply and technical-launch isolation. Share controls with paused route. **Pending.** |
| 2 · FW-79 | Classic, clear, cirrus, fair cumulus and broken-cloud appearance; overcast/pre-storm morphology prototypes | Side-by-side directional captures; zero-cloud path has no residual cirrus/shadows; independent shapes distinguish overcast/pre-storm. Final storm/overcast lighting and flight acceptance wait for FW-80. **Pending.** |
| 2 · FW-80 | Unified light/haze/ground-shadow response in fixed, TOD and FW-flow worlds; complete overcast/pre-storm presets | No stale overwrite, doubled exposure or double cloud attenuation; low-angle/night comparisons and actual pilot flight of the complete collection; classic remains exact. **Pending.** |
| 3 · FW-81 | Still / Follow wind / wind-aloft transport with M5-W07 | Cardinal sign/unit tests, zero-wind freeze, phase-continuous changes, shared shadow motion, no render RNG mutation, 30/60/144 FPS equality of accepted transport state. **Pending.** |
| 3 · FW-82 | Visual history/checkpoint lifecycle and paused application; integrate NR-07 appearance input | Reset/restore/old records, aborted scene switch, Home preview isolation, passing Evening → fixed sky → Home. Physics bytes unchanged. **Pending.** |
| 4 · FW-83 | Reused distant storm assets, thunderhead/rainband composition and camera qualification | License/provenance/import evidence, horizon/zoom/moving-camera checks, bounded resources and lighting coherence. **Pending.** |
| 4 · FW-84 | Optional rain curtains, thunder and restrained lightning | Event replay/pause/audio-mute proof, bounded overdraw, flash-off mode and no unimplemented wet-ground effects. **Pending; optional after FW-83.** |
| 5 · FW-85 | Isolated POM/volumetric backend comparison, including a separate Forward+ experiment if justified | Same scenes/cameras/resolution; image, timing, memory and lifecycle comparison. Record accept/reject decision. Production renderer change is a separate project-level decision. **Conditional.** |
| 6 · FW-86 | Integrate M5-W05 spatial weather and distributed aircraft samples into the sky/scenario boundary | Uniform zero-feature parity, independent field oracle, correct RK stage positions/times, wing/tail/propeller response, versioned trace and rollback tests. **Pending prerequisite for interactive storm.** |
| 6 · FW-87 | Authored bounded storm/vortex field prototype and scenario contract, with M5 owners | Core/taper/join checks, finite forces, step refinement, seed replay, valid starts and measured whole-tick cost. No physical validation claim. **Pending.** |
| 7 · FW-88 | Tornado funnel/dust presentation aligned with accepted storm state | World anchoring, core motion alignment, view/LOD/occlusion checks, pause/reset/rewind behavior and invisible-VFX physics parity. **Pending.** |
| 7 · FW-89 | Experimental tornado challenge with briefing, aircraft restrictions and restart/recovery flow | Actual flown entry/exit, expected distributed disturbance, crash/reset and failure handling, enabled-aircraft matrix, owner play review. **Pending.** |
| 8 · FW-90 | Release qualification for each delivered slice and documentation consolidation | Native Windows/Linux/macOS exports, licensed assets packaged, settings migration, regression/capture/performance records and owner sky/flight review. **Pending; repeat only for newly changed scope.** |

Dependencies:

```text
FW-76 → FW-77 → FW-78/79 → FW-80 → FW-81 → FW-82 → ordinary-sky release gate
                                           └────→ FW-83 → optional FW-84
FW-85 is an isolated decision branch; it does not block ordinary skies.
M5-W05 + FW-82 → FW-86 → FW-87 → FW-88 → FW-89 → challenge release gate
FW-90 qualifies each shippable slice; early sky delivery does not wait for a tornado.
```

Suggested PR boundaries: contract; selector/persistence; ordinary presets; lighting integration; transport; lifecycle; distant storm intake/composition; optional FX; backend experiment; spatial integration; field model; tornado presentation; challenge; release evidence. Split any row further if it combines a numerical law change with broad UI/asset changes.

### Indicative effort, not a schedule commitment

For one experienced developer, after baseline access is available: ordinary presets/UI/lifecycle **12–20 engineering days**; distant storm and optional FX **6–12 days**; isolated backend evaluation **3–5 days**; spatial integration/vortex/tornado qualification **15–30 days or more**, depending on M5 readiness. Cross-platform and pilot reviews add calendar time. These are planning estimates, not measured velocity; re-estimate after FW-76 and FW-86. Deliver the ordinary sky collection before committing to the expensive branch.

## 10. Verification and performance gates

### Numerical and lifecycle checks

Use focused new tests only for meaningful contracts: validation/round-trip/migration, cardinal drift signs and periods, integrated phase after a wind edit, scene isolation, replay/rollback, pure spatial queries and local-load response. Existing tests remain authoritative for unchanged physics. Deliberate sign/seed/clock/center-limit mutations run in disposable copies.

For visual-only phases compare complete accepted simulation checkpoints and flight traces with sky options on/off, including turbulence RNG bits, atmosphere, propulsion auxiliaries and event history. Compare bytes on the same pinned runtime where the current contract promises exact equality. Do not re-record golden flights for a visual change. Cross-platform images may differ; exact pixel claims require the same GPU/driver/render path.

For spatial weather verify calm/constant-field equivalence, analytic cardinal flow, core center, very large/small radius, invalid inputs, near-ground limits, smooth entry/exit, frame-rate-independent replay and RK refinement on declared smooth segments. Exercise differential wind across the airframe; a uniform-wind test cannot establish torque response. Separate valid strong disturbance from invalid extrapolation of the aerodynamic model.

### Image and flight matrix

Capture native production scenes, not only shader thumbnails:

| Dimension | Minimum coverage |
| --- | --- |
| Sky | Every ordinary preset; thickest/darkest configuration; classic and zero-feature controls |
| Light | Fixed legacy day, explicit TOD daylight, moving FW Evening, sunrise/low sun, moonlit and dark night |
| View | Toward/across/away from light, zenith, horizon, runway approach; pilot normal/zoom plus chase/onboard where supported |
| Motion | Still, complete calm, cardinal wind, strong qualified mean, independent aloft direction; t=0,10,120 s and long-run wrap/restore |
| Aircraft | Every enabled catalog aircraft, bright/dark liveries, near/mid/far distance, crossing a bright rim and dark base |
| Output | 720p baseline, 1080p, high-DPI UI; EN/ES; each supported desktop export |

Use pairwise coverage for the broad matrix and full combinations for critical cases: classic parity, clear sky, overcast low sun, dark storm aircraft tracking and tornado entry. Store original PNGs, clips, render logs, camera/config/seed, source hashes and timings in each step's evidence folder. Image checks should reject seams, unintended cloud remnants, shadow sign errors and hidden aircraft; they do not replace an owner flight review.

**Gate sky:** the owner can find the selector without a new instruction, distinguish the presets without their labels, and fly takeoff/circuit/landing while continuously tracking the aircraft. Review the actual new skies as well as classic. Beauty and readability are both required; do not pass by removing all detail.

**Gate challenge:** scene and field are aligned; the aircraft's response changes with position; entry/recovery/crash/reset are coherent; no physics change occurs when VFX or audio is disabled. Intensity remains inside the published experimental envelope. Severe-weather physical realism stays unclaimed.

### Proposed budgets to freeze before implementation

These are proposed acceptance targets, **not achieved measurements**. Name a minimum desktop GPU before final performance acceptance; an RTX 3090 result is not minimum-hardware evidence.

| Budget | Initial target |
| --- | --- |
| Ordinary sky, 720p | Additional GPU median ≤0.5 ms and p95 ≤1.0 ms versus current classic on the same machine; explain first-load compilation separately |
| Distant storm / tornado presentation, 720p | Additional GPU p95 ≤2.0 / ≤3.0 ms respectively; if scene total fails, reduce effects or postpone the profile |
| Whole flight | Target 60 fps at qualified resolution; report median/p95/p99 frame time and catch-up counts, with no sustained simulation slowdown |
| Physical weather | Preserve the project's **500 µs per 240 Hz physics tick** acceptance gate; report full evolving flight cost per aircraft, not just isolated field-query timing |
| Runtime resources | Initial extra resident texture/volume budget ≤64 MiB for Compatibility sky collection; assets in export ≤32 MiB compressed. Backend experiment has a separately declared budget. |

Measure GPU time, CPU render submission, individual whole physics ticks, loading stalls, resource memory and total frame time separately. Use three alternating baseline/candidate runs with 10 s warmup and 60 s sampling, VSync state/resolution/driver recorded, without another benchmark running. Include all-sky views, storm overdraw, zoom, resizing and radiance refresh spikes. Verify no growth after at least 20 Home/dialog/flight/restart cycles. If a budget fails, record the failure; do not silently relax it or confuse llvmpipe repeatability with hardware qualification.

Quality settings may reduce visual samples, detail layers, texture size or particle density. They must not change wind-field parameters, seed, challenge difficulty or force calculations. A low-quality tornado still needs a visible indication of the same physical region. Feature failure falls back to a qualified appearance with a clear notice, never an invisible active hazard.

### Existing tools to reuse

- [Atmosphere tools](../../tools/atmosphere/README.md): `check_phase6.py`, `check_cloud_probe.py`, `l4c_verify.py` and `l4c_integration.py`; extend their real-camera controls rather than inventing a parallel capture stack.
- [World tools](../../tools/world/README.md): fixed/TOD/FW parity and sky-state generation checks.
- [TOOLS](../TOOLS.md): `app/test.sh`, actual app captures and export smoke tests. Use the pinned native Windows engine for GPU work; Bash/WSL or Linux workflows for the documented suite.
- Existing UI/weather/TOD/checkpoint tests should be extended at their seams; proposed new files can use `test_sky_appearance_*` and `test_cloud_transport_*`. No command for a not-yet-created harness is presented as currently runnable.

This planning change requires document/link/diff checks only. Runtime, GPU and flight qualification begin with implementation; they have not been performed by this delivery.

## 11. Ownership, risks and completion

| Risk / shared boundary | Mitigation and stop condition |
| --- | --- |
| Two lighting paths overwrite cloud settings | One composed snapshot; regression includes flowing-world transitions. Stop if old state reappears after Apply. |
| Generic docs/addon support differs from pinned GLES3 | Native compile/render probe; do not accept missing clouds as a “quality fallback”. |
| Storm art is impressive only in a screenshot | Pilot flight, zoom and aircraft-contrast review; revise composition before adding more effects. |
| Radiance refresh / transparency cost | Bound update rates and overdraw, profile full scenes, preserve cheap background route. |
| Downloaded sky duplicates baked sun/horizon | Select compatible sky-only inputs or use reference-only; do not patch by hiding the actual solar light. |
| Shader globals leak from Home/preview | Single-active-world lifecycle or scene-local resources; failed-launch and multi-instance tests. |
| Spatial wind or start is numerically invalid | M5 schema/oracle/step refinement, finite guards, fail-before-commit and tested start envelopes. |
| Tornado loads exceed the supported aircraft model | Restrict scenario envelope/capabilities; no artificial survival multipliers or physical-realism claims. |
| UI redesign / NR-07 / night lighting work collides | Re-read registry/status, share controls and appearance contract, keep FW-66–75 night work and NR selection policy in their homes. |
| License or asset download disappears | Freeze approved source identity and license; retain reproducible derivatives and an accepted fallback. |

FW owns sky configuration/composition, sky render components and `assets/sky/weather/`. UI owns shared shell/preferences/i18n edits; TOD owns visual history/time; M5 owns float64 field equations, session/RK plumbing and weather formats; AUD owns thunder/mixing; CR owns crash behavior. Do not edit aircraft generators/data to implement a sky. Shared files need narrow coordinated changes; preserve unrelated working-tree edits and stage only owned work.

At each delivery, update the current world guide with supported choices and limits, retain source/provenance/acceptance evidence, and mark the corresponding rows here. When the plan is complete or superseded, consolidate remaining rationale into the canonical guides/evidence and remove this active plan according to the documentation convention. Do not create a second archive or cleanup report.
