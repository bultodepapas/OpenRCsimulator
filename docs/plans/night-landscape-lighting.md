# Night landscape lighting: one mast, soft field light and an optional campfire

2026-10-13 · **Plan before implementation** · Owner: Field world / environment integration · Steps: **FW-66–75** · Acceptance: **Gate FW-N**, coordinated with LU, SC, TOD, UI and CR.

The requested result is a beautiful, usable rural RC field at night: **one tall lighting mast with four independently aimed lamps**, overlapping pools of light, restrained soft runway markers, an optional airport lighting style, and an optional small animated campfire. The mast supplies the main field illumination; existing club lights and low markers complete the composition. Distant countryside remains dark enough to give the illuminated field depth.

This document owns the proposed work and its acceptance criteria. The [field-world guide](../FIELD-WORLD-PLAN.md) owns current behavior, the [landscape upgrade guide](landscape-upgrade.md) owns existing LU work, and [FW-66 research](../research/field-world/FW-66/README.md) records dated observations, downloads and sources. **No new night feature is implemented by this planning delivery.** Numerical settings below are initial artistic/engineering estimates, not measured luminaire specifications or accepted performance results.

The second [Internet research round](../research/field-world/FW-66/investigations.md) completes **26 distinct investigations** about optics, free resources and the pinned engine. It changes the original plan: narrower horizon-aware beam studies replace the original broad cones; actual light transport must agree with exposure; resource alternatives require stronger material/animation intake; fire replay includes wind history; and visual preference is measured separately from flight readability. Research IDs below identify the supporting evidence and limits.

## 1. What exists and what needs improvement

The inspected production target is Godot **4.7.2-stable**, Compatibility/OpenGL, with 4× MSAA. Preserve this pin and renderer. The field is a 100 × 12 m grass runway, centered at north 15 m / east 0 m; the pilot stands at the origin. The pavilion is at north −22 m / east 0 m and pit shelters at north −18.5 m / east ±31 m. These are repository layout estimates.

| Existing component | Observed implementation | Consequence for this plan |
| --- | --- | --- |
| Main floods | Two 8 m poles at north −8 m / east ±22 m; 12,000 cd authoring estimates, 5,000 K, 30° half-angle, 90 m range | Replace the two-pole composition with one mast and separately aimed heads. Do not multiply the old intensity by the new head count. |
| Windsock | One low 1.2 m flood directed toward the existing sleeve | Keep a low fixture or ground-mounted head; it does not justify another tall lighting pole. The functional windsock support remains. |
| Runway markers | Twelve warm edge markers, six end markers, one dim pilot marker; batched emissive sprites | Retain their soft character and small scale. Markers are visible emitters, not nineteen real-time lights. |
| Marker optics | LU already adds separate core/halo profiles, distance fade and inward-red/outward-green ends | Preserve working directional cues. The airport option builds on them; it does not claim to invent them. |
| Clubhouse | Window glow and two warm veranda OmniLights | Use them to connect the rear social area to the mast lighting. Do not duplicate them. |
| Time/exposure | FW adaptive view exposure and an explicit TOD snapshot route with different local gain; both use LU display caps | Every new emitter must work in both routes without double gain, double exposure or stale daytime light. |
| Collision | A flood fixture currently produces its own pole capsule | Four light heads must not accidentally create four overlapping mast colliders. Retired poles must disappear from both rendering and collision. |

The new [native planning views](../research/field-world/FW-66/README.md#visual-baseline) show broad but disconnected ground pools, a dark gap toward the club, small marker points and little visible lamp construction from the wide camera. The close runway still retains grass texture; preserve that strength. These views are composition evidence, not a hardware benchmark or a before/after result.

Relevant sources are [lights.json](../../app/data/fields/lights.json), [FieldLights](../../app/render/world/field_lights.gd), [AirfieldLighting](../../app/render/landscape_upgrade/airfield_lighting.gd), [runway marker shader](../../app/render/landscape_upgrade/runway_marker.gdshader), [world composition/exposure](../../app/render/world/world.gd) and [collision composition](../../app/scenery/collision_world.gd).

## 2. Art direction and alternatives

The visual hierarchy is: aircraft and usable runway first; the mast and warm clubhouse second; a small campfire third; dark trees, lake and sky as context. Softness comes from smooth light falloff, small diffuse halos and controlled contrast. It must not blur the aircraft or obscure the horizon.

| Direction | Character | Advantages | Cost or weakness | Decision |
| --- | --- | --- | --- | --- |
| **Soft club night** | Neutral-warm mast, warmer low stakes and veranda, optional amber fire | Fits the rural club and the requested solar-lamp softness; preserves current layout | Requires careful overlap so the field does not become a patchwork | **Recommended default** |
| **Airfield night** | Cleaner white runway edges, directional green/red ends, same mast and club | Clear airport association and runway orientation | Excess intensity can make a 100 m RC strip look like a large commercial airport | **Selectable style**, equally polished |
| Moonlit minimal | Mostly sky and marker light, very low mast output | Useful comparison and dark-night atmosphere | Does not satisfy the requested field coverage by itself | Keep as a research comparison, not an extra product preset initially |
| Stadium lighting | Tall industrial tower, many hard beams, broad white exposure | Easy to make bright | Dominates the club, adds clutter/cost and weakens dark adaptation | Reject |
| Full volumetric cinematic scene | Fog volumes, GI, shafts and extensive bloom | Strong still-image effect | Conflicts with the current renderer and flight readability | Reject as this plan's dependency |

Use four visible, proportionate rectangular lamp heads with metal housings, mounting arms and believable pivots. Matte dark/galvanized finishes should read in daytime and catch small night highlights. Emitters must face their illumination direction; the rear of a housing cannot look as bright as its lens. Preserve a dark sky; do not globally increase ambient brightness to conceal poor placement.

Treat the night as three connected zones: a legible runway, a warmer social area and a subdued surrounding landscape. Preserve subtle treeline/horizon separation during pilot pans; compare against a deliberately dark runway-only control before adding ambient light. Full-size aviation references identify the risk of missing peripheral cues, but do not prove the response of an RC simulator user. Moonlight is a separate reference comparison, not a reason to lift every dark surface. See A05/A07.

## 3. One mast: placement, aiming and coverage

Interpret “one pole” as **one tall field-lighting mast**, not deletion of the windsock, fences or small ground stakes. Remove both old tall flood instances and their obsolete hardware/proxies, then create one authoritative mast installation. Reuse one existing mast mesh if the downloaded complete-mast candidate fails intake; attach downloaded lamp heads rather than modeling replacements.

### Placement study

Start the study at north **−8 m**, east **0 m**, with the head cluster at **9 m**. Compare heights 8, 9 and 10 m and small east offsets of ±4 m. These are candidates, not committed placements. Keep the mast behind the pilot line, outside the runway and approach paths, and clear of the central walking route, sightlines, trees, pavilion and pit shelter roofs. Check the current scenery and damage inventory before choosing a final position.

| Head | Initial ground target (north, east, up), m | Initial half-angle | Initial range | Purpose |
| --- | --- | --- | --- | --- |
| West field | (16, −32, 0) | Start 8–12°; re-aim if coverage fails | 65–75 m | Western runway and far edge study |
| Center field | (17, 0, 0) | Start 14–18°; re-aim if coverage fails | 45–60 m | Central working-area study |
| East field | (16, 32, 0) | Start 8–12°; re-aim if coverage fails | 65–75 m | Eastern runway and far edge study |
| Club/pits fill | (−16, 0, 0) | Start 32–44° | 25–35 m | A restrained transition toward preparation/walking space |

**The initial broad-angle proposal is superseded, not accepted.** At these targets the side heads point down by only 12.68° and the center by 19.80°. Their former 28–34° / 34–40° half-angles would extend above horizontal. For a circular cone, use `half_angle_deg <= rad_to_deg(atan2(head_height - target_height, horizontal_distance))` as the direct no-uplight constraint. Recompute it after every height/aim change. A visible hood does not provide optical cutoff for an unshadowed Godot spot. Manufacturer asymmetric photometry is a design reference, not a distribution the current circular spot automatically reproduces. See A01/A02.

These narrower cones may leave gaps. Compare two **four-head** arrangements before freezing geometry: **3 runway + 1 club fill**, and **4 overlapping runway sectors**, using the existing veranda lights to connect the club in the second arrangement. Re-aim inner and outer sectors on the coverage grid. Select the arrangement with useful continuity and restrained spill; do not add hidden lights or extra poles to conceal a failed study. If 8–10 m cannot pass, compare one 12 m mast for sightline/scale/collision cost before expanding the feature. Any residual above-horizontal output must be recorded as an artistic approximation, never described as physical shielding.

All four heads rotate independently. Do not point an optical axis at the pilot's eye or use a rear-facing source bright enough to hide the airplane when panning. The low windsock flood remains a fifth field SpotLight. The existing aircraft landing light brings the intended total to six overlapping spots, leaving headroom below Compatibility's default eight-per-mesh limit. Audit actual overlap with the complete scene, including previews and parked aircraft.

### Tuning sequence

1. Freeze camera, exposure, time, scenery and aircraft pose. Draw a diagnostic aiming/coverage view with identifiable head colors.
2. Compare both four-head arrangements on the actual runway bounds, with gradual overlap and the angular horizon constraint. Check ends and near/far edges, not only the center. Save each head alone and the combined field.
3. Sweep each field head from roughly **4,000–8,000 cd** and any rear fill from **1,000–3,000 cd** as art estimates. Reconcile attenuation first; these old estimates may need revision. Compare aggregate brightness with the existing pair. Maintain independent face-emission and ground-illumination controls.
4. Start the mast at **4,000 K**; compare 3,000 / 3,500 / 4,000 / 4,500 K at matched ground brightness. Keep stake/veranda warmth around the existing 3,000 K appearance. Score actual aircraft and marker color recognition separately from atmosphere preference; Kelvin-derived tint does not simulate CRI or a luminaire spectrum (A06).
5. Tune cone falloff and range. Then enable the existing exposure adaptation and repeat pilot pans between ground, sky, lamps and airplane.
6. Test zero and one shadow-casting mast head. Retain a shadow only if it gives useful depth without jagged crawling or an unacceptable frame cost. Add no second shadowed local source without a measured reason.

**Coverage does not mean uniform brightness everywhere.** The entire runway outline must be readable, the central working area must have useful light, and the side/rear areas must connect visually. Peripheral terrain can fall into darkness. One pole cannot plausibly illuminate the entire distant landscape as if it were day.

A03 adds a useful scale check: the near-center runway sample is 19.235 m from the proposed 9 m head, while the far corner is 58.498 m away. For equal directional candela on flat ground, `E = I h / d³` gives about **28.13× less light** at that far point. Real optics, range taper and material response modify this. Thus “inside the cone” is not a brightness result. Report relative sample brightness (minimum, p5, median, p95), continuity and per-head contributions; use markers to sustain end readability without overexposing the center. Do not report calibrated lux from tone-mapped images.

## 4. Soft lamps and the airport option

### Preserve and refine the existing optics

- Keep a compact lens core and a wider, much dimmer halo. Start from the existing **2.5 px core / 6.5 px halo**, then compare a 5–8 px halo at 720p in the same camera. These are viewport readability estimates, not physical diameters.
- Keep optical size tied to the live projection and viewport. Verify both perspective and orthographic captures; the current runway shader's perspective-only size calculation is a specific audit item.
- Preserve additive emission and opaque depth occlusion. Reject opaque gray/black rectangles, square sprite borders, halos visible through aircraft/buildings, and unbounded growth during zoom.
- Measure core and halo together so widening a halo does not silently multiply total apparent brightness. Keep saturated red/green recognizable under both exposure routes.
- Preserve dusk continuity from the existing +3° to −4° solar-elevation interval. Low lamps fade out by day while hardware remains visible.
- Add a very local ground pool only where a near-camera lamp needs grounding. A shared ground-material contribution is a fallback experiment, not a real light per stake or a dependency on Godot Decal nodes.

### Product controls

Add a compact **Field lighting / Iluminación del campo** choice to the existing conditions flow, coordinated with UI ownership:

| Value | Visible behavior |
| --- | --- |
| **Soft club / Club suave** | One mast, warm soft markers and the existing warm clubhouse. Recommended default. |
| **Airfield / Aeropuerto** | The same mast and geometry, white edge cues and directional green approach/red end cues. Slightly crisper core, still restrained halos. |
| **Off / Apagada** | Field lamp emission and local lights off; physical hardware remains. Does not silently change aircraft lights. |

Add **Campfire / Fogata: Off–On** as a separate optional atmosphere control, initially off. Selecting field lights off does not alter the separately chosen campfire. The UI must make these independent choices understandable. Do not add an entire lighting editor or expose candela, shader caps and renderer terms to players.

Persist selections in validated preferences; direct technical launches continue to ignore saved player settings. Proposed CLI controls are `--field-lighting=club|airfield|off` and `--campfire=on|off`—**not implemented commands yet**. Explicit arguments take precedence over defaults. Record the resolved visual profile, source version and effect seed in capture context and visual checkpoint identity. A light style change must not advance or reset physics.

### Airport language, scaled to this field

Use white runway edges and green facing the approach / red facing into the runway at its ends. Blue denotes an actual taxiway edge; do not paint the runway edge blue or label the gravel access road a taxiway. Existing directional threshold behavior is retained and made data-driven. These color conventions come from [FAA AIM 2-1-4 and 2-1-10](https://www.faa.gov/air_traffic/publications/atpubs/aim_html/chap2_section_1.html); this remains an artistic RC airfield, not a certified airport installation.

Keep existing 20 m edge spacing for the first comparison. Evaluate 10 m spacing only if the pilot cannot read the strip; extra markers are a deliberate data/collision change. Prefer no new taxiway geometry in the first slice. PAPI/VASI, approach strobes, chase effects and rotating beacons are deferred because they add semantics and distractions beyond the requested airport option.

## 5. Free assets and intake policy

**Download before creating a substitute.** The [FW-66 asset ledger](../research/field-world/FW-66/README.md#resource-comparison) distinguishes actual retrieved files from catalog-only candidates. All source URLs, authors, license evidence, archive members and SHA-256 hashes must survive final intake. “Free download” alone is not a redistribution license.

| Need | Preferred route | Alternative and rejection criteria |
| --- | --- | --- |
| Four adjustable lamps | Two downloaded **Innerscene Security – Motion Floodlight** modules; reuse the separate heads/lenses and orient four heads on the one retained mast | Complete four-head 3DAssets mast only after successful download/import and visual review. Its extremely simple geometry is a weak close-view candidate. |
| Low lamp hardware | Preserve existing functional stakes; compare downloaded **Innerscene Path – Stake Path Light** where close views justify the extra detail | It is a path light, not a verified solar product. Do not invent a solar panel or claim a photovoltaic simulation. |
| Campfire base/logs | **Kenney Survival Kit v2**, `campfire-pit.glb`, with palette/material adaptation | TinyWorlds' CC0 branches are an alternate style; the retrieved package is missing its referenced MTL, so it is not the ready-to-use default. |
| Flame animation | **tauran's Animated flame texture**, a retrieved CC0 sprite sheet, as an initial effect candidate | Its baked isometric look can fail side/high-angle views. Reject it if the in-scene turntable shows an obvious flat sticker; evaluate another downloaded sheet before making custom artwork. |
| Alternative flame animation | Downloaded **Mikodrak Fire FX**: two sets of 40 RGBA frames, 81×123 each; compare alongside tauran | Integer frames remove one atlas issue, but low resolution and billboard appearance remain. BenHickling's inspected cyan-white pixel variant is not a suitable default. |
| Smoke | Preserve proven lifecycle; compare downloaded **ohyhei Smoke Sprite Sheet** at low opacity | 21 occupied cells in a 25-cell layout; explicitly select frames and verify order. Reject white cutout puffs or distracting repetition. |
| Hearth ground | Downloaded **Poly Haven Burned Ground 01**, Rob Tuytel, diffuse/OpenGL normal/roughness 1K subset | Small local patch only. Blend the boundary without z-fighting; no whole-terrain replacement or required displacement. |

B01–B03 also compared CC BY floodlight/solar/log models on Sketchfab and Saraskau's CC0 camping pack. Catalog-only models remain unverified because archive access returned 401. None displaces the actual downloaded baseline yet. B06 rejects Kenney's sampled electrical-looking spark sprites; reuse the existing tiny soft particle profile or simple untextured particles for embers. B08 defers a downloaded raymarched fire example: its source targets Godot 4.5 Forward Plus, adds cost/angle risks and does not establish separate bundled-art provenance. No external demo/addon is installed.

Preferred imported runtime format is GLB/glTF 2.0, which Godot recommends in its [format guide](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html). An OBJ fallback needs verified materials and explicit conversion. Keep authoring-only Blender files outside `app/`; exported builds must not require Blender, a browser, an asset account or a network fetch.

For each selected resource: download → hash → inspect package license → inventory actual contents → inspect scale/bounds/materials → import into an isolated Godot 4.7.2 project → daytime and night turntable → optimize through a reproducible source pipeline → export smoke test → register shipped credits. Do not execute scripts/addons bundled with an art pack. Retain source material/UVs and separate head pivots. Permitted adaptation includes instancing, placement, scaling, pivot extraction, palette changes and mesh optimization; it is not a reason to model ordinary available props from scratch.

C10 strengthens intake: run a pinned Khronos glTF validator with external resources loaded from the intake directory, save its report and review unsupported-extension warnings explicitly. A GLB's JSON/accessor inventory is not complete validation. The Kenney palette must be part of that check. Fresh import/export and visual inspection remain separate gates after schema validation.

The retrieved originals and [source ledger](../../assets/landscape/night-lighting/README.md) now live under `assets/landscape/night-lighting/`; accepted derivatives will go under `app/assets/landscape/night-lighting/` during implementation. The Kenney GLB has an external `Textures/colormap.png` dependency, retained beside it. Store exact importer/conversion settings and original source hashes. Extend the existing landscape credits/export inclusion path. Downloads remain research inputs until accepted; do not ship the entire pack just to use one prop.

The twin floodlight has 21 mesh nodes and four materials; two naive copies would add too many draws. After authoring individual head aims, batch compatible static surfaces by material while retaining source pivots and the four emitter transforms in the authoring recipe. Inspect double-sided faces and replace unsupported sensor-transmission behavior with an appropriate opaque material, or omit the unused sensor. Do not confuse small download size with low runtime cost.

The new source maps do not automatically fit the 16 MiB GPU texture budget: uncompressed maps plus mip chains can exceed their JPG download sizes many times over. Qualify supported compression and, if needed, lower-resolution normal/roughness derivatives through the source pipeline. Load only the selected flame alternative. Report actual imported memory before retaining all optional detail.

## 6. Optional campfire: flame, light and placement

The campfire should be a small social accent visible from the clubhouse, with recognizable flame motion and a subtle warm patch on nearby ground. Start with a **0.8–1.2 m** base, **0.4–0.8 m** visible flames and **4–6 m** light range. These are visual estimates.

Study a location beside the existing picnic area on the club side of the pilot line. Select a clear point from the current placement data, away from pavilion walls, benches, parked models, cars, vegetation and walking routes. Do not place it in the runway or let smoke cross the principal aircraft-tracking view. Preserve the existing countryside layout. A simple prepared ground area may reuse an existing downloaded material; no new landscape theme is needed.

### Effect layers

| Layer | Implementation candidate | Initial bounded allocation |
| --- | --- | --- |
| Logs/base | Imported GLB with opaque materials and modest ember emission | One scene; no glow baked into the sky |
| Flame tongues | Downloaded atlas on vertically oriented particle billboards; blended color/opacity over lifetime | 24–48 live particles, roughly 0.5–1.2 s lifetime |
| Embers | Tiny additive particles, sparse and short lived | 8–16 particles, no trail feature dependency |
| Smoke | Reuse the proven smoke lifecycle and a licensed texture if needed; low opacity, depth sorted | 12–24 particles, 2–4 s lifetime; reduced or absent at distance |
| Ground/object light | One warm OmniLight, bounded independently from visible flame brightness | One new OmniLight, no shadow initially |

The atlas is 1024 × 512 with a 12 × 6 layout: cell dimensions are non-integral in pixels. Inspect actual frame boundaries, filtering, mip bleed and looping before using `particles_anim_h_frames/v_frames`. If necessary, repack the downloaded frames with padding using a documented conversion; do not silently call a resized picture a new animation source.

Compare the downloaded alternative flame frames from B04 before committing to that sheet. Keep a source frame manifest, integer crop bounds, loop order and padding recipe. Test all frames and distant mip levels. `Mipmaps > Limit` is not an implemented fix in the reviewed Godot documentation; disabling all mips is also not an acceptable general remedy. Match premultiplied-alpha textures with the corresponding material, or use straight alpha consistently (C05/C06).

Use additive emission only where it improves flame/ember appearance; compare it against alpha-mix tongues on both dark and bright backgrounds. Smoke uses subdued alpha blending and depth sorting. Keep opaque depth testing for all three, with transparent depth writing disabled unless a specific probe demonstrates a better result. Do not fix sorting by rendering the fire over the aircraft. Validate intersections at ground level, from the club, overhead and across the lake.

Prefer a small `GPUParticles3D` implementation because the repository already has native Compatibility smoke evidence. A minimal isolated probe must validate this specific flame material, atlas and sorting. Keep `CPUParticles3D` as a measured fallback, not a claim that GPU particles are unavailable in Compatibility. Godot documents the [particle properties](https://docs.godotengine.org/en/4.7/tutorials/3d/particles/properties.html) and [CPU particle API](https://docs.godotengine.org/en/4.7/classes/class_cpuparticles3d.html); project-specific evidence remains essential.

Use the simulation's presentation clock and a fixed visual seed, not shader `TIME` or wall-clock randomness. Fire motion uses elapsed simulation seconds, **not the accelerated solar clock**: the Evening preset must not make flames run 20× faster. Pause freezes flames, embers, smoke and flicker. Reset/home/reload clear or reconstruct them by an explicit rule. A saved phase/seed alone cannot reconstruct smoke subjected to changing wind: include bounded emission/wind history over the longest particle lifetime, or explicitly choose a consistent clear/restart policy for visual checkpoint restoration. This is presentation data, not aerodynamic state.

C07 adds a native clock probe: qualify `use_fixed_seed`, `restart(keep_seed)` and explicit requested processing with `speed_scale = 0` on 4.7.2. Do not depend on `GPUParticles3D.emit_particle()` in Compatibility. Compare equal simulation timestamps at 30/60/144 render FPS, after pause and after off-screen return; define tolerances for visual state instead of promising pixel identity across GPU vendors. The CPU fallback must obey the same clock contract.

Use smooth deterministic intensity variation, initially ±10–15% around a stable mean, with no abrupt strobe or whole-scene exposure pulse. Use actual readonly M5 wind for a bounded smoke lean if enabled; do not create thermal forces or change aerodynamic weather. The visible fire must illuminate nearby objects through its local light—an emissive texture alone does not provide that effect in this pipeline.

A flame is not a collision volume. The tangible base/logs need a bounded static proxy if reachable, consistent with SC/CR damage conventions; no thermal injury, combustion solver or fuel-system coupling is part of this visual feature. Optional fire audio is a later AUD-owned addition using a downloaded licensed loop, not a requirement for the lighting slice.

## 7. Godot integration and technical traps

### Separate the installation from its emitters

Introduce a versioned **field-lighting data extension** that represents one mast with multiple heads. Proposed authored structure: `installations` contain physical hardware IDs, transforms, asset references and collision dimensions; `emitters` reference their installation and carry local pose, aim, intensity, range, cone, tint and role. Keep `{value, unit, kind, source}` for quantities. Normalize this into the existing scene-light evaluation path rather than teaching every caller a different schema.

Retain an explicit v1 reader for old field files and fixtures; author the new default as v2 only when validation/render/collision consumers are ready. Reject duplicate IDs, dangling installation references, nonfinite values, empty sources, invalid quantities, coincident position/aim, invalid ranges/cones and excessive active lights. Do not merely raise `MAX_FLOODS` and create a pole per head. Author one mast proxy and explicit low-fixture proxies; stable IDs must connect visible removal, collision and crash damage.

| Boundary | Planned work and constraint |
| --- | --- |
| `render/world/field_lights.gd` | Normalize v1/v2, build head light nodes, evaluate a matching analytic light contribution for exposure, preserve fixture IDs. |
| `render/landscape_upgrade/airfield_lighting.gd` | Bind imported hardware and head emitters once; retain dusk/exposure caps. Replace `name.begins_with("flood_")` role inference with explicit role data. |
| `render/world/world.gd` | Compose a single installation and optional fire in Home, flight and fixtures; pass resolved visual settings and clock. No second `WorldEnvironment`. |
| `runway_marker.gdshader` | Profile color/softness and threshold orientation from data, with live projection, depth and bounded output. Avoid sharing accidental material mutations between worlds. |
| `scenery/collision_world.gd` and setup | One source placement feeds render and float64 proxies. Delete old-pole proxies, include reachable new hardware, update world identity. Coordinate with SC/LU/CR. |
| Existing preferences/conditions/i18n | Validated profile and fire preference, visible Home/flight consistency, English/Spanish labels; coordinate with UI/TOD. |
| New bounded fire helper under `render/world/` | Imported base and native particles; readonly clock/wind; explicit restore/cleanup and independent off switch. |

### Light falloff and exposure must agree

The current `FieldLights.illuminance_point()` assumes inverse-square falloff and a sharp angular inclusion check, while `build()` does not explicitly assign `spot_attenuation` or `spot_angle_attenuation`. Godot's [SpotLight3D reference](https://docs.godotengine.org/en/4.7/classes/class_spotlight3d.html) describes a default distance attenuation of 1 and inverse-square at 2; its angle is a **half-angle**. This is an audit finding, not proof that the current pixels are physically wrong.

Before changing brightness, probe the installed engine at several distances/angles and match the exposure estimator to the chosen light law, including smooth cone falloff and bounded display gain. Do not tune a new scene around an unnoticed disagreement or advertise calibrated lux from the current artistic conversion. Record the chosen law in DECISIONS when implementing FW-68. Include all four mast heads in `_ground_light`/view adaptation; evaluate whether the small fire needs a bounded contribution without letting flicker drive global exposure.

C01 checked the pinned GLES3 implementation. Its radial transport is proportional to `max(1 - (d / R)^4, 0)^2 / max(d, 0.0001)^decay`; angular smoothing is an additional factor and the renderer uploads the reciprocal of the authored angular attenuation. Do not copy the raw property directly into the shader exponent. Keep transport, surface-incidence response and display gain distinct. Probe distance/range fractions 0.1/0.5/0.9/1.01 and cone-angle fractions 0/0.5/0.9/1.01; compare normalized profiles before tuning energy. Exact upstream file hashes are in the research record.

### Renderer choices

The official [renderer comparison](https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html) lists Compatibility's default per-mesh light limits and excludes volumetric fog, positional PCSS and light projector textures. Use finite-range spots, ordinary shadow filtering where verified, and controlled cone edges. `light_size` is not a promise of area-light soft shadows on this renderer.

Glow is available, but Compatibility uses a reduced implementation; built-in camera auto-exposure is Forward+ only. Keep the existing scripted exposure. C02 replaces the original vague “low-strength” experiment: `glow_strength` has no effect on this backend; qualify `glow_intensity` and available threshold controls against local halos. Use a lens/white-fuselage/grass/sky patch probe and both exposure routes. Reject washed-out markers or an aircraft halo. The scene must still work with glow off. [Godot Environment reference](https://docs.godotengine.org/en/4.7/classes/class_environment.html).

C03 separates beam-edge softness from shadow filtering: evaluate cone overlap with shadows disabled, then compare one head using low/high PCF against no shadow. Pinned GLES3 has five/thirteen-tap PCF paths; these do not create physical area-light penumbrae. Keep only a visibly useful result that passes moving-aircraft and thin-pole artifact checks.

C04 constrains batching: merge compatible mast surfaces, but do not merge all lit scenery into one field-wide object just to lower draw calls. Light masks and per-mesh limits must remain correct for terrain, clubhouse, aircraft and fireground. Test an aircraft crossing overlaps with all allowed lights on; unshaded marker batches do not replace lit hardware.

C08 adds a reflection transition check: coordinate with the existing lake/reflection implementation and inspect Club → Airfield → Off plus day → night. If a static probe retains obsolete lighting, request a bounded refresh after the transition settles. Keep the existing probe budget and dynamic-particle exclusions; do not introduce continuous probe updates for flicker or promise accurate flame reflections.

Keep current sky/AgX/haze behavior as the starting baseline. Any fog or grade change requires a separate paired comparison, including daylight. Transparency ordering and LDR banding remain real risks; inspect side views, ground intersections, lake/reflection views and low-gradient halos. [Rendering limitations](https://docs.godotengine.org/en/4.7/tutorials/3d/3d_rendering_limitations.html). Do not change camera depth ranges to hide a sprite/material defect.

## 8. Budgets and quality gates

These are **proposed acceptance budgets**, to be frozen with a clean baseline in FW-66 and adjusted only with recorded reasoning. No result in the planning research closes them.

| Resource | Initial target / hard review trigger |
| --- | --- |
| Tall field-lighting masts | Exactly **one** in every new lighting style; no duplicate hidden rendering or collision instance |
| Local spots affecting the field | Five field spots + one active-aircraft landing light; **≤6 intended**, always below the engine's configured per-mesh limit |
| Local omnis | Existing two veranda lights + at most one fire light = **≤3**. This explicitly proposes a conditional +1 over LU's previous two-omni budget. |
| Shadowed local lights | Default zero; compare one mast head. Hard cap two only after explicit measured review. |
| New visible draws | Target ≤12 above matched baseline without fire, ≤18 with fire; count imported material surfaces and effect passes |
| Imported triangles | Target ≤40k for the mast/head assembly and ≤10k for the campfire; inspect close quality before further reduction |
| Textures / package | New GPU texture allocation ≤16 MiB; new compressed runtime assets ≤10 MiB; record actual import formats/mips |
| Fire particles | ≤96 live particles total; no per-particle real light, unbounded spawn or per-marker process callback |
| Native frame time | Full-scene p95 ≤16.67 ms at 1080p on the measured target; added night cost target ≤1.5 ms p95 and ≤2.5 ms p99 in paired runs |
| Flight state | Identical unobstructed fixed-input physics trace with effects on/off; geometry edits may deliberately change collision-world identity, never aerodynamic coefficients |

If over budget, first remove optional glow/shadows, reduce fire smoke/overdraw, combine compatible imported material surfaces and tighten light ranges. Keep four recognizable head directions and readable runway cues. Do not solve a cost failure by switching renderers or removing the airport option.

### Acceptance matrix

| Area | Required evidence | Reject when |
| --- | --- | --- |
| Composition | Matched old/new pilot, club, runway-inside, both thresholds, close mast and elevated overview views | The field becomes a stadium, the center has a conspicuous black gap, or a new lamp dominates aircraft tracking |
| Ground coverage | Fixed-exposure light-only pairs; a 2 m diagnostic sample grid over the runway, excluding declared shadows | A full-width dark band breaks the usable strip; overlap clips grass texture or forms a visible hard cone seam |
| Upward spill / placement | Per-head depression-versus-half-angle report, grid overlays for both four-head arrangements and a pilot-height orbit | A decorative hood is used as a false cutoff claim, residual spill is unreported, or coverage requires hidden extra lamps/poles |
| Softness | Core/halo profile images at 30/100/300 m, both 720p/1080p, FOV 50°/6°/1° and orthographic control | Square borders, dark rectangles, halo scale jumps, merged neighboring markers or loss of red/green distinction |
| Direction/occlusion | Inside/outside/end-on threshold views; front/back/side head views; opaque aircraft/building blockers | Wrong end color, bright lamp backs, light sprites through blockers or all-around green ends |
| Clipping/contrast | Fixed masks for grass, aircraft, sky and emitter cores; report 8-bit clipping and local contrast | >0.5% clipped ground/aircraft ROI pixels excluding emitter cores, or aircraft silhouette contrast drops >10% versus matched baseline |
| Exposure/transition | Both FW and explicit TOD; +3°, 0°, −4° solar elevation, sunset, blue hour, night and night_dark; pans between sky/field | Popping, doubled gain, stale lighting, oscillating exposure, or fire flicker pumping the whole scene |
| Fire | ≥10 s motion clips at near/mid/far range and side/elevated views; on/off pairs | Flat sticker illusion, obvious looping seams, black alpha fringes, excessive smoke, floor clipping or culling pops |
| Lifecycle | Pause 5 s, resume, reset, time edit, checkpoint restore, return Home, repeated profile changes and off-screen return | Particles advance during pause, duplicate nodes appear, a light leaks between worlds, or controls alter flight state |
| Reflection transitions | Same lake/material view before and after Club/Airfield/Off and day/night changes | Stale bright lamps persist when switched off, refresh storms occur, or optional particles exceed probe/draw budgets |
| Collision | Swept contact fixture for the new mast and a pass through each retired mast location | Multiple mast hits, an invisible old obstacle, wrong damage target or render/collision disagreement |
| Hardware/export | Sequential paired native captures; current desktop export smoke; low-end GPU review | Shader/resource errors, absent credits/resources, missing Linux/macOS check reported as a pass, or unacceptable frame spikes |
| Human flight | Same aircraft/routes before and after, including takeoff, banked pass and landing; review both styles | Pilot loses attitude/runway readability or dislikes the softness/brightness despite passing numerical checks |

The ROI thresholds above are screening criteria on encoded images, **not photometric measurements**. Freeze masks and exposure with the baseline; show the raw images alongside metrics. When geometry differs, compare equivalent visible aircraft/ground regions and identify exclusions in the report. Do not retune masks after seeing a failure. Overall appeal remains a human review criterion.

### Controlled art and flight review

Run the experiments in order so a prettier image cannot hide a coverage failure: (1) head arrangement/height/aim at fixed color and exposure; (2) relative brightness and cone overlap; (3) 3,000–4,500 K sweep at matched ground brightness; (4) local halo size; (5) optional PCF/glow; (6) fire off/on. Carry only the best two passing candidates into each review, keeping a record of rejected alternatives and why they failed.

For A08, code the candidates A/B and balance presentation order; do not reveal “new” or the expected winner until after ratings. Use the same aircraft, routes and camera states. Ask the reviewer to identify aircraft bank/orientation and threshold direction at near/mid/far views, then separately rate brightness, softness and atmosphere. Record errors/time without pretending a single review is a population study. A preferred still image does not pass if actual aircraft tracking gets worse.

## 9. Execution order and proof/status

| ID | Work | Proof / status |
| --- | --- | --- |
| **FW-66** | Inspect current world, compare resources, capture starting composition, establish scope and ownership | **Planning evidence and 26-question Internet follow-up complete.** Fresh immutable source/capture baseline before implementation still pending; concurrent aircraft work prevented a clean second capture. |
| **FW-67** | Import preferred downloaded heads, optional path lamp, campfire base and qualified fire/smoke/hearth candidates into an isolated intake scene | Source file/author/license/hash manifest prepared for ten files; static inspection completed. Pending: validator/dependency reports, native scale/material/animation tests, day/night/side-view captures, optimized runtime counts and export success. |
| **FW-68** | Version data, normalize installations/emitters, reconcile light falloff/exposure and update one-mast collision identity | Pending: old-v1 fixtures still parse, malformed-v2 rejection, light budget/unique proxy tests; DECISIONS entry before integration. |
| **FW-69** | Compose one mast/four heads, compare both arrangements/height/aim, remove retired tall fixtures and their colliders | Pending: horizon-constrained coverage/close-up/daylight pairs; exactly one physical mast and four independent head transforms; windsock still readable. |
| **FW-70** | Blend pools, tune emission/soft halos, qualify optional shadow/glow | Pending: fixed-exposure and adapted pairs, occlusion/zoom/distance/color tests and incremental native cost. |
| **FW-71** | Add the Club/Airfield/Off profile and conditions/preference integration | Pending: both styles are visibly distinct, directional semantics correct, localized labels fit, CLI priority/defaults/checkpoint context covered. |
| **FW-72** | Add optional fire with imported base, animated flames, bounded smoke/embers and one local light | Pending: motion/turntable, wind/clock/pause/restore, sorting/culling and incremental cost evidence. May be declined as an optional feature without weakening mast/airport delivery. |
| **FW-73** | Cross-route integration and regression | Pending: focused suites, parse sweep, unobstructed trace parity, daylight preservation outside declared geometry, collision/damage mapping and aircraft-light regression. |
| **FW-74** | Native performance, fresh import/export and full review bundle | Pending: same-hardware sequential ABBA blocks, 60 warmup + ≥600 measured frames per run/view, p50/p95/p99 and run variation, draws/textures/triangles, logs, credits and package smoke. |
| **FW-75** | Pilot/art acceptance and consolidation | Pending: both styles reviewed in flight; optional fire separately accepted; update canonical guides and fold completed rationale/evidence into them, then remove this plan. Gate FW-N remains open until actual owner review. |

Keep each step independently reviewable. Add lamps before postprocessing; establish useful coverage before decorating it. An unsuitable campfire atlas must not delay the mast and airport work. No runtime step is marked complete by a resource download, a screenshot of an asset store or a headless test alone.

## 10. Verification workflow and delivery

Use the existing [landscape tools](../../tools/landscape/README.md), [world tools](../../tools/world/README.md) and [developer commands](../TOOLS.md). Capture production `World.build()` rather than a disconnected beauty scene. Native render captures must run without `--headless`; headless is appropriate for data/lifecycle/parse checks.

Existing focused suites to extend/run according to changed boundaries: `test_world_field_lights.gd`, `test_landscape_lighting.gd`, `test_world_flow.gd`, `test_landscape_collision_setup.gd`, `test_landscape_collision_world.gd`, and UI/TOD preference/checkpoint tests. Preserve the FW-62-R1 `capture_aircraft_lights.gd` regression because a shared sprite change can reintroduce dark wing blocks. Use `tools/landscape/verify_markers.py` for the current marker fixtures. New fire tests must examine rendered animation and lifecycle, not merely count nodes.

Example of the **existing** native baseline command (choose a fresh absolute output directory for every run):

```powershell
& ./.tools/Godot_v4.7.2-stable_win64_console.exe --path app --audio-driver Dummy --rendering-driver opengl3 --script res://tests/capture_landscape_upgrade.gd -- --time_of_day=night --cases=postcard_club,runway_inside,pilot_north --out=C:/Temp/openrc-night-baseline --frames=600 --width=1920 --height=1080
```

Add new view/profile switches only as their implementation lands. Run benchmarks sequentially with other GPU jobs stopped by their owners; never kill another track's processes. Record binary/hash, renderer, GPU/driver, resolution, source snapshot, arguments, settings, warmup/sample counts and output hashes. A screenshot left behind by an earlier process is not a successful new capture. Check both logs and completion manifests.

C09 defines the paired performance protocol: three ABBA blocks (baseline/candidate/candidate/baseline), identical settings, fixed seeds and a proving image from every run. Record VSync/frame cap and GPU power conditions; keep full-frame intervals, CPU rendering setup and per-viewport GPU/CPU measurements separate. Do not sum CPU and GPU durations as total frame time. Report per-run percentiles and between-run variation; if the effect is smaller than run variation, call it inconclusive and extend sampling. Native macOS Compatibility lacks the documented Visual Profiler support, so label that hardware's measurement method explicitly rather than reporting zero as success.

Before runtime integration, validate draft scripts outside `app/`. After integration run relevant checks and `app/test.sh` from a suitable LF Linux/WSL snapshot as documented; preserve known independent failures rather than weakening a gate. Keep golden flights unchanged unless an intentional physics change is separately authorized—none is proposed here.

The final review bundle contains: matched wide/pilot/close images, short actual flight clips, fire motion if selected, light/profile inventory, rejected-alternative notes, data/collision/lifecycle results, frame statistics, source/license/asset hashes, export proof and explicit unclosed hardware/pilot gates. A native RTX 3090 capture can establish behavior on that device; it cannot establish low-end hardware acceptance.
